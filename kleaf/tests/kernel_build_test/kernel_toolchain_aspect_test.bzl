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

def _kernel_toolchain_pass_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)

    if ctx.files.toolchain_version_file:
        check_action = test_utils.find_action(env, "KernelBuildCheckToolchain")
        asserts.true(env, ctx.files.toolchain_version_file[0] in check_action.inputs.to_list())

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

def _make_fake_toolchain(name):
    native.filegroup(
        name = name,
        srcs = [],
        tags = ["manual"],
    )
    label = "//{}:{}".format(native.package_name(), name)
    write_file(
        name = name + "_file",
        out = name + "_file/toolchain_version",
        content = [label],
        tags = ["manual"],
    )
    return struct(label = label, file = name + "_file")

def kernel_toolchain_aspect_test(name):
    suffixes = ("a", "b")

    toolchains = {
        suffix: _make_fake_toolchain(name + "_fake_toolchain_" + suffix)
        for suffix in suffixes
    }

    for base_suffix, base_toolchain in toolchains.items():
        kernel_build(
            name = name + "_kernel_" + base_suffix,
            toolchain_version = base_toolchain.label,
            build_config = "build.config.fake",
            outs = [],
            tags = ["manual"],
        )

        filegroup_name = name + "_filegroup_" + base_suffix

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

        kernel_filegroup(
            name = filegroup_name,
            deps = [
                base_toolchain.file,
                filegroup_name + "_unstripped_modules",
                filegroup_name + "_staging_archive",
            ],
            module_outs_file = filegroup_name + "_module_outs_file",
            tags = ["manual"],
        )

    tests = []

    for base_kernel_type in ("kernel", "filegroup"):
        for base_suffix, base_toolchain in toolchains.items():
            for device_suffix, device_toolchain in toolchains.items():
                test_name = "{name}_{device_suffix}_against_{base_kernel_type}_{base_suffix}_test".format(
                    name = name,
                    device_suffix = device_suffix,
                    base_kernel_type = base_kernel_type,
                    base_suffix = base_suffix,
                )
                base_kernel = "{name}_{base_kernel_type}_{base_suffix}".format(
                    name = name,
                    base_kernel_type = base_kernel_type,
                    base_suffix = base_suffix,
                )

                kernel_build(
                    name = test_name + "_device_kernel",
                    base_kernel = base_kernel,
                    toolchain_version = device_toolchain.label,
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
                        toolchain_version_file = base_toolchain.label,
                    )
                elif base_suffix == device_suffix:
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
