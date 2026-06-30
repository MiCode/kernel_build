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

def _pre_defconfig_fragments_menuconfig_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script = hermetic_tools.setup + """
        export RUNFILES_DIR=$(realpath .)
        {test_script} \\
            --kernel_config_exec {kernel_config_exec} \\
            --pre_defconfig_fragment {pre_defconfig_fragment}
    """.format(
        test_script = ctx.executable._test_script.short_path,
        kernel_config_exec = ctx.executable.kernel_config.short_path,
        pre_defconfig_fragment = ctx.file.pre_defconfig_fragment.short_path,
    )
    script_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(script_file, script, is_executable = True)
    runfiles = ctx.runfiles([
        script_file,
        ctx.file.pre_defconfig_fragment,
    ], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge_all([
        ctx.attr._test_script[DefaultInfo].default_runfiles,
        ctx.attr.kernel_config[DefaultInfo].default_runfiles,
    ])
    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = runfiles,
    )

_pre_defconfig_fragments_menuconfig_test = rule(
    implementation = _pre_defconfig_fragments_menuconfig_test_impl,
    attrs = {
        "kernel_config": attr.label(
            executable = True,
            # Avoid exec transition that builds the kernel_config in the wrong transition
            cfg = "target",
        ),
        "pre_defconfig_fragment": attr.label(allow_single_file = True),
        "_test_script": attr.label(
            executable = True,
            cfg = "exec",
            default = ":pre_defconfig_fragments_menuconfig_test",
        ),
    },
    test = True,
    toolchains = [hermetic_toolchain.type],
)

def pre_defconfig_fragments_menuconfig_test(
        name,
        kernel_build,
        pre_defconfig_fragment,
        **kwargs):
    kernel_build = native.package_relative_label(kernel_build)
    _pre_defconfig_fragments_menuconfig_test(
        name = name,
        kernel_config = kernel_build.same_package_label(kernel_build.name + "_config"),
        pre_defconfig_fragment = pre_defconfig_fragment,
        **kwargs
    )
