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

InitramfsInfo = provider(fields = {
    "initramfs_img": "Output image",
    "initramfs_staging_archive": "Archive of initramfs staging directory",
})

def _initramfs_impl(ctx):
    initramfs_img = ctx.actions.declare_file("{}/initramfs.img".format(ctx.label.name))
    modules_load = ctx.actions.declare_file("{}/modules.load".format(ctx.label.name))
    vendor_boot_modules_load = ctx.outputs.vendor_boot_modules_load
    initramfs_staging_archive = ctx.actions.declare_file("{}/initramfs_staging_archive.tar.gz".format(ctx.label.name))

    outputs = [
        initramfs_img,
        modules_load,
    ]
    if vendor_boot_modules_load:
        outputs.append(vendor_boot_modules_load)

    modules_staging_dir = initramfs_img.dirname + "/staging"
    initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"

    cp_vendor_boot_modules_load_cmd = ""
    if vendor_boot_modules_load:
        cp_vendor_boot_modules_load_cmd = """
               cp ${{modules_root_dir}}/modules.load {vendor_boot_modules_load}
        """.format(
            vendor_boot_modules_load = vendor_boot_modules_load.path,
        )

    additional_inputs = []
    if ctx.file.modules_options:
        cp_modules_options_cmd = """
            cp {modules_options} ${{modules_root_dir}}/modules.options
    """.format(
            modules_options = ctx.file.modules_options.path,
        )
        additional_inputs.append(ctx.file.modules_options)
    else:
        cp_modules_options_cmd = """
            : > ${modules_root_dir}/modules.options
    """

    command = """
               mkdir -p {initramfs_staging_dir}
             # Build initramfs
               create_modules_staging "${{MODULES_LIST}}" {modules_staging_dir} \
                 {initramfs_staging_dir} "${{MODULES_BLOCKLIST}}" "-e"
               modules_root_dir=$(readlink -e {initramfs_staging_dir}/lib/modules/*) || exit 1
               cp ${{modules_root_dir}}/modules.load {modules_load}
               {cp_vendor_boot_modules_load_cmd}
               {cp_modules_options_cmd}
               mkbootfs "{initramfs_staging_dir}" >"{modules_staging_dir}/initramfs.cpio"
               ${{RAMDISK_COMPRESS}} "{modules_staging_dir}/initramfs.cpio" >"{initramfs_img}"
             # Archive initramfs_staging_dir
               tar czf {initramfs_staging_archive} -C {initramfs_staging_dir} .
             # Remove staging directories
               rm -rf {initramfs_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dir,
        initramfs_staging_dir = initramfs_staging_dir,
        modules_load = modules_load.path,
        initramfs_img = initramfs_img.path,
        initramfs_staging_archive = initramfs_staging_archive.path,
        cp_vendor_boot_modules_load_cmd = cp_vendor_boot_modules_load_cmd,
        cp_modules_options_cmd = cp_modules_options_cmd,
    )

    default_info = image_utils.build_modules_image_impl_common(
        ctx = ctx,
        what = "initramfs",
        outputs = outputs,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        implicit_outputs = [
            initramfs_staging_archive,
        ],
        additional_inputs = additional_inputs,
        mnemonic = "Initramfs",
    )
    return [
        default_info,
        InitramfsInfo(
            initramfs_img = initramfs_img,
            initramfs_staging_archive = initramfs_staging_archive,
        ),
    ]

initramfs = rule(
    implementation = _initramfs_impl,
    doc = """Build initramfs.

When included in a `copy_to_dist_dir` rule, this rule copies the following to `DIST_DIR`:
- `initramfs.img`
- `modules.load`
- `vendor_boot.modules.load`

An additional label, `{name}/vendor_boot.modules.load`, is declared to point to the
corresponding files.
""",
    attrs = image_utils.build_modules_image_attrs_common({
        "vendor_boot_modules_load": attr.output(
            doc = "`vendor_boot.modules.load` or `vendor_kernel_boot.modules.load`",
        ),
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
        "modules_options": attr.label(allow_single_file = True),
    }),
)
