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

"""Tests kernel_build.toolchain_version."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@kernel_toolchain_info//:dict.bzl", "CLANG_VERSION")
load(
    "//build/kernel/kleaf/impl:constants.bzl",
    "MODULES_STAGING_ARCHIVE",
    "UNSTRIPPED_MODULES_ARCHIVE",
)
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:kernel_filegroup.bzl", "kernel_filegroup")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//prebuilts/clang/host/linux-x86/kleaf:versions.bzl", _CLANG_VERSIONS = "VERSIONS")

def _pass_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)
    return analysistest.end(env)

_pass_analysis_test = analysistest.make(
    impl = _pass_analysis_test_impl,
    doc = "Test that `target_under_test` passes analysis phase.",
)

def kernel_toolchain_test(name):
    """Tests kernel_build.toolchain_version.

    Args:
        name: name of the test suite
    """

    tests = []
    for base_toolchain in _CLANG_VERSIONS:
        filegroup_name = name + "_filegroup_" + base_toolchain

        write_file(
            name = filegroup_name + "_staging_archive",
            out = filegroup_name + "_staging_archive/" + MODULES_STAGING_ARCHIVE,
        )
        write_file(
            name = filegroup_name + "_unstripped_modules",
            out = filegroup_name + "_unstripped_modules/" + UNSTRIPPED_MODULES_ARCHIVE,
        )

        write_file(
            name = filegroup_name + "_gki_info",
            out = filegroup_name + "_gki_info/gki-info.txt",
            content = [
                "KERNEL_RELEASE=99.98.97",
                "",
            ],
        )

        native.platform(
            name = filegroup_name + "_target_platform",
            constraint_values = [
                "@platforms//os:android",
                "@platforms//cpu:arm64",
                Label("//prebuilts/clang/host/linux-x86/kleaf:{}".format(base_toolchain)),
            ],
        )

        native.platform(
            name = filegroup_name + "_exec_platform",
            constraint_values = [
                "@platforms//os:linux",
                "@platforms//cpu:x86_64",
                Label("//prebuilts/clang/host/linux-x86/kleaf:{}".format(base_toolchain)),
            ],
        )

        kernel_filegroup(
            name = filegroup_name,
            deps = [
                filegroup_name + "_unstripped_modules",
                filegroup_name + "_staging_archive",
            ],
            gki_artifacts = filegroup_name + "_gki_info",
            target_platform = filegroup_name + "_target_platform",
            exec_platform = filegroup_name + "_exec_platform",
            tags = ["manual"],
        )

        test_name = "{name}_{device_toolchain}_against_filegroup_{base_toolchain}_test".format(
            name = name,
            device_toolchain = CLANG_VERSION,
            base_toolchain = base_toolchain,
        )
        base_kernel = "{name}_filegroup_{base_toolchain}".format(
            name = name,
            base_toolchain = base_toolchain,
        )

        kernel_build(
            name = test_name + "_device_kernel",
            base_kernel = base_kernel,
            outs = [],
            tags = ["manual"],
        )

        if base_toolchain == CLANG_VERSION:
            _pass_analysis_test(
                name = test_name,
                target_under_test = test_name + "_device_kernel",
            )
        else:
            failure_test(
                name = test_name,
                target_under_test = test_name + "_device_kernel",
                error_message_substrs = ["They must use the same `toolchain_version`."],
            )

        tests.append(test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )
