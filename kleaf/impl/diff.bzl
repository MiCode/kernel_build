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

"""Compares two files. If they are different, this target fails to **build**."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _diff_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    quiet_flag = "" if ctx.attr.show_diff else "-q"

    if ctx.attr.failure_message:
        message = "ERROR: {}".format(ctx.attr.failure_message)
    else:
        message = "ERROR: {} and {} differs".format(
            ctx.file.file1.path,
            ctx.file.file2.path,
        )

    flag_file = ctx.actions.declare_file(ctx.attr.name)

    cmd = hermetic_tools.setup + """

if ! diff {quiet_flag} {file1} {file2}; then
    echo {quoted_message} >&2
    exit 1
fi
: > {flag_file}
""".format(
        file1 = ctx.file.file1.path,
        file2 = ctx.file.file2.path,
        quiet_flag = quiet_flag,
        quoted_message = shell.quote(message),
        flag_file = flag_file.path,
    )

    ctx.actions.run_shell(
        inputs = [ctx.file.file1, ctx.file.file2],
        outputs = [flag_file],
        tools = hermetic_tools.deps,
        command = cmd,
        mnemonic = "Diff",
        progress_message = "Comparing files %{label}",
    )

    return DefaultInfo(files = depset([flag_file]))

diff = rule(
    doc = """Compares two files. If they are different, this target fails to **build**.""",
    implementation = _diff_impl,
    attrs = {
        "file1": attr.label(allow_single_file = True),
        "file2": attr.label(allow_single_file = True),
        "show_diff": attr.bool(doc = "Show line to line comparisons"),
        "failure_message": attr.string(),
    },
    toolchains = [hermetic_toolchain.type],
)
