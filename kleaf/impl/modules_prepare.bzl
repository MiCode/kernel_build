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

load(":cache_dir.bzl", "cache_dir")
load(
    ":common_providers.bzl",
    "KernelBuildOriginalEnvInfo",
    "KernelEnvAttrInfo",
    "KernelSerializedEnvInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils")

visibility("//build/kernel/kleaf/...")

def _modules_prepare_subrule_impl(
        subrule_ctx,
        *,
        srcs,
        outdir_tar_gz,
        kernel_serialized_env_info,
        force_generate_headers,
        kernel_toolchains,
        execution_requirements,
        setup_script_name,
        cache_dir_step,
        progress_message_note):
    """Common implementation to prepare for module build.

    Args:
        subrule_ctx: subrule_ctx
        srcs: depset of sources
        outdir_tar_gz: declared output file
        kernel_serialized_env_info: KernelSerializedEnvInfo that has kernel properly configured
            (make defconfig is executed)
        force_generate_headers: If True it forces generation of additional headers after make modules_prepare
        kernel_toolchains: KernelEnvToolchainsInfo
        execution_requirements: arg to run_shell
        setup_script_name: Name of setup script to declare.
        cache_dir_step: See cache_dir.get_step, or a stub step if caching is not needed.
        progress_message_note: suffix to be added to progress_message.

    Returns:
        dict of infos. Keys are info type names, values are infos.
    """
    inputs = []
    tools = []
    transitive_tools = []
    transitive_inputs = []

    transitive_inputs.append(srcs)

    outputs = [outdir_tar_gz]

    transitive_tools.append(kernel_serialized_env_info.tools)
    transitive_inputs.append(kernel_serialized_env_info.inputs)

    inputs += cache_dir_step.inputs
    outputs += cache_dir_step.outputs
    tools += cache_dir_step.tools

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = kernel_serialized_env_info,
        restore_out_dir_cmd = cache_dir_step.cmd,
    )

    force_gen_headers_cmd = ""
    if force_generate_headers:
        force_gen_headers_cmd += """
        # Workaround to force the creation of these missing files.
           mkdir -p ${OUT_DIR}/security/selinux/
           ${OUT_DIR}/scripts/selinux/genheaders/genheaders ${OUT_DIR}/security/selinux/flask.h ${OUT_DIR}/security/selinux/av_permissions.h
        """

    command += """
         # Prepare for the module build
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
         # Additional steps
           {force_gen_headers_cmd}
         # b/279211056: Exclude the top-level source symlink. It is not useful and points outside
         # of the directory, making tar unhappy.
           rm -f ${{OUT_DIR}}/source
         # Package files
           tar czf {outdir_tar_gz} -C ${{OUT_DIR}} .
           {cache_dir_post_cmd}
    """.format(
        force_gen_headers_cmd = force_gen_headers_cmd,
        outdir_tar_gz = outdir_tar_gz.path,
        cache_dir_post_cmd = cache_dir_step.post_cmd,
    )

    debug.print_scripts_subrule(command)
    subrule_ctx.actions.run_shell(
        mnemonic = "ModulesPrepare",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = outputs,
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Preparing for module build{} %{{label}}".format(
            progress_message_note,
        ),
        command = command,
        execution_requirements = execution_requirements,
    )

    setup_script_cmd = modules_prepare_setup_command(
        config_setup_script = kernel_serialized_env_info.setup_script,
        modules_prepare_outdir_tar_gz = outdir_tar_gz,
        kernel_toolchains = kernel_toolchains,
    )

    # <kernel_build>_modules_prepare_setup.sh
    setup_script = subrule_ctx.actions.declare_file(setup_script_name)
    subrule_ctx.actions.write(
        output = setup_script,
        content = setup_script_cmd,
    )

    # Use a dict() so the caller can select the provider the rule uses or returns.
    return {
        "KernelSerializedEnvInfo": KernelSerializedEnvInfo(
            setup_script = setup_script,
            inputs = depset(
                [outdir_tar_gz, setup_script],
                transitive = [kernel_serialized_env_info.inputs],
            ),
            tools = kernel_serialized_env_info.tools,
        ),
        "DefaultInfo": DefaultInfo(files = depset([outdir_tar_gz, setup_script])),
    }

