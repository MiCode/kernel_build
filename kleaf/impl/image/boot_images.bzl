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
Rules for building boot images.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":common_providers.bzl", "KernelBuildInfo", "KernelSerializedEnvInfo")
load(":debug.bzl", "debug")
load(":image/image_utils.bzl", "image_utils")
load(":image/initramfs.bzl", "InitramfsInfo")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

def _build_boot_or_vendor_boot(
        subrule_ctx,
        bin_dir,
        kernel_build,
        initramfs,
        deps,
        outs,
        mkbootimg,
        build_boot,
        vendor_boot_name,
        vendor_ramdisk_binaries,
        vendor_ramdisk_dev_nodes,
        unpack_ramdisk,
        avb_sign_boot_img,
        avb_boot_partition_size,
        avb_boot_key,
        avb_boot_algorithm,
        avb_boot_partition_name,
        ramdisk_compression,
        ramdisk_compression_args,
        dtb_image_file,
        *,
        vendor_bootconfig_file = None,
        kernel_vendor_cmdline = None,
        _search_and_cp_output):
    ## Declare implicit outputs of the command
    ## This is like subrule_ctx.actions.declare_directory(subrule_ctx.label.name) without actually declaring it.
    outdir_short = paths.join(
        subrule_ctx.label.workspace_root,
        subrule_ctx.label.package,
        subrule_ctx.label.name,
    )
    outdir = paths.join(
        bin_dir.path,
        outdir_short,
    )
    modules_staging_dir = outdir + "/staging"
    mkbootimg_staging_dir = modules_staging_dir + "/mkbootimg_staging"

    # Initialized conditionally below.
    initramfs_staging_archive = None
    initramfs_staging_dir = None

    if initramfs:
        initramfs_staging_archive = initramfs[InitramfsInfo].initramfs_staging_archive
        initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"

    # Action output
    out_files = []
    for out in outs:
        out_files.append(subrule_ctx.actions.declare_file("{}/{}".format(subrule_ctx.label.name, out)))

    # Rule output
    extra_default_info_files = []

    kernel_build_outs = depset(transitive = [
        kernel_build[KernelBuildInfo].outs,
        kernel_build[KernelBuildInfo].base_kernel_files,
    ])

    inputs = []
    if initramfs:
        inputs += [
            initramfs[InitramfsInfo].initramfs_img,
            initramfs_staging_archive,
        ]

    transitive_inputs = [
        mkbootimg.files,
        kernel_build_outs,
        kernel_build[KernelSerializedEnvInfo].inputs,
    ]
    transitive_inputs += [target.files for target in deps]

    if dtb_image_file:
        inputs.append(dtb_image_file)

    transitive_tools = [kernel_build[KernelSerializedEnvInfo].tools]

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = kernel_build[KernelSerializedEnvInfo],
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )

    command += """
        MKBOOTIMG_PATH={mkbootimg}
    """.format(mkbootimg = utils.optional_single_path(mkbootimg.files.to_list()))

    if build_boot:
        boot_flag_cmd = "BUILD_BOOT_IMG=1"
    else:
        boot_flag_cmd = "BUILD_BOOT_IMG="

    if not vendor_boot_name:
        vendor_boot_flag_cmd = """
            BUILD_VENDOR_BOOT_IMG=
            SKIP_VENDOR_BOOT=1
            BUILD_VENDOR_KERNEL_BOOT=
        """
    elif vendor_boot_name == "vendor_boot":
        vendor_boot_flag_cmd = """
            BUILD_VENDOR_BOOT_IMG=1
            SKIP_VENDOR_BOOT=
            BUILD_VENDOR_KERNEL_BOOT=
        """
    elif vendor_boot_name == "vendor_kernel_boot":
        vendor_boot_flag_cmd = """
            BUILD_VENDOR_BOOT_IMG=1
            SKIP_VENDOR_BOOT=
            BUILD_VENDOR_KERNEL_BOOT=1
        """
    else:
        fail("{}: unknown vendor_boot_name {}".format(subrule_ctx.label, vendor_boot_name))

    if vendor_ramdisk_binaries:
        vendor_ramdisk_binaries_files = depset(transitive = [target.files for target in vendor_ramdisk_binaries])
        written_vendor_ramdisk_binaries = utils.write_depset(
            vendor_ramdisk_binaries_files,
            "vendor_ramdisk_binaries.txt",
        )

        # build_utils.sh uses singular VENDOR_RAMDISK_BINARY
        command += """
            VENDOR_RAMDISK_BINARY="$(cat {written})"
        """.format(
            written = written_vendor_ramdisk_binaries.depset_file.path,
        )
        transitive_inputs.append(written_vendor_ramdisk_binaries.depset)

    if vendor_ramdisk_dev_nodes:
        vendor_ramdisk_dev_nodes_files = depset(transitive = [target.files for target in vendor_ramdisk_dev_nodes])
        written_vendor_ramdisk_dev_nodes = utils.write_depset(
            vendor_ramdisk_dev_nodes_files,
            "vendor_ramdisk_dev_nodes.txt",
        )
        command += """
            VENDOR_RAMDISK_DEV_NODES="{vendor_ramdisk_dev_nodes}"
        """.format(
            written = written_vendor_ramdisk_dev_nodes.depset_file,
        )
        transitive_inputs.append(written_vendor_ramdisk_dev_nodes.depset)

    command += """
             # Create and restore DIST_DIR.
             # We don't need all of *_for_dist. Copying all declared outputs of kernel_build is
             # sufficient.
               mkdir -p ${{DIST_DIR}}
               cp {kernel_build_outs} ${{DIST_DIR}}
    """.format(
        kernel_build_outs = " ".join([out.path for out in kernel_build_outs.to_list()]),
    )

    if initramfs:
        command += """
               cp {initramfs_img} ${{DIST_DIR}}/initramfs.img
             # Create and restore initramfs_staging_dir
               mkdir -p {initramfs_staging_dir}
               tar xf {initramfs_staging_archive} -C {initramfs_staging_dir}
        """.format(
            initramfs_img = initramfs[InitramfsInfo].initramfs_img.path,
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
    boot_flag_cmd += """
        DTB_IMAGE={dtb_image}
    """.format(
        dtb_image = utils.optional_path(dtb_image_file),
    )
    if unpack_ramdisk:
        boot_flag_cmd += """
            if [[ -n ${SKIP_UNPACKING_RAMDISK} ]]; then
                echo "WARNING: Using SKIP_UNPACKING_RAMDISK in build config is deprecated." >&2
                echo "  Use unpack_ramdisk in kernel_image instead." >&2
            fi
        """
    else:
        boot_flag_cmd += """
            SKIP_UNPACKING_RAMDISK=1
        """
    if avb_sign_boot_img:
        if not avb_boot_partition_size or \
           not avb_boot_key or not avb_boot_algorithm or \
           not avb_boot_partition_name:
            fail("avb_sign_boot_img is true, but one of [avb_boot_partition_size, avb_boot_key," +
                 " avb_boot_algorithm, avb_boot_partition_name] is not specified.")

        boot_flag_cmd += """
            AVB_SIGN_BOOT_IMG=1
            AVB_BOOT_PARTITION_SIZE={avb_boot_partition_size}
            AVB_BOOT_KEY={avb_boot_key}
            AVB_BOOT_ALGORITHM={avb_boot_algorithm}
            AVB_BOOT_PARTITION_NAME={avb_boot_partition_name}
        """.format(
            avb_boot_partition_size = avb_boot_partition_size,
            avb_boot_key = utils.optional_single_path(avb_boot_key.files.to_list()),
            avb_boot_algorithm = avb_boot_algorithm,
            avb_boot_partition_name = avb_boot_partition_name,
        )

    ramdisk_options = image_utils.ramdisk_options(
        ramdisk_compression = ramdisk_compression,
        ramdisk_compression_args = ramdisk_compression_args,
    )

    vendor_bootconfig_command = ""
    if vendor_bootconfig_file:
        vendor_bootconfig_command = """
            VENDOR_BOOTCONFIG_FILE={}
        """.format(vendor_bootconfig_file.path)
        inputs.append(vendor_bootconfig_file)
        extra_default_info_files.append(vendor_bootconfig_file)

    kernel_vendor_cmdline_cmd = ""
    if kernel_vendor_cmdline:
        kernel_vendor_cmdline_cmd = """
            KERNEL_VENDOR_CMDLINE={kernel_vendor_cmdline}
        """.format(kernel_vendor_cmdline = kernel_vendor_cmdline)

    command += """
             # Build boot images
               (
                 {boot_flag_cmd}
                 {vendor_boot_flag_cmd}
                 {set_initramfs_var_cmd}
                 MKBOOTIMG_STAGING_DIR=$(readlink -m {mkbootimg_staging_dir})
                 # Quote because they may contain spaces. Use double quotes because they
                 # may be a variable.
                 RAMDISK_COMPRESS="{ramdisk_compress}"
                 RAMDISK_DECOMPRESS="{ramdisk_decompress}"
                 RAMDISK_EXT="{ramdisk_ext}"
                 {vendor_bootconfig_command}
                 {kernel_vendor_cmdline_cmd}
                 build_boot_images
               )
               {search_and_cp_output} --srcdir ${{DIST_DIR}} --dstdir {outdir} {outs}
             # Remove staging directories
               rm -rf {modules_staging_dir}
    """.format(
        mkbootimg_staging_dir = mkbootimg_staging_dir,
        search_and_cp_output = _search_and_cp_output.executable.path,
        outdir = outdir,
        outs = " ".join(outs),
        modules_staging_dir = modules_staging_dir,
        boot_flag_cmd = boot_flag_cmd,
        vendor_boot_flag_cmd = vendor_boot_flag_cmd,
        set_initramfs_var_cmd = set_initramfs_var_cmd,
        ramdisk_compress = ramdisk_options.ramdisk_compress,
        ramdisk_decompress = ramdisk_options.ramdisk_decompress,
        ramdisk_ext = ramdisk_options.ramdisk_ext,
        vendor_bootconfig_command = vendor_bootconfig_command,
        kernel_vendor_cmdline_cmd = kernel_vendor_cmdline_cmd,
    )

    debug.print_scripts_subrule(command)
    subrule_ctx.actions.run_shell(
        mnemonic = "BootImages",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = out_files,
        tools = [
            # See https://github.com/bazelbuild/bazel/issues/13854.
            # The FilesToRunProvider is added directly here to also add its runfiles.
            _search_and_cp_output,
            # This is a depset of Files, so it can't contain _search_and_cp_output.
            depset(transitive = transitive_tools),
        ],
        progress_message = "Building boot images %{label}",
        command = command,
    )
    return DefaultInfo(files = depset(out_files + extra_default_info_files))

# Common implementation to build boot image or vendor boot image.
# TODO: Split build_boot_images in build_utils
build_boot_or_vendor_boot = subrule(
    implementation = _build_boot_or_vendor_boot,
    attrs = {
        "_search_and_cp_output": attr.label(
            default = Label("//build/kernel/kleaf:search_and_cp_output"),
            cfg = "exec",
            executable = True,
        ),
    },
    subrules = [
        debug.print_scripts_subrule,
        utils.write_depset,
    ],
)

def _boot_images_impl(ctx):
    return build_boot_or_vendor_boot(
        bin_dir = ctx.bin_dir,
        kernel_build = ctx.attr.kernel_build,
        initramfs = ctx.attr.initramfs,
        deps = ctx.attr.deps,
        outs = ctx.attr.outs,
        mkbootimg = ctx.attr.mkbootimg,
        build_boot = ctx.attr.build_boot,
        vendor_boot_name = ctx.attr.vendor_boot_name,
        vendor_ramdisk_binaries = ctx.attr.vendor_ramdisk_binaries,
        vendor_ramdisk_dev_nodes = ctx.attr.vendor_ramdisk_dev_nodes,
        unpack_ramdisk = ctx.attr.unpack_ramdisk,
        avb_sign_boot_img = ctx.attr.avb_sign_boot_img,
        avb_boot_partition_size = ctx.attr.avb_boot_partition_size,
        avb_boot_key = ctx.attr.avb_boot_key,
        avb_boot_algorithm = ctx.attr.avb_boot_algorithm,
        avb_boot_partition_name = ctx.attr.avb_boot_partition_name,
        ramdisk_compression = ctx.attr.ramdisk_compression,
        ramdisk_compression_args = ctx.attr.ramdisk_compression_args,
        dtb_image_file = ctx.file.dtb_image,
    )

boot_images = rule(
    implementation = _boot_images_impl,
    doc = """Build boot images, including `boot.img`, `vendor_boot.img`, etc.

Execute `build_boot_images` in `build_utils.sh`.""",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelSerializedEnvInfo, KernelBuildInfo],
        ),
        "initramfs": attr.label(
            providers = [InitramfsInfo],
        ),
        "deps": attr.label_list(
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
        ),
        "build_boot": attr.bool(),
        "vendor_boot_name": attr.string(doc = """
* If `"vendor_boot"`, build `vendor_boot.img`
* If `"vendor_kernel_boot"`, build `vendor_kernel_boot.img`
* If `None`, skip `vendor_boot`.
""", values = ["vendor_boot", "vendor_kernel_boot"]),
        "vendor_ramdisk_binaries": attr.label_list(allow_files = True),
        "vendor_ramdisk_dev_nodes": attr.label_list(allow_files = True),
        "unpack_ramdisk": attr.bool(
            doc = """ When false it skips unpacking the vendor ramdisk and copy it as
            is, without modifications, into the boot image. Also skip the mkbootfs step.

            It defaults to True. (Allowing falling back to the value in build config.
            This will change in the future, after giving notice about its deprecation.)
            """,
            default = True,
        ),
        "avb_sign_boot_img": attr.bool(
            doc = """ If set to `True` signs the boot image using the avb_boot_key.
            The kernel prebuilt tool `avbtool` is used for signing.""",
        ),
        "avb_boot_partition_size": attr.int(doc = """Size of the boot partition
            in bytes. Used when `avb_sign_boot_img` is True."""),
        "avb_boot_key": attr.label(
            doc = """ Key used for signing.
            Used when `avb_sign_boot_img` is True.""",
            allow_single_file = True,
        ),
        # Note: The actual values comes from:
        # https://cs.android.com/android/platform/superproject/+/master:external/avb/avbtool.py
        "avb_boot_algorithm": attr.string(
            doc = """ `avb_boot_key` algorithm
            used e.g. SHA256_RSA2048. Used when `avb_sign_boot_img` is True.""",
            values = [
                "NONE",
                "SHA256_RSA2048",
                "SHA256_RSA4096",
                "SHA256_RSA8192",
                "SHA512_RSA2048",
                "SHA512_RSA4096",
                "SHA512_RSA8192",
            ],
        ),
        "avb_boot_partition_name": attr.string(doc = """Name of the boot partition.
            Used when `avb_sign_boot_img` is True."""),
        "ramdisk_compression": attr.string(
            doc = "If provided it specfies the format used for any ramdisks generated." +
                  "If not provided a fallback value from build.config is used.",
            values = ["lz4", "gzip"],
        ),
        "ramdisk_compression_args": attr.string(
            doc = "Command line arguments passed only to lz4 command to control compression level.",
        ),
        "dtb_image": attr.label(
            doc = """A dtb.img to packaged.
                If this is set, then *.dtb from `kernel_build` are ignored.

                See [`dtb_image`](#dtb_image).""",
            allow_single_file = True,
        ),
    },
    subrules = [build_boot_or_vendor_boot],
)
