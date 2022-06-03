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

load(
    ":common_providers.bzl",
    "KernelBuildInfo",
    "KernelEnvInfo",
)
load(":debug.bzl", "debug")

def _kernel_headers_impl(ctx):
    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.env[KernelEnvInfo].dependencies
    inputs += [
        ctx.attr.kernel_build[KernelBuildInfo].out_dir_kernel_headers_tar,
    ]
    out_file = ctx.actions.declare_file("{}/kernel-headers.tar.gz".format(ctx.label.name))
    command = ctx.attr.env[KernelEnvInfo].setup + """
            # Restore headers in ${{OUT_DIR}}
              mkdir -p ${{OUT_DIR}}
              tar xf {out_dir_kernel_headers_tar} -C ${{OUT_DIR}}
            # Create archive
              (
                real_out_file=$(realpath {out_file})
                cd ${{ROOT_DIR}}/${{KERNEL_DIR}}
                find arch include ${{OUT_DIR}} -name *.h -print0         \
                    | tar czf ${{real_out_file}}                         \
                        --absolute-names                                 \
                        --dereference                                    \
                        --transform "s,.*$OUT_DIR,,"                     \
                        --transform "s,^,kernel-headers/,"               \
                        --null -T -
              )
    """.format(
        out_file = out_file.path,
        out_dir_kernel_headers_tar = ctx.attr.kernel_build[KernelBuildInfo].out_dir_kernel_headers_tar.path,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelHeaders",
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Building kernel headers %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(files = depset([out_file])),
    ]

kernel_headers = rule(
    implementation = _kernel_headers_impl,
    doc = "Build `kernel-headers.tar.gz`",
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelBuildInfo],  # for out_dir_kernel_headers_tar only
        ),
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