modules_prepare_subrule = subrule(
    implementation = _modules_prepare_subrule_impl,
    subrules = [debug.print_scripts_subrule],
)

def _modules_prepare_impl(ctx):
    cache_dir_step = cache_dir.get_step(
        ctx = ctx,
        common_config_tags = ctx.attr.config[KernelEnvAttrInfo].common_config_tags,
        symlink_name = "modules_prepare",
    )

    return modules_prepare_subrule(
        srcs = depset(transitive = [target.files for target in ctx.attr.srcs]),
        outdir_tar_gz = ctx.outputs.outdir_tar_gz,
        kernel_serialized_env_info = ctx.attr.config[KernelSerializedEnvInfo],
        force_generate_headers = ctx.attr.force_generate_headers,
        kernel_toolchains = ctx.attr.config[KernelBuildOriginalEnvInfo].env_info.toolchains,
        setup_script_name = "{name}/{name}_setup.sh".format(name = ctx.label.name),
        execution_requirements = kernel_utils.local_exec_requirements(ctx),
        cache_dir_step = cache_dir_step,
        progress_message_note = ctx.attr.config[KernelEnvAttrInfo].progress_message_note,
    ).values()

def modules_prepare_setup_command(
        config_setup_script,
        modules_prepare_outdir_tar_gz,
        kernel_toolchains):
    """Set up environment for building modules.

    Args:
        config_setup_script: The script to set up environment after configuration
        modules_prepare_outdir_tar_gz: the tarball of $OUT_DIR after make modules_prepare
        kernel_toolchains: KernelEnvToolchainsInfo

    Returns:
        the command to set up environment
    """

    cmd = """
        source {config_setup_script}
        # Restore modules_prepare outputs. Assumes env setup.
        [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
        mkdir -p ${{OUT_DIR}}
        tar xf {modules_prepare_outdir_tar_gz} -C ${{OUT_DIR}}
    """.format(
        config_setup_script = config_setup_script.path,
        modules_prepare_outdir_tar_gz = modules_prepare_outdir_tar_gz.path,
    )

    # HACK: The binaries in $OUT_DIR (e.g. fixdep) are built with @kleaf being the root Bazel module.
    # But this is not necessarily the case when the archive is used, especially when using @kleaf
    # as a dependent Bazel module to build kernel drivers. In that case, symlink
    # prebuilts/kernel-build-tools so libc_musl.so etc. can be found properly.
    # TODO(b/372807147): Clean this up by letting kernel_filegroup build modules_prepare after all
    #   dependencies for modules_prepare is figured out.
    kleaf_repo_workspace_root = Label(":modules_prepare.bzl").workspace_root
    kleaf_repo_workspace_root_slash = kleaf_repo_workspace_root + "/"
    if kleaf_repo_workspace_root:
        for runpath in kernel_toolchains.host_runpaths:
            if not runpath.startswith(kleaf_repo_workspace_root_slash):
                continue
            bare_runpath = runpath.removeprefix(kleaf_repo_workspace_root_slash)
            cmd += """
                if [[ ! -d {bare_runpath} ]]; then
                    (
                        linkdir="$(dirname {bare_runpath})"
                        mkdir -p "${{linkdir}}"
                        ln -s $(realpath {runpath} --relative-to "${{linkdir}}") {bare_runpath}
                    )
                fi
            """.format(
                runpath = runpath,
                bare_runpath = bare_runpath,
            )

    return cmd

def _modules_prepare_additional_attrs():
    return cache_dir.attrs()

modules_prepare = rule(
    doc = "Rule that runs `make modules_prepare` to prepare `$OUT_DIR` for modules.",
    implementation = _modules_prepare_impl,
    attrs = {
        "config": attr.label(
            mandatory = True,
            providers = [
                KernelEnvAttrInfo,
                KernelSerializedEnvInfo,
                KernelBuildOriginalEnvInfo,
            ],
            doc = "the kernel_config target",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "outdir_tar_gz": attr.output(
            mandatory = True,
            doc = "the packaged ${OUT_DIR} files",
        ),
        "force_generate_headers": attr.bool(
            doc = "If True it forces generation of additional headers after make modules_prepare",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    } | _modules_prepare_additional_attrs(),
    subrules = [
        modules_prepare_subrule,
    ],
)
