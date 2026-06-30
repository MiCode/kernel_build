# Copyright (C) 2025 The Android Open Source Project
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

"""Test helper for building a single object file against the target platform."""

load(
    "//build/kernel/kleaf/impl:common_providers.bzl",
    "KernelBuildExtModuleInfo",
)
load("//build/kernel/kleaf/impl:utils.bzl", "kernel_utils", "utils")

def _test_cc_object_impl(ctx):
    out_stem = ctx.file.src.basename.removesuffix(ctx.file.src.extension).removesuffix(".")
    out = ctx.actions.declare_file("{}/{}.o".format(ctx.label.name, out_stem))

    setup_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].mod_min_env
    transitive_inputs = [setup_info.inputs]
    tools = [setup_info.tools]

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = setup_info,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += """
        # Note: This drops other flags added by Kbuild. But it is good enough for tests.
        clang ${{USERCFLAGS}} -c -o {out} {src}
    """.format(
        out = out.path,
        src = ctx.file.src.path,
    )
    ctx.actions.run_shell(
        command = command,
        inputs = depset([ctx.file.src], transitive = transitive_inputs),
        tools = tools,
        outputs = [out],
        progress_message = "Building {}.o %{{label}}".format(out_stem),
        mnemonic = "CcObject",
    )

    return DefaultInfo(files = depset([out]))

test_cc_object = rule(
    implementation = _test_cc_object_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = True,
        ),
        "kernel_build": attr.label(providers = [
            KernelBuildExtModuleInfo,
        ]),
    },
)
