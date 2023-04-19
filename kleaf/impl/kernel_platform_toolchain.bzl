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

"""Helper to resolve toolchain for a single platform."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")
load(":common_providers.bzl", "KernelPlatformToolchainInfo")

def _kernel_platform_toolchain_impl(ctx):
    cc_info = cc_common.merge_cc_infos(
        cc_infos = [src[CcInfo] for src in ctx.attr.deps],
    )

    cc_toolchain = find_cpp_toolchain(ctx, mandatory = False)

    if not cc_toolchain:
        # Intentionally not put any keys so kernel_toolchains emit a hard error
        return KernelPlatformToolchainInfo()

    all_files = depset(cc_info.compilation_context.direct_headers, transitive = [
        cc_info.compilation_context.headers,
        cc_toolchain.all_files,
    ])

    return KernelPlatformToolchainInfo(
        compiler_version = cc_toolchain.compiler,
        toolchain_id = cc_toolchain.toolchain_id,
        all_files = all_files,
        # All executables are in the same place, so just use the compiler executable
        # to locate PATH.
        bin_path = paths.dirname(cc_toolchain.compiler_executable),
    )

kernel_platform_toolchain = rule(
    doc = """Helper to resolve toolchain for a single platform.""",
    implementation = _kernel_platform_toolchain_impl,
    attrs = {
        "deps": attr.label_list(providers = [CcInfo]),
        # For using mandatory = False
        "_cc_toolchain": attr.label(default = "@bazel_tools//tools/cpp:optional_current_cc_toolchain"),
    },
    toolchains = use_cpp_toolchain(mandatory = False),
    fragments = ["cpp"],
)
