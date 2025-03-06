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

load(
    ":common_providers.bzl",
    "DdkConfigInfo",
    "DdkConfigOutputsInfo",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")
load(
    ":ddk/ddk_config/ddk_config_info_subrule.bzl",
    "combine_ddk_config_info",
    "empty_ddk_config_info",
)
load(":ddk/ddk_config/ddk_config_restore_out_dir_step.bzl", "ddk_config_restore_out_dir_step")
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/impl/...")

DdkConfigMainActionInfo = provider(
    "Return value of ddk_config_main_action_subrule",
    fields = {
        "out_dir": "Output directory",
        "kconfig_ext_step": "StepInfo to set up Kconfig.ext",
        "kconfig_ext": "The directory for KCONFIG_EXT",
        "override_parent_log": """override_parent.log file that explains why this target overrides
            .config/Kconfig from parent, triggering olddefconfig""",
    },
)

def _create_merge_dot_config_step_impl(
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
        # Backup existing .config for comparison later. The .config.old is a snapshot of the
        # existing $kleaf_out_dir_include_candidate.
        cp ${{OUT_DIR}}/.config ${{OUT_DIR}}/.config.old

        if [[ -z "${{ddk_config_using_parent_kconfig_ext}}" ]]; then
            echo "ERROR: create_merge_dot_config_step should be invoked after create_kconfig_ext_step!" >&2
            exit 1
        fi

        # If adding extra defconfig on top of parent, then merge combined defconfig depset on
        # kernel_build's .config
        if ! diff -q {parent_defconfig_depset} {combined_defconfig_depset} > /dev/null; then

            (
                echo "WARNING: Adding extra defconfig files:"
                diff {parent_defconfig_depset} {combined_defconfig_depset} || true
                echo "This may cause an extra olddefconfig step."
                echo
            ) >> {override_parent_log}

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
        combined_defconfig_depset = combined.defconfig_written.depset_file.path,
        parent_defconfig_depset = parent_ddk_config_info.defconfig_written.depset_file.path,
        merge_combined_defconfig_on_kernel_build_dot_config = config_utils.create_merge_config_cmd(
            base_expr = "${OUT_DIR}/.config",
            defconfig_fragments_paths_expr = "$(cat {})".format(combined.defconfig_written.depset_file.path),
        ),
        restore_parent_out_dir_cmd = restore_parent_out_dir.cmd,
        override_parent_log = override_parent_log.path,
    )

    return StepInfo(
        inputs = depset(transitive = [
            combined.defconfig_written.depset,
            parent_ddk_config_info.defconfig_written.depset,
            restore_parent_out_dir.inputs,
        ]),
        cmd = cmd,
        tools = restore_parent_out_dir.tools,
        outputs = restore_parent_out_dir.outputs,
    )

_create_merge_dot_config_step = subrule(
    implementation = _create_merge_dot_config_step_impl,
    subrules = [
        ddk_config_restore_out_dir_step,
    ],
)

def _create_kconfig_ext_step_impl(
        subrule_ctx,
        *,
        combined,
        parent_ddk_config_info,
        parent_outputs_info,
        override_parent_log):
    kconfig_ext = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/kconfig_ext")

    cmd = """
        if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ]; then
            parent_kconfig_depset_file={parent_kconfig_depset_file_short}
            combined_kconfig_depset_file={combined_kconfig_depset_file_short}
            kconfig_ext_dir={kconfig_ext_short}
            parent_kconfig_ext_dir={parent_kconfig_ext_short}
            override_parent_log={override_parent_log_short}
        else
            parent_kconfig_depset_file={parent_kconfig_depset_file}
            combined_kconfig_depset_file={combined_kconfig_depset_file}
            kconfig_ext_dir={kconfig_ext}
            parent_kconfig_ext_dir={parent_kconfig_ext}
            override_parent_log={override_parent_log}
        fi

        # Backup the value of KCONFIG_EXT_PREFIX for comparison later.
        OLD_KCONFIG_EXT_PREFIX=${{KCONFIG_EXT_PREFIX}}

        ddk_config_using_parent_kconfig_ext=0

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
        parent_kconfig_depset_file = parent_ddk_config_info.kconfig_written.depset_file.path,
        combined_kconfig_depset_file = combined.kconfig_written.depset_file.path,
        kconfig_ext = kconfig_ext.path,
        parent_kconfig_ext = utils.optional_path(parent_outputs_info.kconfig_ext),
        override_parent_log = override_parent_log.path,
        parent_kconfig_depset_file_short = parent_ddk_config_info.kconfig_written.depset_short_file.short_path,
        combined_kconfig_depset_file_short = combined.kconfig_written.depset_short_file.short_path,
        kconfig_ext_short = kconfig_ext.short_path,
        parent_kconfig_ext_short = utils.optional_short_path(parent_outputs_info.kconfig_ext),
        override_parent_log_short = override_parent_log.short_path,
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

_create_kconfig_ext_step = subrule(implementation = _create_kconfig_ext_step_impl)

def _create_oldconfig_step_impl(
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

_create_oldconfig_step = subrule(
    implementation = _create_oldconfig_step_impl,
    subrules = [
        config_utils.create_check_defconfig_step,
    ],
)

def _ddk_config_main_action_subrule_impl(
        subrule_ctx,
        *,
        ddk_config_info,
        parent,
        kernel_build_ddk_config_env,
        defconfig_files,
        override_parent):
    """Impl for ddk_config_main_action_subrule

    Args:
        subrule_ctx: subrule_ctx
        ddk_config_info: from ddk_config_info_subrule
        parent: optional parent target
        kernel_build_ddk_config_env: environment for building DDK config from kernel_build
        defconfig_files: defconfig files of the ddk_module to check against at the end
        override_parent: See ddk_module_config.override_parent.

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

    out_dir = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/out_dir")

    transitive_inputs = [
        kernel_build_ddk_config_env.inputs,
    ]

    tools = [kernel_build_ddk_config_env.tools]
    outputs = [out_dir, override_parent_log]

    combined = combine_ddk_config_info(
        parent_label = parent.label if parent else None,
        parent = parent_ddk_config_info,
        child = ddk_config_info,
    )

    merge_dot_config_step = _create_merge_dot_config_step(
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
        override_parent_log = override_parent_log,
    )
    kconfig_ext_step = _create_kconfig_ext_step(
        combined = combined,
        parent_ddk_config_info = parent_ddk_config_info,
        parent_outputs_info = parent_outputs_info,
        override_parent_log = override_parent_log,
    )
    oldconfig_step = _create_oldconfig_step(
        defconfig_files = defconfig_files,
        has_parent = bool(parent),
        override_parent = override_parent,
        override_parent_log = override_parent_log,
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
        serialized_env_info = kernel_build_ddk_config_env,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd() + """
            kleaf_do_not_rsync_out_dir_include=1
        """,
    )
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
        merge_config_cmd = merge_dot_config_step.cmd,
        kconfig_ext_cmd = kconfig_ext_step.cmd,
        oldconfig_cmd = oldconfig_step.cmd,
        out_dir = out_dir.path,
    )
    debug.print_scripts_subrule(command)
    subrule_ctx.actions.run_shell(
        inputs = depset(transitive = transitive_inputs),
        tools = tools,
        outputs = outputs,
        command = command,
        mnemonic = "DdkConfig",
        progress_message = "Creating DDK module configuration %{label}",
    )

    return DdkConfigMainActionInfo(
        out_dir = out_dir,
        kconfig_ext_step = kconfig_ext_step,
        kconfig_ext = utils.single_file(kconfig_ext_step.outputs),
        override_parent_log = override_parent_log,
    )

ddk_config_main_action_subrule = subrule(
    implementation = _ddk_config_main_action_subrule_impl,
    subrules = [
        debug.print_scripts_subrule,
        ddk_config_restore_out_dir_step,
        empty_ddk_config_info,
        combine_ddk_config_info,
        _create_merge_dot_config_step,
        _create_kconfig_ext_step,
        _create_oldconfig_step,
        utils.write_depset,
    ],
)
