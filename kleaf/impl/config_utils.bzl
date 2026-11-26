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

load(
    ":common_providers.bzl",
    "StepInfo",
)

visibility("//build/kernel/kleaf/...")

def _create_merge_config_cmd(base_expr, defconfig_fragments_paths_expr, quiet = None):
    """Returns a command that merges defconfig fragments into the .config represented by `base_expr`

    Args:
        base_expr: A shell expression that evaluates to the base config file.
        defconfig_fragments_paths_expr: A shell expression that evaluates
            to a list of paths to the defconfig fragments.
        quiet: Whether to suppress warning messages for overridden values.

    Returns:
        the command that merges defconfig fragments into the .config represented by `base_expr`
    """
    cmd = """
        (
            # Remove any trailing comments
            sanitized_fragments=
            for fragment in {defconfig_fragments_paths_expr}; do
                new_fragment=${{OUT_DIR}}/defconfig_fragments/${{fragment}}
                mkdir -p $(dirname ${{new_fragment}})
                # Use Python, not sed, to support non-greedy regex matching
                # I avoided perl because it is not hermetic yet.
                python3 -c 'import re, sys; [print(re.sub(r"(\\S+=[^#]*?)\\s*#.*$", r"\\1", l.rstrip("\\
n"))) for l in open(sys.argv[1])]' ${{fragment}} > ${{new_fragment}}
                sanitized_fragments="${{sanitized_fragments}} ${{new_fragment}}"
            done

            # Merge target defconfig into .config from kernel_build
            KCONFIG_CONFIG={base_expr}.tmp \\
                ${{KERNEL_DIR}}/scripts/kconfig/merge_config.sh \\
                    -m -r {quiet_arg} \\
                    {base_expr} \\
                    ${{sanitized_fragments}} > /dev/null
            mv {base_expr}.tmp {base_expr}
        )
    """.format(
        base_expr = base_expr,
        defconfig_fragments_paths_expr = defconfig_fragments_paths_expr,
        quiet_arg = "-Q" if quiet else "",
    )
    return cmd

def _create_check_defconfig_step_impl(
        _subrule_ctx,
        defconfig,
        pre_defconfig_fragments,
        post_defconfig_fragments,
        *,
        _check_config):
    """Checks $OUT_DIR/.config against a given list of defconfig and fragments.

    Args:
        _subrule_ctx: subrule_ctx
        defconfig: File of the base defconfig to be checked against.
            Requirements in it may be overridden by pre_defconfig_fragments
            or post_defconfig_fragments silently.
        pre_defconfig_fragments: List of **pre** defconfig fragments applied
            before `make defconfig`.

            **Order matters.** Requirements in later fragments override earlier
            fragments silently.

            Requirements in post_defconfig_fragments overrides
            pre_defconfig_fragments silently.
        post_defconfig_fragments: List of **post** defconfig fragments applied
            at the end.

            All requirements in each fragment is enforced, so order does not
            matter.
        _check_config: FilesToRunProvider for `check_config.py`.
    """
    defconfig_arg = ""
    if defconfig:
        defconfig_arg = "--defconfig {}".format(defconfig.path)
    pre_arg = ""
    if pre_defconfig_fragments:
        pre_arg = "--pre_defconfig_fragments {}".format(" ".join([fragment.path for fragment in pre_defconfig_fragments]))
    post_arg = ""
    if post_defconfig_fragments:
        post_arg = "--post_defconfig_fragments {}".format(" ".join([fragment.path for fragment in post_defconfig_fragments]))

    cmd = """
        {check_config} \\
            --dot_config ${{OUT_DIR}}/.config \\
            {defconfig_arg} \\
            {pre_arg} \\
            {post_arg} \\
    """.format(
        check_config = _check_config.executable.path,
        defconfig_arg = defconfig_arg,
        pre_arg = pre_arg,
        post_arg = post_arg,
    )
    return StepInfo(
        inputs = depset(post_defconfig_fragments),
        outputs = [],
        tools = [_check_config],
        cmd = cmd,
    )

_create_check_defconfig_step = subrule(
    implementation = _create_check_defconfig_step_impl,
    attrs = {
        "_check_config": attr.label(
            default = ":check_config",
            executable = True,
            cfg = "exec",
        ),
    },
)

config_utils = struct(
    create_merge_config_cmd = _create_merge_config_cmd,
    create_check_defconfig_step = _create_check_defconfig_step,
)
