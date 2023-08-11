# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Creates proper .config and others for kernel_build."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")
load(":cache_dir.bzl", "cache_dir")
load(
    ":common_providers.bzl",
    "KernelBuildOriginalEnvInfo",
    "KernelEnvAndOutputsInfo",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
    "KernelEnvMakeGoalsInfo",
    "KernelToolchainInfo",
)
load(":config_utils.bzl", "config_utils")
load(":debug.bzl", "debug")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":kernel_config_settings.bzl", "kernel_config_settings")
load(":kgdb.bzl", "kgdb")
load(":scripts_config_arg_builder.bzl", _config = "scripts_config_arg_builder")
load(":stamp.bzl", "stamp")
load(":utils.bzl", "kernel_utils")

visibility("//build/kernel/kleaf/...")

def _determine_local_path(ctx, file_name, file_attr):
    """A local action that stores the path to sandboxed file to a file object"""

    # Use a local action so we get an absolute path in the execroot that
    # does not tear down as sandboxes. Then write the absolute path into the
    # abspath.
    #
    # In practice, the absolute path looks something like:
    #    /<workspace_root>/out/bazel/output_user_root/<hash>/execroot/__main__/bazel-out/k8-fastbuild/<file>
    #
    # Alternatively, we could use a relative path. However, gen_autoksyms.sh
    # interprets relative paths as paths relative to $abs_srctree, which
    # is $(realpath $ROOT_DIR/$KERNEL_DIR). The $abs_srctree is:
    # - A path within the sandbox for sandbox actions
    # - /<workspace_root>/$KERNEL_DIR for local actions
    # Whether KernelConfig is executed in a sandbox may not be consistent with
    # whether a dependant action is executed in a sandbox. This causes the
    # interpretation of CONFIG_* to be inconsistent in the two actions. Hence,
    # we stick with absolute paths.
    #
    # NOTE: This may hurt remote caching for developer builds. We may want to
    # re-visit this when we implement remote caching for developers.

    hermetic_tools = hermetic_toolchain.get(ctx)
    abspath = ctx.actions.declare_file("{}/{}.abspath".format(ctx.attr.name, file_name))
    command = hermetic_tools.setup + """
      # Record the absolute path so we can use in .config
        readlink -e {file_attr_path} > {abspath}
    """.format(
        abspath = abspath.path,
        file_attr_path = file_attr.path,
    )
    ctx.actions.run_shell(
        command = command,
        inputs = [file_attr],
        outputs = [abspath],
        tools = hermetic_tools.deps,
        mnemonic = "KernelConfigLocalPath",
        progress_message = "Storing sandboxed path for {}".format(file_name),
        execution_requirements = {
            "local": "1",
        },
    )
    return abspath

def _determine_raw_symbollist_path(ctx):
    """A local action that stores the path to `abi_symbollist.raw` to a file object."""

    return _determine_local_path(ctx, "abi_symbollist.raw", ctx.files.raw_kmi_symbol_list[0])

def _determine_module_signing_key_path(ctx):
    """A local action that stores the path to `signing_key.pem` to a file object."""

    if not ctx.file.module_signing_key:
        return None

    return _determine_local_path(ctx, "signing_key.pem", ctx.file.module_signing_key)

def _determine_system_trusted_key_path(ctx):
    """A local action that stores the path to `trusted_key.pem` to a file object."""

    if not ctx.file.system_trusted_key:
        return None

    return _determine_local_path(ctx, "trusted_key.pem", ctx.file.system_trusted_key)

