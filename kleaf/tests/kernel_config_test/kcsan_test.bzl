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

"""Test that if --kcsan is specified and --lto is not none or unspecified, fail."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")

def _kcsan_test_impl(ctx):
    env = analysistest.begin(ctx)

    if ctx.attr._expect_failure:
        asserts.expect_failure(env, "--kcsan requires --lto=none")
    return analysistest.end(env)

def _make_kcsan_test(kcsan, lto):
    # --lto=default becomes --lto=none when --kcsan; see kernel_config_transition.
    expect_failure = kcsan and lto not in ("default", "none")
    return analysistest.make(
        impl = _kcsan_test_impl,
        config_settings = {
            "@//build/kernel/kleaf:kcsan": kcsan,
            "@//build/kernel/kleaf:lto": lto,
        },
        expect_failure = expect_failure,
        attrs = {
            "_expect_failure": attr.bool(default = expect_failure),
        },
    )

_kcsan_tests = {
    (kcsan, lto): _make_kcsan_test(kcsan, lto)
    for kcsan in (True, False)
    for lto in LTO_VALUES
}

# Hack to fix "Invalid rule class hasn't been exported by a bzl file"
# List all values in _kcsan_tests explicitly.
_kcsan_true_default_test = _kcsan_tests[True, "default"]  # @unused
_kcsan_true_thin_test = _kcsan_tests[True, "thin"]  # @unused
_kcsan_true_full_test = _kcsan_tests[True, "full"]  # @unused
_kcsan_true_none_test = _kcsan_tests[True, "none"]  # @unused
_kcsan_true_fast_test = _kcsan_tests[True, "fast"]  # @unused
_kcsan_false_default_test = _kcsan_tests[False, "default"]  # @unused
_kcsan_false_thin_test = _kcsan_tests[False, "thin"]  # @unused
_kcsan_false_full_test = _kcsan_tests[False, "full"]  # @unused
_kcsan_false_none_test = _kcsan_tests[False, "none"]  # @unused
_kcsan_false_fast_test = _kcsan_tests[False, "fast"]  # @unused

def kcsan_test(name):
    """Define tests for `--kcsan`.

    Args:
        name: Name for this test.
    """
    tests = []

    kernel_build(
        name = name + "_subject",
        tags = ["manual"],
        build_config = "//common:build.config.gki.aarch64",
        outs = [],
    )
    for kcsan in (True, False):
        for lto in LTO_VALUES:
            kcsan_test_name = "{}_kcsan_{}_lto_{}".format(name, kcsan, lto)
            kcsan_test = _kcsan_tests[kcsan, lto]
            kcsan_test(
                name = kcsan_test_name,
                target_under_test = name + "_subject",
            )
            tests.append(kcsan_test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )
