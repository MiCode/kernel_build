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

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    ":common_providers.bzl",
    "KernelBuildAbiInfo",
    "KernelEnvInfo",
    "KernelUnstrippedModulesInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "utils")

def _abi_dump_impl(ctx):
    full_abi_out_file = _abi_dump_full(ctx)
    abi_out_file = _abi_dump_filtered(ctx, full_abi_out_file)
    return [
        DefaultInfo(files = depset([full_abi_out_file, abi_out_file])),
        OutputGroupInfo(abi_out_file = depset([abi_out_file])),
    ]

def _abi_dump_epilog_cmd(path, append_version):
    ret = ""
    if append_version:
        ret += """
             # Append debug information to abi file
               echo "
<!--
     libabigail: $(abidw --version)
-->" >> {path}
""".format(path = path)
    return ret

def _abi_dump_full(ctx):
    abi_linux_tree = utils.intermediates_dir(ctx) + "/abi_linux_tree"
    full_abi_out_file = ctx.actions.declare_file("{}/abi-full.xml".format(ctx.attr.name))
    vmlinux = utils.find_file(name = "vmlinux", files = ctx.files.kernel_build, what = "{}: kernel_build".format(ctx.attr.name), required = True)

    unstripped_dir_provider_targets = [ctx.attr.kernel_build] + ctx.attr.kernel_modules
    unstripped_dir_providers = [target[KernelUnstrippedModulesInfo] for target in unstripped_dir_provider_targets]
    for prov, target in zip(unstripped_dir_providers, unstripped_dir_provider_targets):
        if not prov.directory:
            fail("{}: Requires dep {} to set collect_unstripped_modules = True".format(ctx.label, target.label))
    unstripped_dirs = [prov.directory for prov in unstripped_dir_providers]

    inputs = [vmlinux, ctx.file._dump_abi]
    inputs += ctx.files._dump_abi_scripts
    inputs += unstripped_dirs

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    # Directories could be empty, so use a find + cp
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        mkdir -p {abi_linux_tree}
        find {unstripped_dirs} -name '*.ko' -exec cp -pl -t {abi_linux_tree} {{}} +
        cp -pl {vmlinux} {abi_linux_tree}
        {dump_abi} --linux-tree {abi_linux_tree} --out-file {full_abi_out_file}
        {epilog}
        rm -rf {abi_linux_tree}
    """.format(
        abi_linux_tree = abi_linux_tree,
        unstripped_dirs = " ".join([unstripped_dir.path for unstripped_dir in unstripped_dirs]),
        dump_abi = ctx.file._dump_abi.path,
        vmlinux = vmlinux.path,
        full_abi_out_file = full_abi_out_file.path,
        epilog = _abi_dump_epilog_cmd(full_abi_out_file.path, True),
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [full_abi_out_file],
        command = command,
        mnemonic = "AbiDumpFull",
        progress_message = "Extracting ABI {}".format(ctx.label),
    )
    return full_abi_out_file

def _abi_dump_filtered(ctx, full_abi_out_file):
    abi_out_file = ctx.actions.declare_file("{}/abi.xml".format(ctx.attr.name))
    inputs = [full_abi_out_file]

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    combined_abi_symbollist = ctx.attr.kernel_build[KernelBuildAbiInfo].combined_abi_symbollist
    if combined_abi_symbollist:
        inputs += [
            ctx.file._filter_abi,
            combined_abi_symbollist,
        ]

        command += """
            {filter_abi} --in-file {full_abi_out_file} --out-file {abi_out_file} --kmi-symbol-list {abi_symbollist}
            {epilog}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
            filter_abi = ctx.file._filter_abi.path,
            abi_symbollist = combined_abi_symbollist.path,
            epilog = _abi_dump_epilog_cmd(abi_out_file.path, False),
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
        mnemonic = "AbiDumpFiltered",
        progress_message = "Filtering ABI dump {}".format(ctx.label),
    )
    return abi_out_file

abi_dump = rule(
    implementation = _abi_dump_impl,
    doc = "Extracts the ABI.",
    attrs = {
        "kernel_build": attr.label(providers = [KernelEnvInfo, KernelBuildAbiInfo, KernelUnstrippedModulesInfo]),
        "kernel_modules": attr.label_list(providers = [KernelUnstrippedModulesInfo]),
        "_dump_abi_scripts": attr.label(default = "//build/kernel:dump-abi-scripts"),
        "_dump_abi": attr.label(default = "//build/kernel:abi/dump_abi", allow_single_file = True),
        "_filter_abi": attr.label(default = "//build/kernel:abi/filter_abi", allow_single_file = True),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
