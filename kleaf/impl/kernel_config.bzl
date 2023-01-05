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
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")
load(":cache_dir.bzl", "cache_dir")
load(
    ":common_providers.bzl",
    "KernelConfigEnvInfo",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
)
load(":debug.bzl", "debug")
load(":kernel_config_settings.bzl", "kernel_config_settings")
load(":kernel_config_transition.bzl", "kernel_config_transition")
load(":kgdb.bzl", "kgdb")
load(":scripts_config_arg_builder.bzl", _config = "scripts_config_arg_builder")
load(":stamp.bzl", "stamp")
load(":utils.bzl", "kernel_utils")

def _determine_raw_symbollist_path(ctx):
    """A local action that stores the path to `abi_symbollist.raw` to a file object."""

    # Use a local action so we get an absolute path in the execroot that
    # does not tear down as sandboxes. Then write the absolute path into the
    # abi_symbollist.raw.abspath.
    #
    # In practice, the absolute path looks something like:
    #    /<workspace_root>/out/bazel/output_user_root/<hash>/execroot/__main__/bazel-out/k8-fastbuild/bin/common/kernel_aarch64_raw_kmi_symbol_list/abi_symbollist.raw
    #
    # Alternatively, we could use a relative path. However, gen_autoksyms.sh
    # interprets relative paths as paths relative to $abs_srctree, which
    # is $(realpath $ROOT_DIR/$KERNEL_DIR). The $abs_srctree is:
    # - A path within the sandbox for sandbox actions
    # - /<workspace_root>/$KERNEL_DIR for local actions
    # Whether KernelConfig is executed in a sandbox may not be consistent with
    # whether a dependant action is executed in a sandbox. This causes the
    # interpretation of CONFIG_UNUSED_KSYMS_WHITELIST inconsistent in the
    # two actions. Hence, we stick with absolute paths.
    #
    # NOTE: This may hurt remote caching for developer builds. We may want to
    # re-visit this when we implement remote caching for developers.
    abspath = ctx.actions.declare_file("{}/abi_symbollist.raw.abspath".format(ctx.attr.name))
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
      # Record the absolute path so we can use in .config
        readlink -e {raw_kmi_symbol_list} > {abspath}
    """.format(
        abspath = abspath.path,
        raw_kmi_symbol_list = ctx.file.raw_kmi_symbol_list.path,
    )
    ctx.actions.run_shell(
        command = command,
        inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + [ctx.file.raw_kmi_symbol_list],
        outputs = [abspath],
        mnemonic = "KernelConfigLocalRawSymbolList",
        progress_message = "Determining raw symbol list path for trimming {}".format(ctx.label),
        execution_requirements = {
            "local": "1",
        },
    )
    return abspath

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
    lto_config_flag = ctx.attr.lto[BuildSettingInfo].value

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

    return struct(configs = lto_configs, deps = [])

def _config_trim(ctx):
    """Return configs for trimming and `raw_symbol_list_path_file`.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    if trim_nonlisted_kmi_utils.get_value(ctx) and not ctx.file.raw_kmi_symbol_list:
        fail("{}: trim_nonlisted_kmi is set but raw_kmi_symbol_list is empty.".format(ctx.label))

    if not trim_nonlisted_kmi_utils.get_value(ctx):
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

def _config_kasan(ctx):
    """Return configs for --kasan.

    Args:
        ctx: ctx
    Returns:
        A struct, where `configs` is a list of arguments to `scripts/config`,
        and `deps` is a list of input files.
    """
    lto = ctx.attr.lto[BuildSettingInfo].value
    kasan = ctx.attr.kasan[BuildSettingInfo].value

    if not kasan:
        return struct(configs = [], deps = [])

    if lto != "none":
        fail("{}: --kasan requires --lto=none, but --lto is {}".format(ctx.label, lto))

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

def _reconfig(ctx):
    """Return a command and extra inputs to re-configure `.config` file."""
    configs = []
    deps = []

    for fn in (
        _config_lto,
        _config_trim,
        _config_kasan,
        _config_gcov,
        kgdb.get_scripts_config_args,
    ):
        pair = fn(ctx)
        configs += pair.configs
        deps += pair.deps

    if not configs:
        return struct(cmd = "", deps = deps)

    return struct(cmd = """
        ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config {configs}
        make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
    """.format(configs = " ".join(configs)), deps = deps)

