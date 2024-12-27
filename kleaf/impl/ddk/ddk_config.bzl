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

load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelSerializedEnvInfo",
)
load(":ddk/ddk_config/ddk_config_info_subrule.bzl", "ddk_config_info_subrule")
load(":ddk/ddk_config/ddk_config_main_action_subrule.bzl", "ddk_config_main_action_subrule")
load(":utils.bzl", "kernel_utils")

visibility("//build/kernel/kleaf/...")

def _ddk_config_impl(ctx):
    ddk_config_info = ddk_config_info_subrule(
        kconfig_targets = [ctx.attr.kconfig] if ctx.attr.kconfig else [],
        defconfig_targets = [ctx.attr.defconfig] if ctx.attr.defconfig else [],
        deps = ctx.attr.module_deps + ctx.attr.module_hdrs,
        extra_defconfigs = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_module_defconfig_fragments,
    )

    main_action_ret = ddk_config_main_action_subrule(
        bin_dir_path = ctx.bin_dir.path,
        ddk_config_info = ddk_config_info,
        kernel_build_ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        defconfig_files = ctx.files.defconfig,
    )

    serialized_env_info = _create_serialized_env_info(
        ctx = ctx,
        out_dir = main_action_ret.out_dir,
    )

    _menuconfig_ret = _get_config_script(
        serialized_env_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        out_dir = main_action_ret.out_dir,
        main_action_ret = main_action_ret,
        src_defconfig = ctx.file.defconfig,
    )

    return [
        DefaultInfo(
            files = depset([main_action_ret.out_dir]),
            executable = _menuconfig_ret.executable,
            runfiles = ctx.runfiles(transitive_files = _menuconfig_ret.runfiles_depset),
        ),
        serialized_env_info,
        ddk_config_info,
    ]

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
    },
    subrules = [
        ddk_config_info_subrule,
        ddk_config_main_action_subrule,
        _get_config_script,
    ],
    executable = True,
)
