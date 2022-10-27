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
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load("//build/kernel/kleaf/impl:ddk/makefiles.bzl", "makefiles")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", "ddk_module")
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", "ddk_headers")
load("//build/kernel/kleaf/impl:common_providers.bzl", "ModuleSymversInfo")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//build/kernel/kleaf/tests/utils:contain_lines_test.bzl", "contain_lines_test")

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

    action = None
    for item in actions:
        if item.mnemonic == "DdkMakefiles":
            action = item

    asserts.true(env, action)

    argv_dict = _argv_to_dict(action.argv[1:])

    asserts.set_equals(
        env,
        sets.make(argv_dict.get("--kernel-module-srcs", [])),
        sets.make([e.path for e in ctx.files.expected_module_srcs]),
    )
    asserts.equals(env, argv_dict.get("--kernel-module-out"), [ctx.attr.expected_module_out])

    expected_module_symvers = []
    for dep in ctx.attr.expected_deps:
        if ModuleSymversInfo in dep:
            expected_module_symvers.append(dep[ModuleSymversInfo].restore_path)
    asserts.set_equals(
        env,
        sets.make(argv_dict.get("--module-symvers-list", [])),
        sets.make(expected_module_symvers),
    )

    # Check content + ordering of include dirs, so do list comparison.
    asserts.equals(
        env,
        argv_dict.get("--include-dirs", []),
        ctx.attr.expected_includes,
    )

    return analysistest.end(env)

