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

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:ddk/makefiles.bzl", "makefiles")
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", "ddk_headers")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")

def _argv_to_dict(argv):
    """A naive algorithm that transforms argv to a dictionary.

    E.g.:

    ```
    _argv_to_dict(["--foo", "bar", "baz", "--qux", "quux"])
    ```

    produces

    ```
    {
        "--foo": ["bar", "baz"],
        "--qux": ["quux"]
    }
    ```
    """

    ret = dict()
    key = None

    for item in argv:
        if item.startswith("-"):
            key = item
            if key not in ret:
                ret[key] = []
        else:
            ret[key].append(item)

    return ret

def _makefiles_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)
    asserts.equals(env, 1, len(actions))
    argv_dict = _argv_to_dict(actions[0].argv[1:])

    asserts.set_equals(
        env,
        sets.make(argv_dict.get("--kernel-module-srcs", [])),
        sets.make([e.path for e in ctx.files.expected_module_srcs]),
    )
    asserts.equals(env, argv_dict.get("--kernel-module-out"), [ctx.attr.expected_module_out])

    # We don't have tests on deps = [some module], so it is always empty
    asserts.set_equals(
        env,
        sets.make(argv_dict.get("--module-symvers-list", [])),
        sets.make([]),
    )

    asserts.set_equals(
        env,
        sets.make(argv_dict.get("--include-dirs", [])),
        sets.make(ctx.attr.expected_includes),
    )

    return analysistest.end(env)

_makefiles_test = analysistest.make(
    impl = _makefiles_test_impl,
    attrs = {
        "expected_module_srcs": attr.label_list(allow_files = True),
        "expected_module_out": attr.string(),
        "expected_includes": attr.string_list(),
    },
)

def _makefiles_test_make(
        name,
        expected_includes = None,
        **kwargs):
    makefiles(
        name = name + "_makefiles",
        tags = ["manual"],
        **kwargs
    )

    _makefiles_test(
        name = name,
        target_under_test = name + "_makefiles",
        expected_module_srcs = kwargs.get("module_srcs"),
        expected_module_out = kwargs.get("module_out"),
        expected_includes = expected_includes,
    )

def _bad_dep_test_make(
        name,
        error_message,
        **kwargs):
    makefiles(
        name = name + "_makefiles",
        tags = ["manual"],
        **kwargs
    )
    failure_test(
        name = name,
        target_under_test = name + "_makefiles",
        error_message_substrs = [error_message],
    )

def makefiles_test_suite(name):
    """Defines analysis test for `makefiles`."""
    tests = []

    _makefiles_test_make(
        name = name + "_simple",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
    )
    tests.append(name + "_simple")

    _makefiles_test_make(
        name = name + "_multiple_sources",
        module_srcs = ["self.c", "dep.c"],
        module_out = "foo.ko",
    )
    tests.append(name + "_multiple_sources")

    ddk_headers(
        name = name + "_base_headers",
        hdrs = ["self.h"],
        includes = ["."],
    )

    _makefiles_test_make(
        name = name + "_dep_on_headers",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_deps = [name + "_base_headers"],
        expected_includes = [native.package_name()],
    )
    tests.append(name + "_dep_on_headers")

    native.filegroup(
        name = name + "_empty_filegroup",
        srcs = [],
        tags = ["manual"],
    )
    _bad_dep_test_make(
        name = name + "_bad_dep",
        error_message = "is not a valid item in deps",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_deps = [name + "_empty_filegroup"],
    )
    tests.append(name + "_bad_dep")

    native.test_suite(
        name = name,
        tests = tests,
    )
