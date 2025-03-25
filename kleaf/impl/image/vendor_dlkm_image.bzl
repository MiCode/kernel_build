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
"""
Build vendor_dlkm.img for vendor modules.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    ":common_providers.bzl",
    "ImagesInfo",
    "KernelModuleInfo",
)
load(
    ":image/image_utils.bzl",
    "SYSTEM_DLKM_MODULES_LOAD_NAME",
    "SYSTEM_DLKM_STAGING_ARCHIVE_NAME",
    "VENDOR_DLKM_STAGING_ARCHIVE_NAME",
    "image_utils",
)
load(":image/initramfs.bzl", "InitramfsInfo")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _get_vendor_boot_modules_load(ctx):
    """Determine the single file from attr vendor_boot_modules_load.

    Implementation note: allow_single_file is not set because it allows providing
    initramfs.
    """
    if not ctx.attr.vendor_boot_modules_load:
        return None
    if InitramfsInfo in ctx.attr.vendor_boot_modules_load:
        return ctx.attr.vendor_boot_modules_load[InitramfsInfo].vendor_boot_modules_load
    if not ctx.files.vendor_boot_modules_load:
        fail("vendor_boot_modules_load = {} does not have any files".format(ctx.attr.vendor_boot_modules_load.label))
    if len(ctx.files.vendor_boot_modules_load) > 1:
        fail("Only a single file is allowed in vendor_boot_modules_load.")
    return ctx.files.vendor_boot_modules_load[0]

def _vendor_dlkm_image_impl(ctx):
    vendor_dlkm_img = ctx.actions.declare_file("{}/vendor_dlkm.img".format(ctx.label.name))
    vendor_dlkm_modules_load = ctx.actions.declare_file("{}/vendor_dlkm.modules.load".format(ctx.label.name))
    out_modules_blocklist = ctx.actions.declare_file("{}/vendor_dlkm.modules.blocklist".format(ctx.label.name))
    modules_staging_dir = vendor_dlkm_img.dirname + "/staging"
    vendor_dlkm_staging_dir = modules_staging_dir + "/vendor_dlkm_staging"
    etc_files = " ".join([f.path for f in ctx.files.etc_files])

    vendor_dlkm_staging_archive = None
    if ctx.attr.archive:
        vendor_dlkm_staging_archive = ctx.actions.declare_file("{}/{}".format(ctx.label.name, VENDOR_DLKM_STAGING_ARCHIVE_NAME))

    command = ""
    additional_inputs = []

    vendor_boot_modules_load = _get_vendor_boot_modules_load(ctx)
    if vendor_boot_modules_load:
        command += """
                # Restore vendor_boot.modules.load or vendor_kernel_boot.modules.load
                # to modules.load, where build_utils.sh build_vendor_dlkm uses
                  cat {vendor_boot_modules_load} >> ${{DIST_DIR}}/modules.load
        """.format(
            vendor_boot_modules_load = vendor_boot_modules_load.path,
        )
        additional_inputs.append(vendor_boot_modules_load)

    exclude_system_dlkm_step = _exclude_system_dlkm(
        ctx,
        modules_staging_dir = modules_staging_dir,
    )
    command += exclude_system_dlkm_step.cmd
    additional_inputs += exclude_system_dlkm_step.inputs

    additional_inputs.extend(ctx.files.modules_list)
    additional_inputs.extend(ctx.files.modules_blocklist)
    additional_inputs.extend(ctx.files.props)

    outputs = []
    vendor_dlkm_flatten_img = None
    vendor_dlkm_flatten_img_name = None
    vendor_dlkm_flatten_modules_load = None
    vendor_dlkm_flatten_modules_load_name = None
    if ctx.attr.build_flatten:
        vendor_dlkm_flatten_img = ctx.actions.declare_file("{}/vendor_dlkm.flatten.img".format(ctx.label.name))
        outputs.append(vendor_dlkm_flatten_img)
        vendor_dlkm_flatten_img_name = "vendor_dlkm.flatten.img"

        vendor_dlkm_flatten_modules_load_name = "vendor_dlkm.flatten.modules.load"
        vendor_dlkm_flatten_modules_load = ctx.actions.declare_file(
            "{}/{}".format(ctx.label.name, vendor_dlkm_flatten_modules_load_name),
        )
        outputs.append(vendor_dlkm_flatten_modules_load)

    command += """
            # Use `strip_modules` intead of relying on this.
               unset DO_NOT_STRIP_MODULES
            # Build vendor_dlkm
              mkdir -p {vendor_dlkm_staging_dir}
              (
                VENDOR_DLKM_MODULES_LIST={modules_list}
                VENDOR_DLKM_MODULES_BLOCKLIST={input_modules_blocklist}
                VENDOR_DLKM_PROPS={props}
                MODULES_STAGING_DIR={modules_staging_dir}
                VENDOR_DLKM_ETC_FILES={quoted_etc_files}
                VENDOR_DLKM_FS_TYPE={fs_type}
                VENDOR_DLKM_STAGING_DIR={vendor_dlkm_staging_dir}
                VENDOR_DLKM_GEN_FLATTEN_IMAGE={build_flatten_image}
                build_vendor_dlkm {archive}
              )
            # Move output files into place
              mv "${{DIST_DIR}}/vendor_dlkm.img" {vendor_dlkm_img}
               if [[ {build_flatten_image} == "1" ]]; then
                mv "${{DIST_DIR}}/{vendor_dlkm_flatten_img_name}" {vendor_dlkm_flatten_img}
                mv "${{DIST_DIR}}/{vendor_dlkm_flatten_modules_load_name}" {vendor_dlkm_flatten_modules_load}
               fi
              mv "${{DIST_DIR}}/vendor_dlkm.modules.load" {vendor_dlkm_modules_load}
              if [[ -f "${{DIST_DIR}}/vendor_dlkm_staging_archive.tar.gz" ]]; then
                mv "${{DIST_DIR}}/vendor_dlkm_staging_archive.tar.gz" {vendor_dlkm_staging_archive}
              fi
              if [[ -f "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" ]]; then
                mv "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" {out_modules_blocklist}
              else
                : > {out_modules_blocklist}
              fi
            # Remove staging directories
              rm -rf {vendor_dlkm_staging_dir}
    """.format(
        build_flatten_image = int(ctx.attr.build_flatten),
        modules_staging_dir = modules_staging_dir,
        quoted_etc_files = shell.quote(etc_files),
        modules_list = utils.optional_path(ctx.file.modules_list),
        input_modules_blocklist = utils.optional_path(ctx.file.modules_blocklist),
        props = utils.optional_path(ctx.file.props),
        fs_type = ctx.attr.fs_type,
        vendor_dlkm_staging_dir = vendor_dlkm_staging_dir,
        vendor_dlkm_flatten_img = vendor_dlkm_flatten_img.path if vendor_dlkm_flatten_img else "/dev/null",
        vendor_dlkm_flatten_img_name = vendor_dlkm_flatten_img_name,
        vendor_dlkm_flatten_modules_load = vendor_dlkm_flatten_modules_load.path if vendor_dlkm_flatten_modules_load else "/dev/null",
        vendor_dlkm_flatten_modules_load_name = vendor_dlkm_flatten_modules_load_name,
        vendor_dlkm_img = vendor_dlkm_img.path,
        vendor_dlkm_modules_load = vendor_dlkm_modules_load.path,
        out_modules_blocklist = out_modules_blocklist.path,
        archive = "1" if ctx.attr.archive else "",
        vendor_dlkm_staging_archive = vendor_dlkm_staging_archive.path if ctx.attr.archive else None,
    )

    additional_inputs += ctx.files.etc_files

    outputs += [
        vendor_dlkm_img,
        vendor_dlkm_modules_load,
        out_modules_blocklist,
    ]

    if ctx.attr.archive:
        outputs.append(vendor_dlkm_staging_archive)

    default_info = image_utils.build_modules_image(
        what = "vendor_dlkm",
        outputs = outputs,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        set_ext_modules = True,
        additional_inputs = additional_inputs,
        mnemonic = "VendorDlkmImage",
        kernel_modules_install = ctx.attr.kernel_modules_install,
        deps = ctx.attr.deps,
        create_modules_order = ctx.attr.create_modules_order,
    )

    images_info = ImagesInfo(files_dict = {
        vendor_dlkm_img.basename: depset([vendor_dlkm_img]),
    })

    return [
        default_info,
        images_info,
    ]

def _exclude_system_dlkm(ctx, modules_staging_dir):
    if not ctx.attr.dedup_dlkm_modules:
        return struct(cmd = "", inputs = [])

    inputs = []

    if ctx.attr.system_dlkm_image:
        system_dlkm_files = ctx.files.system_dlkm_image
        src_attr = "system_dlkm_image"
    elif ctx.attr.base_system_dlkm_image:
        system_dlkm_files = ctx.files.base_system_dlkm_image
        src_attr = "base_system_dlkm_image"
    else:
        fail("{}: With dedup_dlkm_modules, either build_system_dlkm or base_system_dlkm_image must be set".format(
            ctx.label,
        ))

    system_dlkm_staging_archive = utils.find_file(
        name = SYSTEM_DLKM_STAGING_ARCHIVE_NAME,
        files = system_dlkm_files,
        what = "{} ({} for {})".format(ctx.attr.base_system_dlkm_image.label, src_attr, ctx.label),
        required = True,
    )
    system_dlkm_modules_load = utils.find_file(
        name = SYSTEM_DLKM_MODULES_LOAD_NAME,
        files = system_dlkm_files,
        what = "{} ({} for {})".format(ctx.attr.base_system_dlkm_image.label, src_attr, ctx.label),
        required = True,
    )
    inputs += [system_dlkm_staging_archive, system_dlkm_modules_load]

    cmd = """
            # Extract modules from system_dlkm staging archive for depmod
              mkdir -p {modules_staging_dir}
              tar xf {system_dlkm_staging_archive} --wildcards -C {modules_staging_dir} '*.ko'
            # Ensure system_dlkm modules aren't loaded
              cat {system_dlkm_modules_load} >> ${{DIST_DIR}}/modules.load
    """.format(
        system_dlkm_staging_archive = system_dlkm_staging_archive.path,
        modules_staging_dir = modules_staging_dir,
        system_dlkm_modules_load = system_dlkm_modules_load.path,
    )

    return struct(cmd = cmd, inputs = inputs)

vendor_dlkm_image = rule(
    implementation = _vendor_dlkm_image_impl,
    doc = """Build vendor_dlkm image.

