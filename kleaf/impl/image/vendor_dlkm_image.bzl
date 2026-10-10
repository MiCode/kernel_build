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

load(":debug.bzl", "debug")
load(":image/image_utils.bzl", "image_utils")

def _vendor_dlkm_image_impl(ctx):
    vendor_dlkm_img = ctx.actions.declare_file("{}/vendor_dlkm.img".format(ctx.label.name))
    vendor_dlkm_modules_load = ctx.actions.declare_file("{}/vendor_dlkm.modules.load".format(ctx.label.name))
    vendor_dlkm_modules_blocklist = ctx.actions.declare_file("{}/vendor_dlkm.modules.blocklist".format(ctx.label.name))
    modules_staging_dir = vendor_dlkm_img.dirname + "/staging"
    vendor_dlkm_staging_dir = modules_staging_dir + "/vendor_dlkm_staging"

    command = ""
    additional_inputs = []
    if ctx.file.vendor_boot_modules_load:
        command += """
                # Restore vendor_boot.modules.load or vendor_kernel_boot.modules.load
                # to modules.load, where build_utils.sh build_vendor_dlkm uses
                  cp {vendor_boot_modules_load} ${{DIST_DIR}}/modules.load
        """.format(
            vendor_boot_modules_load = ctx.file.vendor_boot_modules_load.path,
        )
        additional_inputs.append(ctx.file.vendor_boot_modules_load)

    command += """
            # Build vendor_dlkm
              mkdir -p {vendor_dlkm_staging_dir}
              (
                MODULES_STAGING_DIR={modules_staging_dir}
                VENDOR_DLKM_STAGING_DIR={vendor_dlkm_staging_dir}
                build_vendor_dlkm
              )
            # Move output files into place
              mv "${{DIST_DIR}}/vendor_dlkm.img" {vendor_dlkm_img}
              mv "${{DIST_DIR}}/vendor_dlkm.modules.load" {vendor_dlkm_modules_load}
              if [[ -f "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" ]]; then
                mv "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" {vendor_dlkm_modules_blocklist}
              else
                : > {vendor_dlkm_modules_blocklist}
              fi
            # Remove staging directories
              rm -rf {vendor_dlkm_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dir,
        vendor_dlkm_staging_dir = vendor_dlkm_staging_dir,
        vendor_dlkm_img = vendor_dlkm_img.path,
        vendor_dlkm_modules_load = vendor_dlkm_modules_load.path,
        vendor_dlkm_modules_blocklist = vendor_dlkm_modules_blocklist.path,
    )

    return image_utils.build_modules_image_impl_common(
        ctx = ctx,
        what = "vendor_dlkm",
        outputs = [vendor_dlkm_img, vendor_dlkm_modules_load, vendor_dlkm_modules_blocklist],
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        additional_inputs = additional_inputs,
        mnemonic = "VendorDlkmImage",
    )

vendor_dlkm_image = rule(
    implementation = _vendor_dlkm_image_impl,
    doc = """Build vendor_dlkm image.

Execute `build_vendor_dlkm` in `build_utils.sh`.

When included in a `copy_to_dist_dir` rule, this rule copies a `vendor_dlkm.img` to `DIST_DIR`.
""",
    attrs = image_utils.build_modules_image_attrs_common({
        "vendor_boot_modules_load": attr.label(
            allow_single_file = True,
            doc = """File to `vendor_boot.modules.load`.

Modules listed in this file is stripped away from the `vendor_dlkm` image.""",
        ),
        "vendor_dlkm_modules_list": attr.label(allow_single_file = True),
        "vendor_dlkm_modules_blocklist": attr.label(allow_single_file = True),
        "vendor_dlkm_props": attr.label(allow_single_file = True),
    }),
)
