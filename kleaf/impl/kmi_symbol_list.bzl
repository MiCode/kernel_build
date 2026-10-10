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

def _kmi_symbol_list_impl(ctx):
    if not ctx.files.srcs:
        return

    inputs = [] + ctx.files.srcs
    inputs += ctx.attr.env[KernelEnvInfo].dependencies
    inputs += ctx.files._kernel_abi_scripts

    outputs = []
    out_file = ctx.actions.declare_file("{}/abi_symbollist".format(ctx.attr.name))
    report_file = ctx.actions.declare_file("{}/abi_symbollist.report".format(ctx.attr.name))
    outputs = [out_file, report_file]

    command = ctx.attr.env[KernelEnvInfo].setup + """
        mkdir -p {out_dir}
        {process_symbols} --out-dir={out_dir} --out-file={out_file_base} \
            --report-file={report_file_base} --in-dir="${{ROOT_DIR}}" \
            {srcs}
    """.format(
        process_symbols = ctx.file._process_symbols.path,
        out_dir = out_file.dirname,
        out_file_base = out_file.basename,
        report_file_base = report_file.basename,
        srcs = " ".join([f.path for f in ctx.files.srcs]),
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KmiSymbolList",
        inputs = inputs,
        outputs = outputs,
        progress_message = "Creating abi_symbollist and report {}".format(ctx.label),
        command = command,
    )

    return [
        DefaultInfo(files = depset(outputs)),
        OutputGroupInfo(abi_symbollist = depset([out_file])),
    ]

kmi_symbol_list = rule(
    implementation = _kmi_symbol_list_impl,
    doc = "Build `abi_symbollist` if there are `srcs`, otherwise don't build anything.",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(
            doc = "`KMI_SYMBOL_LIST` + `ADDTIONAL_KMI_SYMBOL_LISTS`",
            allow_files = True,
        ),
        "_kernel_abi_scripts": attr.label(default = "//build/kernel:kernel-abi-scripts"),
        "_process_symbols": attr.label(default = "//build/kernel:abi/process_symbols", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
