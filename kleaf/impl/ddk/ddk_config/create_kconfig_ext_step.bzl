# Copyright (C) 2025 The Android Open Source Project
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

"""Creates a step that generates kconfig_ext."""

load(
    ":common_providers.bzl",
    "StepInfo",
)
load(":utils.bzl", "utils")

visibility("private")

def _create_kconfig_ext_step_compare_in_shell_impl(
        subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        cmd_prefix):
    kconfig_ext = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/kconfig_ext")
    cmd = cmd_prefix + """
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            kconfig_ext_dir={kconfig_ext_short}
        else
            kconfig_ext_dir={kconfig_ext}
        fi

        # Backup the value of KCONFIG_EXT_PREFIX for comparison later.
        OLD_KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}}

        # Copy all Kconfig files to our new KCONFIG_EXT directory
        if [[ "${{KERNEL_DIR}}/" == "/" ]]; then
            echo "ERROR: FATAL: KERNEL_DIR is not set!" >&2
            exit 1
        fi

        # If adding extra kconfig on top of parent, then apply combined on top of existing
        # KCONFIG_EXT_PREFIX from kernel_build.
        if ! diff -q ${{parent_kconfig_depset_file}} ${{combined_kconfig_depset_file}} > /dev/null; then

            (
                echo "WARNING: Adding extra Kconfig files:"
                diff ${{parent_kconfig_depset_file}} ${{combined_kconfig_depset_file}} || true
                echo "This may cause an extra olddefconfig step."
                echo
            ) >> ${{override_parent_log}}

            rsync -aL --include="*/" --include="Kconfig*" --exclude="*" ${{KERNEL_DIR}}/${{KCONFIG_EXT_PREFIX}} ${{kconfig_ext_dir}}/
            KCONFIG_EXT_PREFIX=$(realpath ${{kconfig_ext_dir}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
            (
                for kconfig in $(cat ${{combined_kconfig_depset_file}}); do
                    mod_kconfig_rel=$(realpath ${{ROOT_DIR}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/${{kconfig}}
                    echo 'source "'"${{mod_kconfig_rel}}"'"' >> ${{kconfig_ext_dir}}/Kconfig.ext
                done
            )
            # At this point, combined is likely non-empty, so the new KCONFIG_EXT_PREFIX/Kconfig.ext
            # will be different from the old one, triggering olddefconfig.

        # Otherwise if there's a parent and parent kconfig depset is not empty, use parent's kconfig_ext
        elif [[ -n "${{parent_kconfig_ext_dir}}" ]] && grep -q '\\S' < ${{parent_kconfig_depset_file}}; then

            rsync -aL ${{parent_kconfig_ext_dir}}/ ${{kconfig_ext_dir}}/
            KCONFIG_EXT_PREFIX=$(realpath ${{kconfig_ext_dir}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/

            # Prefer .config and include/ from parent.
            ddk_config_using_parent_kconfig_ext=1

            # Reset OLD_KCONFIG_EXT_PREFIX to not trigger olddefconfig, because we'll prefer .config
            # and include/ from parent by setting ddk_config_using_parent_kconfig_ext=1
            OLD_KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}}

        # Otherwise do nothing. Copy full KCONFIG_EXT_PREFIX from kernel_build.
        else
            rsync -aL --include="*/" --include="Kconfig*" --exclude="*" ${{KERNEL_DIR}}/${{KCONFIG_EXT_PREFIX}} ${{kconfig_ext_dir}}/
            KCONFIG_EXT_PREFIX=$(realpath ${{kconfig_ext_dir}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
        fi
    """.format(
        kconfig_ext = kconfig_ext.path,
        kconfig_ext_short = kconfig_ext.short_path,
    )

    inputs = []
    if parent_outputs_info.kconfig_ext:
        inputs.append(parent_outputs_info.kconfig_ext)

    return StepInfo(
        inputs = depset(inputs, transitive = [
            parent_ddk_config_info.kconfig_written.depset,
            combined.kconfig_written.depset,
        ]),
        cmd = cmd,
        tools = [],
        outputs = [kconfig_ext],
    )

_create_kconfig_ext_step_compare_in_shell = subrule(
    implementation = _create_kconfig_ext_step_compare_in_shell_impl,
)

def _create_kconfig_ext_step_impl(
        _subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        override_parent_log):
    """Creates a step to create the KCONFIG_EXT directory for this target.

    After the command of this step is executed, a kconfig_ext directory is created, and
    KCONFIG_EXT_PREFIX is set to be the path of it relative to KERNEL_DIR.

    Args:
        _subrule_ctx: subrule_ctx
        combined: The combined DdkConfigInfo (parent + this target)
        parent_ddk_config_info: The parent DdkConfigInfo
        parent_outputs_info: The parent DdkConfigOutputsInfo
        override_parent_log: This step writes to this log file to explain why this target would
            have required extra `make olddefconfig` on top of parent.

            This is not added to outputs list of the step, even though the step appends to this log.
            The caller should put this in the output list of the action.

    Returns:
        A step to be used in ddk_config_main_action_subrule. The outputs field contains
        a single file, which is the kconfig_ext directory.
    """

    cmd_prefix = """
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            parent_kconfig_depset_file={parent_kconfig_depset_file_short}
            combined_kconfig_depset_file={combined_kconfig_depset_file_short}
            parent_kconfig_ext_dir={parent_kconfig_ext_short}
            override_parent_log={override_parent_log_short}
        else
            parent_kconfig_depset_file={parent_kconfig_depset_file}
            combined_kconfig_depset_file={combined_kconfig_depset_file}
            parent_kconfig_ext_dir={parent_kconfig_ext}
            override_parent_log={override_parent_log}
        fi

        ddk_config_using_parent_kconfig_ext=0
    """.format(
        parent_kconfig_depset_file = parent_ddk_config_info.kconfig_written.depset_file.path,
        combined_kconfig_depset_file = combined.kconfig_written.depset_file.path,
        parent_kconfig_ext = utils.optional_path(parent_outputs_info.kconfig_ext),
        override_parent_log = override_parent_log.path,
        parent_kconfig_depset_file_short = parent_ddk_config_info.kconfig_written.depset_short_file.short_path,
        combined_kconfig_depset_file_short = combined.kconfig_written.depset_short_file.short_path,
        parent_kconfig_ext_short = utils.optional_short_path(parent_outputs_info.kconfig_ext),
        override_parent_log_short = override_parent_log.short_path,
    )

    return _create_kconfig_ext_step_compare_in_shell(
        cmd_prefix = cmd_prefix,
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
    )

create_kconfig_ext_step = subrule(
    implementation = _create_kconfig_ext_step_impl,
    subrules = [
        _create_kconfig_ext_step_compare_in_shell,
    ],
)
