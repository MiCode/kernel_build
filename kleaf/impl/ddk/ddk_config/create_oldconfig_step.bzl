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

"""Creates a step that runs make olddefconfig"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":common_providers.bzl",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")

visibility("private")

def _create_oldconfig_step_in_shell_impl(
        _subrule_ctx,
        combined,
        defconfig_files,
        has_parent,
        override_parent,
        override_parent_log):
    cmd = """
        if ! diff -q ${{OUT_DIR}}/.config.old ${{OUT_DIR}}/.config > /dev/null || \\
            ! ( cd ${{KERNEL_DIR}}; diff -q ${{OLD_KCONFIG_EXT_PREFIX}}Kconfig.ext ${{KCONFIG_EXT_PREFIX}}Kconfig.ext ) > /dev/null
        then
            (
                echo "ERROR: detected defconfig/Kconfig changes, triggering olddefconfig."
                echo "Changes in .config:"
                diff ${{OUT_DIR}}/.config.old ${{OUT_DIR}}/.config || true
                echo "Changes in Kconfig:"
                ( cd ${{KERNEL_DIR}}; diff -q ${{OLD_KCONFIG_EXT_PREFIX}}Kconfig.ext ${{KCONFIG_EXT_PREFIX}}Kconfig.ext || true )
                echo
            ) >> {override_parent_log}

            if {has_parent} && [[ "{override_parent}" == "deny" ]]; then
                cat {override_parent_log} >&2
                exit 1
            fi

            # Use olddefconfig because we want to use the (new and combined) .config as base, and
            # set unspecified values to their default value.
            make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} \\
                KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}} \\
                olddefconfig

            # Tell oldconfig_step to capture $OUT_DIR/include instead.
            kleaf_out_dir_include_candidate="${{OUT_DIR}}/include/"
            kleaf_auto_conf_cmd_replace_variables=1

        elif [[ "{override_parent}" == "expect_override" ]]; then
            echo "ERROR: Expecting target to override parent values, but not overriding anything!" >&2
            exit 1
        fi

        rm -f ${{OUT_DIR}}/.config.old
        unset OLD_KCONFIG_EXT_PREFIX
    """.format(
        has_parent = "true" if has_parent else "false",
        override_parent = override_parent,
        override_parent_log = override_parent_log.path,
    )

    transitive_inputs = [
        # We use KCONFIG_EXT_PREFIX in this step, which requires this and parent Kconfigs.
        combined.kconfig_written.original_depset,
    ]
    tools = []
    outputs = []

    if defconfig_files:
        check_defconfig_step = config_utils.create_check_defconfig_step(
            defconfig = None,
            pre_defconfig_fragments = [],
            post_defconfig_fragments = defconfig_files,
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
            defconfig_files,
            transitive = transitive_inputs,
        ),
        cmd = cmd,
        tools = tools,
        outputs = outputs,
    )

_create_oldconfig_step_in_shell = subrule(
    implementation = _create_oldconfig_step_in_shell_impl,
    subrules = [
        config_utils.create_check_defconfig_step,
    ],
)

def _create_oldconfig_step_in_analysis_phase_impl(
        subrule_ctx,
        kconfig_ext_step,
        merge_dot_config_step,
        combined,
        defconfig_files,
        has_parent,
        override_parent,
        override_parent_log):
    if kconfig_ext_step.kconfig_ext_source != "this" and not merge_dot_config_step.maybe_dot_config_modified:
        # Inherting Kconfig and defconfig, so there is definitely nothing changed. Take the
        # easy way out.

        if override_parent == "expect_override":
            fail("{}: Expecting target to override parent values, but not overriding anything!".format(subrule_ctx.label))

        if defconfig_files:
            # Should not reach here because if there are any defconfig fragments in this target,
            # then maybe_dot_config_modified is always True.
            fail("{}: Should not reach here. defconfig_files = {}".format(subrule_ctx.label, defconfig_files))

        return StepInfo(
            inputs = depset(),
            cmd = "",
            tools = [],
            outputs = [],
        )

    # .config might need to change. Evaluate this in the execution phase.
    return _create_oldconfig_step_in_shell(
        combined = combined,
        defconfig_files = defconfig_files,
        has_parent = has_parent,
        override_parent = override_parent,
        override_parent_log = override_parent_log,
    )

_create_oldconfig_step_in_analysis_phase = subrule(
    implementation = _create_oldconfig_step_in_analysis_phase_impl,
    subrules = [
        config_utils.create_check_defconfig_step,
        _create_oldconfig_step_in_shell,
    ],
)

def _create_oldconfig_step_impl(
        _subrule_ctx,
        kconfig_ext_step,
        merge_dot_config_step,
        combined,
        defconfig_files,
        has_parent,
        override_parent,
        override_parent_log,
        _optimize_ddk_config_actions):
    """Creates a step that calls `make olddefconfig` if necessary.

    Args:
        _subrule_ctx: _subrule_ctx
        kconfig_ext_step: KconfigExtStepInfo from create_kconfig_ext_step
        merge_dot_config_step: MergeDotConfigStepInfo from create_merge_dot_config_step
        combined: The combined DdkConfigInfo (parent + this target)
        defconfig_files: List of defconfig fragments to check the final .config against
        has_parent: whether the outer ddk_module_config target has parent set.
        override_parent: whether it is allowed to override kconfig/.config from parent.
        override_parent_log: This step writes to this log file to explain why this target would
            have required extra `make olddefconfig` on top of parent.

            This is not added to outputs list of the step, even though the step appends to this log.
            The caller should put this in the output list of the action.
        _optimize_ddk_config_actions: See flag
    Returns:
        StepInfo
    """
    if _optimize_ddk_config_actions[BuildSettingInfo].value:
        return _create_oldconfig_step_in_analysis_phase(
            kconfig_ext_step = kconfig_ext_step,
            merge_dot_config_step = merge_dot_config_step,
            combined = combined,
            defconfig_files = defconfig_files,
            has_parent = has_parent,
            override_parent = override_parent,
            override_parent_log = override_parent_log,
        )
    return _create_oldconfig_step_in_shell(
        combined = combined,
        defconfig_files = defconfig_files,
        has_parent = has_parent,
        override_parent = override_parent,
        override_parent_log = override_parent_log,
    )

create_oldconfig_step = subrule(
    implementation = _create_oldconfig_step_impl,
    attrs = {
        "_optimize_ddk_config_actions": attr.label(
            default = "//build/kernel/kleaf:optimize_ddk_config_actions",
        ),
    },
    subrules = [
        _create_oldconfig_step_in_shell,
        _create_oldconfig_step_in_analysis_phase,
    ],
)
