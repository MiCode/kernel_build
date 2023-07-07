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

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//build/kernel/kleaf/impl:constants.bzl",
    "MODULES_STAGING_ARCHIVE",
)
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:kernel_filegroup.bzl", "kernel_filegroup")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//build/kernel/kleaf/tests:test_utils.bzl", "test_utils")
load("//prebuilts/clang/host/linux-x86/kleaf:versions.bzl", _CLANG_VERSIONS = "VERSIONS")

def _kernel_toolchain_pass_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)

    if ctx.files.toolchain_version_file:
        check_action = test_utils.find_action(env, "KernelBuildCheckToolchain")
        asserts.true(
            env,
            ctx.files.toolchain_version_file[0] in check_action.inputs.to_list(),
            "{}: {} not in inputs of KernelBuildCheckToolchain".format(
                analysistest.target_under_test(env).label,
                ctx.files.toolchain_version_file[0],
            ),
        )

    return analysistest.end(env)

_kernel_toolchain_pass_analysis_test = analysistest.make(
    impl = _kernel_toolchain_pass_analysis_test_impl,
    attrs = {
        "toolchain_version_file": attr.label(
            doc = """If set, also check that there is a `KernelBuildCheckToolchain` action
                     that checks against the given label.""",
        ),
    },
)

def kernel_toolchain_test(name):
    """Tests kernel_build.toolchain_version.

    Args:
        name: name of the test suite
    """

    for clang_version in _CLANG_VERSIONS:
        kernel_build(
            name = name + "_kernel_" + clang_version,
            toolchain_version = clang_version,
            build_config = "build.config.fake",
            outs = [],
            tags = ["manual"],
        )

        filegroup_name = name + "_filegroup_" + clang_version

        write_file(
            name = filegroup_name + "_staging_archive",
            out = filegroup_name + "_staging_archive/" + MODULES_STAGING_ARCHIVE,
        )
        write_file(
            name = filegroup_name + "_unstripped_modules",
            out = filegroup_name + "_unstripped_modules/unstripped_modules.tar.gz",
        )

        write_file(
            name = filegroup_name + "_module_outs_file",
            out = filegroup_name + "_module_outs_file/my_modules",
        )

        write_file(
            name = filegroup_name + "_gki_info",
            out = filegroup_name + "_gki_info/gki-info.txt",
            content = [
                "KERNEL_RELEASE=99.98.97",
                "",
            ],
        )

        write_file(
            name = filegroup_name + "_toolchain_version",
            out = filegroup_name + "/toolchain_version",
            content = [clang_version],
        )

        kernel_filegroup(
            name = filegroup_name,
            deps = [
                filegroup_name + "_toolchain_version",
                filegroup_name + "_unstripped_modules",
                filegroup_name + "_staging_archive",
            ],
            module_outs_file = filegroup_name + "_module_outs_file",
            gki_artifacts = filegroup_name + "_gki_info",
            tags = ["manual"],
        )

    tests = []

    for base_kernel_type in ("kernel", "filegroup"):
        for base_toolchain in _CLANG_VERSIONS:
            for device_toolchain in _CLANG_VERSIONS:
                test_name = "{name}_{device_toolchain}_against_{base_kernel_type}_{base_toolchain}_test".format(
                    name = name,
                    device_toolchain = device_toolchain,
                    base_kernel_type = base_kernel_type,
                    base_toolchain = base_toolchain,
                )
                base_kernel = "{name}_{base_kernel_type}_{base_toolchain}".format(
                    name = name,
                    base_kernel_type = base_kernel_type,
                    base_toolchain = base_toolchain,
                )

                kernel_build(
                    name = test_name + "_device_kernel",
                    base_kernel = base_kernel,
                    toolchain_version = device_toolchain,
                    build_config = "build.config.fake",
                    outs = [],
                    tags = ["manual"],
                )

                if base_kernel_type == "filegroup":
                    # When base_kernel is a kernel_filegroup, the check is deferred to
                    # execution phase, so analysis phase always passes.
                    # Check that there's an action in the execution phase to check toolchain
                    # version.
                    _kernel_toolchain_pass_analysis_test(
                        name = test_name,
                        target_under_test = test_name + "_device_kernel",
                        toolchain_version_file = base_kernel + "_toolchain_version",
                    )
                elif base_toolchain == device_toolchain:
                    _kernel_toolchain_pass_analysis_test(
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
