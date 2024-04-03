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

"""
 Test `strip_modules`.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:kernel_module.bzl", "kernel_module")
load("//build/kernel/kleaf/tests:test_utils.bzl", "test_utils")

# Check effect of strip_modules
def _strip_modules_test_impl(ctx):
    env = analysistest.begin(ctx)

    expected_mnemonic = ctx.attr.action_mnemonic

    action = test_utils.find_action(env, expected_mnemonic)
    script = test_utils.get_shell_script(env, action)
    found_strip_modules = "INSTALL_MOD_STRIP=1" in script

    asserts.equals(
        env,
        actual = found_strip_modules,
        expected = ctx.attr.expect_strip_modules,
        msg = "expect_strip_modules = {}, but INSTALL_MOD_STRIP=1 {}".format(
            ctx.attr.expect_strip_modules,
            "found" if found_strip_modules else "not found",
        ),
    )
    return analysistest.end(env)

_ANALYSIS_TEST_ATTRS = {
    "action_mnemonic": attr.string(
        mandatory = True,
        values = [
            "KernelBuild",
            "KernelModule",
        ],
    ),
    "expect_strip_modules": attr.bool(),
    "_config_is_local": attr.label(
        default = "//build/kernel/kleaf:config_local",
    ),
}

_strip_modules_test = analysistest.make(
    impl = _strip_modules_test_impl,
    attrs = _ANALYSIS_TEST_ATTRS,
)

_strip_modules_debug_test = analysistest.make(
    impl = _strip_modules_test_impl,
    attrs = _ANALYSIS_TEST_ATTRS,
    config_settings = {
        str(Label("//build/kernel/kleaf:debug")): True,
    },
)

def kernel_build_strip_modules_test(name):
    """Define tests for `strip_modules`.

    Args:
      name: Name of this test suite.
    """
    tests = []

    for strip_modules in (True, False, None):
        strip_modules_str = str(strip_modules)
        name_prefix = name + strip_modules_str
        test_prefix = name + "_strip_modules_" + strip_modules_str
        kernel_build(
            name = name_prefix + "_build",
            build_config = "build.config.fake",
            outs = [],
            strip_modules = strip_modules,
            tags = ["manual"],
        )
        _strip_modules_test(
            name = test_prefix + "_build_test",
            target_under_test = name_prefix + "_build",
            action_mnemonic = "KernelBuild",
            expect_strip_modules = bool(strip_modules),
        )
        tests.append(test_prefix + "_build_test")

        _strip_modules_debug_test(
            name = test_prefix + "_build_debug_test",
            target_under_test = name_prefix + "_build",
            action_mnemonic = "KernelBuild",
            expect_strip_modules = False,
        )
        tests.append(test_prefix + "_build_debug_test")

        kernel_module(
            name = name_prefix + "_module",
            kernel_build = name_prefix + "_build",
            tags = ["manual"],
        )
        _strip_modules_test(
            name = test_prefix + "_module_test",
            target_under_test = name_prefix + "_module",
            action_mnemonic = "KernelModule",
            expect_strip_modules = strip_modules,
        )
        tests.append(test_prefix + "_module_test")

        _strip_modules_debug_test(
            name = test_prefix + "_module_debug_test",
            target_under_test = name_prefix + "_module",
            action_mnemonic = "KernelModule",
            expect_strip_modules = False,
        )
        tests.append(test_prefix + "_module_debug_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
