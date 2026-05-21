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

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")

visibility("//common-modules/virtual-device/...")

def _vendor_boot_image_test_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    vendor_boot_image = utils.find_file(
        "vendor_boot.img",
        ctx.files.vendor_boot_image,
        what = "{}: vendor_boot_image".format(ctx.label),
        required = True,
    )

    extracted = ctx.actions.declare_directory("{}/extracted".format(ctx.label.name))
    args = ctx.actions.args()
    args.add("--boot_img", vendor_boot_image)
    args.add("--out", extracted.path)
    cmd = hermetic_tools.setup + """
        {unpack_bootimg} "$@" > {extracted}/stdout.txt
    """.format(
        unpack_bootimg = ctx.executable._unpack_bootimg.path,
        extracted = extracted.path,
    )
    ctx.actions.run_shell(
        inputs = [vendor_boot_image],
        outputs = [extracted],
        arguments = [args],
        tools = [hermetic_tools.deps, ctx.executable._unpack_bootimg],
        command = cmd,
        progress_message = "Extracting vendor_boot",
        mnemonic = "ExtractVendorBoot",
    )

    test_script = hermetic_tools.setup
    direct_runfiles = [extracted]

    if ctx.attr.check_vendor_bootconfig:
        vendor_bootconfig = utils.find_file(
            "vendor-bootconfig.img",
            ctx.files.vendor_boot_image,
            what = "{}: vendor_boot_image".format(ctx.label),
            required = True,
        )
        direct_runfiles.append(vendor_bootconfig)
        test_script += """
            if ! diff -q {extracted}/bootconfig {vendor_bootconfig}; then
                echo "ERROR: bootconfig differs" >&2
                diff {extracted}/bootconfig {vendor_bootconfig} >&2
                exit 1
            fi
        """.format(
            extracted = extracted.short_path,
            vendor_bootconfig = vendor_bootconfig.short_path,
        )
    if ctx.attr.expected_cmdline:
        test_script += """
            if ! grep -q -F "vendor command line args: "{quoted_expected_cmdline} {extracted}/stdout.txt; then
                echo "ERROR: cmdline differs. " >&2
                echo "expected: "{quoted_expected_cmdline} >&2
                grep -F "vendor command line args:" {extracted}/stdout.txt >&2
                exit 1
            fi
        """.format(
            quoted_expected_cmdline = shell.quote(ctx.attr.expected_cmdline),
            extracted = extracted.short_path,
        )
    if ctx.attr.expected_header_version:
        test_script += """
            if ! grep -q -F "vendor boot image header version: {expected_header_version}" {extracted}/stdout.txt; then
                echo "ERROR: header version differs. " >&2
                echo "expected: "{expected_header_version} >&2
                grep -F "vendor boot image header version:" {extracted}/stdout.txt >&2
                exit 1
            fi
        """.format(
            expected_header_version = ctx.attr.expected_header_version,
            extracted = extracted.short_path,
        )

    test_script_file = ctx.actions.declare_file("{}/test.sh".format(ctx.label.name))
    ctx.actions.write(test_script_file, test_script, is_executable = True)
    runfiles = ctx.runfiles(
        files = direct_runfiles,
        transitive_files = hermetic_tools.deps,
    )
    return DefaultInfo(
        files = depset([test_script_file]),
        executable = test_script_file,
        runfiles = runfiles,
    )

vendor_boot_image_test = rule(
    doc = """Tests contents of vendor_boot.img.""",
    implementation = _vendor_boot_image_test_impl,
    attrs = {
        "_unpack_bootimg": attr.label(
            default = "//tools/mkbootimg:unpack_bootimg",
            cfg = "exec",
            executable = True,
        ),
        "check_vendor_bootconfig": attr.bool(
            doc = """Checks content of bootconfig is the same as `vendor-bootconfig.img`.

            Requires that `vendor_boot_image` contains `vendor-bootconfig.img` in `outs`.
            """,
        ),
        "vendor_boot_image": attr.label(
            doc = "The vendor_boot_image().",
            allow_files = True,
        ),
        "expected_cmdline": attr.string(
            doc = "The expected kernel_vendor_cmdline in the image.",
        ),
        "expected_header_version": attr.int(),
    },
    test = True,
    toolchains = [hermetic_toolchain.type],
)
