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

"""Subrule for creating the main action that configurates a DDK module.

One notable output for the action is .config for the DDK module."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":common_providers.bzl",
    "DdkConfigInfo",
    "DdkConfigOutputsInfo",
)
load(":ddk/ddk_config/create_kconfig_ext_step.bzl", "create_kconfig_ext_step")
load(":ddk/ddk_config/create_merge_dot_config_step.bzl", "create_merge_dot_config_step")
load(":ddk/ddk_config/create_oldconfig_step.bzl", "create_oldconfig_step")
load(
    ":ddk/ddk_config/ddk_config_info_subrule.bzl",
    "combine_ddk_config_info",
    "empty_ddk_config_info",
)
load(":ddk/ddk_config/ddk_config_restore_out_dir_step.bzl", "ddk_config_restore_out_dir_step")
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

DDK_CONFIG_MAIN_ACTION_MNEMONIC = "DdkConfig"

DdkConfigMainActionInfo = provider(
    "Return value of ddk_config_main_action_subrule",
    fields = {
        "out_dir": "Output directory",
        "kconfig_ext_step": "StepInfo to set up Kconfig.ext",
        "kconfig_ext": "The directory for KCONFIG_EXT. None if using KCONFIG_EXT_PREFIX",
        "override_parent_log": """override_parent.log file that explains why this target overrides
            .config/Kconfig from parent, triggering olddefconfig""",
    },
)

def _ddk_config_main_action_subrule_impl(
        subrule_ctx,
        *,
        ddk_config_info,
        parent,
        kernel_build_ddk_config_env,
        defconfig_files,
        override_parent,
        _optimize_ddk_config_actions):
    """Impl for ddk_config_main_action_subrule

    Args:
        subrule_ctx: subrule_ctx
        ddk_config_info: from ddk_config_info_subrule
        parent: optional parent target
        kernel_build_ddk_config_env: environment for building DDK config from kernel_build
        defconfig_files: defconfig files of the ddk_module to check against at the end
        override_parent: See ddk_module_config.override_parent.
        _optimize_ddk_config_actions: See flag

    Returns:
        DdkConfigMainActionInfo
    """

    override_parent_log = subrule_ctx.actions.declare_file("{}/override_parent.log".format(subrule_ctx.label.name))

    # If there is no parent, use an empty info to simplify shell checks.
    parent_outputs_info = DdkConfigOutputsInfo(
        out_dir = None,
        kconfig_ext = None,
    )
    parent_ddk_config_info = empty_ddk_config_info(kernel_build_ddk_config_env = None)
    if parent:
        parent_outputs_info = parent[DdkConfigOutputsInfo]
        parent_ddk_config_info = parent[DdkConfigInfo]

    transitive_inputs = []
    tools = []
    outputs = [override_parent_log]

    combined = combine_ddk_config_info(
        parent_label = parent.label if parent else None,
        parent = parent_ddk_config_info,
        child = ddk_config_info,
    )

    kconfig_ext_step = create_kconfig_ext_step(
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
        override_parent_log = override_parent_log,
    )
    merge_dot_config_step = create_merge_dot_config_step(
        kconfig_ext_step = kconfig_ext_step,
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
        override_parent_log = override_parent_log,
    )
    oldconfig_step = create_oldconfig_step(
        kconfig_ext_step = kconfig_ext_step,
        merge_dot_config_step = merge_dot_config_step,
        combined = combined,
        defconfig_files = defconfig_files,
        has_parent = bool(parent),
        override_parent = override_parent,
        override_parent_log = override_parent_log,
    )

    steps = [
        merge_dot_config_step.step_info,
        kconfig_ext_step.step_info,
        oldconfig_step,
    ]

    for step in steps:
        transitive_inputs.append(step.inputs)
        tools += step.tools
        outputs += step.outputs

    # If true, we don't need to do anything real in the execution phase.
    skip_execution_phase_checks = (
        # feature flag
        _optimize_ddk_config_actions[BuildSettingInfo].value and

        # Inheriting kconfig_ext from parent or from kernel_build; no change to Kconfig fragments.
        kconfig_ext_step.kconfig_ext_source != "this" and

        # Definitely not adding extra defconfig fragments (false positives okay)
        not merge_dot_config_step.maybe_dot_config_modified
    )
    if skip_execution_phase_checks:
        subrule_ctx.actions.write(override_parent_log, "")
        out_dir = None
        if parent:
            out_dir = parent_outputs_info.out_dir
        return DdkConfigMainActionInfo(
            out_dir = out_dir,
            kconfig_ext_step = kconfig_ext_step,
            kconfig_ext = kconfig_ext_step.kconfig_ext,
            override_parent_log = override_parent_log,
        )

    out_dir = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/out_dir")
    outputs.append(out_dir)

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = kernel_build_ddk_config_env,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd() + """
            kleaf_do_not_rsync_out_dir_include=1
        """,
    )
    transitive_inputs.append(kernel_build_ddk_config_env.inputs)
    tools.append(kernel_build_ddk_config_env.tools)

    command += """
        : > {override_parent_log}
        {kconfig_ext_cmd}
        {merge_config_cmd}
        {oldconfig_cmd}

        # Copy outputs
        rsync -aL ${{OUT_DIR}}/.config {out_dir}/.config
        if [[ -z ${{kleaf_out_dir_include_candidate}} ]]; then
            echo "ERROR: kleaf_out_dir_include_candidate is not set!" >&2
            exit 1
        fi
        rsync -aL "${{kleaf_out_dir_include_candidate}}" {out_dir}/include/

        if [[ ${{kleaf_auto_conf_cmd_replace_variables}} == "1" ]]; then
            # Ensure reproducibility. The value of the real $ROOT_DIR is replaced in the setup script.
            sed -i'' -e 's:'"${{ROOT_DIR}}"':${{ROOT_DIR}}:g' {out_dir}/include/config/auto.conf.cmd
        fi
        unset kleaf_auto_conf_cmd_replace_variables
    """.format(
        override_parent_log = override_parent_log.path,
        merge_config_cmd = merge_dot_config_step.step_info.cmd,
        kconfig_ext_cmd = kconfig_ext_step.step_info.cmd,
        oldconfig_cmd = oldconfig_step.cmd,
        out_dir = out_dir.path,
    )
    debug.print_scripts_subrule(command)
    subrule_ctx.actions.run_shell(
        inputs = depset(transitive = transitive_inputs),
        tools = tools,
        outputs = outputs,
        command = command,
        mnemonic = DDK_CONFIG_MAIN_ACTION_MNEMONIC,
        progress_message = "Creating DDK module configuration %{label}",
    )

    return DdkConfigMainActionInfo(
        out_dir = out_dir,
        kconfig_ext_step = kconfig_ext_step,
        kconfig_ext = kconfig_ext_step.kconfig_ext,
        override_parent_log = override_parent_log,
    )

ddk_config_main_action_subrule = subrule(
    implementation = _ddk_config_main_action_subrule_impl,
    attrs = {
        "_optimize_ddk_config_actions": attr.label(
            default = "//build/kernel/kleaf:optimize_ddk_config_actions",
        ),
    },
    subrules = [
        debug.print_scripts_subrule,
        ddk_config_restore_out_dir_step,
        empty_ddk_config_info,
        combine_ddk_config_info,
        create_merge_dot_config_step,
        create_kconfig_ext_step,
        create_oldconfig_step,
        utils.write_depset,
    ],
)
