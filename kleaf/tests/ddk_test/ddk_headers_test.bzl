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

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", "DdkHeadersInfo", "ddk_headers")

def _good_includes_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    asserts.set_equals(
        env,
        sets.make(ctx.attr.expected_includes),
        sets.make(target_under_test[DdkHeadersInfo].includes.to_list()),
    )

    return analysistest.end(env)

_good_includes_test = analysistest.make(
    impl = _good_includes_test_impl,
    attrs = {
        "expected_includes": attr.string_list(),
    },
)

def _ddk_headers_good_includes_test(name, includes, expected_includes):
    ddk_headers(
        name = name + "_headers",
        includes = includes,
        tags = ["manual"],
    )
    _good_includes_test(
        name = name,
        target_under_test = name + "_headers",
        expected_includes = expected_includes,
    )

def _bad_includes_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.error_message)
    return analysistest.end(env)

_bad_includes_test = analysistest.make(
    impl = _bad_includes_test_impl,
    attrs = {"error_message": attr.string()},
    expect_failure = True,
)

def _ddk_headers_bad_includes_test(name, includes, error_message):
    ddk_headers(
        name = name + "_headers",
        includes = includes,
        tags = ["manual"],
    )
    _bad_includes_test(
        name = name,
        target_under_test = name + "_headers",
        error_message = error_message,
    )

def ddk_headers_test_suite(name):
    """Defines analysis test for `ddk_headers`."""

    tests = []

    _ddk_headers_good_includes_test(
        name = name + "_self",
        includes = ["."],
        expected_includes = [native.package_name()],
    )
    tests.append(name + "_self")

    _ddk_headers_good_includes_test(
        name = name + "_subdir",
        includes = ["include"],
        expected_includes = ["{}/include".format(native.package_name())],
    )
    tests.append(name + "_subdir")

    _ddk_headers_good_includes_test(
        name = name + "_subdir_subdir",
        includes = ["include/foo"],
        expected_includes = ["{}/include/foo".format(native.package_name())],
    )
    tests.append(name + "_subdir_subdir")

    _ddk_headers_good_includes_test(
        name = name + "_multiple",
        includes = [".", "include", "include/foo"],
        expected_includes = [
            native.package_name(),
            "{}/include".format(native.package_name()),
            "{}/include/foo".format(native.package_name()),
        ],
    )
    tests.append(name + "_multiple")

    _ddk_headers_bad_includes_test(
        name = name + "_prefix_dot",
        includes = ["./foo"],
        error_message = "not normalized to foo",
    )
    tests.append(name + "_prefix_dot")

    _ddk_headers_bad_includes_test(
        name = name + "_trailing_slash",
        includes = ["foo/"],
        error_message = "not normalized to foo",
    )
    tests.append(name + "_trailing_slash")

    _ddk_headers_bad_includes_test(
        name = name + "_absolute",
        includes = ["/foo"],
        error_message = "Absolute directories not allowed",
    )
    tests.append(name + "_absolute")

    _ddk_headers_bad_includes_test(
        name = name + "_parent_include",
        includes = [".."],
        error_message = "Invalid include directory",
    )
    tests.append(name + "_parent_include")

    _ddk_headers_bad_includes_test(
        name = name + "_parent_self_include",
        includes = ["../" + paths.basename(native.package_name())],
        error_message = "Invalid include directory",
    )
    tests.append(name + "_parent_self_include")

    native.test_suite(
        name = name,
        tests = tests,
    )
