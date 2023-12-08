# Copyright (C) 2024 The Android Open Source Project
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

"""Module extension that instantiates key_value_repo."""

load("//build/kernel/kleaf:key_value_repo.bzl", "key_value_repo")
load("//prebuilts/clang/host/linux-x86/kleaf:clang_toolchain_repository.bzl", "clang_toolchain_repository")

visibility("public")

def _kernel_toolchain_ext_impl(module_ctx):
    toolchain_constants = []
    for module in module_ctx.modules:
        for installed in module.tags.install:
            toolchain_constants.append(installed._toolchain_constants)

    if not toolchain_constants:
        fail("kernel_toolchain_ext is not installed")

    if len(toolchain_constants) > 1:
        fail("kernel_toolchain_ext is installed {} times, expected once".format(len(toolchain_constants)))

    key_value_repo(
        name = "kernel_toolchain_info",
        srcs = [toolchain_constants[0]],
    )
    clang_toolchain_repository(
        name = "kleaf_clang_toolchain",
    )

def make_kernel_toolchain_ext(toolchain_constants):
    return module_extension(
        doc = "Declares an extension named `kernel_toolchain_info` that contains toolchain information.",
        implementation = _kernel_toolchain_ext_impl,
        tag_classes = {
            "install": tag_class(
                doc = "Declares a potential location that contains toolchain information.",
                attrs = {
                    "_toolchain_constants": attr.label(default = toolchain_constants),
                },
            ),
        },
    )
