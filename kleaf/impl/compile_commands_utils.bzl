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

"""Utility functions for building compile_commands.json."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

visibility("//build/kernel/kleaf/...")

def _compile_commands_config_settings_raw():
    """Attributes of rules that supports `compile_commands.json`."""
    return {
        "_build_compile_commands": "//build/kernel/kleaf/impl:build_compile_commands",
    }

def _building_compdb(ctx):
    """Returns true if building compdb, false otherwise."""
    internal_compdb = getattr(ctx.attr, "internal_compdb", "respect_build_setting")
    if internal_compdb == "skip":
        return False
    if internal_compdb == "respect_build_setting":
        return ctx.attr._build_compile_commands[BuildSettingInfo].value

    fail("Invalid value for internal_compdb! {}".format(internal_compdb))

def _get_step(ctx, compile_commands_parent):
    """Returns a step for grabbing required files for `compile_commands.json`

    Args:
        ctx: ctx
        compile_commands_parent: where to find compile_commands.json built by Kbuild

    Returns:
        A struct with these fields:
        * inputs
        * tools
        * outputs
        * compile_commands_out_dir
        * compile_commands_with_vars
    """
    cmd = ""
    compile_commands_with_vars = None
    common_out_dir = None
    outputs = []
    if _building_compdb(ctx):
        common_out_dir = ctx.actions.declare_directory("{name}/compile_commands_common_out_dir".format(name = ctx.label.name))
        compile_commands_with_vars = ctx.actions.declare_file(
            "{name}/compile_commands_with_vars.json".format(name = ctx.label.name),
        )
        outputs += [common_out_dir, compile_commands_with_vars]
        cmd = """
            (
            # HACK: get the workspace root and replace it with the fake ROOT_DIR. (b/343803993)
            KLEAF_INTERNAL_WORKSPACE_DIR=$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}}/Makefile)
            KLEAF_INTERNAL_WORKSPACE_DIR=${{KLEAF_INTERNAL_WORKSPACE_DIR%/${{KERNEL_DIR}}/Makefile}}
            rsync -a --prune-empty-dirs \\
                --include '*/' \\
                --include '*.c' \\
                --include '*.S' \\
                --include '*.h' \\
                --include '*.cflags' \\
                --include '*.asflags' \\
                --include '*.ldflags' \\
                --exclude '*' ${{COMMON_OUT_DIR}}/ {common_out_dir}/
            sed -e "s:${{COMMON_OUT_DIR}}:\\${{COMMON_OUT_DIR}}:g;s:${{ROOT_DIR}}:\\${{ROOT_DIR}}:g;s:${{KLEAF_INTERNAL_WORKSPACE_DIR}}:\\${{ROOT_DIR}}:g" \\
                {compile_commands_parent}/compile_commands.json > {compile_commands_with_vars}
            )
        """.format(
            common_out_dir = common_out_dir.path,
            compile_commands_with_vars = compile_commands_with_vars.path,
            compile_commands_parent = compile_commands_parent,
        )
    return struct(
        inputs = [],
        tools = [],
        cmd = cmd,
        outputs = outputs,
        compile_commands_with_vars = compile_commands_with_vars,
        compile_commands_common_out_dir = common_out_dir,
    )

def _additional_make_goals(ctx):
    """Returns a list of additional `MAKE_GOALS`.

    Args:
        ctx: ctx
    """
    if _building_compdb(ctx):
        return ["compile_commands.json"]
    return []

compile_commands_utils = struct(
    get_step = _get_step,
    config_settings_raw = _compile_commands_config_settings_raw,
    additional_make_goals = _additional_make_goals,
)