Execute `build_vendor_dlkm` in `build_utils.sh`.

When included in a `pkg_files` target included by `pkg_install`, this rule copies the following to
`destdir`:

- `vendor_dlkm.img`
- `vendor_dlkm_flatten.img` if build_vendor_dlkm_flatten is True
""",
    attrs = {
        "kernel_modules_install": attr.label(
            mandatory = True,
            providers = [KernelModuleInfo],
            doc = "The [`kernel_modules_install`](#kernel_modules_install).",
        ),
        "deps": attr.label_list(
            allow_files = True,
            doc = """A list of additional dependencies to build system_dlkm image.

            This must include the following:

            - The file specified by `selinux_fc` in `props`, if set
            """,
        ),
        "create_modules_order": attr.bool(
            default = True,
            doc = """Whether to create and keep a modules.order file generated
                by a postorder traversal of the `kernel_modules_install` sources.
                It defaults to `True`.""",
        ),
        "build_flatten": attr.bool(
            default = False,
            doc = "When True it builds vendor_dlkm image with no `uname -r` in the path",
        ),
        "vendor_boot_modules_load": attr.label(
            allow_files = True,
            doc = """File to `vendor_boot.modules.load`.

                Modules listed in this file is stripped away from the `vendor_dlkm` image.

                As a special case, you may also provide a [`initramfs`](#initramfs) target here,
                in which case the `vendor_boot.modules.load` of the initramfs is used.
            """,
        ),
        "archive": attr.bool(doc = "Whether to archive the `vendor_dlkm` modules"),
        "fs_type": attr.string(
            doc = """Filesystem for `vendor_dlkm.img`.""",
            values = ["ext4", "erofs"],
            default = "ext4",
        ),
        "modules_list": attr.label(
            allow_single_file = True,
            doc = """An optional file
                containing the list of kernel modules which shall be copied into a
                `vendor_dlkm` partition image. Any modules passed into `MODULES_LIST` which
                become part of the `vendor_boot.modules.load` will be trimmed from the
                `vendor_dlkm.modules.load`.""",
        ),
        "etc_files": attr.label_list(
            allow_files = True,
            doc = "Files that need to be copied to `vendor_dlkm.img` etc/ directory.",
        ),
        "modules_blocklist": attr.label(
            allow_single_file = True,
            doc = """An optional file containing a list of modules
                which are blocked from being loaded.

                This file is copied directly to the staging directory and should be in the format:
                ```
                blocklist module_name
                ```""",
        ),
        "props": attr.label(
            allow_single_file = True,
            doc = """A text file containing
                the properties to be used for creation of a `vendor_dlkm` image
                (filesystem, partition size, etc). If this is not set (and
                `build_vendor_dlkm` is), a default set of properties will be used
                which assumes an ext4 filesystem and a dynamic partition.""",
        ),
        "dedup_dlkm_modules": attr.bool(doc = "Whether to exclude `system_dlkm` modules"),
        "system_dlkm_image": attr.label(),
        "base_system_dlkm_image": attr.label(allow_files = True, doc = """
            The `system_dlkm_image()` corresponding to the `base_kernel` of the
            `kernel_build`. This is required if `dedup_dlkm_modules and not system_dlkm_image`.
            For example, if `base_kernel` of `kernel_build()` is `//common:kernel_aarch64`,
            then `base_system_dlkm_image` is `//common:kernel_aarch64_system_dlkm_image`.
        """),
    },
    subrules = [image_utils.build_modules_image],
)