def _config_gcov(ctx):
    """Return configs for GCOV.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    gcov = ctx.attr.gcov[BuildSettingInfo].value

    if not gcov:
        return struct(configs = [], deps = [])
    configs = [
        _config.enable("GCOV_KERNEL"),
        _config.enable("GCOV_PROFILE_ALL"),
        # TODO(b/291710318) Allow section mismatch when using GCOV_PROFILE_ALL
        #  modpost: vmlinux.o: section mismatch in reference: cpumask_andnot (section: .text) -> efi_systab_phys (section: .init.data)
        _config.enable("SECTION_MISMATCH_WARN_ONLY"),
        # TODO: Re-enable when https://github.com/ClangBuiltLinux/linux/issues/1778 is fixed.
        _config.disable("CFI_CLANG"),
    ]
    return struct(configs = configs, deps = [])

def _config_lto(ctx):
    """Return configs for LTO.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    lto_config_flag = ctx.attr.lto

    lto_configs = []
    if lto_config_flag == "none":
        lto_configs += [
            _config.disable("LTO_CLANG"),
            _config.enable("LTO_NONE"),
            _config.disable("LTO_CLANG_THIN"),
            _config.disable("LTO_CLANG_FULL"),
            _config.disable("THINLTO"),
            _config.set_val("FRAME_WARN", 0),
        ]
    elif lto_config_flag == "thin":
        lto_configs += [
            _config.enable("LTO_CLANG"),
            _config.disable("LTO_NONE"),
            _config.enable("LTO_CLANG_THIN"),
            _config.disable("LTO_CLANG_FULL"),
            _config.enable("THINLTO"),
        ]
    elif lto_config_flag == "full":
        lto_configs += [
            _config.enable("LTO_CLANG"),
            _config.disable("LTO_NONE"),
            _config.disable("LTO_CLANG_THIN"),
            _config.enable("LTO_CLANG_FULL"),
            _config.disable("THINLTO"),
        ]
    elif lto_config_flag == "fast":
        # Set lto=thin only if LTO full is enabled.
        lto_configs += [
            _config.enable_if(condition = "LTO_CLANG_FULL", config = "LTO_CLANG"),
            _config.disable_if(condition = "LTO_CLANG_FULL", config = "LTO_NONE"),
            _config.enable_if(condition = "LTO_CLANG_FULL", config = "LTO_CLANG_THIN"),
            _config.enable_if(condition = "LTO_CLANG_FULL", config = "THINLTO"),
            _config.disable_if(condition = "LTO_CLANG_FULL", config = "LTO_CLANG_FULL"),
        ]

    return struct(configs = lto_configs, deps = [])

def _config_trim(ctx):
    """Return configs for trimming and `raw_symbol_list_path_file`.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    if trim_nonlisted_kmi_utils.get_value(ctx) and not ctx.files.raw_kmi_symbol_list:
        fail("{}: trim_nonlisted_kmi is set but raw_kmi_symbol_list is empty.".format(ctx.label))

    if len(ctx.files.raw_kmi_symbol_list) > 1:
        fail("{}: raw_kmi_symbol_list must only provide at most one file".format(ctx.label))

    if not trim_nonlisted_kmi_utils.get_value(ctx):
        return struct(configs = [], deps = [])

    if ctx.attr._kgdb[BuildSettingInfo].value:
        # buildifier: disable=print
        print("\nWARNING: {this_label}: Symbol trimming \
              IGNORED because --kgdb is set!".format(this_label = ctx.label))
        return struct(configs = [], deps = [])

    raw_symbol_list_path_file = _determine_raw_symbollist_path(ctx)
    configs = [
        _config.disable("UNUSED_SYMBOLS"),
        _config.enable("TRIM_UNUSED_KSYMS"),
        _config.set_str(
            "UNUSED_KSYMS_WHITELIST",
            "$(cat {})".format(raw_symbol_list_path_file.path),
        ),
    ]
    return struct(configs = configs, deps = [raw_symbol_list_path_file])

def _config_keys(ctx):
    """Return configs for module signing keys and system trusted keys.

    Note: by embedding the system path into the binary, the resulting build
    becomes non-deterministic and the path leaks into the binary. It can be
    discovered with `strings` or even by inspecting the kernel config from the
    binary.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """

    module_signing_key_file = _determine_module_signing_key_path(ctx)
    system_trusted_key_file = _determine_system_trusted_key_path(ctx)
    configs = []
    deps = []
    if module_signing_key_file:
        configs.append(_config.set_str(
            "MODULE_SIG_KEY",
            "$(cat {})".format(module_signing_key_file.path),
        ))
        deps.append(module_signing_key_file)

    if system_trusted_key_file:
        configs.append(_config.set_str(
            "SYSTEM_TRUSTED_KEYS",
            "$(cat {})".format(system_trusted_key_file.path),
        ))
        deps.append(system_trusted_key_file)

    return struct(configs = configs, deps = deps)

def _config_kasan(ctx):
    """Return configs for --kasan.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    lto = ctx.attr.lto
    kasan = ctx.attr.kasan[BuildSettingInfo].value

    if not kasan:
        return struct(configs = [], deps = [])

    if ctx.attr.kasan_sw_tags[BuildSettingInfo].value:
        fail("{}: cannot have both --kasan and --kasan_sw_tags simultaneously".format(ctx.label))

    if lto != "none":
        fail("{}: --kasan requires --lto=none, but --lto is {}".format(ctx.label, lto))

    if trim_nonlisted_kmi_utils.get_value(ctx):
        fail("{}: --kasan requires trimming to be disabled".format(ctx.label))

    configs = [
        _config.enable("KASAN"),
        _config.enable("KASAN_INLINE"),
        _config.enable("KCOV"),
        _config.enable("PANIC_ON_WARN_DEFAULT_ENABLE"),
        _config.disable("RANDOMIZE_BASE"),
        _config.disable("KASAN_OUTLINE"),
        _config.set_val("FRAME_WARN", 0),
        _config.disable("SHADOW_CALL_STACK"),
    ]
    return struct(configs = configs, deps = [])

