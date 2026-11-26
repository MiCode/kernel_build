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
"""
Rules for building vendor_boot or vendor_kernel_boot image.
"""

load(":common_providers.bzl", "KernelBuildInfo", "KernelSerializedEnvInfo")
load(":image/boot_images.bzl", "build_boot_or_vendor_boot")
load(":image/initramfs.bzl", "InitramfsInfo")

visibility("//build/kernel/kleaf/...")

def _vendor_boot_image_impl(ctx):
    outs = ctx.attr.outs
    vendor_bootconfig_file = None
    if ctx.attr.vendor_bootconfig:
        vendor_bootconfig_file = ctx.actions.declare_file("{}/vendor-bootconfig.img".format(ctx.label.name))
        ctx.actions.write(vendor_bootconfig_file, "\n".join(ctx.attr.vendor_bootconfig) + "\n")
        outs = list(outs)
        if vendor_bootconfig_file.basename in outs:
            outs.remove(vendor_bootconfig_file.basename)
    if ctx.attr.vendor_ramdisk_dev_nodes:
        # buildifier: disable=print
        print("""\nWARNING: vendor_ramdisk_dev_nodes option will be deprecated from vendor_boot. Use the
              option from initramfs""")

    return build_boot_or_vendor_boot(
        bin_dir = ctx.bin_dir,
        kernel_build = ctx.attr.kernel_build,
        initramfs = ctx.attr.initramfs,
        deps = ctx.attr.deps,
        outs = outs,
        mkbootimg = ctx.attr.mkbootimg,
        build_boot = False,
        vendor_boot_name = ctx.attr.vendor_boot_name,
        vendor_ramdisk_binaries = ctx.attr.vendor_ramdisk_binaries,
        vendor_ramdisk_dev_nodes = ctx.attr.vendor_ramdisk_dev_nodes,
        unpack_ramdisk = ctx.attr.unpack_ramdisk,
        avb_sign_boot_img = False,
        avb_boot_partition_size = None,
        avb_boot_key = None,
        avb_boot_algorithm = None,
        avb_boot_partition_name = None,
        ramdisk_compression = ctx.attr.ramdisk_compression,
        ramdisk_compression_args = ctx.attr.ramdisk_compression_args,
        dtb_image_file = ctx.file.dtb_image,
        vendor_bootconfig_file = vendor_bootconfig_file,
        kernel_vendor_cmdline = ctx.attr.kernel_vendor_cmdline,
        header_version = ctx.attr.header_version,
    )

vendor_boot_image = rule(
    doc = "Build `vendor_boot` or `vendor_kernel_boot` image.",
    implementation = _vendor_boot_image_impl,
    attrs = {
        "kernel_build": attr.label(
            doc = "The [`kernel_build`](#kernel_build).",
            mandatory = True,
            providers = [KernelSerializedEnvInfo, KernelBuildInfo],
        ),
        "initramfs": attr.label(
            doc = "The [`initramfs`](#initramfs).",
            providers = [InitramfsInfo],
        ),
        "dtb_image": attr.label(
            doc = """A dtb.img to packaged.
                If this is set, then *.dtb from `kernel_build` are ignored.

                See [`dtb_image`](#dtb_image).""",
            allow_single_file = True,
        ),
        "deps": attr.label_list(
            doc = "Additional dependencies to build boot images.",
            allow_files = True,
        ),
        "outs": attr.string_list(
            doc = """A list of output files that will be installed to `DIST_DIR` when
                `build_boot_images` in `build/kernel/build_utils.sh` is executed.

                Unlike `kernel_images`, you must specify the list explicitly.
            """,
            allow_empty = False,
        ),
        "mkbootimg": attr.label(
            allow_single_file = True,
            default = "//tools/mkbootimg:mkbootimg.py",
            doc = """mkbootimg.py script which builds boot.img.
                Only used if `build_boot`. If `None`,
                default to `//tools/mkbootimg:mkbootimg.py`.
                NOTE: This overrides `MKBOOTIMG_PATH`.
            """,
        ),
        "ramdisk_compression": attr.string(
            doc = "If provided it specfies the format used for any ramdisks generated." +
                  "If not provided a fallback value from build.config is used.",
            values = ["lz4", "gzip"],
        ),
        "ramdisk_compression_args": attr.string(
            doc = "Command line arguments passed only to lz4 command to control compression level.",
        ),
        "vendor_boot_name": attr.string(
            doc = """Name of `vendor_boot` image.

                * If `"vendor_boot"`, build `vendor_boot.img`
                * If `"vendor_kernel_boot"`, build `vendor_kernel_boot.img`
            """,
            values = ["vendor_boot", "vendor_kernel_boot"],
            default = "vendor_boot",
        ),
        "vendor_ramdisk_binaries": attr.label_list(allow_files = True, doc = """
                List of vendor ramdisk binaries
                which includes the device-specific components of ramdisk like the fstab
                file and the device-specific rc files. If specifying multiple vendor ramdisks
                and identical file paths exist in the ramdisks, the file from last ramdisk is used.

                Note: **order matters**. To prevent buildifier from sorting the list, add the following:
                ```
                # do not sort
                ```
            """),
        "vendor_ramdisk_dev_nodes": attr.label_list(allow_files = True, doc = """
                List of dev nodes description files
                which describes special device files to be added to the vendor
                ramdisk. File format is as accepted by mkbootfs.
            """),
        "unpack_ramdisk": attr.bool(
            doc = """ When false it skips unpacking the vendor ramdisk and copy it as
            is, without modifications, into the boot image. Also skip the mkbootfs step.

            Unlike `kernel_images()`, `unpack_ramdisk` must be specified explicitly to clarify the
            intent.
            """,
            mandatory = True,
        ),
        "vendor_bootconfig": attr.string_list(
            doc = """bootconfig parameters.

                Each element is present as a line in the bootconfig section.

                Requires header version >= 4.
            """,
        ),
        "kernel_vendor_cmdline": attr.string(
            doc = """string of kernel parameters for vendor boot image""",
        ),
        "header_version": attr.int(
            doc = """Boot image header version.

            If unspecified, falls back to the value of BOOT_IMAGE_HEADER_VERSION
            in build configs. If BOOT_IMAGE_HEADER_VERSION is not set, defaults
            to 3.""",
            # It is intentional that 0 is not in the list. When specified explicitly,
            # the user can only provide these values. If unset, the value is 0.
            values = [3, 4],
        ),
    },
    subrules = [build_boot_or_vendor_boot],
)
