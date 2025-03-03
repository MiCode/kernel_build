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

"""Merge Module.symvers from different sources."""

load(
    ":common_providers.bzl",
    "ModuleSymversFileInfo",
)
load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _merge_module_symvers_impl(ctx):
    merged_module_symvers = ctx.actions.declare_file("{}/Module.symvers".format(ctx.label.name))
    hermetic_tools = hermetic_toolchain.get(ctx)

    command = hermetic_tools.setup + """
        cat "$@" > {merged_module_symvers}
    """.format(
        merged_module_symvers = merged_module_symvers.path,
    )
    transitive_srcs_depset = depset(
        transitive = [
            src[ModuleSymversFileInfo].module_symvers
            for src in ctx.attr.srcs
            if ModuleSymversFileInfo in src
        ],
    )
    args = ctx.actions.args()
    args.add_all(transitive_srcs_depset)
    ctx.actions.run_shell(
        mnemonic = "MergeModuleSymvers",
        inputs = transitive_srcs_depset,
        outputs = [merged_module_symvers],
        progress_message = "Merging Module.symvers %{label}",
        command = command,
        arguments = [args],
        tools = hermetic_tools.deps,
    )
    return DefaultInfo(files = depset([merged_module_symvers]))

merge_module_symvers = rule(
    implementation = _merge_module_symvers_impl,
    doc = """Merge Module.symvers files""",
    attrs = {
        "srcs": attr.label_list(
            providers = [ModuleSymversFileInfo],
            doc = """
            It accepts targets from any of the following rules:
              - [ddk_module](#ddk_module)
              - [kernel_module_group](#kernel_module_group)
              - [kernel_build](#kernel_build) (it requires `keep_module_symvers = True` to be set).
            """,
        ),
    },
    toolchains = [
        hermetic_toolchain.type,
    ],
)
