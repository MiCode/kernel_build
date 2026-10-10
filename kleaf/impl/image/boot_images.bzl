# Copyright (C) 2022 The Android Open Source Project
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

load(":common_providers.bzl", "KernelBuildInfo", "KernelEnvInfo")
load(":debug.bzl", "debug")
load(":image/image_utils.bzl", "image_utils")
load(":image/initramfs.bzl", "InitramfsInfo")

def _boot_images_impl(ctx):
    outdir = ctx.actions.declare_directory(ctx.label.name)
    modules_staging_dir = outdir.path + "/staging"
    mkbootimg_staging_dir = modules_staging_dir + "/mkbootimg_staging"

    if ctx.attr.initramfs:
        initramfs_staging_archive = ctx.attr.initramfs[InitramfsInfo].initramfs_staging_archive
        initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"

    outs = []
    for out in ctx.outputs.outs:
        outs.append(out.short_path[len(outdir.short_path) + 1:])

    kernel_build_outs = ctx.attr.kernel_build[KernelBuildInfo].outs + ctx.attr.kernel_build[KernelBuildInfo].base_kernel_files

    inputs = [
        ctx.file.mkbootimg,
        ctx.file._search_and_cp_output,
    ]
    if ctx.attr.initramfs:
        inputs += [
            ctx.attr.initramfs[InitramfsInfo].initramfs_img,
            initramfs_staging_archive,
        ]
    inputs += ctx.files.deps
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += kernel_build_outs
    inputs += ctx.files.vendor_ramdisk_binaries

    command = ""
    command += ctx.attr.kernel_build[KernelEnvInfo].setup

    if ctx.attr.build_boot:
        boot_flag_cmd = "BUILD_BOOT_IMG=1"
    else:
        boot_flag_cmd = "BUILD_BOOT_IMG="

    if not ctx.attr.vendor_boot_name:
        vendor_boot_flag_cmd = """
            BUILD_VENDOR_BOOT_IMG=
            SKIP_VENDOR_BOOT=1
            BUILD_VENDOR_KERNEL_BOOT=
        """
    elif ctx.attr.vendor_boot_name == "vendor_boot":
        vendor_boot_flag_cmd = """
            BUILD_VENDOR_BOOT_IMG=1
            SKIP_VENDOR_BOOT=
            BUILD_VENDOR_KERNEL_BOOT=
        """
    elif ctx.attr.vendor_boot_name == "vendor_kernel_boot":
        vendor_boot_flag_cmd = """
            BUILD_VENDOR_BOOT_IMG=1
            SKIP_VENDOR_BOOT=
            BUILD_VENDOR_KERNEL_BOOT=1
        """
    else:
        fail("{}: unknown vendor_boot_name {}".format(ctx.label, ctx.attr.vendor_boot_name))

    if ctx.files.vendor_ramdisk_binaries:
        # build_utils.sh uses singular VENDOR_RAMDISK_BINARY
        command += """
            VENDOR_RAMDISK_BINARY="{vendor_ramdisk_binaries}"
        """.format(
            vendor_ramdisk_binaries = " ".join([file.path for file in ctx.files.vendor_ramdisk_binaries]),
        )

    command += """
             # Create and restore DIST_DIR.
             # We don't need all of *_for_dist. Copying all declared outputs of kernel_build is
             # sufficient.
               mkdir -p ${{DIST_DIR}}
               cp {kernel_build_outs} ${{DIST_DIR}}
    """.format(
        kernel_build_outs = " ".join([out.path for out in kernel_build_outs]),
    )

    if ctx.attr.initramfs:
        command += """
               cp {initramfs_img} ${{DIST_DIR}}/initramfs.img
             # Create and restore initramfs_staging_dir
               mkdir -p {initramfs_staging_dir}
               tar xf {initramfs_staging_archive} -C {initramfs_staging_dir}
        """.format(
            initramfs_img = ctx.attr.initramfs[InitramfsInfo].initramfs_img.path,
            initramfs_staging_dir = initramfs_staging_dir,
            initramfs_staging_archive = initramfs_staging_archive.path,
        )
        set_initramfs_var_cmd = """
               BUILD_INITRAMFS=1
               INITRAMFS_STAGING_DIR={initramfs_staging_dir}
        """.format(
            initramfs_staging_dir = initramfs_staging_dir,
        )
    else:
        set_initramfs_var_cmd = """
               BUILD_INITRAMFS=
               INITRAMFS_STAGING_DIR=
        """

    command += """
             # Build boot images
               (
                 {boot_flag_cmd}
                 {vendor_boot_flag_cmd}
                 {set_initramfs_var_cmd}
                 MKBOOTIMG_STAGING_DIR=$(readlink -m {mkbootimg_staging_dir})
                 build_boot_images
               )
               {search_and_cp_output} --srcdir ${{DIST_DIR}} --dstdir {outdir} {outs}
             # Remove staging directories
               rm -rf {modules_staging_dir}
    """.format(
        mkbootimg_staging_dir = mkbootimg_staging_dir,
        search_and_cp_output = ctx.file._search_and_cp_output.path,
        outdir = outdir.path,
        outs = " ".join(outs),
        modules_staging_dir = modules_staging_dir,
        boot_flag_cmd = boot_flag_cmd,
        vendor_boot_flag_cmd = vendor_boot_flag_cmd,
        set_initramfs_var_cmd = set_initramfs_var_cmd,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "BootImages",
        inputs = inputs,
        outputs = ctx.outputs.outs + [outdir],
        progress_message = "Building boot images {}".format(ctx.label),
        command = command,
    )

boot_images = rule(
    implementation = _boot_images_impl,
    doc = """Build boot images, including `boot.img`, `vendor_boot.img`, etc.

Execute `build_boot_images` in `build_utils.sh`.""",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildInfo],
        ),
        "initramfs": attr.label(
            providers = [InitramfsInfo],
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
        "outs": attr.output_list(),
        "mkbootimg": attr.label(
            allow_single_file = True,
            default = "//tools/mkbootimg:mkbootimg.py",
        ),
        "build_boot": attr.bool(),
        "vendor_boot_name": attr.string(doc = """
* If `"vendor_boot"`, build `vendor_boot.img`
* If `"vendor_kernel_boot"`, build `vendor_kernel_boot.img`
* If `None`, skip `vendor_boot`.
""", values = ["vendor_boot", "vendor_kernel_boot"]),
        "vendor_ramdisk_binaries": attr.label_list(allow_files = True),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
        ),
    },
)
