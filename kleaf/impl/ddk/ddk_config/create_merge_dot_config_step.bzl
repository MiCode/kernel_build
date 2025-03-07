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

"""Creates a step that merges .config."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":common_providers.bzl",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")
load(":ddk/ddk_config/ddk_config_restore_out_dir_step.bzl", "ddk_config_restore_out_dir_step")
load(":utils.bzl", "utils")

visibility("private")

MergeDotConfigStepInfo = provider(
    """Return value of create_merge_dot_config_step""",
    fields = {
        "step_info": "StepInfo",
        "maybe_dot_config_modified": """
            If optimize_ddk_config_actions:

            -   True if .config might have been modified
            -   False if .config definitely haven't been modified.

            Otherwise, this field is not set (hasattr is False).
        """,
    },
)

_BACKUP_DOT_CONFIG_CMD = """
    # Backup existing .config for comparison later. The .config.old is a snapshot of the
    # existing $kleaf_out_dir_include_candidate.
    cp ${OUT_DIR}/.config ${OUT_DIR}/.config.old
"""

def _warn_extra_defconfig_cmd(
        parent_ddk_config_info,
        combined,
        override_parent_log):
    return """
        (
            echo "WARNING: Adding extra defconfig files:"
            diff {parent_defconfig_depset} {combined_defconfig_depset} || true
            echo "This may cause an extra olddefconfig step."
            echo
        ) >> {override_parent_log}
    """.format(
        combined_defconfig_depset = combined.defconfig_written.depset_file.path,
        parent_defconfig_depset = parent_ddk_config_info.defconfig_written.depset_file.path,
        override_parent_log = override_parent_log.path,
    )

def _create_merge_dot_config_step_in_shell_impl(
        _subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        override_parent_log):
    restore_parent_out_dir = ddk_config_restore_out_dir_step(
        out_dir = parent_outputs_info.out_dir,
    )

    cmd = """
        {backup_dot_config_cmd}

        if [[ -z "${{ddk_config_using_parent_kconfig_ext}}" ]]; then
            echo "ERROR: create_merge_dot_config_step should be invoked after create_kconfig_ext_step!" >&2
            exit 1
        fi

        # If adding extra defconfig on top of parent, then merge combined defconfig depset on
        # kernel_build's .config
        if ! diff -q {parent_defconfig_depset} {combined_defconfig_depset} > /dev/null; then

            {warn_extra_defconfig_cmd}

            {merge_combined_defconfig_on_kernel_build_dot_config}
            # If .config changes, it differs from .config.old and will trigger olddefconfig later.

        # Otherwise if parent defconfig depset is not empty, use parent's .config and include/ directly
        # Also, if using parent's Kconfig.ext directly, also sync parent's .config and set
        # kleaf_out_dir_include_candidate to parent's include/
        #   make sure .config has the correct default values from parent's Kconfig.ext
        elif grep -q '\\S' < {parent_defconfig_depset} || [[ "${{ddk_config_using_parent_kconfig_ext}}" == "1" ]]; then
            {restore_parent_out_dir_cmd}
            # Because kleaf_out_dir_include_candidate is updated, update .config.old to maybe skip
            # olddefconfig.
            cp ${{OUT_DIR}}/.config ${{OUT_DIR}}/.config.old

        # Otherwise nothing to do. Use kernel_build's .config directly
        fi

        # We don't need the value of ddk_config_using_parent_kconfig_ext any more after merging .config.
        unset ddk_config_using_parent_kconfig_ext
    """.format(
        backup_dot_config_cmd = _BACKUP_DOT_CONFIG_CMD,
        combined_defconfig_depset = combined.defconfig_written.depset_file.path,
        parent_defconfig_depset = parent_ddk_config_info.defconfig_written.depset_file.path,
        warn_extra_defconfig_cmd = _warn_extra_defconfig_cmd(
            parent_ddk_config_info = parent_ddk_config_info,
            combined = combined,
            override_parent_log = override_parent_log,
        ),
        merge_combined_defconfig_on_kernel_build_dot_config = config_utils.create_merge_config_cmd(
            base_expr = "${OUT_DIR}/.config",
            defconfig_fragments_paths_expr = "$(cat {})".format(combined.defconfig_written.depset_file.path),
        ),
        restore_parent_out_dir_cmd = restore_parent_out_dir.cmd,
    )

    return MergeDotConfigStepInfo(
        # Intentionally not set maybe_dot_config_modified if optimize_ddk_config_actions is not set
        step_info = StepInfo(
            inputs = depset(transitive = [
                combined.defconfig_written.depset,
                parent_ddk_config_info.defconfig_written.depset,
                restore_parent_out_dir.inputs,
            ]),
            cmd = cmd,
            tools = restore_parent_out_dir.tools,
            outputs = restore_parent_out_dir.outputs,
        ),
    )

_create_merge_dot_config_step_in_shell = subrule(
    implementation = _create_merge_dot_config_step_in_shell_impl,
    subrules = [
        ddk_config_restore_out_dir_step,
    ],
)

def _create_merge_dot_config_step_in_analysis_phase_impl(
        _subrule_ctx,
        *,
        kconfig_ext_step,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        override_parent_log):
    # If adding extra defconfig on top of parent, then merge combined defconfig depset on
    # kernel_build's .config
    if not utils.depset_equal(
        parent_ddk_config_info.defconfig_written.original_depset,
        combined.defconfig_written.original_depset,
    ):
        cmd = _BACKUP_DOT_CONFIG_CMD
        cmd += _warn_extra_defconfig_cmd(
            parent_ddk_config_info = parent_ddk_config_info,
            combined = combined,
            override_parent_log = override_parent_log,
        )
        cmd += config_utils.create_merge_config_cmd(
            base_expr = "${OUT_DIR}/.config",
            defconfig_fragments_paths_expr = "$(cat {})".format(combined.defconfig_written.depset_file.path),
        )

        # If .config changes, it differs from .config.old and will trigger olddefconfig later.

        return MergeDotConfigStepInfo(
            maybe_dot_config_modified = True,
            step_info = StepInfo(
                inputs = depset(transitive = [
                    combined.defconfig_written.depset,
                    parent_ddk_config_info.defconfig_written.depset,
                ]),
                cmd = cmd,
                tools = [],
                outputs = [],
            ),
        )

    # Otherwise if parent defconfig depset is not empty, use parent's .config and include/ directly
    # Also, if using parent's Kconfig.ext directly, also sync parent's .config and set
    # kleaf_out_dir_include_candidate to parent's include/
    #   make sure .config has the correct default values from parent's Kconfig.ext
    if parent_ddk_config_info.defconfig_written.original_depset and kconfig_ext_step.kconfig_ext_source == "parent":
        restore_parent_out_dir = ddk_config_restore_out_dir_step(
            out_dir = parent_outputs_info.out_dir,
        )
        cmd = _BACKUP_DOT_CONFIG_CMD
        cmd += restore_parent_out_dir.cmd
        cmd += """
            # Because kleaf_out_dir_include_candidate is updated, update .config.old to maybe skip
            # olddefconfig.
            cp ${OUT_DIR}/.config ${OUT_DIR}/.config.old
        """
        return MergeDotConfigStepInfo(
            maybe_dot_config_modified = False,
            step_info = StepInfo(
                inputs = restore_parent_out_dir.inputs,
                cmd = cmd,
                tools = restore_parent_out_dir.tools,
                outputs = restore_parent_out_dir.outputs,
            ),
        )

    # Otherwise nothing to do. Use kernel_build's .config directly
    return MergeDotConfigStepInfo(
        maybe_dot_config_modified = False,
        step_info = StepInfo(
            inputs = depset(),
            # TODO: b/400799412 - delete this CMD once all users of .config.old
            #   in ddk_config/ddk_module_config is handling optimize_ddk_config_actions flag
            #   properly.
            cmd = _BACKUP_DOT_CONFIG_CMD,
            tools = [],
            outputs = [],
        ),
    )

_create_merge_dot_config_step_in_analysis_phase = subrule(
    implementation = _create_merge_dot_config_step_in_analysis_phase_impl,
    subrules = [
        ddk_config_restore_out_dir_step,
    ],
)

def _create_merge_dot_config_step_impl(
        _subrule_ctx,
        *,
        kconfig_ext_step,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        override_parent_log,
        _optimize_ddk_config_actions):
    """Creates a step that applies defconfig fragments on .config.

    Args:
        _subrule_ctx: subrule_ctx
        kconfig_ext_step: KconfigExtStepInfo from create_kconfig_ext_step
        combined: Combined DdkConfigInfo (parent + this target)
        parent_ddk_config_info: The parent DdkConfigInfo
        parent_outputs_info: The parent DdkConfigOutputsInfo
        override_parent_log: This step writes to this log file to explain why this target would
            have required extra `make olddefconfig` on top of parent.

            This is not added to outputs list of the step, even though the step appends to this log.
            The caller should put this in the output list of the action.
        _optimize_ddk_config_actions: see flag

    Returns:
        MergeDotConfigStepInfo
    """
    if _optimize_ddk_config_actions[BuildSettingInfo].value:
        return _create_merge_dot_config_step_in_analysis_phase(
            kconfig_ext_step = kconfig_ext_step,
            combined = combined,
            parent_ddk_config_info = parent_ddk_config_info,
            parent_outputs_info = parent_outputs_info,
            override_parent_log = override_parent_log,
        )
    return _create_merge_dot_config_step_in_shell(
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
        override_parent_log = override_parent_log,
    )

create_merge_dot_config_step = subrule(
    implementation = _create_merge_dot_config_step_impl,
    attrs = {
        "_optimize_ddk_config_actions": attr.label(
            default = "//build/kernel/kleaf:optimize_ddk_config_actions",
        ),
    },
    subrules = [
        _create_merge_dot_config_step_in_shell,
        _create_merge_dot_config_step_in_analysis_phase,
    ],
)
