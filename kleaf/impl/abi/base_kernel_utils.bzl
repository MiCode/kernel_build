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

"""Utilities for determining the value of base_kernel."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":common_providers.bzl",
    "DefconfigFragmentsInfo",
    "DefconfigInfo",
    "GcovInfo",
    "KernelBuildAbiInfo",
    "KernelBuildInTreeModulesInfo",
    "KernelBuildMixedTreeInfo",
    "KernelToolchainInfo",
)

visibility("//build/kernel/kleaf/...")

_FORCE_IGNORE_BASE_KERNEL_SETTING = "//build/kernel/kleaf/impl:force_ignore_base_kernel"

def _base_kernel_config_settings_raw():
    return {
        "_force_ignore_base_kernel": _FORCE_IGNORE_BASE_KERNEL_SETTING,
    }

def _base_kernel_non_config_attrs():
    """Attributes of rules that supports adding vmlinux via outgoing-edge transitions."""
    return {
        "base_kernel": attr.label(
            providers = [
                DefconfigInfo,
                DefconfigFragmentsInfo,
                KernelBuildInTreeModulesInfo,
                KernelBuildMixedTreeInfo,
                KernelBuildAbiInfo,
                KernelToolchainInfo,
                GcovInfo,
            ],
        ),
    }

def _get_base_kernel(ctx):
    """Returns base_kernel."""
    if ctx.attr._force_ignore_base_kernel[BuildSettingInfo].value:
        return None
    return ctx.attr.base_kernel

def _get_base_kernel_for_module_names(ctx):
    """Returns base_kernel for getting the list of module_outs in the base kernel (GKI modules)."""

    # base_kernel_for_module_outs ignores _force_ignore_base_kernel
    return ctx.attr.base_kernel

def _get_base_kernel_for_ddk_headers(ctx):
    """Returns base_kernel for getting the common DDK headers."""

    # always inherit ddk_module_headers from base_kernel, regardless of _force_ignore_base_kernel.
    # This is so that for ABI monitoring or compile_commands, even though _force_ignore_base_kernel,
    # dependant DDK modules can still build properly.
    return ctx.attr.base_kernel

def _get_base_modules_staging_archive(ctx):
    # ignores _force_ignore_base_kernel, because this is for ABI purposes.
    if not ctx.attr.base_kernel:
        return None
    return ctx.attr.base_kernel[KernelBuildAbiInfo].modules_staging_archive

def _get_base_defconfig_info(ctx):
    # ignores _force_ignore_base_kernel, because inheriting defconfig from base_kernel
    # makes sense even when running ABI monitoring on device kernel_build.
    if not ctx.attr.base_kernel:
        return None
    return ctx.attr.base_kernel[DefconfigInfo]

def _get_base_defconfig_fragments_info(ctx):
    # ignores _force_ignore_base_kernel, because inheriting defconfig fragments from base_kernel
    # makes sense even when running ABI monitoring on device kernel_build.
    if not ctx.attr.base_kernel:
        return None
    return ctx.attr.base_kernel[DefconfigFragmentsInfo]

base_kernel_utils = struct(
    config_settings_raw = _base_kernel_config_settings_raw,
    non_config_attrs = _base_kernel_non_config_attrs,
    get_base_kernel = _get_base_kernel,
    get_base_kernel_for_module_names = _get_base_kernel_for_module_names,
    get_base_kernel_for_ddk_headers = _get_base_kernel_for_ddk_headers,
    get_base_modules_staging_archive = _get_base_modules_staging_archive,
    get_base_defconfig_info = _get_base_defconfig_info,
    get_base_defconfig_fragments_info = _get_base_defconfig_fragments_info,
)
