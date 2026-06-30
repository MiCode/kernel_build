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

"""
Subrule for checking rustavailable.
"""

load(":utils.bzl", "kernel_utils", "utils")

visibility("private")

def _rust_available_impl(
        subrule_ctx,
        *,
        serialized_env_info,
        inputs):
    """Checks rustavailable.

    Args:
        subrule_ctx: subrule_ctx
        serialized_env_info: KernelSerializedEnvInfo from kernel_config to set up environment.
        inputs: depset of inputs like kernel sources
    """

    out = subrule_ctx.actions.declare_file("{}/rustavailable_flag_file".format(subrule_ctx.label.name))
    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = serialized_env_info,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += """
        make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} rustavailable
        : > {out}
    """.format(
        out = out.path,
    )
    subrule_ctx.actions.run_shell(
        inputs = depset(transitive = [serialized_env_info.inputs, inputs]),
        tools = serialized_env_info.tools,
        outputs = [out],
        command = command,
        mnemonic = "RustAvailable",
        progress_message = "Checking rustavailable",
    )
    return out

rustavailable = subrule(
    implementation = _rust_available_impl,
)
