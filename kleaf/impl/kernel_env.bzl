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

"""Source-able build environment for kernel build."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@kernel_toolchain_info//:dict.bzl", "VARS")
load(":abi/force_add_vmlinux_utils.bzl", "force_add_vmlinux_utils")
load(
    ":common_providers.bzl",
    "KernelBuildConfigInfo",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
    "KernelEnvMakeGoalsInfo",
    "KernelEnvToolchainsInfo",
    "KernelToolchainInfo",
)
load(":compile_commands_utils.bzl", "compile_commands_utils")
load(":debug.bzl", "debug")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":kernel_config_settings.bzl", "kernel_config_settings")
load(":kernel_dtstree.bzl", "DtstreeInfo")
load(":kgdb.bzl", "kgdb")
load(":stamp.bzl", "stamp")
load(":status.bzl", "status")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _toolchains_transition_impl(_settings, attr):
    return {
        "//command_line_option:platforms": str(attr.target_platform),
        "//command_line_option:host_platform": str(attr.exec_platform),
    }

_toolchains_transition = transition(
    implementation = _toolchains_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
        "//command_line_option:host_platform",
    ],
)

def _get_kbuild_symtypes(ctx):
    if ctx.attr.kbuild_symtypes == "auto":
        return ctx.attr._kbuild_symtypes_flag[BuildSettingInfo].value
    elif ctx.attr.kbuild_symtypes == "true":
        return True
    elif ctx.attr.kbuild_symtypes == "false":
        return False

    # Should not reach
    fail("{}: kernel_env has unknown value for kbuild_symtypes: {}".format(ctx.attr.label, ctx.attr.kbuild_symtypes))

def _get_toolchains(ctx):
    return ctx.attr._toolchains[0][KernelEnvToolchainsInfo]

def _get_check_arch_cmd(ctx):
    toolchains = _get_toolchains(ctx)
    expected_arch = toolchains.target_arch
    if expected_arch == "riscv64":
        expected_arch = "riscv"

    level = "WARNING"
    exit_cmd = ""
    if ctx.attr._kernel_use_resolved_toolchains[BuildSettingInfo].value:
        level = "ERROR"
        exit_cmd = "exit 1"

    return """
        if [[ "$ARCH" != "{expected_arch}" ]]; then
            echo '{level}: {label} must specify arch = '"${{ARCH/riscv/riscv64}}"'.' >&2
            {exit_cmd}
        fi
    """.format(
        level = level,
        label = ctx.label,
        expected_arch = expected_arch,
        exit_cmd = exit_cmd,
    )

def _get_make_goals(ctx):
    # Fallback to goals from build.config
    make_goals = ["${MAKE_GOALS}"]
    if ctx.attr.make_goals:
        # This is a basic sanitization of the input.
        for goal in ctx.attr.make_goals:
            if " " in goal or ";" in goal:
                fail("ERROR {}: '{}' is not a valid item of make_goals.".format(ctx.label, goal))
        make_goals = list(ctx.attr.make_goals)
    make_goals += force_add_vmlinux_utils.additional_make_goals(ctx)
    make_goals += kgdb.additional_make_goals(ctx)
    make_goals += compile_commands_utils.additional_make_goals(ctx)
    return make_goals

def _get_make_goals_deprecation_warning(ctx):
    # Omit the warning if the goals have been set
    if ctx.attr.make_goals:
        return ""

    msg = """
          # Warning about MAKE_GOALS deprecation.
          if [[ -n ${{MAKE_GOALS}} ]] ; then
            KLEAF_MAKE_TARGETS=$(echo "${{MAKE_GOALS% }}" | sed '/^$/d' | sed 's/\\S*/  "&",/g')
            #  Omit when empty.
            if [[ -z ${{KLEAF_MAKE_TARGETS}} ]]; then
              echo "WARNING: Empty MAKE_GOALS detected. Ensure all targets are listed explicitly."
            else
              echo "WARNING: MAKE_GOALS from build.config is being deprecated, use make_goals in kernel_build;" >&2
              echo "Consider adding:\n\nmake_goals = [\n${{KLEAF_MAKE_TARGETS}}" >&2
              echo "],\n\nto {build_target} kernel." >&2
            fi
            unset KLEAF_MAKE_TARGETS
          fi
    """.format(
        build_target = str(ctx.label).removesuffix("_env"),
    )
    return msg

def _kernel_env_impl(ctx):
    srcs = [
        s
        for s in ctx.files.srcs
        if "/build.config" in s.path or s.path.startswith("build.config")
    ]

    build_config = ctx.file.build_config
    kconfig_ext = ctx.file.kconfig_ext
    dtstree_makefile = None
    dtstree_srcs = []
    if ctx.attr.dtstree != None:
        dtstree_makefile = ctx.attr.dtstree[DtstreeInfo].makefile
        dtstree_srcs = ctx.attr.dtstree[DtstreeInfo].srcs

    setup_env = ctx.file.setup_env
    preserve_env = ctx.executable.preserve_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)

    hermetic_tools = hermetic_toolchain.get(ctx)

    inputs = [
        build_config,
    ]
    inputs += srcs

    transitive_inputs = []
    for target in [ctx.attr.build_config] + ctx.attr.srcs:
        if KernelBuildConfigInfo in target:
            transitive_inputs.append(target[KernelBuildConfigInfo].deps)

    tools = [
        setup_env,
        ctx.file._build_utils_sh,
        preserve_env,
    ]
    transitive_tools = [hermetic_tools.deps]

    toolchains = _get_toolchains(ctx)

    command = hermetic_tools.setup
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += debug.trap()

    if kconfig_ext:
        command += """
              export KCONFIG_EXT={kconfig_ext}
            """.format(
            kconfig_ext = kconfig_ext.path,
        )
    if dtstree_makefile:
        command += """
              export DTSTREE_MAKEFILE={dtstree}
            """.format(
            dtstree = dtstree_makefile.short_path,
        )

    command += _get_make_verbosity_command(ctx)

    kbuild_symtypes = _get_kbuild_symtypes(ctx)
    command += """
        export KBUILD_SYMTYPES={}
    """.format("1" if kbuild_symtypes else "")

    # If multiple targets have the same KERNEL_DIR are built simultaneously
    # with --spawn_strategy=local, try to isolate their OUT_DIRs.
    defconfig_fragments = ctx.files.defconfig_fragments
    config_tags_out = kernel_config_settings.kernel_env_get_config_tags(
        ctx = ctx,
        mnemonic_prefix = "KernelEnv",
        defconfig_fragments = defconfig_fragments,
    )
    inputs.append(config_tags_out.env)

    # For actions using cache_dir, OUT_DIR_SUFFIX is handled by cache_dir.bzl.
    # For actions that do not use cache_dir, OUT_DIR_SUFFIX is useless because
    # the action is already in a sandbox. Hence unset it.
    command += """
          export OUT_DIR_SUFFIX=
    """

    set_source_date_epoch_ret = stamp.set_source_date_epoch(ctx)
    command += set_source_date_epoch_ret.cmd
    inputs += set_source_date_epoch_ret.deps

    make_goals = _get_make_goals(ctx)
    make_goals_deprecation_warning = _get_make_goals_deprecation_warning(ctx)

    if ctx.attr._rust_tools:
        rustc = utils.find_file("rustc", ctx.files._rust_tools, "rust tools", required = True)
        bindgen = utils.find_file("bindgen", ctx.files._rust_tools, "rust tools", required = True)
        command += """
            RUST_PREBUILT_BIN={quoted_rust_bin}
            CLANGTOOLS_PREBUILT_BIN={quoted_clangtools_bin}
        """.format(
            quoted_rust_bin = shell.quote(rustc.dirname),
            quoted_clangtools_bin = shell.quote(bindgen.dirname),
        )

    command += """
        # create a build environment
          source {build_utils_sh}
          export BUILD_CONFIG={build_config}
          {set_localversion_cmd}
          source {setup_env}
          {check_arch_cmd}
        # Variables from resolved toolchain
          {toolchains_setup_env_var_cmd}
        # TODO(b/236012223) Remove the warning after deprecation.
          {make_goals_deprecation_warning}
        # Add a comment with config_tags for debugging
          cp -p {config_tags_comment_file} {out}
          chmod +w {out}
          echo >> {out}
        # capture it as a file to be sourced in downstream rules
          {preserve_env} >> {out}
        """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
        build_config = build_config.path,
        set_localversion_cmd = stamp.set_localversion_cmd(ctx),
        setup_env = setup_env.path,
        check_arch_cmd = _get_check_arch_cmd(ctx),
        toolchains_setup_env_var_cmd = toolchains.setup_env_var_cmd,
        make_goals_deprecation_warning = make_goals_deprecation_warning,
        preserve_env = preserve_env.path,
        out = out_file.path,
        config_tags_comment_file = config_tags_out.env.path,
    )

    progress_message_note = kernel_config_settings.get_progress_message_note(ctx, defconfig_fragments)

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelEnv",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_file],
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Creating build environment {}{}".format(progress_message_note, ctx.label),
        command = command,
    )

    setup = hermetic_tools.setup
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        setup += debug.trap()

    set_up_jobs_cmd = """
        # Increase parallelism # TODO(b/192655643): do not use -j anymore
          export MAKEFLAGS="${{MAKEFLAGS}} -j$(
            make_jobs="$({get_make_jobs_cmd})"
            if [[ -n "$make_jobs" ]]; then
              echo "$make_jobs"
            else
              nproc
            fi
          )"
    """.format(
        get_make_jobs_cmd = status.get_volatile_status_cmd(ctx, "MAKE_JOBS"),
    )

    setup += """
         # error on failures
           set -e
           set -o pipefail
         # utility functions
           source {build_utils_sh}
         # source the build environment
           source {env}
           {set_up_jobs_cmd}
         # setup LD_LIBRARY_PATH for prebuilts
           export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${{ROOT_DIR}}/{linux_x86_libs_path}
         # Set up KCONFIG_EXT
           if [ -n "${{KCONFIG_EXT}}" ]; then
             export KCONFIG_EXT_PREFIX=$(realpath $(dirname ${{KCONFIG_EXT}}) --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
           fi
           if [ -n "${{DTSTREE_MAKEFILE}}" ]; then
             export dtstree=$(realpath -s $(dirname ${{DTSTREE_MAKEFILE}}) --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})
           fi
         # Set up KCPPFLAGS
         # For Kleaf local (non-sandbox) builds, $ROOT_DIR is under execroot but
         # $ROOT_DIR/$KERNEL_DIR is a symlink to the real source tree under
         # workspace root, making $abs_srctree not under $ROOT_DIR.
           if [[ "$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}})" != "${{ROOT_DIR}}/${{KERNEL_DIR}}" ]]; then
             export KCPPFLAGS="$KCPPFLAGS -ffile-prefix-map=$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}})/="
           fi
           """.format(
        env = out_file.path,
        build_utils_sh = ctx.file._build_utils_sh.path,
        linux_x86_libs_path = ctx.files._linux_x86_libs[0].dirname,
        set_up_jobs_cmd = set_up_jobs_cmd,
    )

    setup_tools = [
        ctx.file._build_utils_sh,
    ]
    setup_tools += ctx.files._rust_tools
    setup_transitive_tools = [
        toolchains.all_files,
        hermetic_tools.deps,
    ]

    setup_inputs = [
        out_file,
        ctx.version_file,
    ]
    if kconfig_ext:
        setup_inputs.append(kconfig_ext)
    setup_inputs += dtstree_srcs

    run_env = _get_run_env(ctx, srcs)

    env_info = KernelEnvInfo(
        inputs = depset(setup_inputs),
        tools = depset(setup_tools, transitive = setup_transitive_tools),
        setup = setup,
        run_env = run_env,
    )
    return [
        env_info,
        KernelEnvAttrInfo(
            kbuild_symtypes = kbuild_symtypes,
            progress_message_note = progress_message_note,
            common_config_tags = config_tags_out.common,
        ),
        KernelEnvMakeGoalsInfo(
            make_goals = make_goals,
        ),
        KernelToolchainInfo(
            toolchain_version = toolchains.compiler_version,
        ),
        DefaultInfo(files = depset([out_file])),
    ]

def _get_make_verbosity_command(ctx):
    command = """
        # error on failures
          set -e
          set -o pipefail
    """

    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += """
          export MAKEFLAGS="${MAKEFLAGS} V=1"
        """
    else:
        if ctx.attr._debug_make_verbosity[BuildSettingInfo].value == "E":
            command += """
            # Run Make in silence mode to suppress most of the info output
            export MAKEFLAGS="${MAKEFLAGS} -s"
            """
        if ctx.attr._debug_make_verbosity[BuildSettingInfo].value == "D":
            command += """
            # Similar to --debug_annotate_scripts without additional traps.
            set -x
            export MAKEFLAGS="${MAKEFLAGS} V=1"
            """
        if ctx.attr._debug_make_verbosity[BuildSettingInfo].value == "V":
            command += """
            # Similar to D but even more verbsose
            set -x
            export MAKEFLAGS="${MAKEFLAGS} V=2"
            """

    return command

def _get_run_env(ctx, srcs):
    """Returns setup script for execution phase.

    Unlike the setup script for regular builds, this doesn't modify variables from build.config for
    a proper build, e.g.:

    - It doesn't respect `MAKE_JOBS`
    - It doesn't set `KCONFIG_EXT_PREFIX` or `dtstree`
    - It doesn't set `SOURCE_DATE_EPOCH` or scmversion properly
    """

    toolchains = _get_toolchains(ctx)
    hermetic_tools = hermetic_toolchain.get(ctx)

    setup = hermetic_tools.run_setup
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        setup += debug.trap()
    setup += _get_make_verbosity_command(ctx)
    setup += """
        # create a build environment
          source {build_utils_sh}
          export BUILD_CONFIG={build_config}

        # Silence "git: command not found" and "date: bad date @"
          export SOURCE_DATE_EPOCH=0

          source {setup_env}
    """.format(
        build_utils_sh = ctx.file._build_utils_sh.short_path,
        build_config = ctx.file.build_config.short_path,
        setup_env = ctx.file.setup_env.short_path,
    )
    setup += hermetic_tools.run_additional_setup
    tools = [
        ctx.file.setup_env,
        ctx.file._build_utils_sh,
    ]
    tools += ctx.files._rust_tools
    transitive_tools = [
        toolchains.all_files,
        hermetic_tools.deps,
    ]
    inputs = srcs + [
        ctx.file.build_config,
    ]

    return KernelEnvInfo(
        setup = setup,
        inputs = depset(inputs),
        tools = depset(tools, transitive = transitive_tools),
    )

def _get_rust_tools(rust_toolchain_version):
    if not rust_toolchain_version:
        return []

    rust_binaries = "//prebuilts/rust/linux-x86/%s:binaries" % rust_toolchain_version

    bindgen = "//prebuilts/clang-tools:linux-x86/bin/bindgen"

    return [Label(rust_binaries), Label(bindgen)]

def _kernel_env_additional_attrs():
    return dicts.add(
        kernel_config_settings.of_kernel_env(),
    )

kernel_env = rule(
    implementation = _kernel_env_impl,
    doc = """Generates a rule that generates a source-able build environment.

          A build environment is defined by a single entry build config file
          that can refer to further build config files.

          Example:
          ```
              kernel_env(
                  name = "kernel_aarch64_env,
                  build_config = "build.config.gki.aarch64",
                  srcs = glob(["build.config.*"]),
              )
          ```
          """,
    attrs = {
        "build_config": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "label referring to the main build config",
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = """labels that this build config refers to, including itself.
            E.g. ["build.config.gki.aarch64", "build.config.gki"]""",
        ),
        "defconfig_fragments": attr.label_list(
            doc = "defconfig fragments",
            allow_files = True,
        ),
        "setup_env": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:_setup_env"),
            doc = "label referring to _setup_env.sh",
            cfg = "exec",
        ),
        "preserve_env": attr.label(
            default = Label("//build/kernel/kleaf:preserve_env"),
            doc = "label referring to the script capturing the environment",
            cfg = "exec",
            executable = True,
        ),
        "rust_toolchain_version": attr.string(
            doc = "the version of the rust toolchain to use for this environment",
            default = VARS.get("RUSTC_VERSION", ""),
        ),
        "kconfig_ext": attr.label(
            allow_single_file = True,
            doc = "an external Kconfig.ext file sourced by the base kernel",
        ),
        "dtstree": attr.label(
            providers = [DtstreeInfo],
            doc = "Device tree",
        ),
        "kbuild_symtypes": attr.string(
            doc = "`KBUILD_SYMTYPES`",
            default = "auto",
            values = ["true", "false", "auto"],
        ),
        "make_goals": attr.string_list(doc = "`MAKE_GOALS`"),
        "target_platform": attr.label(
            mandatory = True,
            doc = """Target platform that describes characteristics of the target device.

                See https://bazel.build/extending/platforms.
            """,
        ),
        "exec_platform": attr.label(
            mandatory = True,
            doc = """Execution platform, where the build is executed.

                See https://bazel.build/extending/platforms.
            """,
        ),
        "_rust_tools": attr.label_list(default = _get_rust_tools, allow_files = True),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils"),
            cfg = "exec",
        ),
        "_toolchains": attr.label(
            doc = "Provides all toolchains that the kernel build needs.",
            default = "//build/kernel/kleaf/impl:kernel_toolchains",
            providers = [KernelEnvToolchainsInfo],
            cfg = _toolchains_transition,
        ),
        "_debug_annotate_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_annotate_scripts",
        ),
        "_debug_make_verbosity": attr.label(default = "//build/kernel/kleaf:debug_make_verbosity"),
        "_config_is_local": attr.label(default = "//build/kernel/kleaf:config_local"),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_linux_x86_libs": attr.label(default = "//prebuilts/kernel-build-tools:linux-x86-libs"),
        "_kernel_use_resolved_toolchains": attr.label(
            default = "//build/kernel/kleaf:incompatible_kernel_use_resolved_toolchains",
        ),
        "_cache_dir_config_tags": attr.label(
            default = "//build/kernel/kleaf/impl:cache_dir_config_tags",
            executable = True,
            cfg = "exec",
        ),
        "_write_depset": attr.label(
            default = "//build/kernel/kleaf/impl:write_depset",
            executable = True,
            cfg = "exec",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | _kernel_env_additional_attrs(),
    toolchains = [hermetic_toolchain.type],
)
