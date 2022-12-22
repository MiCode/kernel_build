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

load(
    ":common_providers.bzl",
    "KernelConfigEnvInfo",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
)
load(":cache_dir.bzl", "cache_dir")
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils")

def _modules_prepare_impl(ctx):
    inputs = []
    transitive_inputs = [target.files for target in ctx.attr.srcs]

    outputs = [ctx.outputs.outdir_tar_gz]

    tools = []
    tools += ctx.attr.config[KernelConfigEnvInfo].env_info.dependencies
    tools += ctx.attr.config[KernelConfigEnvInfo].post_env_info.dependencies

    cache_dir_step = cache_dir.get_step(
        ctx = ctx,
        common_config_tags = ctx.attr.config[KernelEnvAttrInfo].common_config_tags,
        symlink_name = "modules_prepare",
    )
    inputs += cache_dir_step.inputs
    outputs += cache_dir_step.outputs
    tools += cache_dir_step.tools

    command = ctx.attr.config[KernelConfigEnvInfo].env_info.setup
    command += cache_dir_step.cmd
    command += ctx.attr.config[KernelConfigEnvInfo].post_env_info.setup
    command += """
         # Prepare for the module build
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
         # Package files
           tar czf {outdir_tar_gz} -C ${{OUT_DIR}} .
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
        tools = tools,
        progress_message = "Preparing for module build %s" % ctx.label,
        command = command,
        execution_requirements = kernel_utils.local_exec_requirements(ctx),
    )

    setup = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
           mkdir -p ${{OUT_DIR}}
           tar xf {outdir_tar_gz} -C ${{OUT_DIR}}
           """.format(outdir_tar_gz = ctx.outputs.outdir_tar_gz.path)

    return [KernelEnvInfo(
        dependencies = [ctx.outputs.outdir_tar_gz],
        setup = setup,
    )]

modules_prepare = rule(
    doc = "Rule that runs `make modules_prepare` to prepare `$OUT_DIR` for modules.",
    implementation = _modules_prepare_impl,
    attrs = {
        "config": attr.label(
            mandatory = True,
            providers = [KernelEnvAttrInfo, KernelConfigEnvInfo],
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
    },
)
