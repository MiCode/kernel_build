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

visibility("//build/kernel/kleaf/...")

def _create_merge_dot_config_cmd(defconfig_fragments_paths_expr):
    """Returns a command that merges defconfig fragments into `$OUT_DIR/.config`

    Args:
        defconfig_fragments_paths_expr: A shell expression that evaluates
            to a list of paths to the defconfig fragments.

    Returns:
        the command that merges defconfig fragments into `$OUT_DIR/.config`
    """
    cmd = """
        # Merge target defconfig into .config from kernel_build
        KCONFIG_CONFIG=${{OUT_DIR}}/.config.tmp \\
            ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh \\
                -m -r \\
                ${{OUT_DIR}}/.config \\
                {defconfig_fragments_paths_expr} > /dev/null
        mv ${{OUT_DIR}}/.config.tmp ${{OUT_DIR}}/.config
    """.format(
        defconfig_fragments_paths_expr = defconfig_fragments_paths_expr,
    )
    return cmd

def _create_check_defconfig_cmd(label, defconfig_fragments_paths_expr):
    """Returns a command that checks defconfig fragments are set in `$OUT_DIR/.config`

    Args:
        defconfig_fragments_paths_expr: A shell expression that evaluates
            to a list of paths to the defconfig fragments.
        label: label of the current target

    Returns:
        the command that checks defconfig fragments against `$OUT_DIR/.config`
    """
    cmd = """
        (
            for defconfig_path in {defconfig_fragments_paths_expr}; do
                config_set='s/^(CONFIG_\\w*)=.*/\\1/p'
                config_not_set='s/^# (CONFIG_\\w*) is not set$/\\1/p'
                configs=$(sed -n -E -e "${{config_set}}" -e "${{config_not_set}}" ${{defconfig_path}})
                msg=""
                for config in ${{configs}}; do
                    defconfig_value=$(grep -w -e "${{config}}" ${{defconfig_path}})
                    actual_value=$(grep -w -e "${{config}}" ${{OUT_DIR}}/.config || true)

                    config_not_set_regexp='^# CONFIG_[A-Z_]+ is not set$'
                    if [[ "${{defconfig_value}}" =~ ${{config_not_set_regexp}} ]]; then
                        defconfig_value=""
                    fi
                    if [[ "${{actual_value}}" =~ ${{config_not_set_regexp}} ]]; then
                        actual_value=""
                    fi

                    if [[ "${{defconfig_value}}" != "${{actual_value}}" ]] ; then
                        msg="${{msg}}
    ${{config}}: actual '${{actual_value}}', expected '${{defconfig_value}}' from ${{defconfig_path}}."
                        found_unexpected=1
                    fi
                done
                if [[ -n "${{msg}}" ]]; then
                    echo "ERROR: {label}: ${{msg}}
    Are they declared in Kconfig?" >&2
                    exit 1
                fi
            done
        )
    """.format(
        label = label,
        defconfig_fragments_paths_expr = defconfig_fragments_paths_expr,
    )
    return cmd

config_utils = struct(
    create_merge_dot_config_cmd = _create_merge_dot_config_cmd,
    create_check_defconfig_cmd = _create_check_defconfig_cmd,
)
