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

load(
    ":common_providers.bzl",
    "KernelBuildInfo",
    "KernelEnvInfo",
)

def _kernel_compile_commands_impl(ctx):
    interceptor_output = ctx.attr.kernel_build[KernelBuildInfo].interceptor_output
    if not interceptor_output:
        fail("{}: kernel_build {} does not have enable_interceptor = True.".format(ctx.label, ctx.attr.kernel_build.label))
    compile_commands = ctx.actions.declare_file(ctx.attr.name + "/compile_commands.json")
    inputs = [interceptor_output]
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    command = ctx.attr.kernel_build[KernelEnvInfo].setup
    command += """
             # Generate compile_commands.json
               interceptor_analysis -l {interceptor_output} -o {compile_commands} -t compdb_commands --relative
    """.format(
        interceptor_output = interceptor_output.path,
        compile_commands = compile_commands.path,
    )
    ctx.actions.run_shell(
        mnemonic = "KernelCompileCommands",
        inputs = inputs,
        outputs = [compile_commands],
        command = command,
        progress_message = "Building compile_commands.json {}".format(ctx.label),
    )
    return DefaultInfo(files = depset([compile_commands]))

kernel_compile_commands = rule(
    implementation = _kernel_compile_commands_impl,
    doc = """
Generate `compile_commands.json` from a `kernel_build`.
    """,
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            doc = "The `kernel_build` rule to extract from.",
            providers = [KernelEnvInfo, KernelBuildInfo],
        ),
    },
)
