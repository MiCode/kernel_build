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
    system_dlkm_staging_archive = ctx.actions.declare_file("{}/system_dlkm_staging_archive.tar.gz".format(ctx.label.name))

    modules_staging_dir = system_dlkm_img.dirname + "/staging"
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    command = """
               mkdir -p {system_dlkm_staging_dir}
             # Build system_dlkm.img
               create_modules_staging "${{MODULES_LIST}}" {modules_staging_dir} \
                 {system_dlkm_staging_dir} "${{MODULES_BLOCKLIST}}" "-e"
               modules_root_dir=$(ls {system_dlkm_staging_dir}/lib/modules/*)
             # Re-sign the stripped modules using kernel build time key
               for module in $(find {system_dlkm_staging_dir} -type f -name '*.ko'); do
                   "${{OUT_DIR}}"/scripts/sign-file sha1 \
                   "${{OUT_DIR}}"/certs/signing_key.pem \
                   "${{OUT_DIR}}"/certs/signing_key.x509 "${{module}}"
               done
             # Build system_dlkm.img with signed GKI modules
               mkfs.erofs -zlz4hc "{system_dlkm_img}" "{system_dlkm_staging_dir}"
             # No need to sign the image as modules are signed; add hash footer
               avbtool add_hashtree_footer \
                   --partition_name system_dlkm \
                   --image "{system_dlkm_img}"
             # Archive system_dlkm_staging_dir
               tar czf {system_dlkm_staging_archive} -C {system_dlkm_staging_dir} .
             # Remove staging directories
               rm -rf {system_dlkm_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dir,
        system_dlkm_staging_dir = system_dlkm_staging_dir,
        system_dlkm_img = system_dlkm_img.path,
        system_dlkm_staging_archive = system_dlkm_staging_archive.path,
    )

    default_info = image_utils.build_modules_image_impl_common(
        ctx = ctx,
        what = "system_dlkm",
        outputs = [system_dlkm_img, system_dlkm_staging_archive],
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        mnemonic = "SystemDlkmImage",
    )
    return [default_info]

system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm.img an erofs image with GKI modules.

When included in a `copy_to_dist_dir` rule, this rule copies the `system_dlkm.img` to `DIST_DIR`.

""",
    attrs = image_utils.build_modules_image_attrs_common({
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
    }),
)
