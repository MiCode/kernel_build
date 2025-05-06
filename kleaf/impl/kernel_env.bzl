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
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@kernel_toolchain_info//:dict.bzl", "VARS")
load(":abi/force_add_vmlinux_utils.bzl", "force_add_vmlinux_utils")
load(
    ":common_providers.bzl",
    "DtstreeInfo",
    "KernelBuildConfigInfo",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
    "KernelEnvMakeGoalsInfo",
    "KernelToolchainInfo",
)
load(":compile_commands_utils.bzl", "compile_commands_utils")
load(":debug.bzl", "debug")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":kernel_config_settings.bzl", "kernel_config_settings")
load(":kernel_toolchains_utils.bzl", "kernel_toolchains_utils")
load(":kgdb.bzl", "kgdb")
load(":set_kernel_dir.bzl", "set_kernel_dir")
load(":stamp.bzl", "stamp")
load(":status.bzl", "status")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _get_kbuild_symtypes(ctx):
    if ctx.attr.kbuild_symtypes == "auto":
        return ctx.attr._kbuild_symtypes_flag[BuildSettingInfo].value
    elif ctx.attr.kbuild_symtypes == "true":
        return True
    elif ctx.attr.kbuild_symtypes == "false":
        return False

    # Should not reach
    fail("{}: kernel_env has unknown value for kbuild_symtypes: {}".format(ctx.attr.label, ctx.attr.kbuild_symtypes))

def _get_set_arch_cmd(ctx):
    """Returns command that sets ARCH.

    This is called before `source _setup_env.sh` so that it can be overridden by build configs.
    """
    toolchains = kernel_toolchains_utils.get(ctx)
    inferred_arch = toolchains.target_arch
    if inferred_arch == "riscv64":
        inferred_arch = "riscv"
    return """
        export ARCH="{inferred_arch}"
    """.format(
        inferred_arch = inferred_arch,
    )

