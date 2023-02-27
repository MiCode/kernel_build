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

"""Utilities for configuring trim_nonlisted_kmi."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

TRIM_NONLISTED_KMI_SETTING_VALUES = struct(
    enabled = "enabled",
    disabled = "disabled",
    unknown = "unknown",
)

TRIM_NONLISTED_KMI_SETTING = "//build/kernel/kleaf/impl:trim_nonlisted_kmi_setting"

def _trim_nonlisted_kmi_transition_impl(settings, attr):
    """Common transition implementation for `trim_nonlisted_kmi`."""

    setting = settings[TRIM_NONLISTED_KMI_SETTING]
    attr_val = attr.trim_nonlisted_kmi

    if setting == TRIM_NONLISTED_KMI_SETTING_VALUES.unknown:
        if attr_val:
            setting = TRIM_NONLISTED_KMI_SETTING_VALUES.enabled
        else:
            setting = TRIM_NONLISTED_KMI_SETTING_VALUES.disabled

    # Otherwise the setting is overridden, ignore the attribute value.

    return {TRIM_NONLISTED_KMI_SETTING: setting}

def _trim_nonlisted_kmi_transition_inputs():
    """Inputs for transition for `trim_nonlisted_kmi`."""
    return [
        TRIM_NONLISTED_KMI_SETTING,
    ]

def _trim_nonlisted_kmi_transition_outputs():
    """Outputs for transition for `trim_nonlisted_kmi`."""
    return [
        TRIM_NONLISTED_KMI_SETTING,
    ]

def _trim_nonlisted_kmi_config_settings_raw():
    return {"_trim_nonlisted_kmi_setting": TRIM_NONLISTED_KMI_SETTING}

def _trim_nonlisted_kmi_non_config_attrs():
    """Attributes of rules that supports configuring `trim_nonlisted_kmi`."""
    return {
        "trim_nonlisted_kmi": attr.bool(),
    }

def _trim_nonlisted_kmi_get_value(ctx):
    """Returns the value of the real `trim_nonlisted_kmi` configuration."""
    setting = ctx.attr._trim_nonlisted_kmi_setting[BuildSettingInfo].value
    if setting == "unknown":
        fail("\nFATAL: {label}: did not set {setting_label} properly! Please report a bug.".format(
            label = ctx.label,
            setting_label = ctx.attr._trim_nonlisted_kmi_setting.label,
        ))
    return setting == TRIM_NONLISTED_KMI_SETTING_VALUES.enabled

trim_nonlisted_kmi_utils = struct(
    transition_impl = _trim_nonlisted_kmi_transition_impl,
    transition_inputs = _trim_nonlisted_kmi_transition_inputs,
    transition_outputs = _trim_nonlisted_kmi_transition_outputs,
    config_settings_raw = _trim_nonlisted_kmi_config_settings_raw,
    non_config_attrs = _trim_nonlisted_kmi_non_config_attrs,
    get_value = _trim_nonlisted_kmi_get_value,
)
