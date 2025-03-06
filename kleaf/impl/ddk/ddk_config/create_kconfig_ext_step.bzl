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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":common_providers.bzl",
    "StepInfo",
)
load(":utils.bzl", "utils")

visibility("private")

KconfigExtStepInfo = provider(
    "Return value of create_kconfig_ext_step",
    fields = {
        "step_info": "StepInfo",
        "kconfig_ext": """
            The File pointing to kconfig_ext.

            If using kconfig_ext from parent, this is kconfig_ext from parent.

            If using kconfig_ext from kernel_build, this is `None`.
        """,
        "kconfig_ext_source": """
            If optimize_ddk_config_actions:

            -   "kernel_build" if we know we are using KCONFIG_EXT_PREFIX from kernel_build
            -   "parent" if we know we are using kconfig_ext from parent (which may be from kernel_build)
            -   "this" if we know we are creating a new kconfig_ext directory

            Otherwise, this field is not set (hasattr is False).""",
    },
)

def _set_kconfig_ext_dir_cmd(kconfig_ext):
    return """
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            kconfig_ext_dir={kconfig_ext_short}
        else
            kconfig_ext_dir={kconfig_ext}
        fi
    """.format(
        kconfig_ext = kconfig_ext.path,
        kconfig_ext_short = kconfig_ext.short_path,
    )

_WARN_EXTRA_KCONFIG_CMD = """
    (
        echo "WARNING: Adding extra Kconfig files:"
        diff ${parent_kconfig_depset_file} ${combined_kconfig_depset_file} || true
        echo "This may cause an extra olddefconfig step."
        echo
    ) >> ${override_parent_log}
"""

_CHECK_KERNEL_DIR_SET_CMD = """
    if [[ "${KERNEL_DIR}/" == "/" ]]; then
        echo "ERROR: FATAL: KERNEL_DIR is not set!" >&2
        exit 1
    fi
"""

_BACKUP_KCONFIG_EXT_PREFIX_CMD = """
    # Backup the value of KCONFIG_EXT_PREFIX for comparison later.
    OLD_KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}
"""

_SET_KCONFIG_EXT_PREFIX_CMD = """
    KCONFIG_EXT_PREFIX=$(realpath ${kconfig_ext_dir} --relative-to ${ROOT_DIR}/${KERNEL_DIR})/
"""

_COPY_KCONFIG_TO_KCONFIG_EXT_CMD = """
    # Copy all Kconfig files to our new KCONFIG_EXT directory
    rsync -aL --include="*/" --include="Kconfig*" --exclude="*" ${{KERNEL_DIR}}/${{KCONFIG_EXT_PREFIX}} ${{kconfig_ext_dir}}/
    {set_kconfig_ext_prefix_cmd}
    (
        for kconfig in $(cat ${{combined_kconfig_depset_file}}); do
            mod_kconfig_rel=$(realpath ${{ROOT_DIR}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/${{kconfig}}
            echo 'source "'"${{mod_kconfig_rel}}"'"' >> ${{kconfig_ext_dir}}/Kconfig.ext
        done
    )
    # At this point, combined is likely non-empty, so the new KCONFIG_EXT_PREFIX/Kconfig.ext
    # will be different from the old one, triggering olddefconfig.
""".format(set_kconfig_ext_prefix_cmd = _SET_KCONFIG_EXT_PREFIX_CMD)

_USE_PARENT_KCONFIG_EXT_CMD = """
    {set_kconfig_ext_prefix_cmd}

    # Reset OLD_KCONFIG_EXT_PREFIX to not trigger olddefconfig, because we'll prefer .config
    # and include/ from parent by setting ddk_config_using_parent_kconfig_ext=1
    OLD_KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}}
""".format(set_kconfig_ext_prefix_cmd = _SET_KCONFIG_EXT_PREFIX_CMD)

def _create_kconfig_ext_step_compare_in_shell_impl(
        subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        cmd_prefix):
    kconfig_ext = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/kconfig_ext")

    cmd = cmd_prefix
    cmd += _set_kconfig_ext_dir_cmd(kconfig_ext)
    cmd += _BACKUP_KCONFIG_EXT_PREFIX_CMD
    cmd += _CHECK_KERNEL_DIR_SET_CMD

    cmd += """
        # If adding extra kconfig on top of parent, then apply combined on top of existing
        # KCONFIG_EXT_PREFIX from kernel_build.
        if ! diff -q ${{parent_kconfig_depset_file}} ${{combined_kconfig_depset_file}} > /dev/null; then

            {warn_extra_kconfig_cmd}
            {copy_kconfig_to_kconfig_ext_cmd}

        # Otherwise if there's a parent and parent kconfig depset is not empty, use parent's kconfig_ext
        elif [[ -n "${{parent_kconfig_ext_dir}}" ]] && grep -q '\\S' < ${{parent_kconfig_depset_file}}; then

            rsync -aL ${{parent_kconfig_ext_dir}}/ ${{kconfig_ext_dir}}/

            # Prefer .config and include/ from parent.
            ddk_config_using_parent_kconfig_ext=1

            {use_parent_kconfig_ext_cmd}

        # Otherwise do nothing. Copy full KCONFIG_EXT_PREFIX from kernel_build.
        else
            rsync -aL --include="*/" --include="Kconfig*" --exclude="*" ${{KERNEL_DIR}}/${{KCONFIG_EXT_PREFIX}} ${{kconfig_ext_dir}}/
            KCONFIG_EXT_PREFIX=$(realpath ${{kconfig_ext_dir}} --relative-to ${{ROOT_DIR}}/${{KERNEL_DIR}})/
        fi
    """.format(
        warn_extra_kconfig_cmd = _WARN_EXTRA_KCONFIG_CMD,
        copy_kconfig_to_kconfig_ext_cmd = _COPY_KCONFIG_TO_KCONFIG_EXT_CMD,
        use_parent_kconfig_ext_cmd = _USE_PARENT_KCONFIG_EXT_CMD,
    )

    inputs = []
    if parent_outputs_info.kconfig_ext:
        inputs.append(parent_outputs_info.kconfig_ext)

    return KconfigExtStepInfo(
        kconfig_ext = kconfig_ext,
        # Intentionally not set kconfig_ext_source if optimize_ddk_config_actions is not set
        # so we detect places where we don't check the flag properly
        step_info = StepInfo(
            inputs = depset(inputs, transitive = [
                parent_ddk_config_info.kconfig_written.depset,
                combined.kconfig_written.depset,
            ]),
            cmd = cmd,
            tools = [],
            outputs = [kconfig_ext],
        ),
    )

