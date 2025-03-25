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
Build system_dlkm image for GKI modules.
"""

load("//build/kernel/kleaf/impl:constants.bzl", "SYSTEM_DLKM_COMMON_OUTS")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load(
    ":common_providers.bzl",
    "ImagesInfo",
    "KernelModuleInfo",
)
load(
    ":image/image_utils.bzl",
    "image_utils",
    _MODULES_LOAD_NAME = "SYSTEM_DLKM_MODULES_LOAD_NAME",
    _STAGING_ARCHIVE_NAME = "SYSTEM_DLKM_STAGING_ARCHIVE_NAME",
)

visibility("//build/kernel/kleaf/...")

_SUPPORTED_FS_TYPES = ("ext4", "erofs")

def _system_dlkm_image_impl(ctx):
    system_dlkm_modules_load = ctx.actions.declare_file("{}/{}".format(ctx.label.name, _MODULES_LOAD_NAME))
    system_dlkm_staging_archive = ctx.actions.declare_file("{}/{}".format(ctx.label.name, _STAGING_ARCHIVE_NAME))
    out_modules_blocklist = ctx.actions.declare_file("{}/system_dlkm.modules.blocklist".format(ctx.label.name))

    modules_staging_dir = system_dlkm_staging_archive.dirname + "/staging"
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    additional_inputs = []
    restore_modules_install = True
    extract_staging_archive_cmd = ""
    extra_flags_cmd = ""

    kernel_build_infos = ctx.attr.kernel_modules_install[KernelModuleInfo].kernel_build_infos
    if kernel_build_infos.images_info.base_kernel_label != None:
        if ctx.attr.base == None:
            fail("""{this_label}: Building device-specific system_dlkm ({kernel_build} has base_kernel {base_kernel_label}), but base is not set. Perhaps add the following?
    base = "{base_kernel_label}_system_dlkm_image"
                 """.format(
                this_label = ctx.label,
                kernel_build = kernel_build_infos.label,
                base_kernel_label = kernel_build_infos.images_info.base_kernel_label,
            ))

        # When building device-specific system_dlkm against GKI's
        # system_dlkm_staging_archive.tar.gz, do not restore the modules_install archive from
        # the device build.
        restore_modules_install = False
        base_kernel_system_dlkm_staging_archive = utils.find_file(
            name = _STAGING_ARCHIVE_NAME,
            files = ctx.files.base,
            what = "{} (images for {})".format(ctx.attr.base.label, ctx.label),
            required = True,
        )
        additional_inputs.append(base_kernel_system_dlkm_staging_archive)

        extract_staging_archive_cmd = """
                # Extract staging archive
                  mkdir -p {modules_staging_dir}
                  tar xf {base_kernel_system_dlkm_staging_archive} -C {modules_staging_dir}
        """.format(
            base_kernel_system_dlkm_staging_archive = base_kernel_system_dlkm_staging_archive.path,
            modules_staging_dir = modules_staging_dir,
        )

        extra_flags_cmd = """
                     # Trick create_modules_staging to not strip, because they are already stripped and signed
                       DO_NOT_STRIP_MODULES=
                     # Trick create_modules_staging to not look at external modules. They aren't related.
                       EXT_MODULES=
                       EXT_MODULES_MAKEFILE=
                     # Tell build_system_dlkm to not sign, because they are already signed and stripped
                       SYSTEM_DLKM_RE_SIGN=0
        """

    additional_inputs.extend(ctx.files.modules_list)
    additional_inputs.extend(ctx.files.modules_blocklist)
    additional_inputs.extend(ctx.files.props)
    additional_inputs.extend(ctx.files.internal_extra_archive_files)

    command = ""
    outputs = []
    outputs_to_compare = []
    for fs_type in ctx.attr.fs_types:
        if fs_type == "kleaf_internal_legacy_ext4_single":
            # buildifier: disable=print
            print("\nWARNING: {}: system_dlkm_fs_type is deprecated. Use system_dlkm_fs_types instead.".format(ctx.label))
            fs_type = "ext4"
            system_dlkm_img = ctx.actions.declare_file("{}/system_dlkm.img".format(ctx.label.name))
            system_dlkm_img_name = "system_dlkm.img"
        else:
            system_dlkm_img = ctx.actions.declare_file("{}/system_dlkm.{}.img".format(ctx.label.name, fs_type))
            system_dlkm_img_name = "system_dlkm.{}.img".format(fs_type)

        if fs_type not in _SUPPORTED_FS_TYPES:
            fail("Filesystem type {} is not supported".format(fs_type))

        outputs.append(system_dlkm_img)
        outputs_to_compare.append(system_dlkm_img_name)

        system_dlkm_flatten_img = None
        system_dlkm_flatten_img_name = None
        system_dlkm_flatten_modules_load = None
        system_dlkm_flatten_modules_load_name = None
        if ctx.attr.build_flatten:
            system_dlkm_flatten_img = ctx.actions.declare_file("{}/system_dlkm.flatten.{}.img".format(ctx.label.name, fs_type))
            outputs.append(system_dlkm_flatten_img)
            system_dlkm_flatten_img_name = "system_dlkm.flatten.{}.img".format(fs_type)
            outputs_to_compare.append(system_dlkm_flatten_img_name)

            system_dlkm_flatten_modules_load_name = "system_dlkm.flatten.modules.load"
            system_dlkm_flatten_modules_load = ctx.actions.declare_file(
                "{}/{}".format(ctx.label.name, system_dlkm_flatten_modules_load_name),
            )
            outputs.append(system_dlkm_flatten_modules_load)
            outputs_to_compare.append(system_dlkm_flatten_modules_load_name)

        command += """
                   {extract_staging_archive_cmd}
                 # Build {system_dlkm_img_name}
                   mkdir -p {system_dlkm_staging_dir}
                   (
                     MODULES_LIST={modules_list}
                     MODULES_BLOCKLIST={modules_blocklist}
                     SYSTEM_DLKM_PROPS={system_dlkm_props}
                     MODULES_STAGING_DIR={modules_staging_dir}
                     SYSTEM_DLKM_FS_TYPE={fs_type}
                     SYSTEM_DLKM_STAGING_DIR={system_dlkm_staging_dir}
                     SYSTEM_DLKM_IMAGE_NAME={system_dlkm_img_name}
                     SYSTEM_DLKM_GEN_FLATTEN_IMAGE={build_flatten_image}
                     SYSTEM_DLKM_EXTRA_ARCHIVE_FILES="{system_dlkm_extra_archive_files}"
                     {extra_flags_cmd}
                     build_system_dlkm
                   )
                 # Move output files into place
                   mv "${{DIST_DIR}}/{system_dlkm_img_name}" {system_dlkm_img}
                   if [[ {build_flatten_image} == "1" ]]; then
                     mv "${{DIST_DIR}}/{system_dlkm_flatten_img_name}" {system_dlkm_flatten_img}
                     mv "${{DIST_DIR}}/{system_dlkm_flatten_modules_load_name}" {system_dlkm_flatten_modules_load}
                   fi
                   mv "${{DIST_DIR}}/system_dlkm.modules.load" {system_dlkm_modules_load}
                   mv "${{DIST_DIR}}/system_dlkm_staging_archive.tar.gz" {system_dlkm_staging_archive}
                   if [ -f "${{DIST_DIR}}/system_dlkm.modules.blocklist" ]; then
                     mv "${{DIST_DIR}}/system_dlkm.modules.blocklist" {out_modules_blocklist}
                   else
                     : > {out_modules_blocklist}
                   fi

                 # Remove staging directories
                   rm -rf {system_dlkm_staging_dir}
        """.format(
            build_flatten_image = int(ctx.attr.build_flatten),
            extract_staging_archive_cmd = extract_staging_archive_cmd,
            extra_flags_cmd = extra_flags_cmd,
            modules_staging_dir = modules_staging_dir,
            modules_list = utils.optional_single_path(ctx.files.modules_list),
            modules_blocklist = utils.optional_single_path(ctx.files.modules_blocklist),
            system_dlkm_props = utils.optional_path(ctx.file.props),
            fs_type = fs_type,
            system_dlkm_staging_dir = system_dlkm_staging_dir,
            system_dlkm_flatten_img = system_dlkm_flatten_img.path if system_dlkm_flatten_img else "/dev/null",
            system_dlkm_flatten_img_name = system_dlkm_flatten_img_name,
            system_dlkm_flatten_modules_load = system_dlkm_flatten_modules_load.path if system_dlkm_flatten_modules_load else "/dev/null",
            system_dlkm_flatten_modules_load_name = system_dlkm_flatten_modules_load_name,
            system_dlkm_img = system_dlkm_img.path,
            system_dlkm_img_name = system_dlkm_img_name,
            system_dlkm_modules_load = system_dlkm_modules_load.path,
            system_dlkm_staging_archive = system_dlkm_staging_archive.path,
            system_dlkm_extra_archive_files = " ".join([file.path for file in ctx.files.internal_extra_archive_files]),
            out_modules_blocklist = out_modules_blocklist.path,
        )

    outputs += [
        system_dlkm_modules_load,
        system_dlkm_staging_archive,
        out_modules_blocklist,
    ]

    default_info = image_utils.build_modules_image(
        what = "system_dlkm",
        outputs = outputs,
        additional_inputs = additional_inputs,
        restore_modules_install = restore_modules_install,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        mnemonic = "SystemDlkmImage",
        kernel_modules_install = ctx.attr.kernel_modules_install,
        deps = ctx.attr.deps,
        create_modules_order = False,
    )

    utils.compare_file_names(
        default_info.files.to_list(),
        SYSTEM_DLKM_COMMON_OUTS + outputs_to_compare,
        what = "{}: Internal error: not producing the expected list of outputs".format(ctx.label),
    )

    images_info = ImagesInfo(files_dict = {
        file.basename: depset([file])
        for file in outputs
        if file.extension == "img"
    })

    return [
        default_info,
        images_info,
    ]

system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm partition image with signed GKI modules.

When included in a `pkg_files` target included by `pkg_install`, this rule copies the following to
`destdir`:

- `system_dlkm.[erofs|ext4].img` if `fs_types` is specified
- `system_dlkm.flatten.[erofs|ext4].img` if `build_flatten` is True
- `system_dlkm.modules.load`

""",
    attrs = {
        "kernel_modules_install": attr.label(
            mandatory = True,
            providers = [KernelModuleInfo],
            doc = "The [`kernel_modules_install`](#kernel_modules_install).",
        ),
        "deps": attr.label_list(
            doc = """A list of additional dependencies to build system_dlkm image.""",
            allow_files = True,
        ),
        "base": attr.label(allow_files = True, doc = """
            The `system_dlkm_image()` corresponding to the `base_kernel` of the
            `kernel_build`. This is required for building a device-specific `system_dlkm` image.
            For example, if `base_kernel` of `kernel_build()` is `//common:kernel_aarch64`,
            then `base` is `//common:kernel_aarch64_system_dlkm_image`.
        """),
        "build_flatten": attr.bool(
            default = False,
            doc = "When True it builds system_dlkm image with no `uname -r` in the path.",
        ),
        # kernel_images() may provide a or_file() target with zero files. So use allow_files here
        # and check within the implementation.
        "modules_list": attr.label(allow_files = True, doc = """
            An optional file
            containing the list of kernel modules which shall be copied into a
            system_dlkm partition image.
        """),
        "modules_blocklist": attr.label(allow_files = True, doc = """
            An optional file containing a list of modules
            which are blocked from being loaded.

            This file is copied directly to the staging directory and should be in the format:
            ```
            blocklist module_name
            ```
        """),
        "fs_types": attr.string_list(
            doc = """List of file systems type for `system_dlkm` images.

                Supported filesystems for `system_dlkm` image are `ext4` and `erofs`.
                If not specified, build `system_dlkm.img` with ext4. Otherwise, build
                `system_dlkm.<fs>.img` for each file system type in the list.""",
            allow_empty = False,
            default = ["ext4"],
        ),
        "props": attr.label(allow_single_file = True, doc = """
            A text file containing
            the properties to be used for creation of a `system_dlkm` image
            (filesystem, partition size, etc). If this is not set (and
            `build_system_dlkm` is), a default set of properties will be used
            which assumes an ext4 filesystem and a dynamic partition.
        """),
        "internal_extra_archive_files": attr.label_list(
            allow_files = True,
            doc = """**Internal only; subject to change without notice.** 
                Extra files to be placed at the root of the archive.
            """,
        ),
    },
    subrules = [image_utils.build_modules_image],
)
