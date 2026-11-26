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

"""Drop-in replacement for skylib's common_settings.bzl.

- `make_variable` attribute is not supported.
- `error_message`: If set, and the value of the flag is not the same as the default value,
  emit a build error.
- `warn_message`: If set, and the value of the flag is not the same as the default value,
  emit a warning.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

visibility("//build/kernel/kleaf/...")

def _bool_flag_impl(ctx):
    if ctx.attr.build_setting_default != ctx.build_setting_value:
        if ctx.attr.error_message:
            fail("{} has unsupported value {}. {}".format(
                ctx.label,
                ctx.build_setting_value,
                ctx.attr.error_message,
            ))
        if ctx.attr.warn_message:
            # buildifier: disable=print
            print("\nWARNING: {} has deprecated value {}. {}".format(
                ctx.label,
                ctx.build_setting_value,
                ctx.attr.warn_message,
            ))

    return [
        BuildSettingInfo(value = ctx.build_setting_value),
    ]

_bool_flag = rule(
    implementation = _bool_flag_impl,
    build_setting = config.bool(flag = True),
    attrs = {
        "error_message": attr.string(),
        "warn_message": attr.string(),
    },
)

def bool_flag(
        name,
        error_message = None,
        warn_message = None,
        build_setting_default = None,
        **kwargs):
    _bool_flag(
        name = name,
        error_message = error_message,
        warn_message = warn_message,
        build_setting_default = build_setting_default,
        **kwargs
    )

def _string_flag_impl(ctx):
    if ctx.attr.values and ctx.build_setting_value not in ctx.attr.values:
        fail("{} has invalid value {}. Valid values are {}".format(
            ctx.label,
            ctx.build_setting_value,
            ctx.attr.values,
        ))

    deprecated_values = ctx.attr.deprecated_values
    if not deprecated_values:
        deprecated_values = [value for value in ctx.attr.values if value != ctx.attr.build_setting_default]

    if ctx.build_setting_value in deprecated_values:
        if ctx.attr.error_message:
            fail("{} has unsupported value {}. {}".format(
                ctx.label,
                ctx.build_setting_value,
                ctx.attr.error_message,
            ))
        if ctx.attr.warn_message:
            # buildifier: disable=print
            print("\nWARNING: {} has deprecated value {}. {}".format(
                ctx.label,
                ctx.build_setting_value,
                ctx.attr.warn_message,
            ))

    return [
        BuildSettingInfo(value = ctx.build_setting_value),
    ]

string_flag = rule(
    implementation = _string_flag_impl,
    build_setting = config.string(flag = True),
    attrs = {
        "error_message": attr.string(),
        "warn_message": attr.string(),
        "values": attr.string_list(),
        "deprecated_values": attr.string_list(),
    },
)
