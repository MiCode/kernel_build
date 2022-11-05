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

Only *_flag / *_settings that affects the behavior in --config=local should be mentioned here.
In particular:
- --config=stamp is not in these lists because it is mutually exclusive with --config=local.
"""

def _kernel_build_config_settings_raw():
    return {
        "_preserve_cmd": "//build/kernel/kleaf/impl:preserve_cmd",
        "_use_kmi_symbol_list_strict_mode": "//build/kernel/kleaf:kmi_symbol_list_strict_mode",
    }

def _kernel_build_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_build_config_settings_raw().items()
    }

def _kernel_config_config_settings_raw():
    return {
        "kasan": "//build/kernel/kleaf:kasan",
        "lto": "//build/kernel/kleaf:lto",
    }

def _kernel_config_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_config_config_settings_raw().items()
    }

def _kernel_env_config_settings_raw():
    return {
        "_kbuild_symtypes_flag": "//build/kernel/kleaf:kbuild_symtypes",
    }

def _kernel_env_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_env_config_settings_raw().items()
    }

kernel_config_settings = struct(
    of_kernel_build = _kernel_build_config_settings,
    of_kernel_config = _kernel_config_config_settings,
    of_kernel_env = _kernel_env_config_settings,
)
