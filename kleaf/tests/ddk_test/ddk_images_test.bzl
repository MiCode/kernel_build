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

"""Tests for `kernel_images` with `ddk_module`'s."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(
    "//build/kernel/kleaf:kernel.bzl",
    "ddk_module",
    "initramfs",
    "kernel_module_group",
    "kernel_modules_install",
)
load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/tests:hermetic_test.bzl", "hermetic_test")
load("//build/kernel/kleaf/tests/utils:contain_lines_test.bzl", "contain_lines_test")

def _get_top_level_file_impl(ctx):
    out = ctx.actions.declare_file(paths.join(ctx.attr.name, ctx.attr.filename))
    src = None
    for file in ctx.files.target:
        if file.basename == ctx.attr.filename:
            src = file
            break

    hermetic_tools = hermetic_toolchain.get(ctx)
    command = hermetic_tools.setup + """
        if [[ -f {src} ]]; then
            cp -pL {src} {out}
        else
            : > {out}
        fi
    """.format(
        src = src.path,
        out = out.path,
    )
    ctx.actions.run_shell(
        outputs = [out],
        inputs = ctx.files.target,
        tools = hermetic_tools.deps,
        command = command,
        mnemonic = "KernelImageTestGetTopLevelFile",
    )
    return DefaultInfo(
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]),
    )

get_top_level_file = rule(
    implementation = _get_top_level_file_impl,
    doc = "Gets the top level file from a rule.",
    attrs = {
        "target": attr.label(allow_files = True),
        "filename": attr.string(),
    },
    toolchains = [hermetic_toolchain.type],
)

def ddk_images_test_suite(name):
    """Defines analysis test for `kernel_images` with `ddk_module`'s.

    Args:
        name: Name for this test suite.
    """

    # Setup BEGIN
    # TODO: Find a way to remove this dependency on ACK.
    kernel_build_name = "//common:kernel_aarch64"
    ddk_deps = ["//common:all_headers_aarch64"]

    ddk_module(
        name = name + "_base",
        out = name + "_base.ko",
        srcs = ["license.c"],
        kernel_build = kernel_build_name,
        deps = ddk_deps,
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_self",
        out = name + "_self.ko",
        srcs = ["license.c"],
        kernel_build = kernel_build_name,
        deps = ddk_deps,
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_dep",
        out = name + "_dep.ko",
        srcs = ["license.c"],
        kernel_build = kernel_build_name,
        deps = ddk_deps,
        tags = ["manual"],
    )

    kernel_module_group(
        name = name + "_group",
        srcs = [
            name + "_self",
            name + "_base",
        ],
        tags = ["manual"],
    )

    kernel_modules_install(
        name = name + "_modules_install",
        kernel_build = kernel_build_name,
        kernel_modules = [
            name + "_group",
            name + "_dep",
        ],
        tags = ["manual"],
    )

    tests = []
    module_prefix = "extra/build/kernel/kleaf/tests/ddk_test/"

    # Default case
    initramfs(
        name = name + "_image_initramfs",
        tags = ["manual"],
        kernel_modules_install = name + "_modules_install",
    )
    write_file(
        name = name + "_expected",
        out = name + "_expected/modules.load",
        content = [
            module_prefix + name + "_self.ko",
            module_prefix + name + "_base.ko",
            module_prefix + name + "_dep.ko",
        ],
        tags = ["manual"],
    )
    get_top_level_file(
        name = name + "_modules_load",
        filename = "modules.load",
        target = name + "_image_initramfs",
        tags = ["manual"],
    )
    contain_lines_test(
        name = name + "_modules_load_test",
        expected = name + "_expected",
        actual = name + "_modules_load",
        order = True,
    )
    tests.append(name + "_modules_load_test")

    # Providing a modules.load list
    write_file(
        name = name + "_load_self_module_only",
        out = name + "_single_expected/modules.load",
        content = [
            module_prefix + name + "_self.ko",
        ],
        tags = ["manual"],
    )
    initramfs(
        name = name + "_image_initramfs_with_modules_load",
        tags = ["manual"],
        kernel_modules_install = name + "_modules_install",
        modules_load = name + "_load_self_module_only",
    )

    get_top_level_file(
        name = name + "_single_modules_load",
        filename = "modules.load",
        target = name + "_image_initramfs_with_modules_load",
        tags = ["manual"],
    )
    diff_test(
        name = name + "_single_modules_load_test",
        file1 = name + "_single_modules_load",
        file2 = name + "_load_self_module_only",
        # Avoid running it without the hermetic_test wrapper
        tags = ["manual"],
    )
    hermetic_test(
        name = name + "_single_modules_load_hermetic_test",
        actual = name + "_single_modules_load_test",
    )
    tests.append(name + "_single_modules_load_hermetic_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
