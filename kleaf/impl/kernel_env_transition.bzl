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

"""Incoming edge transition for `kernel_env`."""

load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")

def _kernel_env_transition_impl(settings, attr):
    ret = trim_nonlisted_kmi_utils.transition_impl(settings, attr)
    return ret

kernel_env_transition = transition(
    implementation = _kernel_env_transition_impl,
    inputs = trim_nonlisted_kmi_utils.transition_inputs(),
    outputs = trim_nonlisted_kmi_utils.transition_outputs(),
)
