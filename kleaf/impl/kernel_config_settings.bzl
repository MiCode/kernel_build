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

"""A central location for the list of [config settings](https://bazel.build/extending/config) that
affects the following:

- kernel_build
- kernel_config

This is important for non-sandboxed actions because they may cause clashing in the out/cache
directory.

Only *_flag / *_settings that affects the content of the cached $OUT_DIR should be mentioned here.
In particular:
- --config=stamp is not in these lists because it is mutually exclusive with --config=local.
- --allow_undeclared_modules is not listed because it only affects artifact collection.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":abi/base_kernel_utils.bzl", "base_kernel_utils")
load(":abi/force_add_vmlinux_utils.bzl", "force_add_vmlinux_utils")
load(":abi/trim_nonlisted_kmi_utils.bzl", "trim_nonlisted_kmi_utils")
load(":kgdb.bzl", "kgdb")

def _kernel_build_config_settings_raw():
    return dicts.add(
        trim_nonlisted_kmi_utils.config_settings_raw(),
        force_add_vmlinux_utils.config_settings_raw(),
        base_kernel_utils.config_settings_raw(),
        kgdb.config_settings_raw(),
        {
            "_preserve_cmd": "//build/kernel/kleaf/impl:preserve_cmd",
            "_use_kmi_symbol_list_strict_mode": "//build/kernel/kleaf:kmi_symbol_list_strict_mode",
            "_gcov": "//build/kernel/kleaf:gcov",
        },
    )

def _kernel_build_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_build_config_settings_raw().items()
    }

def _kernel_config_config_settings_raw():
    return dicts.add(
        trim_nonlisted_kmi_utils.config_settings_raw(),
        kgdb.config_settings_raw(),
        {
            "kasan": "//build/kernel/kleaf:kasan",
            "lto": "//build/kernel/kleaf:lto",
            "gcov": "//build/kernel/kleaf:gcov",
        },
    )

def _kernel_config_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_config_config_settings_raw().items()
    }

def _kernel_env_config_settings_raw():
    return dicts.add(
        _kernel_build_config_settings_raw(),
        _kernel_config_config_settings_raw(),
        force_add_vmlinux_utils.config_settings_raw(),
        kgdb.config_settings_raw(),
        {
            "_kbuild_symtypes_flag": "//build/kernel/kleaf:kbuild_symtypes",
        },
    )

def _kernel_env_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_env_config_settings_raw().items()
    }

def _kernel_env_get_out_dir_suffix(ctx):
    """Returns `OUT_DIR_SUFFIX` for `kernel_env`."""
    attr_to_label = _kernel_env_config_settings_raw()

    ret = []
    for attr_name in attr_to_label:
        attr_target = getattr(ctx.attr, attr_name)
        attr_label_name = attr_target.label.name
        attr_val = attr_target[BuildSettingInfo].value
        item = "{}_{}".format(attr_label_name, attr_val)
        ret.append(item)
    ret = sorted(sets.to_list(sets.make(ret)))
    return paths.join(*ret)

# Map of config settings to shortened names
_PROGRESS_MESSAGE_SETTINGS_MAP = {
    "force_add_vmlinux": "with_vmlinux",
    "force_ignore_base_kernel": "",  # already covered by with_vmlinux
    "trim_nonlisted_kmi_setting": "trim",
    "kmi_symbol_list_strict_mode": "",  # Hide because not interesting
}

# List of settings that are always included in progress message
_PROGRESS_MESSAGE_INTERESTING_SETTINGS = [
    "trim_nonlisted_kmi_setting",
]

def _get_progress_message_note(ctx):
    """Returns a description text for progress message.

    This is a shortened and human-readable version of `kernel_env_get_out_dir_suffix`.
    """
    attr_to_label = _kernel_env_config_settings_raw()

    ret = []
    for attr_name in attr_to_label:
        attr_target = getattr(ctx.attr, attr_name)
        attr_label_name = attr_target.label.name
        print_attr_label_name = _PROGRESS_MESSAGE_SETTINGS_MAP.get(attr_label_name, attr_label_name)

        # In _SETTINGS_MAP but value is set to empty to ignore it
        if not print_attr_label_name:
            continue

        attr_val = attr_target[BuildSettingInfo].value

        # Empty values that are not interesting enough are dropped
        if not attr_val and attr_label_name not in _PROGRESS_MESSAGE_INTERESTING_SETTINGS:
            continue
        if attr_val == True:
            ret.append(print_attr_label_name)
        elif attr_val == False:
            ret.append("no{}".format(print_attr_label_name))
        else:
            ret.append("{}={}".format(print_attr_label_name, attr_val))
    ret = sorted(sets.to_list(sets.make(ret)))
    ret = ";".join(ret)
    if ret:
        ret = "({}) ".format(ret)
    return ret

kernel_config_settings = struct(
    of_kernel_build = _kernel_build_config_settings,
    of_kernel_config = _kernel_config_config_settings,
    of_kernel_env = _kernel_env_config_settings,
    kernel_env_get_out_dir_suffix = _kernel_env_get_out_dir_suffix,
    get_progress_message_note = _get_progress_message_note,
)
