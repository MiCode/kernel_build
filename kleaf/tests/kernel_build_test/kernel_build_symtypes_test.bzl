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

# Test `kbuild_symtypes`.

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load(":kernel_env_aspect.bzl", "KernelEnvAspectInfo", "kernel_env_aspect")

def _kbuild_symtypes_test_make_vars(ctx, env):
    kernel_build = analysistest.target_under_test(env)
    kernel_env = kernel_build[KernelEnvAspectInfo].kernel_env
    found_action = False
    found_command = False
    for action in kernel_env.actions:
        if action.mnemonic == "KernelEnv":
            found_action = True
            for arg in action.argv:
                if "KBUILD_SYMTYPES=1" in arg:
                    found_command = True

    asserts.true(
        env,
        found_action,
        msg = "Unable to find `KernelEnv` action in `kernel_env` target {}".format(kernel_env.label),
    )

    asserts.equals(
        env,
        actual = found_command,
        expected = ctx.attr.expect_kbuild_symtypes,
        msg = "expect_kbuild_symtypes = {}, but KBUILD_SYMTYPES is {}found".format(ctx.attr.expect_kbuild_symtypes, "" if found_command else "not "),
    )

def _kbuild_symtypes_test_output(ctx, env):
    kernel_build = analysistest.target_under_test(env)

    found_action = False
    for action in analysistest.target_actions(env):
        if action.mnemonic == "KernelBuild":
            for output in action.outputs.to_list():
                if output.is_directory and output.basename == "symtypes":
                    found_action = True

    asserts.equals(
        env,
        actual = found_action,
        expected = ctx.attr.expect_kbuild_symtypes,
        msg = "expect_kbuild_symtypes = {}, but {} symtypes/ directory".format(ctx.attr.expect_kbuild_symtypes, "found" if found_action else "not found"),
    )

# Check effect of kbuild_symtypes
def _kbuild_symtypes_test_impl(ctx):
    env = analysistest.begin(ctx)

    _kbuild_symtypes_test_make_vars(ctx, env)
    _kbuild_symtypes_test_output(ctx, env)

    return analysistest.end(env)

def _make_kbuild_symtypes_test(kbuild_symtypes_flag_value):
    return analysistest.make(
        impl = _kbuild_symtypes_test_impl,
        attrs = {
            "expect_kbuild_symtypes": attr.bool(),
        },
        config_settings = {
            "@//build/kernel/kleaf:kbuild_symtypes": kbuild_symtypes_flag_value,
        },
        extra_target_under_test_aspects = [kernel_env_aspect],
    )

kbuild_symtypes_flag_true_test = _make_kbuild_symtypes_test(True)
kbuild_symtypes_flag_false_test = _make_kbuild_symtypes_test(False)

def kernel_build_symtypes_test(test_suite_name):
    """Define tests for `kbuild_symtypes`.

    Args:
      test_suite_name: Name of the main test suite.

    Returns:
      Name of the sub-test-suite.
    """
    name = test_suite_name + "_test_kbuild_symtypes"
    tests = []

    for kbuild_symtypes in ("true", "false", "auto"):
        kernel_build(
            name = name + "_" + kbuild_symtypes + "_subject",
            tags = ["manual"],
            build_config = "//common:build.config.gki.aarch64",
            outs = [],
            kbuild_symtypes = kbuild_symtypes,
        )

        kbuild_symtypes_flag_true_test(
            name = name + "_" + kbuild_symtypes + "_flag_true",
            target_under_test = name + "_" + kbuild_symtypes + "_subject",
            expect_kbuild_symtypes = kbuild_symtypes in ("true", "auto"),
        )
        tests.append(name + "_" + kbuild_symtypes + "_flag_true")

        kbuild_symtypes_flag_false_test(
            name = name + "_" + kbuild_symtypes + "_flag_false",
            target_under_test = name + "_" + kbuild_symtypes + "_subject",
            expect_kbuild_symtypes = kbuild_symtypes == "true",
        )
        tests.append(name + "_" + kbuild_symtypes + "_flag_false")

    native.test_suite(
        name = name,
        tests = tests,
    )
    return name