def _config_kasan_sw_tags(ctx):
    """Return configs for --kasan_sw_tags.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    lto = ctx.attr.lto
    kasan_sw_tags = ctx.attr.kasan_sw_tags[BuildSettingInfo].value

    if not kasan_sw_tags:
        return struct(configs = [], deps = [])

    if ctx.attr.kasan[BuildSettingInfo].value:
        fail("{}: cannot have both --kasan and --kasan_sw_tags simultaneously".format(ctx.label))

    if lto != "none":
        fail("{}: --kasan_sw_tags requires --lto=none, but --lto is {}".format(ctx.label, lto))

    if trim_nonlisted_kmi_utils.get_value(ctx):
        fail("{}: --kasan_sw_tags requires trimming to be disabled".format(ctx.label))

    configs = [
        _config.enable("KASAN"),
        _config.enable("KASAN_SW_TAGS"),
        _config.enable("KASAN_OUTLINE"),
        _config.enable("PANIC_ON_WARN_DEFAULT_ENABLE"),
        _config.disable("KASAN_HW_TAGS"),
        _config.set_val("FRAME_WARN", 0),
    ]
    return struct(configs = configs, deps = [])

def _config_kcsan(ctx):
    """Return configs for --kcsan.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    lto = ctx.attr.lto
    kcsan = ctx.attr.kcsan[BuildSettingInfo].value

    if not kcsan:
        return struct(configs = [], deps = [])

    if lto != "none":
        fail("{}: --kcsan requires --lto=none, but --lto is {}".format(ctx.label, lto))

    if trim_nonlisted_kmi_utils.get_value(ctx):
        fail("{}: --kcsan requires trimming to be disabled".format(ctx.label))

    configs = [
        _config.enable("KCSAN"),
        _config.enable("KCSAN_VERBOSE"),
        _config.disable("KCSAN_KCOV_BROKEN"),
        _config.enable("KCOV"),
        _config.enable("KCOV_ENABLE_COMPARISONS"),
        _config.enable("PROVE_LOCKING"),
        _config.disable("KASAN"),
        _config.disable("KASAN_STACK"),
        _config.enable("PANIC_ON_WARN_DEFAULT_ENABLE"),
        _config.disable("RANDOMIZE_BASE"),
        _config.set_val("FRAME_WARN", 0),
        _config.disable("KASAN_HW_TAGS"),
        _config.disable("CFI"),
        _config.disable("CFI_PERMISSIVE"),
        _config.disable("CFI_CLANG"),
        _config.disable("SHADOW_CALL_STACK"),
    ]
    return struct(configs = configs, deps = [])

def _reconfig(ctx):
    """Return a command and extra inputs to re-configure `.config` file."""
    configs = []
    deps = []
    transitive_deps = []
    apply_defconfig_fragments_cmd = ""
    check_defconfig_fragments_cmd = ""

    for fn in (
        _config_lto,
        _config_trim,
        _config_kcsan,
        _config_kasan,
        _config_kasan_sw_tags,
        _config_gcov,
        _config_keys,
        kgdb.get_scripts_config_args,
    ):
        pair = fn(ctx)
        configs += pair.configs
        deps += pair.deps

    if ctx.files.defconfig_fragments:
        transitive_deps += [target.files for target in ctx.attr.defconfig_fragments]
        defconfig_fragments_paths = [f.path for f in ctx.files.defconfig_fragments]

        apply_defconfig_fragments_cmd = config_utils.create_merge_dot_config_cmd(
            " ".join(defconfig_fragments_paths),
        )
        apply_defconfig_fragments_cmd += """
            need_olddefconfig=1
        """

        check_defconfig_fragments_cmd = config_utils.create_check_defconfig_cmd(
            ctx.label,
            " ".join(defconfig_fragments_paths),
        )

    cmd = """
        (
            need_olddefconfig=
            configs_to_apply=$(echo {configs})
            # There could be reconfigurations based on configs which can lead to
            #  an empty `configs_to_apply` even when `configs` is not empty,
            #  for that reason it is better to check it is not empty before using it.
            if [ -n "${{configs_to_apply}}" ]; then
                ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config ${{configs_to_apply}}
                need_olddefconfig=1
            fi

            {apply_defconfig_fragments_cmd}

            if [[ -n "${{need_olddefconfig}}" ]]; then
                make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
            fi

            {check_defconfig_fragments_cmd}
        )
    """.format(
        configs = " ".join(configs),
        apply_defconfig_fragments_cmd = apply_defconfig_fragments_cmd,
        check_defconfig_fragments_cmd = check_defconfig_fragments_cmd,
    )

    return struct(cmd = cmd, deps = depset(deps, transitive = transitive_deps))

