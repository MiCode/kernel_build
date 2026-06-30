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

"""Executes `bazel run XXXX_config` and checks that it updates defconfig
and fragments in an expected way."""

load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")

def _ddk_menuconfig_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script = hermetic_tools.setup + """
        export RUNFILES_DIR=$(realpath .)
        {test_script} \\
            --ddk_config_exec {ddk_config_exec} \\
            --defconfig {defconfig}
    """.format(
        test_script = ctx.executable._test_script.short_path,
        ddk_config_exec = ctx.executable.ddk_config.short_path,
        defconfig = ctx.file.defconfig.short_path,
    )
    script_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(script_file, script, is_executable = True)
    runfiles = ctx.runfiles([
        script_file,
        ctx.file.defconfig,
    ], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge_all([
        ctx.attr._test_script[DefaultInfo].default_runfiles,
        ctx.attr.ddk_config[DefaultInfo].default_runfiles,
    ])
    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

ddk_menuconfig_test = rule(
    implementation = _ddk_menuconfig_test_impl,
    attrs = {
        "ddk_config": attr.label(
            executable = True,
            # Avoid exec transition that builds the kernel in the wrong transition
            cfg = "target",
            mandatory = True,
        ),
        "defconfig": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "_test_script": attr.label(
            executable = True,
            cfg = "exec",
            default = ":ddk_menuconfig_test_binary",
        ),
    },
    test = True,
    toolchains = [hermetic_toolchain.type],
)
