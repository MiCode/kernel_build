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
Test kernel_config against options (e.g. lto).
Require //common package.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//build/kernel/kleaf:kernel.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load("//build/kernel/kleaf/tests/utils:contain_lines_test.bzl", "contain_lines_test")
load(":kernel_config_aspect.bzl", "KernelConfigAspectInfo", "kernel_config_aspect")

_ARCHS = (
    "aarch64",
    "x86_64",
    # b/264407394: gcov does not work with riscv64 because of conflict in CONFIG_CFI_CLANG
    # "riscv64",
)

_INTERESTING_FLAGS = (
    "//build/kernel/kleaf:gcov",
    "//build/kernel/kleaf:btf_debug_info",
)

def _flag_transition_impl(settings, attr):
    ret = dict(settings)
    for key, value in attr.flag_values.items():
        if value == "True":
            ret[key] = True
        elif value == "False":
            ret[key] = False
        else:
            ret[key] = value
    return ret

_flag_transition = transition(
    implementation = _flag_transition_impl,
    inputs = _INTERESTING_FLAGS,
    outputs = _INTERESTING_FLAGS,
)

def _get_config_impl(ctx):
    if not len(ctx.attr.kernel_build) == 1:
        fail("This test does not support multiple configurations yet")

    kernel_build = ctx.attr.kernel_build[0]
    kernel_config = kernel_build[KernelConfigAspectInfo].kernel_config
    out_dir = utils.find_file(
        name = "out_dir",
        files = kernel_config.files.to_list(),
        what = "{}: kernel_config outputs".format(kernel_build.label),
    )

    out = ctx.actions.declare_file("{}/.config".format(ctx.label.name))
    hermetic_tools = hermetic_toolchain.get(ctx)
    command = hermetic_tools.setup + """
        cp -pL {out_dir}/.config {out}
    """.format(
        out_dir = out_dir.path,
        out = out.path,
    )

    ctx.actions.run_shell(
        inputs = [out_dir],
        outputs = [out],
        command = command,
        tools = hermetic_tools.deps,
        mnemonic = "GetConfigFile",
        progress_message = "Getting .config {}".format(ctx.label),
    )

    return DefaultInfo(files = depset([out]))

_get_config = rule(
    implementation = _get_config_impl,
    attrs = {
        "kernel_build": attr.label(
            aspects = [kernel_config_aspect],
            cfg = _flag_transition,
        ),
        "flag_values": attr.string_dict(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [hermetic_toolchain.type],
)

def _transition_test(
        name,
        kernel_build,
        expected):
    tests = []

    for flag, values_expected_lines in expected.items():
        for value, expected_lines in values_expected_lines.items():
            test_name = name + "_" + native.package_relative_label(flag).name + "_" + value

            flag_values = {
                flag: value,
            }

            _get_config(
                name = test_name + "_actual",
                kernel_build = kernel_build,
                flag_values = flag_values,
                tags = ["manual"],
            )

            write_file(
                name = test_name + "_expected",
                out = test_name + "_expected/.config",
                content = expected_lines + [""],
                tags = ["manual"],
            )

            contain_lines_test(
                name = test_name,
                expected = test_name + "_expected",
                actual = test_name + "_actual",
            )

            tests.append(test_name)

    # flag_choices: {gcov: [True, False], ...}
    flag_choices = {}
    for flag, values_expected_lines in expected.items():
        flag_choices[flag] = values_expected_lines.keys()

    # Tests each possible combinations of flags. This is expensive.
    # flag_values: {gcov: True, ...}
    for flag_values in combinations(flag_choices):
        expected_lines = []
        test_name = name + "_comb"
        for flag, value in flag_values.items():
            expected_lines += expected[flag][value]
            test_name += "_" + native.package_relative_label(flag).name + "_" + value

        _get_config(
            name = test_name + "_actual",
            kernel_build = kernel_build,
            flag_values = flag_values,
            tags = ["manual"],
        )

        write_file(
            name = test_name + "_expected",
            out = test_name + "_expected/.config",
            content = expected_lines + [""],
            tags = ["manual"],
        )

        contain_lines_test(
            name = test_name,
            expected = test_name + "_expected",
            actual = test_name + "_actual",
        )

        tests.append(test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )

def kernel_defconfig_fragments_test(name):
    """Tests for various flags on `kernel_config`.

    Args:
        name: name of the test
    """

    tests = []

    for arch in _ARCHS:
        kernel_build_arch = arch
        if kernel_build_arch == "aarch64":
            kernel_build_arch = "arm64"

        name_arch = "{}_{}".format(name, arch)
        kernel_build(
            name = name_arch + "_kernel_build",
            srcs = ["//common:kernel_{}_sources".format(arch)],
            arch = kernel_build_arch,
            build_config = "//common:build.config.gki.{}".format(arch),
            outs = [],
            make_goals = ["Image"],
            tags = ["manual"],
        )

        _transition_test(
            name = name_arch + "_test",
            kernel_build = name_arch + "_kernel_build",
            expected = {
                "//build/kernel/kleaf:gcov": {
                    "True": ["CONFIG_GCOV_KERNEL=y"],
                    "False": ["# CONFIG_GCOV_KERNEL is not set"],
                },
                "//build/kernel/kleaf:btf_debug_info": {
                    "enable": ["CONFIG_DEBUG_INFO_BTF=y"],
                    "disable": ["# CONFIG_DEBUG_INFO_BTF is not set"],
                    "default": [],
                },
            },
        )
        tests.append(name_arch + "_test")

    native.test_suite(
        name = name,
        tests = tests,
    )

def combinations(d):
    """Generates combinations.

    Example:

    ```
    combinations({
        "foo": [1, 2],
        "bar": [100, 200, 300],
    })
    gives [
        {"foo": 1, "bar": 100},
        {"foo": 1, "bar": 200},
        {"foo": 1, "bar": 300},
        {"foo": 2, "bar": 100},
        {"foo": 2, "bar": 200},
        {"foo": 2, "bar": 300},
    ]
    ```

    Args:
        d: a dictionary such that for each `{key: value}` entry, key is the flag
            name, and value is the list of possible values associated with
            this key.

    Returns:
        A list of dictionaries, where each dictionary contains a combination.
        Order is undefined but deterministic.
    """

    ret = []
    num_combinations = 1
    for key, values in d.items():
        num_combinations *= len(values)

    for i in range(num_combinations):
        current_choices = {}
        for key, values in d.items():
            current_choices[key] = values[i % len(values)]
            i //= len(values)
        ret.append(current_choices)

    return ret