def _kernel_config_impl(ctx):
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

    out_dir = ctx.actions.declare_directory(ctx.attr.name + "/out_dir")
    outputs = [out_dir]

    scmversion_command = stamp.scmversion_config_cmd(ctx)
    reconfig = _reconfig(ctx)
    inputs += reconfig.deps

    tools = [] + ctx.attr.env[KernelEnvInfo].dependencies

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
        # SCM version configuration
          {scmversion_command}
        # Re-config
          {reconfig_cmd}
        # HACK: run syncconfig to avoid re-triggerring kernel_build
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} syncconfig
        # Grab outputs
          rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
          rsync -aL ${{OUT_DIR}}/include/ {out_dir}/include/
        # HACK: also keep fixdep for --config=local builds.
        # TODO(b/263415662): Drop it
          mkdir -p {out_dir}/scripts/basic
          rsync -aL ${{OUT_DIR}}/scripts/basic/fixdep {out_dir}/scripts/basic/fixdep
          {cache_dir_post_cmd}
        """.format(
        out_dir = out_dir.path,
        cache_dir_cmd = cache_dir_step.cmd,
        cache_dir_post_cmd = cache_dir_step.post_cmd,
        scmversion_command = scmversion_command,
        reconfig_cmd = reconfig.cmd,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelConfig",
        inputs = inputs,
        outputs = outputs,
        tools = tools,
        progress_message = "Creating kernel config {}{}".format(
            ctx.attr.env[KernelEnvAttrInfo].progress_message_note,
            ctx.label,
        ),
        command = command,
        execution_requirements = kernel_utils.local_exec_requirements(ctx),
    )

    setup_deps = [out_dir]
    setup = """
           [ -z ${{OUT_DIR}} ] && echo "FATAL: configs post_env_info setup run without OUT_DIR set!" >&2 && exit 1
         # Restore kernel config inputs
           mkdir -p ${{OUT_DIR}}/include/
           rsync -aL {out_dir}/.config ${{OUT_DIR}}/.config
           rsync -aL --chmod=D+w {out_dir}/include/ ${{OUT_DIR}}/include/
         # HACK: also keep fixdep for --config=local builds.
         # TODO(b/263415662): Drop it
           mkdir -p ${{OUT_DIR}}/scripts/basic
           rsync -aL --chmod=D+w {out_dir}/scripts/basic/fixdep ${{OUT_DIR}}/scripts/basic/fixdep
    """.format(
        out_dir = out_dir.path,
    )

    if trim_nonlisted_kmi_utils.get_value(ctx):
        # Ensure the dependent action uses the up-to-date abi_symbollist.raw
        # at the absolute path specified in abi_symbollist.raw.abspath
        setup_deps.append(ctx.file.raw_kmi_symbol_list)

    post_env_info = KernelEnvInfo(
        dependencies = setup_deps,
        setup = setup,
    )
    kernel_config_env_info = KernelConfigEnvInfo(
        env_info = ctx.attr.env[KernelEnvInfo],
        post_env_info = post_env_info,
    )

    config_script_ret = _get_config_script(ctx)

    return [
        kernel_config_env_info,
        ctx.attr.env[KernelEnvAttrInfo],
        DefaultInfo(
            files = depset([out_dir]),
            executable = config_script_ret.executable,
            runfiles = config_script_ret.runfiles,
        ),
    ]

def _get_config_script(ctx):
    """Handles config.sh."""
    executable = ctx.actions.declare_file("{}/config.sh".format(ctx.attr.name))

    script = """
          cd ${BUILD_WORKSPACE_DIRECTORY}
    """
    script += ctx.attr.env[KernelEnvInfo].setup

    # TODO(b/254348147): Support ncurses for hermetic tools
    script += """
          export HOSTCFLAGS="${HOSTCFLAGS} --sysroot="
          export HOSTLDFLAGS="${HOSTLDFLAGS} --sysroot="
    """

    script += """
          menucommand="${1:-savedefconfig}"
          if ! [[ "${menucommand}" =~ .*config ]]; then
            echo "Invalid command $menucommand. Must be *config." >&2
            exit 1
          fi

          # Pre-defconfig commands
            eval ${PRE_DEFCONFIG_CMDS}
          # Actual defconfig
            make -C ${KERNEL_DIR} ${TOOL_ARGS} O=${OUT_DIR} ${DEFCONFIG}

          # Show UI
            menuconfig ${menucommand}

          # Post-defconfig commands
            eval ${POST_DEFCONFIG_CMDS}
    """

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(ctx.attr.env[KernelEnvInfo].dependencies)

    return struct(
        executable = executable,
        runfiles = runfiles,
    )

def _kernel_config_additional_attrs():
    return dicts.add(
        kernel_config_settings.of_kernel_config(),
        trim_nonlisted_kmi_utils.non_config_attrs(),
    )

kernel_config = rule(
    implementation = _kernel_config_impl,
    doc = """Defines a kernel config target.

- When `bazel build <target>`, this target runs `make defconfig` etc. during the build.
- When `bazel run <target> -- Xconfig`, this target runs `make Xconfig`.
""",
    cfg = kernel_config_transition,
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelEnvAttrInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "raw_kmi_symbol_list": attr.label(
            doc = "Label to abi_symbollist.raw.",
            allow_single_file = True,
        ),
        "_cache_dir": attr.label(default = "//build/kernel/kleaf:cache_dir"),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_config_is_local": attr.label(default = "//build/kernel/kleaf:config_local"),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_allowlist_function_transition": attr.label(
            # Allow everything because kernel_config is indirectly called in device packages.
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | _kernel_config_additional_attrs(),
    executable = True,
)
