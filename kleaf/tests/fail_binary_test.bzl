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

"""Tests that a binary fails to execute with the given error message."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")

def _fail_binary_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script = hermetic_tools.setup + """
        export RUNFILES_DIR=$(realpath .)
        {test_script} --error_message {quoted_error_message} -- {src} "$@"
    """.format(
        test_script = ctx.executable._test_script.short_path,
        src = ctx.executable.src.short_path,
        quoted_error_message = shell.quote(ctx.attr.error_message),
    )
    script_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(script_file, script, is_executable = True)
    runfiles = ctx.runfiles([
        script_file,
    ], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge_all([
        ctx.attr._test_script[DefaultInfo].default_runfiles,
        ctx.attr.src[DefaultInfo].default_runfiles,
    ])
    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

fail_binary_test = rule(
    implementation = _fail_binary_test_impl,
    attrs = {
        "src": attr.label(
            executable = True,
            # Avoid transitions
            cfg = "target",
            mandatory = True,
        ),
        "error_message": attr.string(mandatory = True),
        "_test_script": attr.label(
            executable = True,
            cfg = "exec",
            default = ":fail_binary_test_binary",
        ),
    },
    test = True,
    toolchains = [hermetic_toolchain.type],
)
