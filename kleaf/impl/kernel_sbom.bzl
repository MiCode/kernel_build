# Copyright (C) 2023 The Android Open Source Project
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

"""Generate an SPDX SBOM."""

load(":common_providers.bzl", "KernelBuildUnameInfo")

def _kernel_sbom_impl(ctx):
    out_file = ctx.actions.declare_file("{}/kernel_sbom.spdx.json".format(ctx.label.name))
    kernel_release = ctx.attr.kernel[KernelBuildUnameInfo].kernel_release

    command = """{kernel_sbom}                         \
                   --output_file {out_file}            \
                   --files {srcs}                      \
                   --version_file {kernel_release}
        """.format(
        kernel_sbom = ctx.executable._kernel_sbom.path,
        out_file = out_file.path,
        srcs = " ".join([f.path for f in ctx.files.srcs]),
        kernel_release = kernel_release.path,
    )

    ctx.actions.run_shell(
        mnemonic = "KernelSbom",
        inputs = ctx.files.srcs + [kernel_release],
        tools = [ctx.executable._kernel_sbom],
        outputs = [out_file],
        progress_message = "Generating Kernel SBOM %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(files = depset([out_file])),
    ]

kernel_sbom = rule(
    implementation = _kernel_sbom_impl,
    doc = """Generate an SPDX SBOM for kernels.""",
    attrs = {
        "srcs": attr.label_list(mandatory = True, allow_files = True),
        "kernel": attr.label(
            mandatory = True,
            providers = [KernelBuildUnameInfo],
        ),
        "_kernel_sbom": attr.label(
            default = "//build/kernel/kleaf:kernel_sbom",
            cfg = "exec",
            executable = True,
        ),
    },
)
