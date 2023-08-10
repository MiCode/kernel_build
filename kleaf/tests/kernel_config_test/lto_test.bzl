# Copyright (C) 2023 The Android Open Source Project
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

"""Test that, if a flag is specified, and --lto is not none or unspecified, fail."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")

def _lto_test_impl_common(ctx):
    env = analysistest.begin(ctx)

    if ctx.attr._expect_failure:
        asserts.expect_failure(env, ctx.attr._expect_failure_message)
    return analysistest.end(env)

def _make_lto_test_common(flag, flag_value, lto, expect_failure_message):
    # --lto=default becomes --lto=none when --debug; see //build/kernel/kleaf:lto_is_none.
    expect_failure = flag_value and lto not in ("default", "none")
    return analysistest.make(
        impl = _lto_test_impl_common,
        config_settings = {
            str(flag): flag_value,
            str(Label("//build/kernel/kleaf:lto")): lto,
        },
        expect_failure = expect_failure,
        attrs = {
            "_expect_failure": attr.bool(default = expect_failure),
            "_expect_failure_message": attr.string(default = expect_failure_message),
        },
    )

def _make_lto_tests_for_flag(flag, flag_values, expect_failure_message):
    return {
        (flag_value, lto): _make_lto_test_common(flag, flag_value, lto, expect_failure_message)
        for flag_value in flag_values
        for lto in LTO_VALUES
    }

def _lto_test_for_flag_common(name, flag, flag_values, test_rules):
    """Define tests for a flag that interacts with --lto.

    Args:
        name: Name for this test.
        flag: Label to the flag
        flag_values: valid values for the flag
        test_rules: return value of `_make_lto_tests_for_flag`
    """
    tests = []

    kernel_build(
        name = name + "_subject",
        tags = ["manual"],
        build_config = Label("//common:build.config.gki.aarch64"),
        outs = [],
    )
    for flag_value in flag_values:
        for lto in LTO_VALUES:
            test_name = "{}_{}_{}_lto_{}".format(name, native.package_relative_label(flag).name, flag_value, lto)
            test_rule = test_rules[flag_value, lto]
            test_rule(
                name = test_name,
                target_under_test = name + "_subject",
            )
            tests.append(test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )

_debug_tests = _make_lto_tests_for_flag(
    flag = Label("//build/kernel/kleaf:debug"),
    flag_values = (True, False),
    expect_failure_message = "--debug requires --lto=none or default",
)

# Hack to fix "Invalid rule class hasn't been exported by a bzl file"
# List all values in _debug_tests explicitly.
_debug_true_default_test = _debug_tests[True, "default"]  # @unused
_debug_true_thin_test = _debug_tests[True, "thin"]  # @unused
_debug_true_full_test = _debug_tests[True, "full"]  # @unused
_debug_true_none_test = _debug_tests[True, "none"]  # @unused
_debug_true_fast_test = _debug_tests[True, "fast"]  # @unused
_debug_false_default_test = _debug_tests[False, "default"]  # @unused
_debug_false_thin_test = _debug_tests[False, "thin"]  # @unused
_debug_false_full_test = _debug_tests[False, "full"]  # @unused
_debug_false_none_test = _debug_tests[False, "none"]  # @unused
_debug_false_fast_test = _debug_tests[False, "fast"]  # @unused

def debug_lto_test(name):
    _lto_test_for_flag_common(
        name = name,
        flag = Label("//build/kernel/kleaf:debug"),
        flag_values = (True, False),
        test_rules = _debug_tests,
    )