_makefiles_test = analysistest.make(
    impl = _makefiles_test_impl,
    attrs = {
        "expected_module_srcs": attr.label_list(allow_files = True),
        "expected_module_out": attr.string(),
        "expected_includes": attr.string_list(),
        "expected_deps": attr.label_list(),
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
        expected_deps = kwargs.get("module_deps"),
    )

def _bad_test_make(
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

def _get_kbuild_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + "/Kbuild")
    src = paths.join(ctx.file.target.path, "Kbuild")
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        cp -pl {src} {out}
    """.format(
        src = src,
        out = out.path,
    )
    ctx.actions.run_shell(
        outputs = [out],
        inputs = [ctx.file.target],
        tools = ctx.attr._hermetic_tools[HermeticToolsInfo].deps,
        command = command,
    )
    return DefaultInfo(
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]),
    )

_get_kbuild = rule(
    implementation = _get_kbuild_impl,
    doc = "Gets the top level `Kbuild` file from a `makefiles` rule.",
    attrs = {
        "target": attr.label(allow_single_file = True),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
    },
)

def _create_makefiles_artifact_test(
        name,
        expected_lines,
        local_defines = None,
        copts = None):
    """Creates a test on the `Kbuild` file generated by `makefiles`."""
    makefiles(
        name = name + "_module_makefiles",
        module_out = name + "_module.ko",
        module_srcs = ["base.c", "self.h"],
        module_local_defines = local_defines,
        module_copts = copts,
        tags = ["manual"],
    )

    write_file(
        name = name + "_expected",
        out = name + "_expected/Kbuild",
        content = expected_lines,
    )

    _get_kbuild(
        name = name + "_kbuild",
        target = name + "_module_makefiles",
    )

    contain_lines_test(
        name = name,
        expected = name + "_expected",
        actual = name + "_kbuild",
    )

def _makefiles_build_test(name):
    """Define build tests for `makefiles`"""
    makefiles(
        name = name + "_subdir_sources_makefiles",
        module_out = name + "_subdir_sources.ko",
        module_srcs = [
            "subdir/foo.c",
        ],
        tags = ["manual"],
    )

    build_test(
        name = name,
        targets = [
            name + "_subdir_sources_makefiles",
        ],
    )

def _makefiles_local_defines_test(name):
    """Defines all tests on `makefiles.local_defines`."""

    tests = []

    _create_makefiles_artifact_test(
        name = name + "_number",
        expected_lines = ["ccflags-y += -DNUMBER=123"],
        local_defines = ["NUMBER=123"],
    )
    tests.append(name + "_number")

    _create_makefiles_artifact_test(
        name = name + "_bool",
        expected_lines = ["ccflags-y += -DBOOL"],
        local_defines = ["BOOL"],
    )
    tests.append(name + "_bool")

    _create_makefiles_artifact_test(
        name = name + "_str",
        expected_lines = ["ccflags-y += -DSTR=string"],
        local_defines = ["STR=string"],
    )
    tests.append(name + "_str")

    _create_makefiles_artifact_test(
        name = name + "_spaces",
        expected_lines = ["ccflags-y += '-DSTR=this is quoted'"],
        local_defines = ["STR=this is quoted"],
    )
    tests.append(name + "_spaces")

    _create_makefiles_artifact_test(
        name = name + "_multiple",
        expected_lines = [
            "ccflags-y += -DFOO",
            "ccflags-y += -DBAR",
        ],
        local_defines = [
            "FOO",
            "BAR",
        ],
    )
    tests.append(name + "_multiple")

    _create_makefiles_artifact_test(
        name = name + "_simple_copt",
        expected_lines = ["ccflags-y += -Wno-foo"],
        copts = ["-Wno-foo"],
    )
    tests.append(name + "_simple_copt")

    _create_makefiles_artifact_test(
        name = name + "_multiple_copt",
        expected_lines = [
            "ccflags-y += -Wno-foo",
            "ccflags-y += -Wno-bar",
        ],
        copts = [
            "-Wno-foo",
            "-Wno-bar",
        ],
    )
    tests.append(name + "_multiple_copt")

    _create_makefiles_artifact_test(
        name = name + "_include_location",
        expected_lines = [
            "ccflags-y += -include",
            "ccflags-y += {}/{}/self.h".format(
                paths.join(*([".."] * len(native.package_name().split("/")))),
                native.package_name(),
            ),
        ],
        copts = ["-include", "$(location self.h)"],
    )
    tests.append(name + "_include_location")

    native.test_suite(
        name = name,
        tests = tests,
    )

def makefiles_test_suite(name):
    """Defines tests for `makefiles`."""
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
        name = name + "_self_headers",
        hdrs = ["self.h"],
        includes = ["."],
    )

    ddk_headers(
        name = name + "_include_headers",
        hdrs = ["include/subdir.h"],
        includes = ["include"],
    )

    ddk_headers(
        name = name + "_base_headers",
        hdrs = ["include/base/base.h"],
        includes = ["include/base"],
    )

    ddk_headers(
        name = name + "_foo_headers",
        hdrs = ["foo.h"],
        includes = ["include/foo"],
    )

    _makefiles_test_make(
        name = name + "_dep_on_headers",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_deps = [name + "_self_headers"],
        expected_includes = [native.package_name()],
    )
    tests.append(name + "_dep_on_headers")

    native.filegroup(
        name = name + "_empty_filegroup",
        srcs = [],
        tags = ["manual"],
    )
    _bad_test_make(
        name = name + "_bad_dep",
        error_message = "is not a valid item in deps",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_deps = [name + "_empty_filegroup"],
    )
    tests.append(name + "_bad_dep")

    _makefiles_test_make(
        name = name + "_export_other_headers",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_hdrs = [name + "_self_headers"],
        expected_includes = [native.package_name()],
    )
    tests.append(name + "_export_other_headers")

    _makefiles_test_make(
        name = name + "_export_local_headers",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_hdrs = ["self.h"],
        module_includes = ["."],
        expected_includes = [native.package_name()],
    )
    tests.append(name + "_export_local_headers")

    _makefiles_build_test(name = name + "_build_test")
    tests.append(name + "_build_test")

    _makefiles_local_defines_test(name = name + "_local_defines_test")
    tests.append(name + "_local_defines_test")

    _bad_test_make(
        name = name + "_bad_copt_location_not_one_token",
        error_message = "An $(location) expression must be its own item",
        module_srcs = ["dep.h"],
        module_out = "dep.ko",
        module_copts = ["-include $(location dep.h)"],
    )
    tests.append(name + "_bad_copt_location_not_one_token")

    _bad_test_make(
        name = name + "_bad_copt_location_not_its_own_token",
        error_message = "An $(location) expression must be its own item",
        module_srcs = ["dep.h"],
        module_out = "dep.ko",
        module_copts = ["-include=$(location dep.h)"],
    )
    tests.append(name + "_bad_copt_location_not_its_own_token")

    _bad_test_make(
        name = name + "_bad_copt_multiple_location_in_one_token",
        error_message = "An $(location) expression must be its own item",
        module_srcs = ["dep.h"],
        module_out = "dep.ko",
        module_copts = ["$(location dep.h) $(location dep.h)"],
    )
    tests.append(name + "_bad_copt_multiple_location_in_one_token")

    _makefiles_test_make(
        name = name + "_include_ordering",
        module_srcs = ["dep.c"],
        module_out = "dep.ko",
        module_includes = [
            # do not sort
            "include/transitive",
            "subdir",
        ],
        module_deps = [
            # do not sort
            name + "_self_headers",
            name + "_include_headers",
        ],
        module_hdrs = [
            # do not sort
            name + "_foo_headers",
            name + "_base_headers",
        ],
        expected_includes = [
            # do not sort
            # First, deps
            native.package_name(),
            "{}/include".format(native.package_name()),
            # Then, hdrs
            "{}/include/foo".format(native.package_name()),
            "{}/include/base".format(native.package_name()),
            # Then, includes
            "{}/include/transitive".format(native.package_name()),
            "{}/subdir".format(native.package_name()),
        ],
    )
    tests.append(name + "_include_ordering")

    # Test that to include hdrs before deps, one must duplicate the hdrs targets in deps
    _makefiles_test_make(
        name = name + "_include_hdrs_before_deps",
        module_deps = [
            # do not sort
            name + "_include_headers",
            name + "_self_headers",
        ],
        module_hdrs = [
            name + "_base_headers",
            name + "_include_headers",
        ],
        expected_includes = [
            # do not sort
            # deps
            "{}/include".format(native.package_name()),
            native.package_name(),
            # hdrs
            "{}/include/base".format(native.package_name()),
            # skip _include_headers
        ],
    )
    tests.append(name + "_include_hdrs_before_deps")

    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = [],
        tags = ["manual"],
    )
    ddk_module(
        name = name + "_parent_include_hdrs_before_deps",
        deps = [
            # do not sort
            name + "_include_headers",
            name + "_self_headers",
        ],
        hdrs = [
            name + "_base_headers",
            name + "_include_headers",
        ],
        kernel_build = name + "_kernel_build",
        srcs = [],
        tags = ["manual"],
    )

    # Children of _include_hdrs_before_deps still gets
    _makefiles_test_make(
        name = name + "_child_include_hdrs_before_deps",
        module_deps = [
            name + "_parent_include_hdrs_before_deps",
        ],
        expected_includes = [
            # do not sort
            # in _include_hdrs_before_deps, in hdrs, _base_headers comes before _include_headers
            "{}/include/base".format(native.package_name()),
            "{}/include".format(native.package_name()),
        ],
    )
    tests.append(name + "_child_include_hdrs_before_deps")

    native.test_suite(
        name = name,
        tests = tests,
    )
