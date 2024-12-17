# Copyright (C) 2023 The Android Open Source Project
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

"""A target that configures a [`ddk_module`](#ddk_module)."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelSerializedEnvInfo",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")
load(":ddk/ddk_config/ddk_config_info_subrule.bzl", "ddk_config_info_subrule")
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

def _ddk_config_impl(ctx):
    out_dir = ctx.actions.declare_directory(ctx.attr.name + "/out_dir")
    ddk_config_info = ddk_config_info_subrule(
        kconfig_targets = [ctx.attr.kconfig] if ctx.attr.kconfig else [],
        defconfig_targets = [ctx.attr.defconfig] if ctx.attr.defconfig else [],
        deps = ctx.attr.module_deps + ctx.attr.module_hdrs,
        extra_defconfigs = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_module_defconfig_fragments,
    )

    main_action_ret = _create_main_action(
        ctx = ctx,
        out_dir = out_dir,
        ddk_config_info = ddk_config_info,
    )

    serialized_env_info = _create_serialized_env_info(
        ctx = ctx,
        out_dir = out_dir,
    )

    _menuconfig_ret = _get_config_script(
        serialized_env_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        out_dir = out_dir,
        main_action_ret = main_action_ret,
        src_defconfig = ctx.file.defconfig,
    )

    return [
        DefaultInfo(
            files = depset([out_dir]),
            executable = _menuconfig_ret.executable,
            runfiles = ctx.runfiles(transitive_files = _menuconfig_ret.runfiles_depset),
        ),
        serialized_env_info,
        ddk_config_info,
    ]

def _create_merge_dot_config_step(defconfig_depset_written):
    defconfig_depset_file = defconfig_depset_written.depset_file
    cmd = """
        if grep -q '\\S' {defconfig_depset_file} ; then
            {merge_dot_config_cmd}
        fi
    """.format(
        defconfig_depset_file = defconfig_depset_file.path,
        merge_dot_config_cmd = config_utils.create_merge_config_cmd(
            base_expr = "${OUT_DIR}/.config",
            defconfig_fragments_paths_expr = "$(cat {})".format(defconfig_depset_file.path),
        ),
    )

    return StepInfo(
        inputs = defconfig_depset_written.depset,
        cmd = cmd,
        tools = [],
        outputs = [],
    )

def _create_kconfig_ext_step(ctx, kconfig_depset_written):
    run_intermediates_dir = paths.join(
        ctx.label.workspace_root,
        ctx.label.package,
        ctx.label.name + "_intermediates",
    )
    intermediates_dir = utils.intermediates_dir(ctx)

    cmd = """
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            kconfig_depset_file={kconfig_depset_file_short}
            intermediates_dir={run_intermediates_dir}
        else
            kconfig_depset_file={kconfig_depset_file}
            intermediates_dir={intermediates_dir}
        fi

        mkdir -p ${{intermediates_dir}}

        # Copy all Kconfig files to our new KCONFIG_EXT directory
        if [[ "${{KERNEL_DIR}}/" == "/" ]]; then
            echo "ERROR: FATAL: KERNEL_DIR is not set!" >&2
            exit 1
        fi
        rsync -aL --include="*/" --include="Kconfig*" --exclude="*" ${{KERNEL_DIR}}/${{KCONFIG_EXT_PREFIX}} ${{intermediates_dir}}/

        KCONFIG_EXT_PREFIX=$(realpath ${{ROOT_DIR}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/${{intermediates_dir}}/

        # Source Kconfig from depending modules
        if grep -q '\\S' < ${{kconfig_depset_file}} ; then
            (
                for kconfig in $(cat ${{kconfig_depset_file}}); do
                    mod_kconfig_rel=$(realpath ${{ROOT_DIR}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/${{kconfig}}
                    echo 'source "'"${{mod_kconfig_rel}}"'"' >> ${{intermediates_dir}}/Kconfig.ext
                done
            )
        fi
    """.format(
        intermediates_dir = intermediates_dir,
        run_intermediates_dir = run_intermediates_dir,
        kconfig_depset_file = kconfig_depset_written.depset_file.path,
        kconfig_depset_file_short = kconfig_depset_written.depset_file.short_path,
    )

    return StepInfo(
        inputs = kconfig_depset_written.depset,
        cmd = cmd,
        tools = [],
        outputs = [],
    )

def _create_oldconfig_step(ctx, defconfig_depset_written, kconfig_depset_written):
    cmd = """
        if grep -q '\\S' < {defconfig_depset_file} || grep -q '\\S' < {kconfig_depset_file} ; then
            # Regenerate include/.
            # We could also run `make syncconfig` but syncconfig is an implementation detail
            # of Kbuild. Hence, just wipe out include/ to force it to be re-regenerated.
            rm -rf ${{OUT_DIR}}/include

            # Use olddefconfig because we want to use the (new and combined) .config as base, and
            # set unspecified values to their default value.
            make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} \\
                KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}} \\
                olddefconfig
        fi
    """.format(
        defconfig_depset_file = defconfig_depset_written.depset_file.path,
        kconfig_depset_file = kconfig_depset_written.depset_file.path,
    )

    transitive_inputs = [
        defconfig_depset_written.depset,
        kconfig_depset_written.depset,
    ]
    tools = []
    outputs = []

    if ctx.file.defconfig:
        check_defconfig_step = config_utils.create_check_defconfig_step(
            defconfig = None,
            pre_defconfig_fragments = [],
            post_defconfig_fragments = [ctx.file.defconfig],
        )
        transitive_inputs.append(check_defconfig_step.inputs)
        tools += check_defconfig_step.tools
        outputs += check_defconfig_step.outputs
        cmd += """
            # Check that configs in my defconfig are still there
            # This does not include defconfig from dependencies, because values from
            # dependencies could technically be overridden by this target.
            {check_defconfig_cmd}
        """.format(
            check_defconfig_cmd = check_defconfig_step.cmd,
        )

    return StepInfo(
        inputs = depset(
            ctx.files.defconfig,
            transitive = transitive_inputs,
        ),
        cmd = cmd,
        tools = tools,
        outputs = outputs,
    )

def _create_main_action(
        ctx,
        out_dir,
        ddk_config_info):
    """Registers the main action that creates the output files."""

    kconfig_depset_written = utils.write_depset(ddk_config_info.kconfig, "kconfig_depset.txt")
    defconfig_depset_written = utils.write_depset(ddk_config_info.defconfig, "defconfig_depset.txt")

    ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env

    transitive_inputs = [
        ddk_config_env.inputs,
    ]

    tools = [ddk_config_env.tools]
    outputs = [out_dir]

    merge_dot_config_step = _create_merge_dot_config_step(
        defconfig_depset_written = defconfig_depset_written,
    )
    kconfig_ext_step = _create_kconfig_ext_step(
        ctx = ctx,
        kconfig_depset_written = kconfig_depset_written,
    )
    oldconfig_step = _create_oldconfig_step(
        ctx = ctx,
        defconfig_depset_written = defconfig_depset_written,
        kconfig_depset_written = kconfig_depset_written,
    )

    steps = [
        merge_dot_config_step,
        kconfig_ext_step,
        oldconfig_step,
    ]

    for step in steps:
        transitive_inputs.append(step.inputs)
        tools += step.tools
        outputs += step.outputs

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = ddk_config_env,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += kernel_utils.set_src_arch_cmd()
    command += """
        {merge_config_cmd}
        {kconfig_ext_cmd}
        {oldconfig_cmd}

        # Copy outputs
        rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
        rsync -aL ${{OUT_DIR}}/include/ {out_dir}/include/

        rm -rf ${{intermediates_dir}}
    """.format(
        merge_config_cmd = merge_dot_config_step.cmd,
        kconfig_ext_cmd = kconfig_ext_step.cmd,
        oldconfig_cmd = oldconfig_step.cmd,
        out_dir = out_dir.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = depset(transitive = transitive_inputs),
        tools = tools,
        outputs = outputs,
        command = command,
        mnemonic = "DdkConfig",
        progress_message = "Creating DDK module configuration %{label}",
    )

    return struct(
        kconfig_ext_step = kconfig_ext_step,
    )

def _create_serialized_env_info(ctx, out_dir):
    """Creates info for module build."""

    # Info from kernel_build
    if ctx.attr.generate_btf:
        # All outputs are required for BTF generation, including vmlinux image
        pre_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].mod_full_env
    else:
        pre_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].mod_min_env

    # Overlay module-specific configs
    setup_script_cmd = """
        . {pre_setup_script}
        rsync -aL {out_dir}/.config ${{OUT_DIR}}/.config
        rsync -aL --chmod=D+w {out_dir}/include/ ${{OUT_DIR}}/include/
    """.format(
        pre_setup_script = pre_info.setup_script.path,
        out_dir = out_dir.path,
    )
    setup_script = ctx.actions.declare_file("{name}/{name}_setup.sh".format(name = ctx.attr.name))
    ctx.actions.write(
        output = setup_script,
        content = setup_script_cmd,
    )
    return KernelSerializedEnvInfo(
        setup_script = setup_script,
        inputs = depset([out_dir, setup_script], transitive = [pre_info.inputs]),
        tools = pre_info.tools,
    )

def _get_config_script_impl(
        subrule_ctx,
        serialized_env_info,
        out_dir,
        main_action_ret,
        src_defconfig):
    """Creates script for `bazel run`.

    Args:
        subrule_ctx: subrule_ctx
        serialized_env_info: environment to set up
        out_dir: output directory of this target
        main_action_ret: from _create_main_action
        src_defconfig: the file pointing to ctx.attr.defconfig; may be none.
    """

    executable = subrule_ctx.actions.declare_file("{}/config.sh".format(subrule_ctx.label.name))
    script = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = serialized_env_info,
        # Not running in a sandbox or in a cache_dir when in `bazel run`.
        restore_out_dir_cmd = "",
    )
    script += """
        # TODO(b/254348147): Support ncurses for hermetic tools
        export HOSTCFLAGS="${{HOSTCFLAGS}} --sysroot="
        export HOSTLDFLAGS="${{HOSTLDFLAGS}} --sysroot="

        usage() {{
            echo "usage: tools/bazel run {label} -- [--stdout] [<menucommand>]" >&2
        }}

        KLEAF_DDK_CONFIG_EMIT_STDOUT=
        menucommand=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            --stdout)
                KLEAF_DDK_CONFIG_EMIT_STDOUT=1
                shift
                ;;
            -*)
                usage
                exit 1
                ;;
            *)
                if [ -n "$menucommand" ]; then
                    usage
                    exit 1
                fi
                menucommand="$1"
                shift
                ;;
            esac
        done
        if [ -z "$menucommand" ]; then
            menucommand="${{1:-savedefconfig}}"
        fi

        if ! [[ "${{menucommand}}" =~ .*config ]]; then
            echo "Invalid command ${{menucommand}}. Must be *config." >&2
            exit 1
        fi
        mkdir -p ${{OUT_DIR}}
        rsync -aL --chmod=F+w,F-x {out_dir}/.config ${{OUT_DIR}}/.config
        rsync -aL --chmod=D+w,F+w,F-x {out_dir}/include/ ${{OUT_DIR}}/include/

        (
            orig_config=$(mktemp)
            changed_config=$(mktemp)
            new_config=$(mktemp)
            trap "rm -f ${{orig_config}} ${{changed_config}} ${{new_config}}" EXIT
            cp "${{OUT_DIR}}/.config" ${{orig_config}}

            {kconfig_ext_cmd}

            make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} \\
                KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}} \\
                ${{menucommand}}

            ${{KERNEL_DIR}}/scripts/diffconfig -m ${{orig_config}} ${{OUT_DIR}}/.config > ${{changed_config}}
    """.format(
        out_dir = out_dir.short_path,
        kconfig_ext_cmd = main_action_ret.kconfig_ext_step.cmd,
        label = subrule_ctx.label,
    )
    if src_defconfig:
        script += """
            KCONFIG_CONFIG=${{new_config}} ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh -m {src_defconfig} ${{changed_config}} > /dev/null
            if [ "${{KLEAF_DDK_CONFIG_EMIT_STDOUT}}" = 1 ]; then
                sort_config ${{new_config}}
            else
                sort_config ${{new_config}} > $(realpath {src_defconfig})
                echo "Updated $(realpath {src_defconfig})"
            fi
        """.format(
            src_defconfig = src_defconfig.short_path,
        )
    else:
        script += """
            if [ "${{KLEAF_DDK_CONFIG_EMIT_STDOUT}}" = 1 ]; then
                sort_config ${{new_config}}
            else
                sorted_new_fragment=$(mktemp)
                sort_config ${{new_config}} > ${{sorted_new_fragment}}
                echo "ERROR: Unable to update any file because defconfig is not set." >&2
                echo "    Please manually set the defconfig attribute of {label} to a file containing" >&2
                echo "    ${{sorted_new_fragment}}" >&2
                # Intentionally not delete sorted_new_fragment
            fi
            exit 1
        """.format(
            label = str(subrule_ctx.label).removesuffix("_config"),
        )

    script += """
        )
    """

    subrule_ctx.actions.write(executable, script, is_executable = True)

    direct_runfiles = [
        serialized_env_info.setup_script,
        out_dir,
    ]
    if src_defconfig:
        direct_runfiles.append(src_defconfig)
    runfiles_depset = depset(
        direct_runfiles,
        transitive = [
            serialized_env_info.inputs,
            serialized_env_info.tools,
            main_action_ret.kconfig_ext_step.inputs,
            depset(main_action_ret.kconfig_ext_step.tools),
        ],
    )

    return struct(
        executable = executable,
        runfiles_depset = runfiles_depset,
    )

_get_config_script = subrule(
    implementation = _get_config_script_impl,
)

ddk_config = rule(
    implementation = _ddk_config_impl,
    doc = "A target that configures a [`ddk_module`](#ddk_module).",
    attrs = {
        "kernel_build": attr.label(
            doc = "[`kernel_build`](#kernel_build).",
            providers = [
                KernelBuildExtModuleInfo,
            ],
            mandatory = True,
        ),
        "kconfig": attr.label(
            allow_single_file = True,
            doc = """The `Kconfig` file for this external module.

See
[`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
for its format.
""",
        ),
        "defconfig": attr.label(
            allow_single_file = True,
            doc = "The `defconfig` file.",
        ),
        # Needed to compose DdkConfigInfo
        "module_deps": attr.label_list(),
        # allow_files = True because https://github.com/bazelbuild/bazel/issues/7516
        "module_hdrs": attr.label_list(allow_files = True),
        "generate_btf": attr.bool(
            default = False,
            doc = "See [kernel_module.generate_btf](#kernel_module-generate_btf)",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    subrules = [
        ddk_config_info_subrule,
        utils.write_depset,
        config_utils.create_check_defconfig_step,
        _get_config_script,
    ],
    executable = True,
)
