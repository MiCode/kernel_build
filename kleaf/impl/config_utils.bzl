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

"""Utilities for *_config.bzl."""

def _create_merge_dot_config_step(defconfig_depset_written):
    cmd = """
        if [[ -s {defconfig_depset_file} ]]; then
            # Merge target defconfig into .config from kernel_build
            KCONFIG_CONFIG=${{OUT_DIR}}/.config.tmp \\
                ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh \\
                    -m -r \\
                    ${{OUT_DIR}}/.config \\
                    $(cat {defconfig_depset_file}) > /dev/null
            mv ${{OUT_DIR}}/.config.tmp ${{OUT_DIR}}/.config
        fi
    """.format(
        defconfig_depset_file = defconfig_depset_written.depset_file.path,
    )

    return struct(
        inputs = defconfig_depset_written.depset,
        cmd = cmd,
    )

def _create_check_defconfig_cmd(module_label, defconfig_path):
    cmd = """
        (
            config_set='s/^(CONFIG_\\w*)=.*/\\1/p'
            config_not_set='s/^# (CONFIG_\\w*) is not set$/\\1/p'
            configs=$(sed -n -E -e "${{config_set}}" -e "${{config_not_set}}" {defconfig_path})
            msg=""
            for config in ${{configs}}; do
                defconfig_value=$(grep -w -e "${{config}}" {defconfig_path})
                actual_value=$(grep -w -e "${{config}}" ${{OUT_DIR}}/.config || true)
                if [[ "${{defconfig_value}}" != "${{actual_value}}" ]] ; then
                    msg="${{msg}}
    ${{config}}: actual '${{actual_value}}', expected '${{defconfig_value}}' from {defconfig_path}."
                    found_unexpected=1
                fi
            done
            if [[ -n "${{msg}}" ]]; then
                echo "ERROR: {module_label}: ${{msg}}
    Are they declared in Kconfig?" >&2
                exit 1
            fi
        )
    """.format(
        module_label = module_label,
        defconfig_path = defconfig_path,
    )
    return cmd

config_utils = struct(
    create_merge_dot_config_step = _create_merge_dot_config_step,
    create_check_defconfig_cmd = _create_check_defconfig_cmd,
)
