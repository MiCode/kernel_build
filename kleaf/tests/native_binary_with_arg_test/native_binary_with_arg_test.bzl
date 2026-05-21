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

"""Tests `native_binary_with_arg`"""

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:native_binary.bzl", "native_binary")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_genrule")
load("//build/kernel/kleaf/impl:native_binary_with_arg.bzl", "native_binary_with_arg")
load("//build/kernel/kleaf/tests:hermetic_test.bzl", "hermetic_test")

visibility("private")

def native_binary_with_arg_test(
        name,
        src,
        args,
        alias = None):
    """Tests `native_binary_with_arg`.

    Args:
        name: name of the test
        src: a binary that prints arguments, separated by new line character
        args: a list of arguments to be embedded
        alias: If set, aliases the internal binary
    """
    if alias:
        native_binary_with_arg(
            name = name + "_bin_real",
            src = src,
            args = args,
        )
        native_binary(
            name = name + "_bin",
            out = name + "_bin",
            src = name + "_bin_real",
        )
    else:
        native_binary_with_arg(
            name = name + "_bin",
            src = src,
            args = args,
        )

    hermetic_genrule(
        name = name + "_actual",
        outs = [name + "_actual.txt"],
        cmd = """
            $(location {name}_bin) > $@
        """.format(name = name),
        tools = [
            name + "_bin",
        ],
    )

    write_file(
        name = name + "_expected",
        out = name + "_expected.txt",
        content = args + [""],
    )

    diff_test(
        name = name + "_diff_test",
        file1 = name + "_actual",
        file2 = name + "_expected",
    )

    hermetic_test(
        name = name,
        actual = name + "_diff_test",
    )
