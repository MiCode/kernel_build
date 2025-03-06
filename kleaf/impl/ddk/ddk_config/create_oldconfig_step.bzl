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

load(
    ":common_providers.bzl",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")

visibility("private")

def _create_oldconfig_step_in_shell_impl(
        _subrule_ctx,
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

    transitive_inputs = []
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

def _create_oldconfig_step_impl(
        _subrule_ctx,
        defconfig_files,
        has_parent,
        override_parent,
        override_parent_log):
    """Creates a step that calls `make olddefconfig` if necessary.

    Args:
        _subrule_ctx: _subrule_ctx
        defconfig_files: List of defconfig fragments to check the final .config against
        has_parent: whether the outer ddk_module_config target has parent set.
        override_parent: whether it is allowed to override kconfig/.config from parent.
        override_parent_log: This step writes to this log file to explain why this target would
            have required extra `make olddefconfig` on top of parent.

            This is not added to outputs list of the step, even though the step appends to this log.
            The caller should put this in the output list of the action.
    Returns:
        StepInfo
    """
    return _create_oldconfig_step_in_shell(
        defconfig_files = defconfig_files,
        has_parent = has_parent,
        override_parent = override_parent,
        override_parent_log = override_parent_log,
    )

create_oldconfig_step = subrule(
    implementation = _create_oldconfig_step_impl,
    subrules = [
        _create_oldconfig_step_in_shell,
    ],
)
