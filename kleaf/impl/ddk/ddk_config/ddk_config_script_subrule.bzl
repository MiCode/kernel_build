# Copyright (C) 2024 The Android Open Source Project
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

"""Subrule to generate menuconfig script for DDK configuration."""

load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/impl/...")

DdkConfigScriptInfo = provider(
    "Return value of ddk_config_script_subrule",
    fields = {
        "executable": "The executable",
        "runfiles_depset": "depset of files to run",
    },
)

def _ddk_config_script_subrule_impl(
        subrule_ctx,
        kernel_build_ddk_config_env,
        out_dir,
        main_action_ret,
        src_defconfig):
    """Creates script for `bazel run`.

    Args:
        subrule_ctx: subrule_ctx
        kernel_build_ddk_config_env: environment to set up
        out_dir: output directory of this target (may be None if inheriting from kernel_build)
        main_action_ret: from _create_main_action
        src_defconfig: the file pointing to ctx.attr.defconfig; may be none.
    """

    executable = subrule_ctx.actions.declare_file("{}/config.sh".format(subrule_ctx.label.name))
    script = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = kernel_build_ddk_config_env,
        # Not running in a sandbox or in a cache_dir when in `bazel run`.
        restore_out_dir_cmd = "",
    )
    script += """
        # TODO(b/254348147): Support ncurses for hermetic tools
        export HOSTCFLAGS="${{HOSTCFLAGS}} --sysroot="
        export HOSTLDFLAGS="${{HOSTLDFLAGS}} --sysroot="

        usage() {{
            echo "usage: tools/bazel run {label} -- [--stdout] [-f|--file FILE] [<menucommand>]" >&2
        }}

        KLEAF_DDK_CONFIG_EMIT_FILE=
        menucommand=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            --stdout)
                KLEAF_DDK_CONFIG_EMIT_FILE=/dev/stdout
                shift
                ;;
            --file|-f)
                KLEAF_DDK_CONFIG_EMIT_FILE="$2"
                shift 2
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

        if [[ -n "{out_dir}" ]]; then
            rsync -aL --chmod=F+w,F-x {out_dir}/.config ${{OUT_DIR}}/.config
            rsync -aL --chmod=D+w,F+w,F-x {out_dir}/include/ ${{OUT_DIR}}/include/
        fi

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
        out_dir = utils.optional_short_path(out_dir),
        kconfig_ext_cmd = main_action_ret.kconfig_ext_step.step_info.cmd,
        label = subrule_ctx.label,
    )
    if src_defconfig:
        script += """
            KCONFIG_CONFIG=${{new_config}} ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh -m {src_defconfig} ${{changed_config}} > /dev/null
            if [ -n "${{KLEAF_DDK_CONFIG_EMIT_FILE}}" ]; then
                sort_config ${{new_config}} > "${{KLEAF_DDK_CONFIG_EMIT_FILE}}"
            else
                sort_config ${{new_config}} > $(realpath {src_defconfig})
                echo "Updated $(realpath {src_defconfig})"
            fi
        """.format(
            src_defconfig = src_defconfig.short_path,
        )
    else:
        script += """
            if [ -n "${{KLEAF_DDK_CONFIG_EMIT_FILE}}" ]; then
                sort_config ${{new_config}} > "${{KLEAF_DDK_CONFIG_EMIT_FILE}}"
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
        kernel_build_ddk_config_env.setup_script,
    ]
    if out_dir:
        direct_runfiles.append(out_dir)
    if src_defconfig:
        direct_runfiles.append(src_defconfig)
    runfiles_depset = depset(
        direct_runfiles,
        transitive = [
            kernel_build_ddk_config_env.inputs,
            kernel_build_ddk_config_env.tools,
            main_action_ret.kconfig_ext_step.step_info.inputs,
            depset(main_action_ret.kconfig_ext_step.step_info.tools),
        ],
    )

    return DdkConfigScriptInfo(
        executable = executable,
        runfiles_depset = runfiles_depset,
    )

ddk_config_script_subrule = subrule(
    implementation = _ddk_config_script_subrule_impl,
)
