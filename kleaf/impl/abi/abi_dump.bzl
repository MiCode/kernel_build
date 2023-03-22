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
"""Rules for ABI extraction."""

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    ":common_providers.bzl",
    "KernelBuildAbiInfo",
    "KernelUnstrippedModulesInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")
load(":abi/abi_transitions.bzl", "with_vmlinux_transition")

def _abi_dump_impl(ctx):
    kernel_utils.check_kernel_build(ctx.attr.kernel_modules, ctx.attr.kernel_build, ctx.label)

    full_abi_out_file_xml = _abi_dump_full(ctx)
    abi_out_file_xml = _abi_dump_filtered(ctx, full_abi_out_file_xml)

    # Run both methods until STG is fully adopted.
    full_abi_out_file_stg = _abi_dump_full_stg(ctx)
    abi_out_file_stg = _abi_dump_filtered_stg(ctx, full_abi_out_file_stg)

    return [
        DefaultInfo(files = depset([
            full_abi_out_file_xml,
            abi_out_file_xml,
            full_abi_out_file_stg,
            abi_out_file_stg,
        ])),
        OutputGroupInfo(
            abi_out_file_xml = depset([abi_out_file_xml]),
            abi_out_file = depset([abi_out_file_stg]),
        ),
    ]

def _unstripped_dirs(ctx):
    unstripped_dirs = []

    unstripped_dir_provider_targets = [ctx.attr.kernel_build] + ctx.attr.kernel_modules
    unstripped_dir_providers = [target[KernelUnstrippedModulesInfo] for target in unstripped_dir_provider_targets]
    for prov, target in zip(unstripped_dir_providers, unstripped_dir_provider_targets):
        dirs_for_target = prov.directories.to_list()
        if not dirs_for_target:
            fail("{}: Requires dep {} to set collect_unstripped_modules = True".format(
                ctx.label,
                target.label,
            ))
        unstripped_dirs += dirs_for_target

    return unstripped_dirs

def _find_vmlinux(ctx):
    return utils.find_file(
        name = "vmlinux",
        files = ctx.files.kernel_build,
        what = "{}: kernel_build".format(ctx.attr.name),
        required = True,
    )

def _abi_dump_full(ctx):
    abi_linux_tree = utils.intermediates_dir(ctx) + "/abi_linux_tree"
    full_abi_out_file = ctx.actions.declare_file("{}/abi-full-generated.xml".format(ctx.attr.name))
    vmlinux = _find_vmlinux(ctx)
    unstripped_dirs = _unstripped_dirs(ctx)

    inputs = [vmlinux]
    inputs += unstripped_dirs

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    # Directories could be empty, so use a find + cp
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        mkdir -p {abi_linux_tree}
        find {unstripped_dirs} -name '*.ko' -exec cp -pl -t {abi_linux_tree} {{}} +
        cp -pl {vmlinux} {abi_linux_tree}
        {dump_abi} --linux-tree {abi_linux_tree} --out-file {full_abi_out_file}
        rm -rf {abi_linux_tree}
    """.format(
        abi_linux_tree = abi_linux_tree,
        unstripped_dirs = " ".join([unstripped_dir.path for unstripped_dir in unstripped_dirs]),
        dump_abi = ctx.executable._dump_abi.path,
        vmlinux = vmlinux.path,
        full_abi_out_file = full_abi_out_file.path,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [full_abi_out_file],
        tools = [ctx.executable._dump_abi],
        command = command,
        mnemonic = "AbiDumpFull",
        progress_message = "Extracting ABI {}".format(ctx.label),
    )
    return full_abi_out_file

def _abi_dump_full_stg(ctx):
    full_abi_out_file = ctx.actions.declare_file("{}/abi-full.stg".format(ctx.attr.name))
    vmlinux = _find_vmlinux(ctx)
    unstripped_dirs = _unstripped_dirs(ctx)

    inputs = [vmlinux, ctx.file._stg]
    inputs += unstripped_dirs
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    # Collect all modules from all directories
    all_modules = ""
    for unstripped_dir in unstripped_dirs:
        all_modules += "{dir_path}/*.ko ".format(
            dir_path = unstripped_dir.path,
        )

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        {stg} --output {full_abi_out_file} --elf {vmlinux} {all_modules}
    """.format(
        stg = ctx.file._stg.path,
        full_abi_out_file = full_abi_out_file.path,
        vmlinux = vmlinux.path,
        all_modules = all_modules,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [full_abi_out_file],
        command = command,
        mnemonic = "AbiDumpFullStg",
        progress_message = "[stg] Extracting ABI {}".format(ctx.label),
    )
    return full_abi_out_file

def _abi_dump_filtered(ctx, full_abi_out_file):
    abi_out_file = ctx.actions.declare_file("{}/abi-generated.xml".format(ctx.attr.name))
    inputs = [full_abi_out_file]

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    combined_abi_symbollist = ctx.attr.kernel_build[KernelBuildAbiInfo].combined_abi_symbollist
    tools = []
    if combined_abi_symbollist:
        inputs.append(combined_abi_symbollist)
        tools.append(ctx.executable._filter_abi)

        command += """
            {filter_abi} --in-file {full_abi_out_file} --out-file {abi_out_file} --kmi-symbol-list {abi_symbollist}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
            filter_abi = ctx.executable._filter_abi.path,
            abi_symbollist = combined_abi_symbollist.path,
        )
    else:
        command += """
            cp -p {full_abi_out_file} {abi_out_file}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
        )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [abi_out_file],
        tools = tools,
        command = command,
        mnemonic = "AbiDumpFiltered",
        progress_message = "Filtering ABI dump {}".format(ctx.label),
    )
    return abi_out_file

def _abi_dump_filtered_stg(ctx, full_abi_out_file):
    abi_out_file = ctx.actions.declare_file("{}/abi.stg".format(ctx.attr.name))
    combined_abi_symbollist = ctx.attr.kernel_build[KernelBuildAbiInfo].combined_abi_symbollist
    inputs = [full_abi_out_file]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup

    if combined_abi_symbollist:
        inputs += [
            ctx.file._stg,
            combined_abi_symbollist,
        ]

        command += """
            {stg} --symbols :{abi_symbollist} --output {abi_out_file} --stg {full_abi_out_file}
        """.format(
            stg = ctx.file._stg.path,
            abi_symbollist = combined_abi_symbollist.path,
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
        )
    else:
        command += """
            cp -p {full_abi_out_file} {abi_out_file}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
        )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [abi_out_file],
        command = command,
        mnemonic = "AbiDumpFilteredStg",
        progress_message = "[stg] Filtering ABI dump {}".format(ctx.label),
    )
    return abi_out_file

abi_dump = rule(
    implementation = _abi_dump_impl,
    doc = "Extracts the ABI.",
    attrs = {
        "kernel_build": attr.label(providers = [KernelBuildAbiInfo, KernelUnstrippedModulesInfo]),
        "kernel_modules": attr.label_list(providers = [KernelUnstrippedModulesInfo]),
        "_dump_abi": attr.label(
            default = "//build/kernel:dump_abi",
            cfg = "exec",
            executable = True,
        ),
        "_filter_abi": attr.label(
            default = "//build/kernel:filter_abi",
            cfg = "exec",
            executable = True,
        ),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
        "_stg": attr.label(
            default = "//prebuilts/kernel-build-tools:linux-x86/bin/stg",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
    },
    cfg = with_vmlinux_transition,
)