def _kernel_config_impl(ctx):
    localversion_file = stamp.write_localversion(ctx)

    inputs = [
        s
        for s in ctx.files.srcs
        if any([token in s.path for token in [
            "Kbuild",
            "Kconfig",
            "Makefile",
            "configs/",
            "scripts/",
            ".fragment",
        ]])
    ]
    transitive_inputs = []

    out_dir = ctx.actions.declare_directory(ctx.attr.name + "/out_dir")
    outputs = [out_dir]

    reconfig = _reconfig(ctx)
    transitive_inputs.append(reconfig.deps)

    tools = []

    transitive_inputs.append(ctx.attr.env[KernelEnvInfo].inputs)
    transitive_tools = [ctx.attr.env[KernelEnvInfo].tools]

    cache_dir_step = cache_dir.get_step(
        ctx = ctx,
        common_config_tags = ctx.attr.env[KernelEnvAttrInfo].common_config_tags,
        symlink_name = "config",
    )
    inputs += cache_dir_step.inputs
    outputs += cache_dir_step.outputs
    tools += cache_dir_step.tools

    command = ctx.attr.env[KernelEnvInfo].setup + """
          {cache_dir_cmd}
        # Pre-defconfig commands
          eval ${{PRE_DEFCONFIG_CMDS}}
        # Actual defconfig
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{DEFCONFIG}}
        # Post-defconfig commands
          eval ${{POST_DEFCONFIG_CMDS}}
        # Re-config
          {reconfig_cmd}
        # HACK: run syncconfig to avoid re-triggerring kernel_build
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} syncconfig
        # Grab outputs
          rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
          rsync -aL ${{OUT_DIR}}/include/ {out_dir}/include/

        # Ensure reproducibility. The value of the real $ROOT_DIR is replaced in the setup script.
          sed -i'' -e 's:'"${{ROOT_DIR}}"':${{ROOT_DIR}}:g' {out_dir}/include/config/auto.conf.cmd

        # HACK: Ensure we always SYNC auto.conf. This ensures binaries like fixdep are always
        # re-built. See b/263415662
          echo "include/config/auto.conf: FORCE" >> {out_dir}/include/config/auto.conf.cmd

          {cache_dir_post_cmd}
        """.format(
        out_dir = out_dir.path,
        cache_dir_cmd = cache_dir_step.cmd,
        cache_dir_post_cmd = cache_dir_step.post_cmd,
        reconfig_cmd = reconfig.cmd,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelConfig",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = outputs,
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Creating kernel config {}{}".format(
            ctx.attr.env[KernelEnvAttrInfo].progress_message_note,
            ctx.label,
        ),
        command = command,
        execution_requirements = kernel_utils.local_exec_requirements(ctx),
    )

    post_setup_deps = [out_dir, localversion_file]
    post_setup = """
           [ -z ${{OUT_DIR}} ] && echo "FATAL: configs post_env_info setup run without OUT_DIR set!" >&2 && exit 1
         # Restore kernel config inputs
           mkdir -p ${{OUT_DIR}}/include/
           rsync -aL {out_dir}/.config ${{OUT_DIR}}/.config
           rsync -aL --chmod=D+w {out_dir}/include/ ${{OUT_DIR}}/include/
           rsync -aL --chmod=F+w {localversion_file} ${{OUT_DIR}}/localversion

         # Restore real value of $ROOT_DIR in auto.conf.cmd
           sed -i'' -e 's:${{ROOT_DIR}}:'"${{ROOT_DIR}}"':g' ${{OUT_DIR}}/include/config/auto.conf.cmd
    """.format(
        out_dir = out_dir.path,
        localversion_file = localversion_file.path,
    )

    if trim_nonlisted_kmi_utils.get_value(ctx):
        # Ensure the dependent action uses the up-to-date abi_symbollist.raw
        # at the absolute path specified in abi_symbollist.raw.abspath
        post_setup_deps += ctx.files.raw_kmi_symbol_list  # This is 0 or 1 file

    env_and_outputs_info = KernelEnvAndOutputsInfo(
        get_setup_script = _env_and_outputs_get_setup_script,
        tools = ctx.attr.env[KernelEnvInfo].tools,
        inputs = depset(post_setup_deps, transitive = transitive_inputs),
        data = struct(
            pre_setup = ctx.attr.env[KernelEnvInfo].setup,
            post_setup = post_setup,
        ),
    )

    config_script_ret = _get_config_script(ctx, inputs)

    return [
        env_and_outputs_info,
        ctx.attr.env[KernelEnvAttrInfo],
        ctx.attr.env[KernelEnvMakeGoalsInfo],
        ctx.attr.env[KernelToolchainInfo],
        KernelBuildOriginalEnvInfo(
            env_info = ctx.attr.env[KernelEnvInfo],
        ),
        DefaultInfo(
            files = depset([out_dir]),
            executable = config_script_ret.executable,
            runfiles = config_script_ret.runfiles,
        ),
    ]

