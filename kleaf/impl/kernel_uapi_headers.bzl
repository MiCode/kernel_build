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

def _kernel_uapi_headers_impl(ctx):
    out_file = ctx.actions.declare_file("{}/kernel-uapi-headers.tar.gz".format(ctx.label.name))
    command = ctx.attr.config[KernelEnvInfo].setup + """
         # Create staging directory
           mkdir -p {kernel_uapi_headers_dir}/usr
         # Actual headers_install
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} INSTALL_HDR_PATH=$(realpath {kernel_uapi_headers_dir}/usr) headers_install
         # Create archive
           tar czf {out_file} --directory={kernel_uapi_headers_dir} usr/
         # Delete kernel_uapi_headers_dir because it is not declared
           rm -rf {kernel_uapi_headers_dir}
    """.format(
        out_file = out_file.path,
        kernel_uapi_headers_dir = out_file.path + "_staging",
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelUapiHeaders",
        inputs = ctx.files.srcs + ctx.attr.config[KernelEnvInfo].dependencies,
        outputs = [out_file],
        progress_message = "Building UAPI kernel headers %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(files = depset([out_file])),
    ]

kernel_uapi_headers = rule(
    implementation = _kernel_uapi_headers_impl,
    doc = """Build kernel-uapi-headers.tar.gz""",
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "config": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "the kernel_config target",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
