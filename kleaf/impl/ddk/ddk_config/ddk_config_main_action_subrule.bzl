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

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common_providers.bzl",
    "StepInfo",
)
load(":config_utils.bzl", "config_utils")
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/impl/...")

DdkConfigMainActionInfo = provider(
    "Return value of ddk_config_main_action_subrule",
    fields = {
        "out_dir": "Output directory",
        "kconfig_ext_step": "StepInfo to set up Kconfig.ext",
    },
)

def _create_merge_dot_config_step_impl(_subrule_ctx, *, defconfig_depset_written):
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

_create_merge_dot_config_step = subrule(
    implementation = _create_merge_dot_config_step_impl,
)

def _create_kconfig_ext_step_impl(subrule_ctx, *, bin_dir_path, kconfig_depset_written):
    run_intermediates_dir = paths.join(
        subrule_ctx.label.workspace_root,
        subrule_ctx.label.package,
        subrule_ctx.label.name + "_intermediates",
    )
    intermediates_dir = paths.join(
        bin_dir_path,
        run_intermediates_dir,
    )

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

_create_kconfig_ext_step = subrule(implementation = _create_kconfig_ext_step_impl)

def _create_oldconfig_step_impl(_subrule_ctx, defconfig_depset_written, kconfig_depset_written, defconfig_files):
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
        bin_dir_path,
        ddk_config_info,
        kernel_build_ddk_config_env,
        defconfig_files):
    """Impl for ddk_config_main_action_subrule

    Args:
        subrule_ctx: subrule_ctx
        bin_dir_path: ctx.bin_dir.path
        ddk_config_info: from ddk_config_info_subrule
        kernel_build_ddk_config_env: environment for building DDK config from kernel_build
        defconfig_files: defconfig files of the ddk_module to check against at the end

    Returns:
        DdkConfigMainActionInfo
    """

    out_dir = subrule_ctx.actions.declare_directory(subrule_ctx.label.name + "/out_dir")

    kconfig_depset_written = utils.write_depset(ddk_config_info.kconfig, "kconfig_depset.txt")
    defconfig_depset_written = utils.write_depset(ddk_config_info.defconfig, "defconfig_depset.txt")

    transitive_inputs = [
        kernel_build_ddk_config_env.inputs,
    ]

    tools = [kernel_build_ddk_config_env.tools]
    outputs = [out_dir]

    merge_dot_config_step = _create_merge_dot_config_step(
        defconfig_depset_written = defconfig_depset_written,
    )
    kconfig_ext_step = _create_kconfig_ext_step(
        bin_dir_path = bin_dir_path,
        kconfig_depset_written = kconfig_depset_written,
    )
    oldconfig_step = _create_oldconfig_step(
        defconfig_depset_written = defconfig_depset_written,
        kconfig_depset_written = kconfig_depset_written,
        defconfig_files = defconfig_files,
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
    )

ddk_config_main_action_subrule = subrule(
    implementation = _ddk_config_main_action_subrule_impl,
    subrules = [
        debug.print_scripts_subrule,
        utils.write_depset,
        _create_merge_dot_config_step,
        _create_kconfig_ext_step,
        _create_oldconfig_step,
    ],
)
