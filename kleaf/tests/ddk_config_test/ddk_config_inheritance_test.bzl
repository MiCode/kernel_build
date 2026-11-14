# Copyright (C) 2024 The Android Open Source Project
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

"""Helper macro for DDK config inheritance test."""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//build/kernel/kleaf/impl:ddk/ddk_module_config.bzl", "ddk_module_config")
load("//build/kernel/kleaf/tests/utils:config_test.bzl", "config_test")
load("//build/kernel/kleaf/tests/utils:contain_lines_test.bzl", "contain_lines_test")
load("//build/kernel/kleaf/tests/utils:ddk_config_get_dot_config.bzl", "ddk_config_get_dot_config")
load(":optimize_ddk_config_actions_transition.bzl", "target_with_optimize_ddk_config_actions")

def ddk_config_inheritance_test(
        name,
        expects,
        kernel_build,
        parent = None,
        defconfig = None,
        override_parent = None,
        override_parent_log_expected_lines = None,
        optimize_ddk_config_actions = None,
        **kwargs):
    """Helper macro for DDK config inheritance test.

    Args:
        name: name of test
        expects: dict of CONFIG_ -> expected value
        kernel_build: kernel_build
        parent: parent ddk_config
        defconfig: defconfig file
        override_parent: ddk_module_config.override_parent
        override_parent_log_expected_lines: Expected lines in override_parent.log
        optimize_ddk_config_actions: If true, pre-set --optimize_ddk_config_actions for the
            internal target. Otherwise pre-set --nooptimize_ddk_config_actions.
        **kwargs: kwargs to internal targets
    """

    tests = []

    ddk_module_config(
        name = name + "_module_config_internal",
        kernel_build = kernel_build,
        parent = parent,
        defconfig = defconfig,
        override_parent = override_parent,
        **kwargs
    )

    target_with_optimize_ddk_config_actions(
        name = name + "_module_config",
        actual = name + "_module_config_internal",
        value = optimize_ddk_config_actions,
        **kwargs
    )

    ddk_config_get_dot_config(
        name = name + "_dot_config",
        target = name + "_module_config",
        **kwargs
    )

    config_test(
        name = name + "_config_test",
        actual = name + "_dot_config",
        expects = expects,
        **kwargs
    )
    tests.append(name + "_config_test")

    native.filegroup(
        name = name + "_override_parent_log_actual",
        srcs = [name + "_module_config"],
        output_group = "override_parent_log",
        **kwargs
    )

    write_file(
        name = name + "_override_parent_log_expected",
        out = name + "_override_parent_log_expected/override_parent.log",
        content = (override_parent_log_expected_lines or []) + [""],
        **kwargs
    )

    contain_lines_test(
        name = name + "_override_parent_log_test",
        expected = name + "_override_parent_log_expected",
        actual = name + "_override_parent_log_actual",
        order = True,
        **kwargs
    )
    tests.append(name + "_override_parent_log_test")

    native.test_suite(
        name = name,
        tests = tests,
        **kwargs
    )
