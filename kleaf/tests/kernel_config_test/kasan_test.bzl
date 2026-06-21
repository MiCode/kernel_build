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

# Test that if --kasan is specified and --lto is not none or unspecified, fail.

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")

def _kasan_test_impl(ctx):
    env = analysistest.begin(ctx)
    if ctx.attr._expect_failure:
        asserts.expect_failure(env, "--kasan requires --lto=none")
    return analysistest.end(env)

def _make_kasan_test(kasan, lto):
    # --lto=default becomes --lto=none when --kasan; see kernel_config_transition.
    expect_failure = kasan and lto not in ("default", "none")
    return analysistest.make(
        impl = _kasan_test_impl,
        config_settings = {
            "@//build/kernel/kleaf:kasan": kasan,
            "@//build/kernel/kleaf:lto": lto,
        },
        expect_failure = expect_failure,
        attrs = {
            "_expect_failure": attr.bool(default = expect_failure),
        },
    )

_kasan_tests = {
    (kasan, lto): _make_kasan_test(kasan, lto)
    for kasan in (True, False)
    for lto in LTO_VALUES
}

# Hack to fix "Invalid rule class hasn't been exported by a bzl file"
# List all values in _kasan_tests explicitly.
_kasan_true_default_test = _kasan_tests[True, "default"]
_kasan_true_thin_test = _kasan_tests[True, "thin"]
_kasan_true_full_test = _kasan_tests[True, "full"]
_kasan_true_none_test = _kasan_tests[True, "none"]
_kasan_false_default_test = _kasan_tests[False, "default"]
_kasan_false_thin_test = _kasan_tests[False, "thin"]
_kasan_false_full_test = _kasan_tests[False, "full"]
_kasan_false_none_test = _kasan_tests[False, "none"]

def kasan_test(name):
    """Define tests for `--kasan`.
    """
    tests = []

    kernel_build(
        name = name + "_subject",
        tags = ["manual"],
        build_config = "//common:build.config.gki.aarch64",
        outs = [],
    )
    for kasan in (True, False):
        for lto in LTO_VALUES:
            kasan_test_name = "{}_kasan_{}_lto_{}".format(name, kasan, lto)
            kasan_test = _kasan_tests[kasan, lto]
            kasan_test(
                name = kasan_test_name,
                target_under_test = name + "_subject",
            )
            tests.append(kasan_test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )
