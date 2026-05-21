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

"""Transition into a given platform.

Transition to attr.target_platform. If it is unset, do not apply any transitions.

As a special case, if it is set to `"//build/kernel/kleaf/impl:command_line_option_host_platform"`,
apply the transition to --host_platform (defaults to @platforms//host, but may be overridden in
the command line or in --config=musl.)
"""

visibility("private")

def _platform_transition_impl(_settings, attr):
    if attr.target_platform == None:
        return None
    return {"//command_line_option:platforms": str(attr.target_platform)}

platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)
