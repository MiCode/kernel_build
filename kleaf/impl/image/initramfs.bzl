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
Build initramfs.
"""

load(
    ":common_providers.bzl",
    "KernelModuleInfo",
)
load(":image/image_utils.bzl", "image_utils")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

InitramfsInfo = provider(
    doc = "Provides information about initramfs outputs.",
    fields = {
        "initramfs_img": "Output image",
        "initramfs_staging_archive": "Archive of initramfs staging directory",
        "vendor_boot_modules_load": "output vendor_boot.modules.load or vendor_kernel_boot.modules.load",
    },
)

def _initramfs_impl(ctx):
    initramfs_img = ctx.actions.declare_file("{}/initramfs.img".format(ctx.label.name))
    modules_load = ctx.actions.declare_file("{}/modules.load".format(ctx.label.name))

    vendor_boot_modules_load = None
    vendor_boot_modules_load_recovery = None
    vendor_boot_modules_load_charger = None
    if ctx.attr.vendor_boot_name:
        vendor_boot_modules_load = ctx.actions.declare_file("{}/{}.modules.load".format(ctx.label.name, ctx.attr.vendor_boot_name))
        if ctx.file.modules_recovery_list:
            vendor_boot_modules_load_recovery = ctx.actions.declare_file("{}/{}.modules.load.recovery".format(ctx.label.name, ctx.attr.vendor_boot_name))
        if ctx.file.modules_charger_list:
            vendor_boot_modules_load_charger = ctx.actions.declare_file("{}/{}.modules.load.charger".format(ctx.label.name, ctx.attr.vendor_boot_name))

    initramfs_staging_archive = ctx.actions.declare_file("{}/initramfs_staging_archive.tar.gz".format(ctx.label.name))

    outputs = [
        initramfs_img,
        modules_load,
    ]
    cp_vendor_boot_modules_load_cmd = ""
    if vendor_boot_modules_load:
        cp_vendor_boot_modules_load_cmd = """
               cp ${{modules_root_dir}}/modules.load {vendor_boot_modules_load}
        """.format(
            vendor_boot_modules_load = vendor_boot_modules_load.path,
        )
        outputs.append(vendor_boot_modules_load)

    cp_modules_load_recovery_cmd = ""
    if ctx.attr.modules_recovery_list:
        modules_load_recovery = ctx.actions.declare_file("{}/modules.load.recovery".format(ctx.label.name))
        cp_modules_load_recovery_cmd = """
               cp ${{modules_root_dir}}/modules.load.recovery {modules_load_recovery}
        """.format(
            modules_load_recovery = modules_load_recovery.path,
        )
        outputs.append(modules_load_recovery)

    cp_vendor_boot_modules_load_recovery_cmd = ""
    if vendor_boot_modules_load_recovery:
        cp_vendor_boot_modules_load_recovery_cmd = """
               cp ${{modules_root_dir}}/modules.load.recovery {vendor_boot_modules_load_recovery}
        """.format(
            vendor_boot_modules_load_recovery = vendor_boot_modules_load_recovery.path,
        )
        outputs.append(vendor_boot_modules_load_recovery)

    cp_modules_load_charger_cmd = ""
    if ctx.attr.modules_charger_list:
        modules_load_charger = ctx.actions.declare_file("{}/modules.load.charger".format(ctx.label.name))
        cp_modules_load_charger_cmd = """
               cp ${{modules_root_dir}}/modules.load.charger {modules_load_charger}
        """.format(
            modules_load_charger = modules_load_charger.path,
        )
        outputs.append(modules_load_charger)

    cp_vendor_boot_modules_load_charger_cmd = ""
    if vendor_boot_modules_load_charger:
        cp_vendor_boot_modules_load_charger_cmd = """
               cp ${{modules_root_dir}}/modules.load.charger {vendor_boot_modules_load_charger}
        """.format(
            vendor_boot_modules_load_charger = vendor_boot_modules_load_charger.path,
        )
        outputs.append(vendor_boot_modules_load_charger)

    modules_staging_dir = initramfs_img.dirname + "/staging"
    initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"

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
    additional_inputs.extend(ctx.files.modules_list)
    additional_inputs.extend(ctx.files.modules_recovery_list)
    additional_inputs.extend(ctx.files.modules_charger_list)
    additional_inputs.extend(ctx.files.modules_blocklist)
    additional_inputs.extend(ctx.files.modules_options)
    additional_inputs.extend(ctx.files.vendor_ramdisk_dev_nodes)

    initramfs_args = ""
    for file in ctx.files.vendor_ramdisk_dev_nodes:
        initramfs_args += " -n " + file.path

    ramdisk_compress = image_utils.ramdisk_options(
        ramdisk_compression = ctx.attr.ramdisk_compression,
        ramdisk_compression_args = ctx.attr.ramdisk_compression_args,
    ).ramdisk_compress

    command = """
               MODULES_LIST={modules_list}
               MODULES_RECOVERY_LIST={modules_recovery_list}
               MODULES_CHARGER_LIST={modules_charger_list}
               MODULES_BLOCKLIST={modules_blocklist}
               MODULES_OPTIONS={modules_options}
               if [ -n "${{TRIM_UNUSED_MODULES}}" ]; then
                   echo "WARNING: TRIM_UNUSED_MODULES is deprecated; use initramfs(trim_unused_modules=) instead." >&2
               fi
               if [ "{trim_unused_modules}" == "1" ]; then
                   TRIM_UNUSED_MODULES=1
               fi
             # Use `strip_modules` intead of relying on this.
               unset DO_NOT_STRIP_MODULES
               mkdir -p {initramfs_staging_dir}
             # Build initramfs
               create_modules_staging "${{MODULES_LIST}}" {modules_staging_dir} \
                       {initramfs_staging_dir} "${{MODULES_BLOCKLIST}}" \
                       "${{MODULES_RECOVERY_LIST:-""}}" "${{MODULES_CHARGER_LIST:-""}}" "-e"
               modules_root_dir=$(readlink -e {initramfs_staging_dir}/lib/modules/*) || exit 1
               cp ${{modules_root_dir}}/modules.load {modules_load}
               {cp_vendor_boot_modules_load_cmd}
               {cp_modules_load_recovery_cmd}
               {cp_vendor_boot_modules_load_recovery_cmd}
               {cp_modules_load_charger_cmd}
               {cp_vendor_boot_modules_load_charger_cmd}
               {cp_modules_options_cmd}
               mkbootfs "{initramfs_staging_dir}" {initramfs_args} >"{modules_staging_dir}/initramfs.cpio"
               {ramdisk_compress} "{modules_staging_dir}/initramfs.cpio" >"{initramfs_img}"
             # Archive initramfs_staging_dir
               tar czf {initramfs_staging_archive} -C {initramfs_staging_dir} .
             # Remove staging directories
               rm -rf {initramfs_staging_dir}
    """.format(
        modules_list = utils.optional_path(ctx.file.modules_list),
        modules_recovery_list = utils.optional_path(ctx.file.modules_recovery_list),
        modules_charger_list = utils.optional_path(ctx.file.modules_charger_list),
        modules_blocklist = utils.optional_path(ctx.file.modules_blocklist),
        modules_options = utils.optional_path(ctx.file.modules_options),
        modules_staging_dir = modules_staging_dir,
        trim_unused_modules = "1" if ctx.attr.trim_unused_modules else "",
        initramfs_staging_dir = initramfs_staging_dir,
        initramfs_args = initramfs_args,
        ramdisk_compress = ramdisk_compress,
        modules_load = modules_load.path,
        initramfs_img = initramfs_img.path,
        initramfs_staging_archive = initramfs_staging_archive.path,
        cp_vendor_boot_modules_load_cmd = cp_vendor_boot_modules_load_cmd,
        cp_modules_load_recovery_cmd = cp_modules_load_recovery_cmd,
        cp_vendor_boot_modules_load_recovery_cmd = cp_vendor_boot_modules_load_recovery_cmd,
        cp_modules_load_charger_cmd = cp_modules_load_charger_cmd,
        cp_vendor_boot_modules_load_charger_cmd = cp_vendor_boot_modules_load_charger_cmd,
        cp_modules_options_cmd = cp_modules_options_cmd,
    )

    default_info = image_utils.build_modules_image(
        what = "initramfs",
        outputs = outputs,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        set_ext_modules = True,
        implicit_outputs = [
            initramfs_staging_archive,
        ],
        additional_inputs = additional_inputs,
        mnemonic = "Initramfs",
        kernel_modules_install = ctx.attr.kernel_modules_install,
        deps = ctx.attr.deps,
        create_modules_order = ctx.attr.create_modules_order,
    )
    return [
        default_info,
        InitramfsInfo(
            initramfs_img = initramfs_img,
            initramfs_staging_archive = initramfs_staging_archive,
            vendor_boot_modules_load = vendor_boot_modules_load,
        ),
    ]

initramfs = rule(
    implementation = _initramfs_impl,
    doc = """Build initramfs.

When included in a `pkg_files` target included by `pkg_install`, this rule copies the following to
`destdir`:

- `initramfs.img`
- `modules.load`
- `modules.load.recovery`
- `modules.load.charger`
- `vendor_boot.modules.load`
- `vendor_boot.modules.load.recovery`
- `vendor_boot.modules.load.charger`
""",
    attrs = {
        "kernel_modules_install": attr.label(
            mandatory = True,
            providers = [KernelModuleInfo],
            doc = "The [`kernel_modules_install`](#kernel_modules_install).",
        ),
        "deps": attr.label_list(
            allow_files = True,
            doc = """A list of additional dependencies to build initramfs.""",
        ),
        "create_modules_order": attr.bool(
            default = True,
            doc = """Whether to create and keep a modules.order file generated
                by a postorder traversal of the `kernel_modules_install` sources.
                It defaults to `True`.""",
        ),
        "modules_list": attr.label(
            allow_single_file = True,
            doc = "A file containing list of modules to use for `vendor_boot.modules.load`.",
        ),
        "modules_recovery_list": attr.label(
            allow_single_file = True,
            doc = "A file containing a list of modules to load when booting into recovery.",
        ),
        "modules_charger_list": attr.label(
            allow_single_file = True,
            doc = "A file containing a list of modules to load when booting intocharger mode.",
        ),
        "modules_blocklist": attr.label(allow_single_file = True, doc = """
            A file containing a list of modules which are
            blocked from being loaded.

            This file is copied directly to staging directory, and should be in the format:
            ```
            blocklist module_name
            ```
            """),
        "modules_options": attr.label(allow_single_file = True, doc = """
            a file copied to `/lib/modules/<kernel_version>/modules.options` on the ramdisk.

            Lines in the file should be of the form:
            ```
            options <modulename> <param1>=<val> <param2>=<val> ...
            ```
            """),
        "ramdisk_compression": attr.string(
            doc = "If provided it specfies the format used for any ramdisks generated." +
                  "If not provided a fallback value from build.config is used.",
            values = ["lz4", "gzip"],
        ),
        "ramdisk_compression_args": attr.string(
            doc = "Command line arguments passed only to lz4 command to control compression level.",
        ),
        "trim_unused_modules": attr.bool(
            default = False,
            doc = """If `True` then modules not mentioned in modules.load are removed
                from the initramfs. It defaults to `False`.""",
        ),
        "vendor_boot_name": attr.string(doc = """Name of `vendor_boot` image.

                * If `"vendor_boot"`, build `vendor_boot.img`
                * If `"vendor_kernel_boot"`, build `vendor_kernel_boot.img`
                * If `None`, skip building `vendor_boot`.
            """, values = ["vendor_boot", "vendor_kernel_boot"]),
        "vendor_ramdisk_dev_nodes": attr.label_list(
            allow_files = True,
            doc = """List of dev nodes description files which describes special device files
                to be added to the vendor ramdisk. File format is as accepted by mkbootfs.
                See `mkbootfs -h` for more details.""",
        ),
    },
    subrules = [image_utils.build_modules_image],
)
