# Copyright (C) 2025 The Android Open Source Project
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

"""Transition that sets optimize_ddk_config_actions"""

visibility("private")

def _optimize_ddk_config_actions_transition_impl(_settings, attr):
    return {
        str(Label("//build/kernel/kleaf:optimize_ddk_config_actions")): attr.value,
    }

_optimize_ddk_config_actions_transition = transition(
    implementation = _optimize_ddk_config_actions_transition_impl,
    inputs = [],
    outputs = [str(Label("//build/kernel/kleaf:optimize_ddk_config_actions"))],
)

def _target_with_optimize_ddk_config_actions_impl(ctx):
    actual = ctx.attr.actual[0]
    return [
        DefaultInfo(
            files = actual.files,
            # Skip other fields like executable since we aren't testing them
        ),
        actual[OutputGroupInfo],
    ]

target_with_optimize_ddk_config_actions = rule(
    implementation = _target_with_optimize_ddk_config_actions_impl,
    attrs = {
        "actual": attr.label(
            cfg = _optimize_ddk_config_actions_transition,
        ),
        "value": attr.bool(),
    },
)
