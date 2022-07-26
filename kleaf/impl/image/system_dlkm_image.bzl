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

def _system_dlkm_image_impl(ctx):
    system_dlkm_img = ctx.actions.declare_file("{}/system_dlkm.img".format(ctx.label.name))
    system_dlkm_modules_load = ctx.actions.declare_file("{}/system_dlkm.modules.load".format(ctx.label.name))
    system_dlkm_staging_archive = ctx.actions.declare_file("{}/system_dlkm_staging_archive.tar.gz".format(ctx.label.name))

    modules_staging_dir = system_dlkm_img.dirname + "/staging"
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    command = """
             # Build system_dlkm.img
               mkdir -p {system_dlkm_staging_dir}
               (
                 MODULES_STAGING_DIR={modules_staging_dir}
                 SYSTEM_DLKM_STAGING_DIR={system_dlkm_staging_dir}
                 build_system_dlkm
               )
             # Move output files into place
               mv "${{DIST_DIR}}/system_dlkm.img" {system_dlkm_img}
               mv "${{DIST_DIR}}/system_dlkm.modules.load" {system_dlkm_modules_load}
               mv "${{DIST_DIR}}/system_dlkm_staging_archive.tar.gz" {system_dlkm_staging_archive}

             # Remove staging directories
               rm -rf {system_dlkm_staging_dir}
    """.format(
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
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        mnemonic = "SystemDlkmImage",
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
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
    }),
)
