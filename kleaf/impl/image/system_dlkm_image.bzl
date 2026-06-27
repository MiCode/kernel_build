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

load("//build/kernel/kleaf/impl:constants.bzl", "SYSTEM_DLKM_OUTS")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load(":debug.bzl", "debug")
load(":image/image_utils.bzl", "image_utils")
load(
    ":common_providers.bzl",
    "KernelImagesInfo",
    "KernelModuleInfo",
)

_STAGING_ARCHIVE_NAME = "system_dlkm_staging_archive.tar.gz"

def _system_dlkm_image_impl(ctx):
    system_dlkm_img = ctx.actions.declare_file("{}/system_dlkm.img".format(ctx.label.name))
    system_dlkm_modules_load = ctx.actions.declare_file("{}/system_dlkm.modules.load".format(ctx.label.name))
    system_dlkm_staging_archive = ctx.actions.declare_file("{}/{}".format(ctx.label.name, _STAGING_ARCHIVE_NAME))

    modules_staging_dir = system_dlkm_img.dirname + "/staging"
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    additional_inputs = []
    restore_modules_install = True
    extract_staging_archive_cmd = ""
    extra_flags_cmd = ""

    kernel_build = ctx.attr.kernel_modules_install[KernelModuleInfo].kernel_build
    if kernel_build[KernelImagesInfo].base_kernel != None:
        if ctx.attr.base_kernel_images == None:
            fail("""{this_label}: Building device-specific system_dlkm ({kernel_build} has base_kernel {base_kernel}), but base_kernel_images is not set. Perhaps add the following?
    base_kernel_images = {base_kernel}_images
                 """.format(
                this_label = ctx.label,
                kernel_build = kernel_build.label,
                base_kernel = kernel_build[KernelImagesInfo].base_kernel,
            ))

        # When building device-specific system_dlkm against GKI's
        # system_dlkm_staging_archive.tar.gz, do not restore the modules_install archive from
        # the device build.
        restore_modules_install = False
        base_kernel_system_dlkm_staging_archive = utils.find_file(
            name = _STAGING_ARCHIVE_NAME,
            files = ctx.files.base_kernel_images,
            what = "{} (images for {})".format(ctx.attr.base_kernel_images.label, ctx.label),
            required = True,
        )
        additional_inputs.append(base_kernel_system_dlkm_staging_archive)

        extract_staging_archive_cmd = """
                # Extract staging archive
                  mkdir -p {system_dlkm_staging_dir}
                  tar xf {base_kernel_system_dlkm_staging_archive} -C {modules_staging_dir}
        """.format(
            base_kernel_system_dlkm_staging_archive = base_kernel_system_dlkm_staging_archive.path,
            modules_staging_dir = modules_staging_dir,
            system_dlkm_staging_dir = system_dlkm_staging_dir,
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

    command = """
               {extract_staging_archive_cmd}
             # Build system_dlkm.img
               mkdir -p {system_dlkm_staging_dir}
               (
                 MODULES_STAGING_DIR={modules_staging_dir}
                 SYSTEM_DLKM_STAGING_DIR={system_dlkm_staging_dir}
                 {extra_flags_cmd}
                 build_system_dlkm
               )
             # Move output files into place
               mv "${{DIST_DIR}}/system_dlkm.img" {system_dlkm_img}
               mv "${{DIST_DIR}}/system_dlkm.modules.load" {system_dlkm_modules_load}
               mv "${{DIST_DIR}}/system_dlkm_staging_archive.tar.gz" {system_dlkm_staging_archive}

             # Remove staging directories
               rm -rf {system_dlkm_staging_dir}
    """.format(
        extract_staging_archive_cmd = extract_staging_archive_cmd,
        extra_flags_cmd = extra_flags_cmd,
        modules_staging_dir = modules_staging_dir,
        system_dlkm_staging_dir = system_dlkm_staging_dir,
        system_dlkm_img = system_dlkm_img.path,
        system_dlkm_modules_load = system_dlkm_modules_load.path,
        system_dlkm_staging_archive = system_dlkm_staging_archive.path,
    )

    default_info = image_utils.build_modules_image_impl_common(
        ctx = ctx,
        what = "system_dlkm",
        outputs = [
            system_dlkm_img,
            system_dlkm_modules_load,
            system_dlkm_staging_archive,
        ],
        additional_inputs = additional_inputs,
        restore_modules_install = restore_modules_install,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        mnemonic = "SystemDlkmImage",
    )

    utils.compare_file_names(
        default_info.files.to_list(),
        SYSTEM_DLKM_OUTS,
        what = "{}: Internal error: not producing the expected list of outputs".format(ctx.label),
    )

    return [default_info]

system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm.img an erofs image with GKI modules.

When included in a `copy_to_dist_dir` rule, this rule copies the following to `DIST_DIR`:
- `system_dlkm.img`
- `system_dlkm.modules.load`

""",
    attrs = image_utils.build_modules_image_attrs_common({
        "base_kernel_images": attr.label(allow_files = True),
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
        "system_dlkm_modules_list": attr.label(allow_single_file = True),
        "system_dlkm_modules_blocklist": attr.label(allow_single_file = True),
        "system_dlkm_props": attr.label(allow_single_file = True),
    }),
)
