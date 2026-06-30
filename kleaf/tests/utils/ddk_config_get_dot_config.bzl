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

"""Retrieves a .config from a ddk_config/ddk_module_config that uses ddk_config_main_action_subrule."""

load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")

def _ddk_config_get_dot_config_impl(ctx):
    out_dir = utils.find_file(
        name = "out_dir",
        files = ctx.files.target,
        what = "{}: target outputs".format(ctx.attr.target.label),
    )

    out = ctx.actions.declare_file("{}/.config".format(ctx.label.name))
    hermetic_tools = hermetic_toolchain.get(ctx)
    command = hermetic_tools.setup + """
        cp -pL {out_dir}/.config {out}
    """.format(
        out_dir = out_dir.path,
        out = out.path,
    )

    ctx.actions.run_shell(
        inputs = [out_dir],
        outputs = [out],
        command = command,
        tools = hermetic_tools.deps,
        mnemonic = "GetDdkConfigFile",
        progress_message = "Getting .config %{label}",
    )

    return DefaultInfo(files = depset([out]))

ddk_config_get_dot_config = rule(
    doc = """Retrieves a .config from a ddk_config/ddk_module_config that uses ddk_config_main_action_subrule.""",
    implementation = _ddk_config_get_dot_config_impl,
    attrs = {
        "target": attr.label(),
    },
    toolchains = [hermetic_toolchain.type],
)
