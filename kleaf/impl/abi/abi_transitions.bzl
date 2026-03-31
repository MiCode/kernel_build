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

"""Transitions for ABI targets."""

load(
    ":abi/trim_nonlisted_kmi_utils.bzl",
    "FORCE_DISABLE_TRIM",
)

visibility("//build/kernel/kleaf/...")

_FORCE_ADD_VMLINUX_SETTING = "//build/kernel/kleaf/impl:force_add_vmlinux"
_KBUILD_SYMTYPES_SETTING = "//build/kernel/kleaf:kbuild_symtypes"
FORCE_IGNORE_BASE_KERNEL_SETTING = "//build/kernel/kleaf/impl:force_ignore_base_kernel"

_WITH_VMLINUX_TRANSITION_OUTPUT_SETTINGS = [
    _FORCE_ADD_VMLINUX_SETTING,
    _KBUILD_SYMTYPES_SETTING,
    FORCE_IGNORE_BASE_KERNEL_SETTING,
]

def _with_vmlinx_transition_impl(_settings, _attr):
    """with_vmlinux: outs += [vmlinux]; base_kernel = None; kbuild_symtypes = True"""
    return {
        _FORCE_ADD_VMLINUX_SETTING: True,
        FORCE_IGNORE_BASE_KERNEL_SETTING: True,
        _KBUILD_SYMTYPES_SETTING: True,
    }

with_vmlinux_transition = transition(
    implementation = _with_vmlinx_transition_impl,
    inputs = [],
    outputs = _WITH_VMLINUX_TRANSITION_OUTPUT_SETTINGS,
)

def _notrim_transition_impl(settings, attr):
    """notrim: like _with_vmlinux, but trim_nonlisted_kmi = False"""
    return _with_vmlinx_transition_impl(settings, attr) | {
        FORCE_DISABLE_TRIM: True,
    }

notrim_transition = transition(
    implementation = _notrim_transition_impl,
    inputs = [],
    outputs = _WITH_VMLINUX_TRANSITION_OUTPUT_SETTINGS + [
        FORCE_DISABLE_TRIM,
    ],
)
