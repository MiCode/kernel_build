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

"""Tests that different DDK use cases are properly marked."""

load(
    "//build/kernel/kleaf:kernel.bzl",
    "ddk_module",
    "ddk_submodule",
)
load(":contains_mark_test.bzl", "contains_mark_test")

def _ddk_module_test_make(
        name,
        **kwargs):
    ddk_module(
        name = name + "_module",
        tags = ["manual"],
        **kwargs
    )

    contains_mark_test(
        name = name,
        kernel_module = name + "_module",
    )

def ddk_made_test(name):
    """Tests built_with DDK marking.

    Args:
        name: name of the test suite.
    """

    # Tests
    tests = []

    # License test (a.k.a one file)
    _ddk_module_test_make(
        name = name + "_license_sample_test",
        srcs = ["license.c"],
        out = name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
        deps = ["//common:all_headers"],
    )
    tests.append(name + "_license_sample_test")

    # Test depenging on a single source ddk_module
    ddk_module(
        name = name + "_dep",
        srcs = ["dep.c"],
        out = name + "_dep.ko",
        kernel_build = "//common:kernel_aarch64",
        deps = ["//common:all_headers"],
    )
    _ddk_module_test_make(
        name = name + "_single_dep_test",
        srcs = ["license.c"],
        out = name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
        deps = [
            name + "_dep",
            "//common:all_headers",
        ],
    )
    tests.append(name + "_single_dep_test")

    # Submodule Tests
    ddk_submodule(
        name = name + "_submodule_dep_a",
        out = name + "_submodule_dep_a.ko",
        srcs = ["license.c"],
        tags = ["manual"],
    )
    _ddk_module_test_make(
        name = name + "_submodule_test",
        kernel_build = "//common:kernel_aarch64",
        deps = [
            name + "_submodule_dep_a",
            "//common:all_headers",
        ],
    )
    tests.append(name + "_submodule_test")
    ddk_submodule(
        name = name + "_submodule_dep_b",
        out = name + "_submodule_dep_b.ko",
        srcs = [
            "subdir/lic.c",
        ],
        tags = ["manual"],
    )

    _ddk_module_test_make(
        name = name + "_submodule_test_a_b",
        kernel_build = "//common:kernel_aarch64",
        deps = [
            name + "_submodule_dep_a",
            name + "_submodule_dep_b",
            "//common:all_headers",
        ],
    )
    tests.append(name + "_submodule_test_a_b")

    # Multiple source files with ddk_marker collision.
    _ddk_module_test_make(
        name = name + "_multiple_files_test",
        srcs = [
            "dep.c",
            "license.c",
        ],
        out = name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
        deps = ["//common:all_headers"],
    )
    tests.append(name + "_multiple_files_test")

    # Tests for subdirectories.
    _ddk_module_test_make(
        name = name + "_multiple_files_in_subdir_test",
        srcs = [
            "subdir/dep.c",
            "subdir/lic.c",
        ],
        out = "subdir/" + name + "_module.ko",
        kernel_build = "//common:kernel_aarch64",
        deps = ["//common:all_headers"],
    )
    tests.append(name + "_multiple_files_in_subdir_test")
    _ddk_module_test_make(
        name = name + "_single_file_in_subdir_test",
        srcs = [
            "subdir/lic.c",
        ],
        out = "subdir/" + name + "_license.ko",
        kernel_build = "//common:kernel_aarch64",
        deps = ["//common:all_headers"],
    )
    tests.append(name + "_single_file_in_subdir_test")

    # Tests all submodules from subdirs
    ddk_submodule(
        name = name + "_sub_dep",
        out = "subdir/dep.ko",
        srcs = [
            "subdir/dep.c",
        ],
        tags = ["manual"],
    )
    ddk_submodule(
        name = name + "_sub_lic",
        out = "subdir/lic.ko",
        srcs = [
            "subdir/lic.c",
        ],
        tags = ["manual"],
    )
    ddk_submodule(
        name = name + "_sub_third",
        out = "subdir/lic_third.ko",
        srcs = [
            # TODO: Check whether this is a valid case, at the
            #  moment of writting this will create a duplicated tag.
            # "subdir/lic.c",
            "subdir/third.c",
        ],
        tags = ["manual"],
    )
    ddk_submodule(
        name = name + "_srcs_one",
        out = "srcs/one.ko",
        srcs = [
            "srcs/one.c",
        ],
        tags = ["manual"],
    )
    ddk_submodule(
        name = name + "_srcs_two",
        out = "srcs/two.ko",
        srcs = [
            "srcs/two.c",
        ],
        tags = ["manual"],
    )
    ddk_submodule(
        name = name + "_src_three_four",
        out = "srcs/three_four.ko",
        srcs = [
            "srcs/three.c",
            "srcs/four.c",
        ],
        tags = ["manual"],
    )
    _ddk_module_test_make(
        name = name + "_submodules_from_subdirs_test",
        kernel_build = "//common:kernel_aarch64",
        deps = [
            name + "_sub_dep",
            name + "_sub_lic",
            name + "_sub_third",
            name + "_srcs_one",
            name + "_srcs_two",
            name + "_src_three_four",
            "//common:all_headers",
        ],
    )
    tests.append(name + "_submodules_from_subdirs_test")

    # From https://docs.kernel.org/core-api/printk-basics.html
    _ddk_module_test_make(
        name = name + "_use_printk",
        kernel_build = "//common:kernel_aarch64",
        out = "use_printk.ko",
        srcs = ["use_printk.c"],
        deps = ["//common:all_headers"],
    )
    tests.append(name + "_use_printk")

    # Single source module with headers.
    _ddk_module_test_make(
        name = name + "_single_subdir_with_headers",
        kernel_build = "//common:kernel_aarch64",
        out = "dep.ko",
        srcs = [
            "subdir/dep.c",
            "subdir/dep.h",
        ],
        deps = ["//common:all_headers"],
    )
    tests.append(name + "_single_subdir_with_headers")

    native.test_suite(
        name = name,
        tests = tests,
    )