_create_kconfig_ext_step_compare_in_shell = subrule(
    implementation = _create_kconfig_ext_step_compare_in_shell_impl,
)

def _create_kconfig_ext_step_compare_in_analysis_phase_impl(
        subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        cmd_prefix):
    # If adding extra kconfig on top of parent, then apply combined on top of existing
    # KCONFIG_EXT_PREFIX from kernel_build.
    if not utils.depset_equal(
        parent_ddk_config_info.kconfig_written.original_depset,
        combined.kconfig_written.original_depset,
    ):
        kconfig_ext = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/kconfig_ext")

        cmd = cmd_prefix
        cmd += _set_kconfig_ext_dir_cmd(kconfig_ext)
        cmd += _WARN_EXTRA_KCONFIG_CMD
        cmd += _CHECK_KERNEL_DIR_SET_CMD
        cmd += _BACKUP_KCONFIG_EXT_PREFIX_CMD
        cmd += _COPY_KCONFIG_TO_KCONFIG_EXT_CMD

        return KconfigExtStepInfo(
            kconfig_ext = kconfig_ext,
            kconfig_ext_source = "this",
            step_info = StepInfo(
                inputs = depset(transitive = [
                    # We need both depset.txt for comparison. We need Kconfig files from
                    # this target to run `make olddefconfig` later. Hence the full depsets from
                    # WrittenDepsetInfo's are added.
                    parent_ddk_config_info.kconfig_written.depset,
                    combined.kconfig_written.depset,
                ]),
                cmd = cmd,
                tools = [],
                outputs = [kconfig_ext],
            ),
        )

    # Otherwise if parent yields a kconfig_ext dir and parent kconfig depset is not empty, use parent's kconfig_ext
    if parent_outputs_info.kconfig_ext and parent_ddk_config_info.kconfig_written.original_depset:
        # We don't need variables from cmd_prefix.
        cmd = _set_kconfig_ext_dir_cmd(parent_outputs_info.kconfig_ext)
        cmd += _USE_PARENT_KCONFIG_EXT_CMD

        return KconfigExtStepInfo(
            kconfig_ext = parent_outputs_info.kconfig_ext,
            kconfig_ext_source = "parent",
            step_info = StepInfo(
                inputs = depset([parent_outputs_info.kconfig_ext]),
                cmd = cmd,
                tools = [],
                outputs = [],
            ),
        )

    # Otherwise do nothing. Copy full KCONFIG_EXT_PREFIX from kernel_build.
    return KconfigExtStepInfo(
        kconfig_ext = None,
        kconfig_ext_source = "kernel_build",
        step_info = StepInfo(inputs = depset(), cmd = "", tools = [], outputs = []),
    )

_create_kconfig_ext_step_compare_in_analysis_phase = subrule(
    implementation = _create_kconfig_ext_step_compare_in_analysis_phase_impl,
)

def _create_kconfig_ext_step_impl(
        _subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        override_parent_log,
        _optimize_ddk_config_actions):
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
        _optimize_ddk_config_actions: See flag

    Returns:
        KconfigExtStepInfo, where:
            -   step: A step to be used in ddk_config_main_action_subrule. The outputs field contains
                a single file, which is the kconfig_ext directory.
            - See KconfigExtStepInfo for other fields
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

    if _optimize_ddk_config_actions[BuildSettingInfo].value:
        return _create_kconfig_ext_step_compare_in_analysis_phase(
            cmd_prefix = cmd_prefix,
            combined = combined,
            parent_ddk_config_info = parent_ddk_config_info,
            parent_outputs_info = parent_outputs_info,
        )

    return _create_kconfig_ext_step_compare_in_shell(
        cmd_prefix = cmd_prefix,
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
    )

create_kconfig_ext_step = subrule(
    implementation = _create_kconfig_ext_step_impl,
    attrs = {
        "_optimize_ddk_config_actions": attr.label(
            default = "//build/kernel/kleaf:optimize_ddk_config_actions",
        ),
    },
    subrules = [
        _create_kconfig_ext_step_compare_in_shell,
        _create_kconfig_ext_step_compare_in_analysis_phase,
    ],
)
