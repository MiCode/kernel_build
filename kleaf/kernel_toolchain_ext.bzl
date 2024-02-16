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
    root_toolchain_constants = []
    kleaf_toolchain_constants = []
    for module in module_ctx.modules:
        installed_constants = [installed.toolchain_constants for installed in module.tags.install]
        if module.is_root:
            root_toolchain_constants += installed_constants
        if module.name == "kleaf":
            kleaf_toolchain_constants += installed_constants

    toolchain_constants = None
    if root_toolchain_constants:
        if len(root_toolchain_constants) > 1:
            fail("kernel_toolchain_ext is installed {} times at root module, expected once".format(len(toolchain_constants)))
        toolchain_constants = root_toolchain_constants[0]
    elif kleaf_toolchain_constants:
        if len(kleaf_toolchain_constants) > 1:
            fail("kernel_toolchain_ext is installed {} times at @kleaf, expected once".format(len(toolchain_constants)))
        toolchain_constants = kleaf_toolchain_constants[0]

    if not toolchain_constants:
        fail("kernel_toolchain_ext is not installed")

    key_value_repo(
        name = "kernel_toolchain_info",
        srcs = [toolchain_constants],
    )
    clang_toolchain_repository(
        name = "kleaf_clang_toolchain",
    )

kernel_toolchain_ext = module_extension(
    doc = "Declares an extension named `kernel_toolchain_info` that contains toolchain information.",
    implementation = _kernel_toolchain_ext_impl,
    tag_classes = {
        "install": tag_class(
            doc = "Declares a potential location that contains toolchain information.",
            attrs = {
                "toolchain_constants": attr.label(mandatory = True),
            },
        ),
    },
)
