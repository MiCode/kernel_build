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

load("//build/kernel/kleaf/impl:ddk/ddk_module_config.bzl", "ddk_module_config")
load("//build/kernel/kleaf/tests/utils:config_test.bzl", "config_test")
load("//build/kernel/kleaf/tests/utils:ddk_config_get_dot_config.bzl", "ddk_config_get_dot_config")

def ddk_config_inheritance_test(
        name,
        expects,
        kernel_build,
        parent = None,
        defconfig = None,
        **kwargs):
    """Helper macro for DDK config inheritance test.

    Args:
        name: name of test
        expects: dict of CONFIG_ -> expected value
        kernel_build: kernel_build
        parent: parent ddk_config
        defconfig: defconfig file
        **kwargs: kwargs to internal targets
    """

    tests = []

    ddk_module_config(
        name = name + "_module_config",
        kernel_build = kernel_build,
        parent = parent,
        defconfig = defconfig,
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

    native.test_suite(
        name = name,
        tests = tests,
        **kwargs
    )
