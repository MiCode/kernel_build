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

# Test `strip_modules`.

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:abi/kernel_build_abi.bzl", "kernel_build_abi")
load("//build/kernel/kleaf/impl:kernel_module.bzl", "kernel_module")

# Check effect of strip_modules
def _strip_modules_test_impl(ctx):
    env = analysistest.begin(ctx)
    found_action = False
    for action in analysistest.target_actions(env):
        if action.mnemonic == ctx.attr.action_mnemonic:
            for arg in action.argv:
                if "INSTALL_MOD_STRIP=1" in arg:
                    found_action = True
                    break
    asserts.equals(
        env,
        actual = found_action,
        expected = ctx.attr.expect_strip_modules,
        msg = "expect_strip_modules = {}, but INSTALL_MOD_STRIP=1 {}".format(
            ctx.attr.expect_strip_modules,
            "found" if found_action else "not found",
        ),
    )
    return analysistest.end(env)

_strip_modules_test = analysistest.make(
    impl = _strip_modules_test_impl,
    attrs = {
        "expect_strip_modules": attr.bool(),
        "action_mnemonic": attr.string(
            mandatory = True,
            values = ["KernelBuild", "KernelModule"],
        ),
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

        # kernel_build_abi defines different targets depending on this
        #  attribute, so adding both to cover more targets.
        for define_abi_targets in (True, False):
            kernel_build_abi(
                name = name_prefix + str(define_abi_targets) + "_abi",
                build_config = "build.config.fake",
                outs = [],
                define_abi_targets = define_abi_targets,
                # Note: When working with mixed builds, device and base kernel
                #  are considered separated and can have distintic values.
                strip_modules = strip_modules,
                tags = ["manual"],
            )
            _strip_modules_test(
                name = test_prefix + str(define_abi_targets) + "_abi_test",
                target_under_test = name_prefix + str(define_abi_targets) + "_abi",
                action_mnemonic = "KernelBuild",
                expect_strip_modules = strip_modules,
            )
            tests.append(name_prefix + str(define_abi_targets) + "_abi_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