def _env_and_outputs_get_setup_script(data, restore_out_dir_cmd):
    """Setup script generator for `KernelEnvAndOutputsInfo`.

    Args:
        data: `data` from `KernelEnvAndOutputsInfo`
        restore_out_dir_cmd: See `KernelEnvAndOutputsInfo`. Provided by user of the info.
    Returns:
        The setup script."""
    return """
        {pre_setup}
        {restore_out_dir_cmd}
        {post_setup}
    """.format(
        pre_setup = data.pre_setup,
        restore_out_dir_cmd = restore_out_dir_cmd,
        post_setup = data.post_setup,
    )

def _get_config_script(ctx, inputs):
    """Handles config.sh."""
    executable = ctx.actions.declare_file("{}/config.sh".format(ctx.attr.name))

    script = ctx.attr.env[KernelEnvInfo].run_env.setup

    # TODO(b/254348147): Support ncurses for hermetic tools
    script += """
          export HOSTCFLAGS="${HOSTCFLAGS} --sysroot="
          export HOSTLDFLAGS="${HOSTLDFLAGS} --sysroot="
    """

    script += kernel_utils.set_src_arch_cmd()

    script += """
            menucommand="${1:-savedefconfig}"
            if ! [[ "${menucommand}" =~ .*config ]]; then
                echo "Invalid command $menucommand. Must be *config." >&2
                exit 1
            fi

            # Pre-defconfig commands
            set -x
            eval ${PRE_DEFCONFIG_CMDS}
            set +x
            # Actual defconfig
            make -C ${KERNEL_DIR} ${TOOL_ARGS} O=${OUT_DIR} ${DEFCONFIG}

            # Show UI
            menuconfig ${menucommand}

            # Post-defconfig commands
            set -x
            eval ${POST_DEFCONFIG_CMDS}
            set +x
    """

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = inputs,
        transitive_files = depset(transitive = [
            ctx.attr.env[KernelEnvInfo].run_env.inputs,
            ctx.attr.env[KernelEnvInfo].run_env.tools,
        ]),
    )

    return struct(
        executable = executable,
        runfiles = runfiles,
    )

def _kernel_config_additional_attrs():
    return dicts.add(
        kernel_config_settings.of_kernel_config(),
        cache_dir.attrs(),
    )

kernel_config = rule(
    implementation = _kernel_config_impl,
    doc = """Defines a kernel config target.

- When `bazel build <target>`, this target runs `make defconfig` etc. during the build.
- When `bazel run <target> -- Xconfig`, this target runs `make Xconfig`.
""",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [
                KernelEnvInfo,
                KernelEnvAttrInfo,
                KernelEnvMakeGoalsInfo,
                KernelToolchainInfo,
            ],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "raw_kmi_symbol_list": attr.label(
            doc = "Label to abi_symbollist.raw. Must be 0 or 1 file.",
            allow_files = True,
        ),
        "module_signing_key": attr.label(
            doc = "Label to module signing key.",
            allow_single_file = True,
        ),
        "system_trusted_key": attr.label(
            doc = "Label to trusted system key.",
            allow_single_file = True,
        ),
        "defconfig_fragments": attr.label_list(
            doc = "defconfig fragments",
            allow_files = True,
        ),
        "_write_depset": attr.label(
            default = "//build/kernel/kleaf/impl:write_depset",
            executable = True,
            cfg = "exec",
        ),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    } | _kernel_config_additional_attrs(),
    executable = True,
    toolchains = [hermetic_toolchain.type],
)
