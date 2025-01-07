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

"""Wraps .o so it can be used in `ddk_module.srcs`."""

load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _ddk_prebuilt_object_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    out_stem = ctx.file.src.basename.removesuffix(ctx.file.src.extension).removesuffix(".")

    out_file = ctx.actions.declare_file("{}/{}.o_shipped".format(ctx.label.name, out_stem))

    command = hermetic_tools.setup + """
        cp -aL {src} {out_file}
    """.format(
        src = ctx.file.src.path,
        out_file = out_file.path,
    )
    ctx.actions.run_shell(
        command = command,
        inputs = ctx.files.src,
        outputs = [out_file],
        tools = hermetic_tools.deps,
        mnemonic = "DdkPrebuiltObjectObject",
        progress_message = "Building {} %{{label}}".format(out_file.basename),
    )

    cmd_file = ctx.actions.declare_file("{}/.{}.o.cmd_shipped".format(ctx.label.name, out_stem))
    if ctx.file.cmd:
        command = hermetic_tools.setup + """
            cp -aL {cmd_src} {cmd_out}
        """.format(
            cmd_src = ctx.file.cmd.path,
            cmd_out = cmd_file.path,
        )
        ctx.actions.run_shell(
            command = command,
            inputs = ctx.files.cmd,
            outputs = [cmd_file],
            tools = hermetic_tools.deps,
            mnemonic = "DdkPrebuiltObjectCmd",
            progress_message = "Building {} %{{label}}".format(cmd_file.basename),
        )
    else:
        ctx.actions.write(cmd_file, "")

    return DefaultInfo(files = depset([out_file, cmd_file]))

ddk_prebuilt_object = rule(
    implementation = _ddk_prebuilt_object_impl,
    doc = """Wraps a `<stem>.o` file so it can be used in [ddk_module.srcs](#ddk_module-srcs).

        An optional `.<stem>.o.cmd` file may be provided. If not provided, a fake
        `.<stem>.o.cmd` is generated.

        Example:

        ```
        ddk_prebuilt_object(
            name = "foo",
            src = "foo.o",
        )

        ddk_module(
            name = "mymod",
            srcs = [":foo"],
            # ...
        )
        ```
    """,
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The .o file, e.g. `foo.o`",
        ),
        "cmd": attr.label(
            allow_single_file = True,
            doc = "The .cmd file, e.g. `.foo.o.cmd`. If missing, an empty file is provided.",
        ),
    },
    toolchains = [hermetic_toolchain.type],
)
