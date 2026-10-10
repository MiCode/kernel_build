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

load(":constants.bzl", "TOOLCHAIN_VERSION_FILENAME")
load(":utils.bzl", "utils")

KernelToolchainInfo = provider(fields = {
    "toolchain_version": "The toolchain version",
    "toolchain_version_file": "A file containing the toolchain version",
})

def _kernel_toolchain_aspect_impl(target, ctx):
    if ctx.rule.kind == "_kernel_build":
        return ctx.rule.attr.config[KernelToolchainInfo]
    if ctx.rule.kind == "kernel_config":
        return ctx.rule.attr.env[KernelToolchainInfo]
    if ctx.rule.kind == "kernel_env":
        return KernelToolchainInfo(toolchain_version = ctx.rule.attr.toolchain_version)

    if ctx.rule.kind == "kernel_filegroup":
        # Create a depset that contains all files referenced by "srcs"
        all_srcs = depset([], transitive = [src.files for src in ctx.rule.attr.srcs])

        # Traverse this depset and look for a file named "toolchain_version".
        # If no file matches, leave it as None so that _kernel_build_check_toolchain prints a
        # warning.
        toolchain_version_file = utils.find_file(name = TOOLCHAIN_VERSION_FILENAME, files = all_srcs.to_list(), what = ctx.label)
        return KernelToolchainInfo(toolchain_version_file = toolchain_version_file)

    fail("{label}: Unable to get toolchain info because {kind} is not supported.".format(
        kind = ctx.rule.kind,
        label = ctx.label,
    ))

kernel_toolchain_aspect = aspect(
    implementation = _kernel_toolchain_aspect_impl,
    doc = "An aspect describing the toolchain of a `_kernel_build`, `kernel_config`, or `kernel_env` rule.",
    attr_aspects = [
        "config",
        "env",
    ],
)
