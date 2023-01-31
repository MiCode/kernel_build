# Copyright (C) 2022 The Android Open Source Project
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

"""Runs `make modules_prepare` to prepare `$OUT_DIR` for modules."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")
load(
    ":common_providers.bzl",
    "KernelEnvAndOutputsInfo",
    "KernelEnvAttrInfo",
)
load(":cache_dir.bzl", "cache_dir")
load(":debug.bzl", "debug")
load(":modules_prepare_transition.bzl", "modules_prepare_transition")
load(":utils.bzl", "kernel_utils")

def _modules_prepare_impl(ctx):
    inputs = []
    tools = []
    transitive_tools = []
    transitive_inputs = []

    transitive_inputs += [target.files for target in ctx.attr.srcs]

    outputs = [ctx.outputs.outdir_tar_gz]

    transitive_tools.append(ctx.attr.config[KernelEnvAndOutputsInfo].tools)
    transitive_inputs.append(ctx.attr.config[KernelEnvAndOutputsInfo].inputs)

    cache_dir_step = cache_dir.get_step(
        ctx = ctx,
        common_config_tags = ctx.attr.config[KernelEnvAttrInfo].common_config_tags,
        symlink_name = "modules_prepare",
    )
    inputs += cache_dir_step.inputs
    outputs += cache_dir_step.outputs
    tools += cache_dir_step.tools

    command = ctx.attr.config[KernelEnvAndOutputsInfo].get_setup_script(
        data = ctx.attr.config[KernelEnvAndOutputsInfo].data,
        restore_out_dir_cmd = cache_dir_step.cmd,
    )
    command += """
         # Prepare for the module build
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
         # Package files
         # TODO(b/243737262): Use tar czf
           mkdir -p $(dirname {outdir_tar_gz})
           tar c -C ${{OUT_DIR}} . | gzip - > {outdir_tar_gz}
           {cache_dir_post_cmd}
    """.format(
        outdir_tar_gz = ctx.outputs.outdir_tar_gz.path,
        cache_dir_post_cmd = cache_dir_step.post_cmd,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "ModulesPrepare",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = outputs,
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Preparing for module build {}{}".format(
            ctx.attr.config[KernelEnvAttrInfo].progress_message_note,
            ctx.label,
        ),
        command = command,
        execution_requirements = kernel_utils.local_exec_requirements(ctx),
    )

    restore_outputs_cmd = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
           mkdir -p ${{OUT_DIR}}
           tar xf {outdir_tar_gz} -C ${{OUT_DIR}}
           """.format(outdir_tar_gz = ctx.outputs.outdir_tar_gz.path)

    return [
        KernelEnvAndOutputsInfo(
            get_setup_script = _env_and_outputs_info_get_setup_script,
            inputs = depset(
                [ctx.outputs.outdir_tar_gz],
                transitive = [ctx.attr.config[KernelEnvAndOutputsInfo].inputs],
            ),
            tools = ctx.attr.config[KernelEnvAndOutputsInfo].tools,
            data = struct(
                config_env_and_outputs_info = ctx.attr.config[KernelEnvAndOutputsInfo],
                restore_outputs_cmd = restore_outputs_cmd,
            ),
        ),
    ]

def _env_and_outputs_info_get_setup_script(data, restore_out_dir_cmd):
    config_env_and_outputs_info = data.config_env_and_outputs_info
    restore_outputs_cmd = data.restore_outputs_cmd
    script = config_env_and_outputs_info.get_setup_script(
        data = config_env_and_outputs_info.data,
        restore_out_dir_cmd = restore_out_dir_cmd,
    )
    script += restore_outputs_cmd
    return script

def _modules_prepare_additional_attrs():
    return dicts.add(
        trim_nonlisted_kmi_utils.non_config_attrs(),
    )

modules_prepare = rule(
    doc = "Rule that runs `make modules_prepare` to prepare `$OUT_DIR` for modules.",
    implementation = _modules_prepare_impl,
    attrs = {
        "config": attr.label(
            mandatory = True,
            providers = [KernelEnvAttrInfo, KernelEnvAndOutputsInfo],
            doc = "the kernel_config target",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "outdir_tar_gz": attr.output(
            mandatory = True,
            doc = "the packaged ${OUT_DIR} files",
        ),
        "_cache_dir": attr.label(default = "//build/kernel/kleaf:cache_dir"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_config_is_local": attr.label(default = "//build/kernel/kleaf:config_local"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | _modules_prepare_additional_attrs(),
    cfg = modules_prepare_transition,
)
