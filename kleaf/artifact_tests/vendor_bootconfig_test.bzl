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

"""Tests that vendor_boot.img has vendor-bootconfig.img"""

load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")

visibility("//common-modules/virtual-device/...")

def _vendor_bootconfig_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    vendor_boot_image = utils.find_file(
        "vendor_boot.img",
        ctx.files.vendor_boot_image,
        what = "{}: vendor_boot_image".format(ctx.label),
        required = True,
    )

    vendor_bootconfig = utils.find_file(
        "vendor-bootconfig.img",
        ctx.files.vendor_boot_image,
        what = "{}: vendor_boot_image".format(ctx.label),
        required = True,
    )

    extracted = ctx.actions.declare_directory("{}/extracted".format(ctx.label.name))
    args = ctx.actions.args()
    args.add("--boot_img", vendor_boot_image)
    args.add("--out", extracted.path)
    ctx.actions.run(
        executable = ctx.executable._unpack_bootimg,
        inputs = [vendor_boot_image],
        outputs = [extracted],
        arguments = [args],
        progress_message = "Extracting vendor_boot",
        mnemonic = "ExtractVendorBoot",
    )

    test_script = hermetic_tools.run_setup + """
        diff -q {extracted}/bootconfig {vendor_bootconfig}
    """.format(
        extracted = extracted.short_path,
        vendor_bootconfig = vendor_bootconfig.short_path,
    )
    test_script_file = ctx.actions.declare_file("{}/test.sh".format(ctx.label.name))
    ctx.actions.write(test_script_file, test_script, is_executable = True)
    runfiles = ctx.runfiles(
        files = [extracted, vendor_bootconfig],
        transitive_files = hermetic_tools.deps,
    )
    return DefaultInfo(
        files = depset([test_script_file]),
        executable = test_script_file,
        runfiles = runfiles,
    )

vendor_bootconfig_test = rule(
    doc = "Tests that vendor_boot.img has vendor-bootconfig.img",
    implementation = _vendor_bootconfig_test_impl,
    attrs = {
        "_unpack_bootimg": attr.label(
            default = "//tools/mkbootimg:unpack_bootimg",
            cfg = "exec",
            executable = True,
        ),
        "vendor_boot_image": attr.label(
            doc = "The vendor_boot_image().",
            allow_files = True,
        ),
    },
    test = True,
    toolchains = [hermetic_toolchain.type],
)
