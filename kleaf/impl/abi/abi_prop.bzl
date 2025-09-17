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
    "KernelBuildAbiInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "utils")

def _abi_prop_impl(ctx):
    content = []
    if ctx.file.kmi_definition:
        content.append("KMI_DEFINITION={}".format(ctx.file.kmi_definition.basename))
        content.append("KMI_MONITORED=1")

        if ctx.attr.kmi_enforced:
            content.append("KMI_ENFORCED=1")

    combined_abi_symbollist = ctx.attr.kernel_build[KernelBuildAbiInfo].combined_abi_symbollist
    if combined_abi_symbollist:
        content.append("KMI_SYMBOL_LIST={}".format(combined_abi_symbollist.basename))

    # This just appends `KERNEL_BINARY=vmlinux`, but find_file additionally ensures that
    # we are building vmlinux.
    vmlinux = utils.find_file(name = "vmlinux", files = ctx.files.kernel_build, what = "{}: kernel_build".format(ctx.attr.name), required = True)
    content.append("KERNEL_BINARY={}".format(vmlinux.basename))

    if ctx.file.modules_archive:
        content.append("MODULES_ARCHIVE={}".format(ctx.file.modules_archive.basename))

    out = ctx.actions.declare_file("{}/abi.prop".format(ctx.attr.name))
    ctx.actions.write(
        output = out,
        content = "\n".join(content) + "\n",
    )
    return DefaultInfo(files = depset([out]))

abi_prop = rule(
    implementation = _abi_prop_impl,
    doc = "Create `abi.prop`",
    attrs = {
        "kernel_build": attr.label(providers = [KernelBuildAbiInfo]),
        "modules_archive": attr.label(allow_single_file = True),
        "kmi_definition": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
    },
)
