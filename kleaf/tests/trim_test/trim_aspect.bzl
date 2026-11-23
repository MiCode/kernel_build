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

"""Aspect that inspects `trim_nonlisted_kmi` attribute for some dependencies of `kernel_build`."""

load("@bazel_skylib//lib:unittest.bzl", "asserts")
load("//build/kernel/kleaf/impl:file_selector.bzl", "FileSelectorInfo")

TrimAspectInfo = provider(
    "Provides the value of `trim_nonlisted_kmi_setting`.",
    fields = {
        "label": "Label of this target",
        "value": "The tristate value of `trim_nonlisted_kmi_setting` of this target",
        "base_info": "The `TrimAspectInfo` of the `base_kernel`",
        "config_info": "The `TrimAspectInfo` of `kernel_config`",
    },
)

def _trim_aspect_impl(_target, ctx):
    if ctx.rule.kind == "_kernel_build":
        base_kernel = ctx.rule.attr.base_kernel
        base_info = base_kernel[TrimAspectInfo] if base_kernel else None

        return TrimAspectInfo(
            label = ctx.label,
            value = ctx.rule.attr.trim_nonlisted_kmi[FileSelectorInfo].value,
            config_info = ctx.rule.attr.config[TrimAspectInfo],
            base_info = base_info,
        )
    elif ctx.rule.kind == "kernel_config":
        return TrimAspectInfo(
            label = ctx.label,
            value = ctx.rule.attr.trim_nonlisted_kmi[FileSelectorInfo].value,
        )

    fail("{label}: Unable to get `_trim_nonlisted_kmi_setting` because {kind} is not supported.".format(
        kind = ctx.rule.kind,
        label = ctx.label,
    ))

trim_aspect = aspect(
    implementation = _trim_aspect_impl,
    doc = "An aspect describing the `trim_nonlisted_kmi_setting` of a `_kernel_build`",
    attr_aspects = [
        "base_kernel",
        "config",
    ],
)

def _check_kernel_config_trim_attr(env, expect_trim, config_info):
    """Check trim_nonlisted_kmi_setting of all internal targets of kernel_build."""
    asserts.equals(
        env,
        expect_trim,
        config_info.value,
        "trim_nonlisted_kmi is not of expected value: {}".format(config_info.label),
    )

def check_kernel_build_trim_attr(env, expect_trim, target_trim_info):
    """Check trim_nonlisted_kmi_setting of all internal targets of kernel_build.

    Args:
        env: the analysis test environment
        expect_trim: expected value of trimming
        target_trim_info: TrimAspectInfo of the tested target
    """
    asserts.equals(
        env,
        expect_trim,
        target_trim_info.value,
        "trim_nonlisted_kmi is not of expected value: {}".format(target_trim_info.label),
    )
    _check_kernel_config_trim_attr(env, expect_trim, target_trim_info.config_info)
