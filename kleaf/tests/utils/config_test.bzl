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

"""Generic test for checking a .config or defconfig file, if contain_lines_test
is not sufficient."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")

def _config_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script = hermetic_tools.setup + """
        export RUNFILES_DIR=$(realpath .)
        {test_script} \\
            --actual {actual} \\
            --expects {quoted_expects}
    """.format(
        test_script = ctx.executable._test_script.short_path,
        actual = ctx.file.actual.short_path,
        quoted_expects = shell.quote(json.encode(ctx.attr.expects)),
    )
    script_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(script_file, script, is_executable = True)
    runfiles = ctx.runfiles([
        script_file,
        ctx.file.actual,
    ], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge(
        ctx.attr._test_script[DefaultInfo].default_runfiles,
    )
    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

config_test = rule(
    implementation = _config_test_impl,
    doc = """Generic test for checking a .config or defconfig file, if
        contain_lines_test is not sufficient.""",
    attrs = {
        "_test_script": attr.label(
            cfg = "exec",
            executable = True,
            default = Label(":config_test"),
        ),
        "actual": attr.label(
            allow_single_file = True,
            doc = """Actual file to test.

                If a directory, it is treated as $OUT_DIR, and $OUT_DIR/.config is tested.""",
        ),
        "expects": attr.string_dict(
            doc = "Expected values of each config. Empty means expecting the config to be unset.",
        ),
    },
    test = True,
    toolchains = [hermetic_toolchain.type],
)
