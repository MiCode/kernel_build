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

load(":common_providers.bzl", "KernelEnvInfo")
load(":debug.bzl", "debug")

def _raw_kmi_symbol_list_impl(ctx):
    if not ctx.file.src:
        return

    inputs = [ctx.file.src]
    inputs += ctx.files._kernel_abi_scripts
    inputs += ctx.attr.env[KernelEnvInfo].dependencies

    out_file = ctx.actions.declare_file("{}/abi_symbollist.raw".format(ctx.attr.name))

    command = ctx.attr.env[KernelEnvInfo].setup + """
        mkdir -p {out_dir}
        cat {src} | {flatten_symbol_list} > {out_file}
    """.format(
        out_dir = out_file.dirname,
        flatten_symbol_list = ctx.file._flatten_symbol_list.path,
        out_file = out_file.path,
        src = ctx.file.src.path,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "RawKmiSymbolList",
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Creating abi_symbollist.raw {}".format(ctx.label),
        command = command,
    )

    return DefaultInfo(files = depset([out_file]))

raw_kmi_symbol_list = rule(
    implementation = _raw_kmi_symbol_list_impl,
    doc = "Build `abi_symbollist.raw` if `src` refers to a file, otherwise don't build anything",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "src": attr.label(
            doc = "Label to `abi_symbollist`",
            allow_single_file = True,
        ),
        "_kernel_abi_scripts": attr.label(default = "//build/kernel:kernel-abi-scripts"),
        "_flatten_symbol_list": attr.label(default = "//build/kernel:abi/flatten_symbol_list", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