def _get_check_arch_cmd(ctx):
    toolchains = kernel_toolchains_utils.get(ctx)
    declared_arch = toolchains.target_arch

    level = "WARNING"
    exit_cmd = ""
    if ctx.attr._kernel_use_resolved_toolchains[BuildSettingInfo].value:
        level = "ERROR"
        exit_cmd = "exit 1"

    return """
        if [[ "${{ARCH/riscv/riscv64}}" != "{declared_arch}" ]]; then
            echo '{level}: {label} must specify arch = '"${{ARCH/riscv/riscv64}}"', but is {declared_arch}.' >&2
            {exit_cmd}
        fi
    """.format(
        level = level,
        label = ctx.label,
        declared_arch = declared_arch,
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

def _get_kconfig_werror_setup(ctx):
    if not ctx.attr._kconfig_werror[BuildSettingInfo].value:
        return ""
    return "export KCONFIG_WERROR=1"

def _get_build_config_inputs_impl(_subrule_ctx, *, srcs, build_config):
    """Gets the list of build config files needed for the build config step.

    This can be an overestimate."""

    # If kernel_build.build_config is not set (build config-less builds), we shouldn't
    # need any build configs. Return early to avoid the big depset expansion in srcs.
    if not build_config or not build_config.files:
        return depset()

    # The depset expansion is unavoidable to reduce the list of inputs fed
    # into the action. This reduces incremental build times by increasing time in the analysis
    # phase.
    inputs = [
        s
        for s in depset(transitive = [target.files for target in srcs]).to_list()
        if "/build.config" in s.path or s.path.startswith("build.config")
    ]
    transitive_inputs = [build_config.files]
    if KernelBuildConfigInfo in build_config:
        transitive_inputs.append(build_config[KernelBuildConfigInfo].deps)
    for target in srcs:
        if KernelBuildConfigInfo in target:
            transitive_inputs.append(target[KernelBuildConfigInfo].deps)
    return depset(inputs, transitive = transitive_inputs)

_get_build_config_inputs = subrule(implementation = _get_build_config_inputs_impl)

def _kernel_env_impl(ctx):
    kconfig_ext = ctx.file.kconfig_ext
    dtstree_makefile = None
    dtstree_srcs = depset()
    if ctx.attr.dtstree != None:
        dtstree_makefile = ctx.attr.dtstree[DtstreeInfo].makefile
        dtstree_srcs = ctx.attr.dtstree[DtstreeInfo].srcs

    setup_env = ctx.file.setup_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)

    hermetic_tools = hermetic_toolchain.get(ctx)

    inputs = []
    transitive_inputs = [_get_build_config_inputs(
        srcs = ctx.attr.srcs,
        build_config = ctx.attr.build_config,
    )]

    tools = [
        setup_env,
        ctx.file._build_utils_sh,
    ]
    transitive_tools = [hermetic_tools.deps]

    toolchains = kernel_toolchains_utils.get(ctx)

    set_kernel_dir_ret = set_kernel_dir(makefile = ctx.file.makefile)

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
    pre_defconfig_fragments = ctx.files.pre_defconfig_fragments
    post_defconfig_fragments = ctx.files.post_defconfig_fragments
    config_tags_out = kernel_config_settings.kernel_env_get_config_tags(
        ctx = ctx,
        mnemonic_prefix = "KernelEnv",
        pre_defconfig_fragments = pre_defconfig_fragments,
        post_defconfig_fragments = post_defconfig_fragments,
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

    kconfig_werror_setup = _get_kconfig_werror_setup(ctx)

    env_setup_cmds = _get_env_setup_cmds(ctx)
    pre_env_script = ctx.actions.declare_file("{}/pre_env.sh".format(ctx.attr.name))
    ctx.actions.write(pre_env_script, env_setup_cmds.pre_env)
    post_env_script = ctx.actions.declare_file("{}/post_env.sh".format(ctx.attr.name))
    ctx.actions.write(post_env_script, env_setup_cmds.post_env)
    inputs += [pre_env_script, post_env_script]

    kleaf_repo_workspace_root = Label(":kernel_env.bzl").workspace_root
    if kleaf_repo_workspace_root:
        bin_dir_and_workspace_root = paths.join(ctx.bin_dir.path, kleaf_repo_workspace_root)
    else:
        bin_dir_and_workspace_root = ctx.bin_dir.path

    quoted_space_and_extra_kcflags = ""
    if ctx.attr.kcflags:
        quoted_space_and_extra_kcflags = shell.quote(" " + (" ".join(ctx.attr.kcflags)))

    command += """
          export DEPMOD=depmod
          export DTC=$(command -v dtc)
          export LLVM=1
        # create a build environment
          source {build_utils_sh}
    """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
    )

    if ctx.attr.build_config and ctx.attr.build_config.files:
        command += """
            export BUILD_CONFIG={build_config}
        """.format(
            build_config = utils.optional_single_path(ctx.files.build_config),
        )
    else:
        command += """
            export KLEAF_INTERNAL_NO_BUILD_CONFIG=1
        """

        # Set branch specific constants.
        for key, value in VARS.items():
            command += """
                export {quoted_key}={quoted_value}
            """.format(
                quoted_key = shell.quote(key),
                quoted_value = shell.quote(value),
            )

    if ctx.file.clang_autofdo_profile:
        set_clang_autofdo_profile_cmd = "export CLANG_AUTOFDO_PROFILE=${ROOT_DIR}/" + ctx.file.clang_autofdo_profile.path
    else:
        set_clang_autofdo_profile_cmd = ""

    command += """
          export KCFLAGS="${{KCFLAGS}}"{quoted_space_and_extra_kcflags}
          {set_kernel_dir_cmd}
          {set_localversion_cmd}
          {set_arch_cmd}
          source {setup_env}
          {check_arch_cmd}
        # Variables from resolved toolchain
          {toolchains_setup_env_var_cmd}
          {set_clang_autofdo_profile_cmd}
        # TODO(b/236012223) Remove the warning after deprecation.
          {make_goals_deprecation_warning}
        # Enforce check configs.
          {kconfig_werror_setup}
        # Identify the build user as 'kleaf' to recognize a kleaf-built kernel
          export KBUILD_BUILD_USER=kleaf

        # Make it so that Rust symbol names do not change when the version
        # string of rustc changes. Note that since the version string includes
        # the date and commit hash from the build environment, even a respin of
        # rustc could cause symbol names to change without this option.
        #
        # https://github.com/rust-lang/rust/blob/617aad8c2e8783f6df8e5d1f8bb1e4bcdc70aa7b/compiler/rustc_span/src/def_id.rs#L179-L189
          export RUSTC_FORCE_RUSTC_VERSION=rustc-android

        # Add a comment with config_tags for debugging
          cp -p {config_tags_comment_file} {out}
          chmod +w {out}
          echo >> {out}

          cat {pre_env_script} >> {out}
          echo >> {out}

        # capture it as a file to be sourced in downstream rules
          ( export -p; export -f ) | \\
            # Remove TMPDIR, set by build bots. Other targets built by the
            # current `bazel` command are affected by the same TMPDIR env var.
            # However, we do not want kernel_filegroup to inherit TMPDIR.
            sed '/^declare -x TMPDIR=/d' | \\
            # Remove the reference to PWD itself
            sed '/^declare -x PWD=/d' | \\
            # Now ensure, new PWD gets expanded
            sed "s|${{PWD}}|\\$PWD|g" | \\
            # Drop reference to bin_dir and replace with variable;
            # Replace $PWD/<not out> with $KLEAF_REPO_DIR/$1
            sed "s|\\$PWD/{hermetic_base}|\\$PWD/\\$KLEAF_HERMETIC_BASE|g" | \\
            sed "s|\\$PWD/{bin_dir_and_workspace_root}|\\$PWD/\\$KLEAF_BIN_DIR_AND_WORKSPACE_ROOT|g" | \\
            sed "s|{bin_dir_and_workspace_root}|\\$KLEAF_BIN_DIR_AND_WORKSPACE_ROOT|g" | \\
            # List of packages that //build/kernel/... depends on. This excludes
            # external/ because they are in different Bazel repositories.
            sed "s|\\$PWD/build|\\$KLEAF_REPO_DIR/build|g" | \\
            sed "s|\\$PWD/prebuilts|\\$KLEAF_REPO_DIR/prebuilts|g" \\
            >> {out}

          echo >> {out}

          cat {post_env_script} >> {out}
        """.format(
        quoted_space_and_extra_kcflags = quoted_space_and_extra_kcflags,
        set_kernel_dir_cmd = set_kernel_dir_ret.cmd,
        set_localversion_cmd = stamp.set_localversion_cmd(ctx),
        set_arch_cmd = _get_set_arch_cmd(ctx),
        setup_env = setup_env.path,
        check_arch_cmd = _get_check_arch_cmd(ctx),
        toolchains_setup_env_var_cmd = toolchains.kernel_setup_env_var_cmd,
        set_clang_autofdo_profile_cmd = set_clang_autofdo_profile_cmd,
        make_goals_deprecation_warning = make_goals_deprecation_warning,
        kconfig_werror_setup = kconfig_werror_setup,
        out = out_file.path,
        config_tags_comment_file = config_tags_out.env.path,
        pre_env_script = pre_env_script.path,
        post_env_script = post_env_script.path,
        hermetic_base = hermetic_tools.internal_hermetic_base,
        bin_dir_and_workspace_root = bin_dir_and_workspace_root,
    )

    progress_message_note = kernel_config_settings.get_progress_message_note(
        ctx,
        pre_defconfig_fragments,
        post_defconfig_fragments,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelEnv",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_file],
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Creating build environment{} %{{label}}".format(progress_message_note),
        command = command,
    )

    setup = get_env_info_setup_command(
        hermetic_tools_setup = hermetic_tools.setup,
        build_utils_sh = ctx.file._build_utils_sh,
        env_setup_script = out_file,
    )

    setup_tools = [
        ctx.file._build_utils_sh,
    ]
    setup_transitive_tools = [
        toolchains.all_files,
        hermetic_tools.deps,
    ]

    setup_inputs = [
        out_file,
        ctx.version_file,
    ]
    setup_transitive_inputs = []
    if kconfig_ext:
        setup_inputs.append(kconfig_ext)
    if ctx.file.clang_autofdo_profile:
        setup_inputs.append(ctx.file.clang_autofdo_profile)
    setup_transitive_inputs.append(dtstree_srcs)
    if dtstree_makefile:
        setup_inputs.append(dtstree_makefile)

    env_info = KernelEnvInfo(
        inputs = depset(setup_inputs, transitive = setup_transitive_inputs),
        tools = depset(setup_tools, transitive = setup_transitive_tools),
        setup = setup,
        toolchains = toolchains,
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

def get_env_info_setup_command(
        hermetic_tools_setup,
        build_utils_sh,
        env_setup_script):
    """Returns text for KernelEnvInfo.setup"""

    return """{hermetic_tools_setup}

        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            source {build_utils_sh_short}
            # source the build environment
            source {env_setup_script_short}
        else
            source {build_utils_sh}
            # source the build environment
            source {env_setup_script}
        fi
    """.format(
        hermetic_tools_setup = hermetic_tools_setup,
        build_utils_sh_short = build_utils_sh.short_path,
        build_utils_sh = build_utils_sh.path,
        env_setup_script_short = env_setup_script.short_path,
        env_setup_script = env_setup_script.path,
    )

def _get_env_setup_cmds(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    pre_env = ""
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        pre_env += debug.trap()

    kleaf_repo_workspace_root = Label(":kernel_env.bzl").workspace_root

    pre_env += """
        # KLEAF_REPO_WORKSPACE_ROOT: workspace_root of the Kleaf repository. See Label.workspace_root.
        # This should be:
        # - Either an empty string if @kleaf is the root module;
        # - or external/kleaf (or some variations of it) if @kleaf is a dependent module
        # This may be overridden by kernel_filegroup.
        KLEAF_REPO_WORKSPACE_ROOT=${{KLEAF_REPO_WORKSPACE_ROOT:-{kleaf_repo_workspace_root}}}

        # hermetic_base for hermetic tools, relative to execroot. This is
        # handled separately from bin_dir because hermetic_tools has a transition
        # attached to it.
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            KLEAF_HERMETIC_BASE=${{KLEAF_HERMETIC_BASE:-{run_hermetic_base}}}
        else
            KLEAF_HERMETIC_BASE=${{KLEAF_HERMETIC_BASE:-{hermetic_base}}}
        fi

        # bin_dir for Kleaf repository, relative to execroot
        # This is:
        # For `bazel build`:
        # - either bazel-out/k8-fastbuild/bin if @kleaf is the root module;
        # - or bazel-out/k8-fastbuild/bin/external/kleaf (or some variations of it)
        #   if @kleaf is a dependent module
        # For `bazel run`:
        # - either . if @kleaf is the root module
        # - or external/kleaf (or some variations of it) if @kleaf is a dependent module
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            KLEAF_BIN_DIR_AND_WORKSPACE_ROOT="${{KLEAF_REPO_WORKSPACE_ROOT:-.}}"
        else
            KLEAF_BIN_DIR_AND_WORKSPACE_ROOT="{bin_dir}${{KLEAF_REPO_WORKSPACE_ROOT:+/$KLEAF_REPO_WORKSPACE_ROOT}}"
        fi

        # Root of Kleaf repository (under execroot aka PWD)
        # This is:
        # - either $PWD if @kleaf is the root module
        # - or $PWD/external/kleaf (or some variations of it) if @kleaf is a dependent module
        KLEAF_REPO_DIR="$PWD${{KLEAF_REPO_WORKSPACE_ROOT:+/$KLEAF_REPO_WORKSPACE_ROOT}}"
    """.format(
        hermetic_base = hermetic_tools.internal_hermetic_base,
        run_hermetic_base = hermetic_tools.internal_run_hermetic_base,
        bin_dir = ctx.bin_dir.path,
        kleaf_repo_workspace_root = kleaf_repo_workspace_root,
    )

    post_env = """
        # Increase parallelism # TODO(b/192655643): do not use -j anymore
        export MAKEFLAGS="${{MAKEFLAGS}} -j$(
            make_jobs="$({get_make_jobs_cmd})"
            if [[ -n "$make_jobs" ]]; then
                echo "$make_jobs"
            else
                nproc
            fi
        ) $(
            keep_going="$({get_make_keep_going_cmd})"
            if [[ "$keep_going" == "true" ]]; then
                echo "--keep_going"
            fi
        )"
        # Set up KCONFIG_EXT
        if [ -n "${{KCONFIG_EXT}}" ]; then
            export KCONFIG_EXT_PREFIX=$(realpath $(dirname ${{KCONFIG_EXT}}) --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
        fi
        if [ -n "${{DTSTREE_MAKEFILE}}" ]; then
            export dtstree=$(realpath -s $(dirname ${{DTSTREE_MAKEFILE}}) --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})
        fi

        # Redeclare KERNEL_DIR to be under $KLEAF_REPO_WORKSPACE_ROOT.
        # Only do that if all of the following is true:
        #   - We are setting up the variables for a kernel_filegroup with prebuilt scripts
        #     (KLEAF_FIX_KERNEL_DIR == 1)
        #   - The kernel_build() that originally built these prebuilts was declared at the
        #     root Bazel module in its workspace (we may relax this requirement in the future if
        #     there's a use case)
        # A typical use case for this is that KERNEL_DIR=common in prebuilt scripts, but if @kleaf
        #    is a dependent module and common/ is below @kleaf, then kernel_filegroup need to fix
        #    the value so that KERNEL_DIR=external/kleaf~/common.
        if [ "${{KLEAF_FIX_KERNEL_DIR}}" = 1 ]; then

            if [ -n "{kernel_build_workspace_root}" ]; then
                echo "ERROR: The original kernel_build() that built these prebuilts was " >&2
                echo "    {kernel_build_label}" >&2
                echo "  It is currently not supported to use these prebuilts within a kernel_filegroup." >&2
                echo "  Instead, the kernel_build() should have been built at the root Bazel module." >&2
                echo "  Please contact the provider for these prebuilts to resolve this error." >&2
                exit 1
            fi

            export KERNEL_DIR=${{KLEAF_REPO_WORKSPACE_ROOT:+$KLEAF_REPO_WORKSPACE_ROOT/}}${{KERNEL_DIR}}
        fi

        ## Set up KCPPFLAGS, KCPPFLAGS_COMPAT, and KRUSTFLAGS

        # Replace ${{ROOT_DIR}} with "/proc/self/cwd" in the file name
        # references in the binaries (e.g. debug info).
        # "/proc/self/cwd" is an absolute path that resolves to a directory
        # where debugger runs. And ${{ROOT_DIR}} layout should be the same as
        # layout on the top of the repo, so if you start a debugger from the
        # top directory, all paths should resolve correctly even on another
        # machine.
        export KCPPFLAGS="-ffile-prefix-map=${{ROOT_DIR}}=/proc/self/cwd"
        export KRUSTFLAGS="--remap-path-prefix=${{ROOT_DIR}}=/proc/self/cwd"

        # For Kleaf local (non-sandbox) builds, $ROOT_DIR is under execroot but
        # $ROOT_DIR/$KERNEL_DIR is a symlink to the real source tree under
        # workspace root, making $abs_srctree not under $ROOT_DIR.
        # Because compiler puts a real path to a binary, it should be a real
        # path in -ffile-prefix-map. Also we would like to leave
        # ${{KERNEL_DIR}} part in the path to be able to run debugger from the
        # top directory, so we go one directory up from
        # ${{ROOT_DIR}}/${{KERNEL_DIR}} before calling realpath.
        if [[ "$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}})" != "${{ROOT_DIR}}/${{KERNEL_DIR}}" ]]; then
            export KCPPFLAGS="$KCPPFLAGS -ffile-prefix-map=$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}}/..)=/proc/self/cwd"
            export KRUSTFLAGS="$KRUSTFLAGS --remap-path-prefix=$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}}/..)=/proc/self/cwd"
        fi
        export KCPPFLAGS_COMPAT="$KCPPFLAGS"

        # Set libclang.so location for use by bindgen for Rust
        LIBCLANG_PATH=$(dirname $(which clang))/../lib
        export LIBCLANG_PATH
    """.format(
        get_make_jobs_cmd = status.get_volatile_status_cmd(ctx, "MAKE_JOBS"),
        get_make_keep_going_cmd = status.get_volatile_status_cmd(ctx, "MAKE_KEEP_GOING"),
        kernel_build_workspace_root = ctx.label.workspace_root,
        kernel_build_label = str(ctx.label).removesuffix("_env"),
    )

    return struct(
        pre_env = pre_env,
        post_env = post_env,
    )

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

def _kernel_env_additional_attrs():
    return dicts.add(
        kernel_config_settings.of_kernel_env(),
        kernel_toolchains_utils.attrs(),
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
                  srcs = glob(["build.config.*"]),
              )
          ```
          """,
    attrs = {
        "build_config": attr.label(
            # Allow filegroup with 0 or 1 files.
            allow_files = True,
            doc = "label referring to the main build config",
        ),
        "makefile": attr.label(doc = "Makefile below KERNEL_DIR", allow_single_file = True),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = """labels that this build config refers to, including itself.
            E.g. ["build.config.gki.aarch64", "build.config.gki"]""",
        ),
        "pre_defconfig_fragments": attr.label_list(
            doc = "**pre** defconfig fragments",
            allow_files = True,
        ),
        "post_defconfig_fragments": attr.label_list(
            doc = "**post** defconfig fragments",
            allow_files = True,
        ),
        "setup_env": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:_setup_env"),
            doc = "label referring to _setup_env.sh",
            cfg = "exec",
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
        "kcflags": attr.string_list(),
        "clang_autofdo_profile": attr.label(allow_single_file = True),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils"),
            cfg = "exec",
        ),
        "_debug_annotate_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_annotate_scripts",
        ),
        "_debug_make_verbosity": attr.label(default = "//build/kernel/kleaf:debug_make_verbosity"),
        "_config_is_local": attr.label(default = "//build/kernel/kleaf:config_local"),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_kernel_use_resolved_toolchains": attr.label(
            default = "//build/kernel/kleaf:incompatible_kernel_use_resolved_toolchains",
        ),
        "_cache_dir_config_tags": attr.label(
            default = "//build/kernel/kleaf/impl:cache_dir_config_tags",
            executable = True,
            cfg = "exec",
        ),
    } | _kernel_env_additional_attrs(),
    toolchains = [hermetic_toolchain.type],
    subrules = [
        set_kernel_dir,
        _get_build_config_inputs,
    ],
)
