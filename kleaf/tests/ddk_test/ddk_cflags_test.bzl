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

"""Tests no duplicated cflags included in DDK module's Kbuild."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_genrule")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", "ddk_module")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")

def ddk_cflags_test_suite(name):
    """Tests no duplicated cflags included in DDK module's Kbuild.

    Args:
        name: name of the test suite."""

    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = ["vmlinux"],
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_subdir",
        out = name + "_subdir.ko",
        srcs = [
            "subdir/foo.c",
            "subdir/foo.h",
        ],
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    tests = []
    hermetic_genrule(
        name = name + "_no_duplicated_lines_test",
        srcs = [
            name + "_subdir_makefiles",
        ],
        outs = ["ignore.txt"],
        cmd = """
        exit_code=0
        for file in $$(ls $<);
        do
            if [[ $${file} == Kbuild ]]
            then
                exit_code=$$(cat $</$${file} | grep "\\.cflags$$" | sort | uniq -d | wc -l)
            fi
        done
        : > $@
        exit $${exit_code}
        """,
        tags = ["manual"],
    )
    build_test(
        name = name + "_no_duplicated_lines_tests",
        targets = [name + "_no_duplicated_lines_test"],
        tags = ["manual"],
    )
    tests.append(name + "_no_duplicated_lines_tests")

    native.test_suite(
        name = name,
        tests = tests,
    )
