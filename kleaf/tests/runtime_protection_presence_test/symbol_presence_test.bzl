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

"""Tests that runtime symbol protection functions are present."""

load("@kernel_toolchain_info//:dict.bzl", "VARS")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/impl:common_providers.bzl", "KernelBuildAbiInfo")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _find_vmlinux(ctx):
    return utils.find_file(
        name = "vmlinux",
        files = ctx.files.kernel_build,
        what = "{}: kernel_build".format(ctx.attr.name),
        required = True,
    )

def _symbol_presence_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    trim_nonlisted_kmi = ctx.attr.kernel_build[KernelBuildAbiInfo].trim_nonlisted_kmi
    script_checks = ""
    if trim_nonlisted_kmi:
        script_checks += """
            if ! grep -q -w gki_unprotected_symbols <<< "${vmlinux_symbols}" ; then
                echo "ERROR: Expected GKI runtime protection symbols missing (unprotected symbols)."
                exit_code=1
            fi
        """

    # TODO: b/401193617 -- As of 03/2025 there is no way to disable only exports protection.
    if trim_nonlisted_kmi and ctx.attr.protected_exports_list:
        script_checks += """
            if ! grep -q -w gki_protected_exports_symbols <<< "${vmlinux_symbols}" ; then
                echo "ERROR: Expected GKI runtime protection symbols missing (protected exports)."
                exit_code=1
            fi
        """
    vmlinux = _find_vmlinux(ctx)
    script = hermetic_tools.run_setup + """
        vmlinux_symbols=$({nm} {vmlinux})
        exit_code=0
        {script_checks}
        exit ${{exit_code}}
    """.format(
        script_checks = script_checks,
        vmlinux = vmlinux.short_path,
        nm = ctx.file._llvm_nm.short_path,
    )

    script_file = ctx.actions.declare_file("{}.sh".format(ctx.label.name))
    ctx.actions.write(script_file, script, is_executable = True)

    return DefaultInfo(
        files = depset([script_file]),
        executable = script_file,
        runfiles = ctx.runfiles([script_file, ctx.file._llvm_nm, vmlinux], transitive_files = hermetic_tools.deps),
    )

symbol_presence_test = rule(
    implementation = _symbol_presence_test_impl,
    doc = """Defines a test for the presence of GKI symbols needed for runtime protection.

            This test explicitly depends on GKI targets.
            See _define_common_kernels_additional_tests in kleaf/common_kernels.bzl for details.
    """,
    attrs = {
        "kernel_build": attr.label(
            doc = "Label to the GKI target.",
            mandatory = True,
            providers = [KernelBuildAbiInfo],
        ),
        "protected_exports_list": attr.label(allow_single_file = True),
        # TODO: b/401193617 -- Use resolved toolchain once it llvm-nm is available.
        #  See //prebuilts/clang/host/linux-x86/kleaf/clang_toolchain.bzl;l=100
        "_llvm_nm": attr.label(
            default =
                "//prebuilts/clang/host/linux-x86/clang-{}:bin/llvm-nm".format(VARS["CLANG_VERSION"]),
            cfg = "exec",
            executable = True,
            allow_single_file = True,
        ),
    },
    test = True,
    toolchains = [
        hermetic_toolchain.type,
    ],
)
