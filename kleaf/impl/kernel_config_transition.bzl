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

"""Incoming edge transition for `kernel_config`.
If --kasan and --lto=default, --lto becomes none.
See https://bazel.build/rules/config#incoming-edge-transitions
"""

load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")
_LTO_FLAG = "//build/kernel/kleaf:lto"
_KASAN_FLAG = "//build/kernel/kleaf:kasan"

def _lto(settings, _attr):
    if settings[_KASAN_FLAG] and settings[_LTO_FLAG] == "default":
        return {_LTO_FLAG: "none"}

    return {_LTO_FLAG: settings[_LTO_FLAG]}

def _impl(settings, attr):
    ret = _lto(settings, attr)
    return ret

kernel_config_transition = transition(
    implementation = _impl,
    inputs = [_KASAN_FLAG, _LTO_FLAG],
    outputs = [_LTO_FLAG],
)
