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

load(":file_selector.bzl", "FileSelectorInfo")

visibility("//build/kernel/kleaf/...")

FORCE_DISABLE_TRIM = "//build/kernel/kleaf/impl:force_disable_trim"
TRIM_NONLISTED_KMI_ATTR_NAME = "trim_nonlisted_kmi"

def _trim_nonlisted_kmi_get_value(ctx):
    """Returns the value of the real `trim_nonlisted_kmi` configuration."""
    return getattr(ctx.attr, TRIM_NONLISTED_KMI_ATTR_NAME)[FileSelectorInfo].value

def _attrs():
    return {TRIM_NONLISTED_KMI_ATTR_NAME: attr.label(
        providers = [FileSelectorInfo],
    )}

trim_nonlisted_kmi_utils = struct(
    get_value = _trim_nonlisted_kmi_get_value,
    attrs = _attrs,
)
