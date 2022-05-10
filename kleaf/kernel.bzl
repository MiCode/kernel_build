# Copyright (C) 2021 The Android Open Source Project
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

load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load("//build/bazel_common_rules/exec:exec.bzl", "exec")
load(
    "//build/kernel/kleaf/impl:common_providers.bzl",
    "KernelBuildAbiInfo",
    "KernelBuildInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
    "KernelUnstrippedModulesInfo",
)
load("//build/kernel/kleaf/impl:debug.bzl", "debug")
load("//build/kernel/kleaf/impl:kernel_build.bzl", _kernel_build_macro = "kernel_build")
load("//build/kernel/kleaf/impl:kernel_build_config.bzl", _kernel_build_config = "kernel_build_config")
load("//build/kernel/kleaf/impl:kernel_compile_commands.bzl", _kernel_compile_commands = "kernel_compile_commands")
load("//build/kernel/kleaf/impl:kernel_dtstree.bzl", "DtstreeInfo", _kernel_dtstree = "kernel_dtstree")
load("//build/kernel/kleaf/impl:kernel_filegroup.bzl", _kernel_filegroup = "kernel_filegroup")
load("//build/kernel/kleaf/impl:kernel_kythe.bzl", _kernel_kythe = "kernel_kythe")
load("//build/kernel/kleaf/impl:kernel_module.bzl", _kernel_module_macro = "kernel_module")
load("//build/kernel/kleaf/impl:kernel_modules_install.bzl", _kernel_modules_install = "kernel_modules_install")
load("//build/kernel/kleaf/impl:kernel_unstripped_modules_archive.bzl", _kernel_unstripped_modules_archive = "kernel_unstripped_modules_archive")
load("//build/kernel/kleaf/impl:merged_kernel_uapi_headers.bzl", _merged_kernel_uapi_headers = "merged_kernel_uapi_headers")
load("//build/kernel/kleaf/impl:btf.bzl", "btf")
load(":directory_with_structure.bzl", dws = "directory_with_structure")
load(":hermetic_tools.bzl", "HermeticToolsInfo")
load(":update_source_file.bzl", "update_source_file")
load(
    "//build/kernel/kleaf/impl:utils.bzl",
    "find_file",
    "find_files",
    "kernel_utils",
    "utils",
)
load(
    "//build/kernel/kleaf/artifact_tests:kernel_test.bzl",
    "kernel_module_test",
)

# Re-exports
kernel_build = _kernel_build_macro
kernel_build_config = _kernel_build_config
kernel_compile_commands = _kernel_compile_commands
kernel_dtstree = _kernel_dtstree
kernel_filegroup = _kernel_filegroup
kernel_kythe = _kernel_kythe
kernel_module = _kernel_module_macro
kernel_modules_install = _kernel_modules_install
kernel_unstripped_modules_archive = _kernel_unstripped_modules_archive
merged_kernel_uapi_headers = _merged_kernel_uapi_headers

def _build_modules_image_impl_common(
        ctx,
        what,
        outputs,
        build_command,
        modules_staging_dir,
        implicit_outputs = None,
        additional_inputs = None,
        mnemonic = None):
    """Command implementation for building images that directly contain modules.

    Args:
        ctx: ctx
        what: what is being built, for logging
        outputs: list of `ctx.actions.declare_file`
        build_command: the command to build `outputs` and `implicit_outputs`
        modules_staging_dir: a staging directory for module installation
        implicit_outputs: like `outputs`, but not installed to `DIST_DIR` (not returned in
          `DefaultInfo`)
    """
    kernel_build = ctx.attr.kernel_modules_install[KernelModuleInfo].kernel_build
    kernel_build_outs = kernel_build[KernelBuildInfo].outs + kernel_build[KernelBuildInfo].base_kernel_files
    system_map = find_file(
        name = "System.map",
        files = kernel_build_outs,
        required = True,
        what = "{}: outs of dependent kernel_build {}".format(ctx.label, kernel_build),
    )
    modules_install_staging_dws = ctx.attr.kernel_modules_install[KernelModuleInfo].modules_staging_dws

    inputs = []
    if additional_inputs != None:
        inputs += additional_inputs
    inputs += [
        system_map,
    ]
    inputs += dws.files(modules_install_staging_dws)
    inputs += ctx.files.deps
    inputs += kernel_build[KernelEnvInfo].dependencies

    command_outputs = []
    command_outputs += outputs
    if implicit_outputs != None:
        command_outputs += implicit_outputs

    command = ""
    command += kernel_build[KernelEnvInfo].setup

    for attr_name in (
        "modules_list",
        "modules_blocklist",
        "modules_options",
        "vendor_dlkm_modules_list",
        "vendor_dlkm_modules_blocklist",
        "vendor_dlkm_props",
    ):
        # Checks if attr_name is a valid attribute name in the current rule.
        # If not, do not touch its value.
        if not hasattr(ctx.file, attr_name):
            continue

        # If it is a valid attribute name, set environment variable to the path if the argument is
        # supplied, otherwise set environment variable to empty.
        file = getattr(ctx.file, attr_name)
        path = ""
        if file != None:
            path = file.path
            inputs.append(file)
        command += """
            {name}={path}
        """.format(
            name = attr_name.upper(),
            path = path,
        )

    # Allow writing to files because create_modules_staging wants to overwrite modules.order.
    command += dws.restore(
        modules_install_staging_dws,
        dst = modules_staging_dir,
        options = "-aL --chmod=F+w",
    )

    command += """
             # Restore System.map to DIST_DIR for run_depmod in create_modules_staging
               mkdir -p ${{DIST_DIR}}
               cp {system_map} ${{DIST_DIR}}/System.map

               {build_command}
    """.format(
        system_map = system_map.path,
        build_command = build_command,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = mnemonic,
        inputs = inputs,
        outputs = command_outputs,
        progress_message = "Building {} {}".format(what, ctx.label),
        command = command,
    )
    return DefaultInfo(files = depset(outputs))

def _build_modules_image_attrs_common(additional = None):
    """Common attrs for rules that builds images that directly contain modules."""
    ret = {
        "kernel_modules_install": attr.label(
            mandatory = True,
            providers = [KernelModuleInfo],
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    }
    if additional != None:
        ret.update(additional)
    return ret

_InitramfsInfo = provider(fields = {
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
        vendor_boot_modules_load,
    ]

    modules_staging_dir = initramfs_img.dirname + "/staging"
    initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"

    command = """
               mkdir -p {initramfs_staging_dir}
             # Build initramfs
               create_modules_staging "${{MODULES_LIST}}" {modules_staging_dir} \
                 {initramfs_staging_dir} "${{MODULES_BLOCKLIST}}" "-e"
               modules_root_dir=$(echo {initramfs_staging_dir}/lib/modules/*)
               cp ${{modules_root_dir}}/modules.load {modules_load}
               cp ${{modules_root_dir}}/modules.load {vendor_boot_modules_load}
               echo "${{MODULES_OPTIONS}}" > ${{modules_root_dir}}/modules.options
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
        vendor_boot_modules_load = vendor_boot_modules_load.path,
        initramfs_img = initramfs_img.path,
        initramfs_staging_archive = initramfs_staging_archive.path,
    )

    default_info = _build_modules_image_impl_common(
        ctx = ctx,
        what = "initramfs",
        outputs = outputs,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        implicit_outputs = [
            initramfs_staging_archive,
        ],
        mnemonic = "Initramfs",
    )
    return [
        default_info,
        _InitramfsInfo(
            initramfs_img = initramfs_img,
            initramfs_staging_archive = initramfs_staging_archive,
        ),
    ]

_initramfs = rule(
    implementation = _initramfs_impl,
    doc = """Build initramfs.

When included in a `copy_to_dist_dir` rule, this rule copies the following to `DIST_DIR`:
- `initramfs.img`
- `modules.load`
- `vendor_boot.modules.load`

An additional label, `{name}/vendor_boot.modules.load`, is declared to point to the
corresponding files.
""",
    attrs = _build_modules_image_attrs_common({
        "vendor_boot_modules_load": attr.output(),
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
        "modules_options": attr.label(allow_single_file = True),
    }),
)

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

    default_info = _build_modules_image_impl_common(
        ctx = ctx,
        what = "system_dlkm",
        outputs = [system_dlkm_img, system_dlkm_staging_archive],
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        mnemonic = "SystemDlkmImage",
    )
    return [default_info]

_system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm.img an erofs image with GKI modules.

When included in a `copy_to_dist_dir` rule, this rule copies the `system_dlkm.img` to `DIST_DIR`.

""",
    attrs = _build_modules_image_attrs_common({
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
    }),
)

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
                # Restore vendor_boot.modules.load
                  cp {vendor_boot_modules_load} ${{DIST_DIR}}/vendor_boot.modules.load
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

    return _build_modules_image_impl_common(
        ctx = ctx,
        what = "vendor_dlkm",
        outputs = [vendor_dlkm_img, vendor_dlkm_modules_load, vendor_dlkm_modules_blocklist],
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        additional_inputs = additional_inputs,
        mnemonic = "VendorDlkmImage",
    )

_vendor_dlkm_image = rule(
    implementation = _vendor_dlkm_image_impl,
    doc = """Build vendor_dlkm image.

Execute `build_vendor_dlkm` in `build_utils.sh`.

When included in a `copy_to_dist_dir` rule, this rule copies a `vendor_dlkm.img` to `DIST_DIR`.
""",
    attrs = _build_modules_image_attrs_common({
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

def _boot_images_impl(ctx):
    outdir = ctx.actions.declare_directory(ctx.label.name)
    modules_staging_dir = outdir.path + "/staging"
    mkbootimg_staging_dir = modules_staging_dir + "/mkbootimg_staging"

    if ctx.attr.initramfs:
        initramfs_staging_archive = ctx.attr.initramfs[_InitramfsInfo].initramfs_staging_archive
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
            ctx.attr.initramfs[_InitramfsInfo].initramfs_img,
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
            initramfs_img = ctx.attr.initramfs[_InitramfsInfo].initramfs_img.path,
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

_boot_images = rule(
    implementation = _boot_images_impl,
    doc = """Build boot images, including `boot.img`, `vendor_boot.img`, etc.

Execute `build_boot_images` in `build_utils.sh`.""",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildInfo],
        ),
        "initramfs": attr.label(
            providers = [_InitramfsInfo],
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

def _dtbo_impl(ctx):
    output = ctx.actions.declare_file("{}/dtbo.img".format(ctx.label.name))
    inputs = []
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.files.srcs
    command = ""
    command += ctx.attr.kernel_build[KernelEnvInfo].setup

    command += """
             # make dtbo
               mkdtimg create {output} ${{MKDTIMG_FLAGS}} {srcs}
    """.format(
        output = output.path,
        srcs = " ".join([f.path for f in ctx.files.srcs]),
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "Dtbo",
        inputs = inputs,
        outputs = [output],
        progress_message = "Building dtbo {}".format(ctx.label),
        command = command,
    )
    return DefaultInfo(files = depset([output]))

_dtbo = rule(
    implementation = _dtbo_impl,
    doc = "Build dtbo.",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildInfo],
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    },
)

def kernel_images(
        name,
        kernel_modules_install,
        kernel_build = None,
        build_initramfs = None,
        build_vendor_dlkm = None,
        build_boot = None,
        build_vendor_boot = None,
        build_vendor_kernel_boot = None,
        build_system_dlkm = None,
        build_dtbo = None,
        dtbo_srcs = None,
        mkbootimg = None,
        deps = None,
        boot_image_outs = None,
        modules_list = None,
        modules_blocklist = None,
        modules_options = None,
        vendor_ramdisk_binaries = None,
        vendor_dlkm_modules_list = None,
        vendor_dlkm_modules_blocklist = None,
        vendor_dlkm_props = None):
    """Build multiple kernel images.

    Args:
        name: name of this rule, e.g. `kernel_images`,
        kernel_modules_install: A `kernel_modules_install` rule.

          The main kernel build is inferred from the `kernel_build` attribute of the
          specified `kernel_modules_install` rule. The main kernel build must contain
          `System.map` in `outs` (which is included if you use `aarch64_outs` or
          `x86_64_outs` from `common_kernels.bzl`).
        kernel_build: A `kernel_build` rule. Must specify if `build_boot`.
        mkbootimg: Path to the mkbootimg.py script which builds boot.img.
          Keep in sync with `MKBOOTIMG_PATH`. Only used if `build_boot`. If `None`,
          default to `//tools/mkbootimg:mkbootimg.py`.
        deps: Additional dependencies to build images.

          This must include the following:
          - For `initramfs`:
            - The file specified by `MODULES_LIST`
            - The file specified by `MODULES_BLOCKLIST`, if `MODULES_BLOCKLIST` is set
          - For `vendor_dlkm` image:
            - The file specified by `VENDOR_DLKM_MODULES_LIST`
            - The file specified by `VENDOR_DLKM_MODULES_BLOCKLIST`, if set
            - The file specified by `VENDOR_DLKM_PROPS`, if set
            - The file specified by `selinux_fc` in `VENDOR_DLKM_PROPS`, if set

        boot_image_outs: A list of output files that will be installed to `DIST_DIR` when
          `build_boot_images` in `build/kernel/build_utils.sh` is executed.

          You may leave out `vendor_boot.img` from the list. It is automatically added when
          `build_vendor_boot = True`.

          If `build_boot` is equal to `False`, the default is empty.

          If `build_boot` is equal to `True`, the default list assumes the following:
          - `BOOT_IMAGE_FILENAME` is not set (which takes default value `boot.img`), or is set to
            `"boot.img"`
          - `vendor_boot.img` if `build_vendor_boot`
          - `RAMDISK_EXT=lz4`. If the build configuration has a different value, replace
            `ramdisk.lz4` with `ramdisk.{RAMDISK_EXT}` accordingly.
          - `BOOT_IMAGE_HEADER_VERSION >= 4`, which creates `vendor-bootconfig.img` to contain
            `VENDOR_BOOTCONFIG`
          - The list contains `dtb.img`
        build_initramfs: Whether to build initramfs. Keep in sync with `BUILD_INITRAMFS`.
        build_system_dlkm: Whether to build system_dlkm.img an erofs image with GKI modules.
        build_vendor_dlkm: Whether to build `vendor_dlkm` image. It must be set if
          `vendor_dlkm_modules_list` is set.

          Note: at the time of writing (Jan 2022), unlike `build.sh`,
          `vendor_dlkm.modules.blocklist` is **always** created
          regardless of the value of `VENDOR_DLKM_MODULES_BLOCKLIST`.
          If `build_vendor_dlkm()` in `build_utils.sh` does not generate
          `vendor_dlkm.modules.blocklist`, an empty file is created.
        build_boot: Whether to build boot image. It must be set if either `BUILD_BOOT_IMG`
          or `BUILD_VENDOR_BOOT_IMG` is set.

          This depends on `initramfs` and `kernel_build`. Hence, if this is set to `True`,
          `build_initramfs` is implicitly true, and `kernel_build` must be set.

          If `True`, adds `boot.img` to `boot_image_outs` if not already in the list.
        build_vendor_boot: Whether to build `vendor_boot.img`. It must be set if either
          `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set,
          and `BUILD_VENDOR_KERNEL_BOOT` is not set.

          At most **one** of `build_vendor_boot` and `build_vendor_kernel_boot` may be set to
          `True`.

          If `True`, adds `vendor_boot.img` to `boot_image_outs` if not already in the list.

        build_vendor_kernel_boot: Whether to build `vendor_kernel_boot.img`. It must be set if either
          `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set,
          and `BUILD_VENDOR_KERNEL_BOOT` is set.

          At most **one** of `build_vendor_boot` and `build_vendor_kernel_boot` may be set to
          `True`.

          If `True`, adds `vendor_kernel_boot.img` to `boot_image_outs` if not already in the list.
        build_dtbo: Whether to build dtbo image. Keep this in sync with `BUILD_DTBO_IMG`.

          If `dtbo_srcs` is non-empty, `build_dtbo` is `True` by default. Otherwise it is `False`
          by default.
        dtbo_srcs: list of `*.dtbo` files used to package the `dtbo.img`. Keep this in sync
          with `MKDTIMG_DTBOS`; see example below.

          If `dtbo_srcs` is non-empty, `build_dtbo` must not be explicitly set to `False`.

          Example:
          ```
          kernel_build(
              name = "tuna_kernel",
              outs = [
                  "path/to/foo.dtbo",
                  "path/to/bar.dtbo",
              ],
          )
          kernel_images(
              name = "tuna_images",
              kernel_build = ":tuna_kernel",
              dtbo_srcs = [
                  ":tuna_kernel/path/to/foo.dtbo",
                  ":tuna_kernel/path/to/bar.dtbo",
              ]
          )
          ```
        modules_list: A file containing list of modules to use for `vendor_boot.modules.load`.

          This corresponds to `MODULES_LIST` in `build.config` for `build.sh`.
        modules_blocklist: A file containing a list of modules which are
          blocked from being loaded.

          This file is copied directly to staging directory, and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        modules_options: A `/lib/modules/modules.options` file is created on the ramdisk containing
          the contents of this variable.

          Lines should be of the form:
          ```
          options <modulename> <param1>=<val> <param2>=<val> ...
          ```

          This corresponds to `MODULES_OPTIONS` in `build.config` for `build.sh`.
        vendor_dlkm_modules_list: location of an optional file
          containing the list of kernel modules which shall be copied into a
          `vendor_dlkm` partition image. Any modules passed into `MODULES_LIST` which
          become part of the `vendor_boot.modules.load` will be trimmed from the
          `vendor_dlkm.modules.load`.

          This corresponds to `VENDOR_DLKM_MODULES_LIST` in `build.config` for `build.sh`.
        vendor_dlkm_modules_blocklist: location of an optional file containing a list of modules
          which are blocked from being loaded.

          This file is copied directly to the staging directory and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `VENDOR_DLKM_MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        vendor_dlkm_props: location of a text file containing
          the properties to be used for creation of a `vendor_dlkm` image
          (filesystem, partition size, etc). If this is not set (and
          `build_vendor_dlkm` is), a default set of properties will be used
          which assumes an ext4 filesystem and a dynamic partition.

          This corresponds to `VENDOR_DLKM_PROPS` in `build.config` for `build.sh`.
        vendor_ramdisk_binaries: List of vendor ramdisk binaries
          which includes the device-specific components of ramdisk like the fstab
          file and the device-specific rc files. If specifying multiple vendor ramdisks
          and identical file paths exist in the ramdisks, the file from last ramdisk is used.

          Note: **order matters**. To prevent buildifier from sorting the list, add the following:
          ```
          # do not sort
          ```

          This corresponds to `VENDOR_RAMDISK_BINARY` in `build.config` for `build.sh`.
    """
    all_rules = []

    build_any_boot_image = build_boot or build_vendor_boot or build_vendor_kernel_boot
    if build_any_boot_image:
        if kernel_build == None:
            fail("{}: Must set kernel_build if any of these are true: build_boot={}, build_vendor_boot={}, build_vendor_kernel_boot={}".format(name, build_boot, build_vendor_boot, build_vendor_kernel_boot))

    # Set default value for boot_image_outs according to build_boot
    if boot_image_outs == None:
        if not build_any_boot_image:
            boot_image_outs = []
        else:
            boot_image_outs = [
                "dtb.img",
                "ramdisk.lz4",
                "vendor-bootconfig.img",
            ]

    boot_image_outs = list(boot_image_outs)

    if build_boot and "boot.img" not in boot_image_outs:
        boot_image_outs.append("boot.img")

    if build_vendor_boot and "vendor_boot.img" not in boot_image_outs:
        boot_image_outs.append("vendor_boot.img")

    if build_vendor_kernel_boot and "vendor_kernel_boot.img" not in boot_image_outs:
        boot_image_outs.append("vendor_kernel_boot.img")

    if build_initramfs:
        _initramfs(
            name = "{}_initramfs".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name),
            modules_list = modules_list,
            modules_blocklist = modules_blocklist,
            modules_options = modules_options,
        )
        all_rules.append(":{}_initramfs".format(name))

    if build_system_dlkm:
        _system_dlkm_image(
            name = "{}_system_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
            modules_list = modules_list,
            modules_blocklist = modules_blocklist,
        )
        all_rules.append(":{}_system_dlkm_image".format(name))

    if build_vendor_dlkm:
        _vendor_dlkm_image(
            name = "{}_vendor_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name) if build_initramfs else None,
            deps = deps,
            vendor_dlkm_modules_list = vendor_dlkm_modules_list,
            vendor_dlkm_modules_blocklist = vendor_dlkm_modules_blocklist,
            vendor_dlkm_props = vendor_dlkm_props,
        )
        all_rules.append(":{}_vendor_dlkm_image".format(name))

    if build_any_boot_image:
        if build_vendor_kernel_boot:
            vendor_boot_name = "vendor_kernel_boot"
        elif build_vendor_boot:
            vendor_boot_name = "vendor_boot"
        else:
            vendor_boot_name = None
        _boot_images(
            name = "{}_boot_images".format(name),
            kernel_build = kernel_build,
            outs = ["{}_boot_images/{}".format(name, out) for out in boot_image_outs],
            deps = deps,
            initramfs = ":{}_initramfs".format(name) if build_initramfs else None,
            mkbootimg = mkbootimg,
            vendor_ramdisk_binaries = vendor_ramdisk_binaries,
            build_boot = build_boot,
            vendor_boot_name = vendor_boot_name,
        )
        all_rules.append(":{}_boot_images".format(name))

    if build_dtbo == None:
        build_dtbo = bool(dtbo_srcs)

    if dtbo_srcs:
        if not build_dtbo:
            fail("{}: build_dtbo must be True if dtbo_srcs is non-empty.")

    if build_dtbo:
        _dtbo(
            name = "{}_dtbo".format(name),
            srcs = dtbo_srcs,
            kernel_build = kernel_build,
        )
        all_rules.append(":{}_dtbo".format(name))

    native.filegroup(
        name = name,
        srcs = all_rules,
    )

def _kernel_extracted_symbols_impl(ctx):
    if ctx.attr.kernel_build_notrim[KernelBuildAbiInfo].trim_nonlisted_kmi:
        fail("{}: Requires `kernel_build` {} to have `trim_nonlisted_kmi = False`.".format(
            ctx.label,
            ctx.attr.kernel_build_notrim.label,
        ))

    if ctx.attr.kmi_symbol_list_add_only and not ctx.file.src:
        fail("{}: kmi_symbol_list_add_only requires kmi_symbol_list.".format(ctx.label))

    out = ctx.actions.declare_file("{}/extracted_symbols".format(ctx.attr.name))
    intermediates_dir = utils.intermediates_dir(ctx)

    gki_modules_list = ctx.attr.gki_modules_list_kernel_build[KernelBuildAbiInfo].module_outs_file
    vmlinux = find_file(name = "vmlinux", files = ctx.files.kernel_build_notrim, what = "{}: kernel_build_notrim".format(ctx.attr.name), required = True)
    in_tree_modules = find_files(suffix = ".ko", files = ctx.files.kernel_build_notrim, what = "{}: kernel_build_notrim".format(ctx.attr.name))
    srcs = [
        gki_modules_list,
        vmlinux,
    ]
    srcs += in_tree_modules
    for kernel_module in ctx.attr.kernel_modules:  # external modules
        srcs += kernel_module[KernelModuleInfo].files

    inputs = [ctx.file._extract_symbols]
    inputs += srcs
    inputs += ctx.attr.kernel_build_notrim[KernelEnvInfo].dependencies

    cp_src_cmd = ""
    flags = ["--symbol-list", out.path]
    flags += ["--gki-modules", gki_modules_list.path]
    if not ctx.attr.module_grouping:
        flags.append("--skip-module-grouping")
    if ctx.attr.kmi_symbol_list_add_only:
        flags.append("--additions-only")
        inputs.append(ctx.file.src)

        # Follow symlinks because we are in the execroot.
        # Do not preserve permissions because we are overwriting the file immediately.
        cp_src_cmd = "cp -L {src} {out}".format(
            src = ctx.file.src.path,
            out = out.path,
        )

    command = ctx.attr.kernel_build_notrim[KernelEnvInfo].setup
    command += """
        mkdir -p {intermediates_dir}
        cp -pl {srcs} {intermediates_dir}
        {cp_src_cmd}
        {extract_symbols} {flags} {intermediates_dir}
        rm -rf {intermediates_dir}
    """.format(
        srcs = " ".join([file.path for file in srcs]),
        intermediates_dir = intermediates_dir,
        extract_symbols = ctx.file._extract_symbols.path,
        flags = " ".join(flags),
        cp_src_cmd = cp_src_cmd,
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out],
        command = command,
        progress_message = "Extracting symbols {}".format(ctx.label),
        mnemonic = "KernelExtractedSymbols",
    )

    return DefaultInfo(files = depset([out]))

_kernel_extracted_symbols = rule(
    implementation = _kernel_extracted_symbols_impl,
    attrs = {
        # We can't use kernel_filegroup + hermetic_tools here because
        # - extract_symbols depends on the clang toolchain, which requires us to
        #   know the toolchain_version ahead of time.
        # - We also don't have the necessity to extract symbols from prebuilts.
        "kernel_build_notrim": attr.label(providers = [KernelEnvInfo, KernelBuildAbiInfo]),
        "kernel_modules": attr.label_list(providers = [KernelModuleInfo]),
        "module_grouping": attr.bool(default = True),
        "src": attr.label(doc = "Source `abi_gki_*` file. Used when `kmi_symbol_list_add_only`.", allow_single_file = True),
        "kmi_symbol_list_add_only": attr.bool(),
        "gki_modules_list_kernel_build": attr.label(doc = "The `kernel_build` which `module_outs` is treated as GKI modules list.", providers = [KernelBuildAbiInfo]),
        "_extract_symbols": attr.label(default = "//build/kernel:abi/extract_symbols", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_abi_dump_impl(ctx):
    full_abi_out_file = _kernel_abi_dump_full(ctx)
    abi_out_file = _kernel_abi_dump_filtered(ctx, full_abi_out_file)
    return [
        DefaultInfo(files = depset([full_abi_out_file, abi_out_file])),
        OutputGroupInfo(abi_out_file = depset([abi_out_file])),
    ]

def _kernel_abi_dump_epilog_cmd(path, append_version):
    ret = ""
    if append_version:
        ret += """
             # Append debug information to abi file
               echo "
<!--
     libabigail: $(abidw --version)
-->" >> {path}
""".format(path = path)
    return ret

def _kernel_abi_dump_full(ctx):
    abi_linux_tree = utils.intermediates_dir(ctx) + "/abi_linux_tree"
    full_abi_out_file = ctx.actions.declare_file("{}/abi-full.xml".format(ctx.attr.name))
    vmlinux = find_file(name = "vmlinux", files = ctx.files.kernel_build, what = "{}: kernel_build".format(ctx.attr.name), required = True)

    unstripped_dir_provider_targets = [ctx.attr.kernel_build] + ctx.attr.kernel_modules
    unstripped_dir_providers = [target[KernelUnstrippedModulesInfo] for target in unstripped_dir_provider_targets]
    for prov, target in zip(unstripped_dir_providers, unstripped_dir_provider_targets):
        if not prov.directory:
            fail("{}: Requires dep {} to set collect_unstripped_modules = True".format(ctx.label, target.label))
    unstripped_dirs = [prov.directory for prov in unstripped_dir_providers]

    inputs = [vmlinux, ctx.file._dump_abi]
    inputs += ctx.files._dump_abi_scripts
    inputs += unstripped_dirs

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    # Directories could be empty, so use a find + cp
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        mkdir -p {abi_linux_tree}
        find {unstripped_dirs} -name '*.ko' -exec cp -pl -t {abi_linux_tree} {{}} +
        cp -pl {vmlinux} {abi_linux_tree}
        {dump_abi} --linux-tree {abi_linux_tree} --out-file {full_abi_out_file}
        {epilog}
        rm -rf {abi_linux_tree}
    """.format(
        abi_linux_tree = abi_linux_tree,
        unstripped_dirs = " ".join([unstripped_dir.path for unstripped_dir in unstripped_dirs]),
        dump_abi = ctx.file._dump_abi.path,
        vmlinux = vmlinux.path,
        full_abi_out_file = full_abi_out_file.path,
        epilog = _kernel_abi_dump_epilog_cmd(full_abi_out_file.path, True),
    )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [full_abi_out_file],
        command = command,
        mnemonic = "AbiDumpFull",
        progress_message = "Extracting ABI {}".format(ctx.label),
    )
    return full_abi_out_file

def _kernel_abi_dump_filtered(ctx, full_abi_out_file):
    abi_out_file = ctx.actions.declare_file("{}/abi.xml".format(ctx.attr.name))
    inputs = [full_abi_out_file]

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    combined_abi_symbollist = ctx.attr.kernel_build[KernelBuildAbiInfo].combined_abi_symbollist
    if combined_abi_symbollist:
        inputs += [
            ctx.file._filter_abi,
            combined_abi_symbollist,
        ]

        command += """
            {filter_abi} --in-file {full_abi_out_file} --out-file {abi_out_file} --kmi-symbol-list {abi_symbollist}
            {epilog}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
            filter_abi = ctx.file._filter_abi.path,
            abi_symbollist = combined_abi_symbollist.path,
            epilog = _kernel_abi_dump_epilog_cmd(abi_out_file.path, False),
        )
    else:
        command += """
            cp -p {full_abi_out_file} {abi_out_file}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
        )
    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [abi_out_file],
        command = command,
        mnemonic = "AbiDumpFiltered",
        progress_message = "Filtering ABI dump {}".format(ctx.label),
    )
    return abi_out_file

_kernel_abi_dump = rule(
    implementation = _kernel_abi_dump_impl,
    doc = "Extracts the ABI.",
    attrs = {
        "kernel_build": attr.label(providers = [KernelEnvInfo, KernelBuildAbiInfo, KernelUnstrippedModulesInfo]),
        "kernel_modules": attr.label_list(providers = [KernelUnstrippedModulesInfo]),
        "_dump_abi_scripts": attr.label(default = "//build/kernel:dump-abi-scripts"),
        "_dump_abi": attr.label(default = "//build/kernel:abi/dump_abi", allow_single_file = True),
        "_filter_abi": attr.label(default = "//build/kernel:abi/filter_abi", allow_single_file = True),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_abi_prop_impl(ctx):
    content = []
    if ctx.file.kmi_definition:
        content.append("KMI_DEFINITION={}".format(ctx.file.kmi_definition.basename))
        content.append("KMI_MONITORED=1")

        if ctx.attr.kmi_enforced:
            content.append("KMI_ENFORCED=1")

    combined_abi_symbollist = ctx.attr.kernel_build[KernelBuildAbiInfo].combined_abi_symbollist
    if combined_abi_symbollist:
        content.append("KMI_SYMBOL_LIST={}".format(combined_abi_symbollist.basename))

    # This just appends `KERNEL_BINARY=vmlinux`, but find_file additionally ensures that
    # we are building vmlinux.
    vmlinux = find_file(name = "vmlinux", files = ctx.files.kernel_build, what = "{}: kernel_build".format(ctx.attr.name), required = True)
    content.append("KERNEL_BINARY={}".format(vmlinux.basename))

    if ctx.file.modules_archive:
        content.append("MODULES_ARCHIVE={}".format(ctx.file.modules_archive.basename))

    out = ctx.actions.declare_file("{}/abi.prop".format(ctx.attr.name))
    ctx.actions.write(
        output = out,
        content = "\n".join(content) + "\n",
    )
    return DefaultInfo(files = depset([out]))

_kernel_abi_prop = rule(
    implementation = _kernel_abi_prop_impl,
    doc = "Create `abi.prop`",
    attrs = {
        "kernel_build": attr.label(providers = [KernelBuildAbiInfo]),
        "modules_archive": attr.label(allow_single_file = True),
        "kmi_definition": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
    },
)

def kernel_build_abi(
        name,
        define_abi_targets = None,
        # for kernel_abi
        kernel_modules = None,
        module_grouping = None,
        abi_definition = None,
        kmi_enforced = None,
        unstripped_modules_archive = None,
        kmi_symbol_list_add_only = None,
        # for kernel_build
        **kwargs):
    """Declare multiple targets to support ABI monitoring.

    This macro is meant to be used in place of the [`kernel_build`](#kernel_build)
    marco. All arguments in `kwargs` are passed to `kernel_build` directly.

    For example, you may have the following declaration. (For actual definition
    of `kernel_aarch64`, see
    [`define_common_kernels()`](#define_common_kernels).

    ```
    kernel_build_abi(name = "kernel_aarch64", **kwargs)
    _dist_targets = ["kernel_aarch64", ...]
    copy_to_dist_dir(name = "kernel_aarch64_dist", data = _dist_targets)
    kernel_build_abi_dist(
        name = "kernel_aarch64_abi_dist",
        kernel_build_abi = "kernel_aarch64",
        data = _dist_targets,
    )
    ```

    The `kernel_build_abi` invocation is equivalent to the following:

    ```
    kernel_build(name = "kernel_aarch64", **kwargs)
    # if define_abi_targets, also define some other targets
    ```

    See [`kernel_build`](#kernel_build) for the targets defined.

    In addition, the following targets are defined:
    - `kernel_aarch64_abi_dump`
      - Building this target extracts the ABI.
      - Include this target in a [`kernel_build_abi_dist`](#kernel_build_abi_dist)
        target to copy ABI dump to `--dist-dir`.
    - `kernel_aarch64_abi`
      - A filegroup that contains `kernel_aarch64_abi_dump`. It also contains other targets
        if `define_abi_targets = True`; see below.

    In addition, the following targets are defined if `define_abi_targets = True`:
    - `kernel_aarch64_abi_update_symbol_list`
      - Running this target updates `kmi_symbol_list`.
    - `kernel_aarch64_abi_update`
      - Running this target updates `abi_definition`.
    - `kernel_aarch64_abi_dump`
      - Building this target extracts the ABI.
      - Include this target in a [`kernel_build_abi_dist`](#kernel_build_abi_dist)
        target to copy ABI dump to `--dist-dir`.

    See build/kernel/kleaf/abi.md for a conversion chart from `build_abi.sh`
    commands to Bazel commands.

    Args:
      name: Name of the main `kernel_build`.
      define_abi_targets: Whether the `<name>_abi` target contains other
        files to support ABI monitoring. If `None`, defaults to `True`.

        If `False`, this macro is equivalent to just calling
        ```
        kernel_build(name = name, **kwargs)
        filegroup(name = name + "_abi", data = [name, abi_dump_target])
        ```

        If `True`, implies `collect_unstripped_modules = True`. See
        [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).
      kernel_modules: A list of external [`kernel_module()`](#kernel_module)s
        to extract symbols from.
      module_grouping: If unspecified or `None`, it is `True` by default.
        If `True`, then the symbol list will group symbols based
        on the kernel modules that reference the symbol. Otherwise the symbol
        list will simply be a sorted list of symbols used by all the kernel
        modules.
      abi_definition: Location of the ABI definition.
      kmi_enforced: This is an indicative option to signal that KMI is enforced.
        If set to `True`, KMI checking tools respects it and
        reacts to it by failing if KMI differences are detected.
      unstripped_modules_archive: A [`kernel_unstripped_modules_archive`](#kernel_unstripped_modules_archive)
        which name is specified in `abi.prop`.
      kmi_symbol_list_add_only: If unspecified or `None`, it is `False` by
        default. If `True`,
        then any symbols in the symbol list that would have been
        removed are preserved (at the end of the file). Symbol list update will
        fail if there is no pre-existing symbol list file to read from. This
        property is intended to prevent unintentional shrinkage of a stable ABI.

        This should be set to `True` if `KMI_SYMBOL_LIST_ADD_ONLY=1`.
      kwargs: See [`kernel_build.kwargs`](#kernel_build-kwargs)
    """

    if define_abi_targets == None:
        define_abi_targets = True

    kwargs = dict(kwargs)
    if kwargs.get("collect_unstripped_modules") == None:
        kwargs["collect_unstripped_modules"] = True

    _kernel_build_abi_define_other_targets(
        name = name,
        define_abi_targets = define_abi_targets,
        kernel_modules = kernel_modules,
        module_grouping = module_grouping,
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        abi_definition = abi_definition,
        kmi_enforced = kmi_enforced,
        unstripped_modules_archive = unstripped_modules_archive,
        kernel_build_kwargs = kwargs,
    )

    kernel_build(name = name, **kwargs)

def _kernel_build_abi_define_other_targets(
        name,
        define_abi_targets,
        kernel_modules,
        module_grouping,
        kmi_symbol_list_add_only,
        abi_definition,
        kmi_enforced,
        unstripped_modules_archive,
        kernel_build_kwargs):
    """Helper to `kernel_build_abi`.

    Defines targets other than the main `kernel_build()`.

    Defines:
    * `{name}_with_vmlinux`
    * `{name}_notrim` (if `define_abi_targets`)
    * `{name}_abi_diff_executable`
    * `{name}_abi`
    """
    new_outs, outs_changed = kernel_utils.kernel_build_outs_add_vmlinux(name, kernel_build_kwargs.get("outs"))

    # with_vmlinux: outs += [vmlinux]
    if outs_changed or kernel_build_kwargs.get("base_kernel"):
        with_vmlinux_kwargs = dict(kernel_build_kwargs)
        with_vmlinux_kwargs["outs"] = kernel_utils.transform_kernel_build_outs(name + "_with_vmlinux", "outs", new_outs)
        with_vmlinux_kwargs["base_kernel_for_module_outs"] = with_vmlinux_kwargs.pop("base_kernel", default = None)
        kernel_build(name = name + "_with_vmlinux", **with_vmlinux_kwargs)
    else:
        native.alias(name = name + "_with_vmlinux", actual = name)

    _kernel_abi_dump(
        name = name + "_abi_dump",
        kernel_build = name + "_with_vmlinux",
        kernel_modules = [module + "_with_vmlinux" for module in kernel_modules] if kernel_modules else kernel_modules,
    )

    if not define_abi_targets:
        _kernel_build_abi_not_define_abi_targets(
            name = name,
            abi_dump_target = name + "_abi_dump",
        )
    else:
        _kernel_build_abi_define_abi_targets(
            name = name,
            kernel_modules = kernel_modules,
            module_grouping = module_grouping,
            kmi_symbol_list_add_only = kmi_symbol_list_add_only,
            abi_definition = abi_definition,
            kmi_enforced = kmi_enforced,
            unstripped_modules_archive = unstripped_modules_archive,
            outs_changed = outs_changed,
            new_outs = new_outs,
            abi_dump_target = name + "_abi_dump",
            kernel_build_with_vmlinux_target = name + "_with_vmlinux",
            kernel_build_kwargs = kernel_build_kwargs,
        )

def _kernel_build_abi_not_define_abi_targets(
        name,
        abi_dump_target):
    """Helper to `_kernel_build_abi_define_other_targets` when `define_abi_targets = False.`

    Defines `{name}_abi` filegroup that only contains the ABI dump, provided
    in `abi_dump_target`.

    Defines:
    * `{name}_abi_diff_executable`
    * `{name}_abi`
    """
    native.filegroup(
        name = name + "_abi",
        srcs = [abi_dump_target],
    )

    # For kernel_build_abi_dist to use when define_abi_targets is not set.
    exec(
        name = name + "_abi_diff_executable",
        script = "",
    )

def _kernel_build_abi_define_abi_targets(
        name,
        kernel_modules,
        module_grouping,
        kmi_symbol_list_add_only,
        abi_definition,
        kmi_enforced,
        unstripped_modules_archive,
        outs_changed,
        new_outs,
        abi_dump_target,
        kernel_build_with_vmlinux_target,
        kernel_build_kwargs):
    """Helper to `_kernel_build_abi_define_other_targets` when `define_abi_targets = True.`

    Define targets to extract symbol list, extract ABI, update them, etc.

    Defines:
    * `{name}_notrim`
    * `{name}_abi_diff_executable`
    * `{name}_abi`
    """

    default_outputs = [abi_dump_target]

    # notrim: outs += [vmlinux], trim_nonlisted_kmi = False
    if kernel_build_kwargs.get("trim_nonlisted_kmi") or outs_changed or kernel_build_kwargs.get("base_kernel"):
        notrim_kwargs = dict(kernel_build_kwargs)
        notrim_kwargs["outs"] = kernel_utils.transform_kernel_build_outs(name + "_notrim", "outs", new_outs)
        notrim_kwargs["trim_nonlisted_kmi"] = False
        notrim_kwargs["kmi_symbol_list_strict_mode"] = False
        notrim_kwargs["base_kernel_for_module_outs"] = notrim_kwargs.pop("base_kernel", default = None)
        kernel_build(name = name + "_notrim", **notrim_kwargs)
    else:
        native.alias(name = name + "_notrim", actual = name)

    # extract_symbols ...
    _kernel_extracted_symbols(
        name = name + "_abi_extracted_symbols",
        kernel_build_notrim = name + "_notrim",
        kernel_modules = [module + "_notrim" for module in kernel_modules] if kernel_modules else kernel_modules,
        module_grouping = module_grouping,
        src = kernel_build_kwargs.get("kmi_symbol_list"),
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        # If base_kernel is set, this is a device build, so use the GKI
        # modules list from base_kernel (GKI). If base_kernel is not set, this
        # likely a GKI build, so use modules_outs from itself.
        gki_modules_list_kernel_build = kernel_build_kwargs.get("base_kernel", name),
    )
    update_source_file(
        name = name + "_abi_update_symbol_list",
        src = name + "_abi_extracted_symbols",
        dst = kernel_build_kwargs.get("kmi_symbol_list"),
    )

    default_outputs += _kernel_build_abi_define_abi_definition_targets(
        name = name,
        abi_definition = abi_definition,
        kmi_enforced = kmi_enforced,
        kmi_symbol_list = kernel_build_kwargs.get("kmi_symbol_list"),
    )

    _kernel_abi_prop(
        name = name + "_abi_prop",
        kmi_definition = name + "_abi_out_file" if abi_definition else None,
        kmi_enforced = kmi_enforced,
        kernel_build = kernel_build_with_vmlinux_target,
        modules_archive = unstripped_modules_archive,
    )
    default_outputs.append(name + "_abi_prop")

    native.filegroup(
        name = name + "_abi",
        srcs = default_outputs,
    )

def _kernel_build_abi_define_abi_definition_targets(
        name,
        abi_definition,
        kmi_enforced,
        kmi_symbol_list):
    """Helper to `_kernel_build_abi_define_abi_targets`.

    Defines targets to extract ABI, update ABI, compare ABI, etc. etc.

    Defines `{name}_abi_diff_executable`.
    """
    if not abi_definition:
        # For kernel_build_abi_dist to use when abi_definition is empty.
        exec(
            name = name + "_abi_diff_executable",
            script = "",
        )
        return []

    default_outputs = []

    native.filegroup(
        name = name + "_abi_out_file",
        srcs = [name + "_abi_dump"],
        output_group = "abi_out_file",
    )

    _kernel_abi_diff(
        name = name + "_abi_diff",
        baseline = abi_definition,
        new = name + "_abi_out_file",
        kmi_enforced = kmi_enforced,
    )
    default_outputs.append(name + "_abi_diff")

    # The default outputs of _abi_diff does not contain the executable,
    # but the reports. Use this filegroup to select the executable
    # so rootpath in _abi_update works.
    native.filegroup(
        name = name + "_abi_diff_executable",
        srcs = [name + "_abi_diff"],
        output_group = "executable",
    )

    native.filegroup(
        name = name + "_abi_diff_git_message",
        srcs = [name + "_abi_diff"],
        output_group = "git_message",
    )

    update_source_file(
        name = name + "_abi_update_definition",
        src = name + "_abi_out_file",
        dst = abi_definition,
    )

    exec(
        name = name + "_abi_nodiff_update",
        data = [
            name + "_abi_extracted_symbols",
            name + "_abi_update_definition",
            kmi_symbol_list,
        ],
        script = """
              # Ensure that symbol list is updated
                if ! diff -q $(rootpath {src_symbol_list}) $(rootpath {dst_symbol_list}); then
                  echo "ERROR: symbol list must be updated before updating ABI definition. To update, execute 'tools/bazel run //{package}:{update_symbol_list_label}'." >&2
                  exit 1
                fi
              # Update abi_definition
                $(rootpath {update_definition})
            """.format(
            src_symbol_list = name + "_abi_extracted_symbols",
            dst_symbol_list = kmi_symbol_list,
            package = native.package_name(),
            update_symbol_list_label = name + "_abi_update_symbol_list",
            update_definition = name + "_abi_update_definition",
        ),
    )

    exec(
        name = name + "_abi_update",
        data = [
            abi_definition,
            name + "_abi_diff_git_message",
            name + "_abi_diff_executable",
            name + "_abi_nodiff_update",
        ],
        script = """
              # Update abi_definition
                $(rootpath {nodiff_update})
              # Create git commit if requested
                if [[ $1 == "--commit" ]]; then
                    real_abi_def="$(realpath $(rootpath {abi_definition}))"
                    git -C $(dirname ${{real_abi_def}}) add $(basename ${{real_abi_def}})
                    git -C $(dirname ${{real_abi_def}}) commit -F $(realpath $(rootpath {git_message}))
                fi
              # Check return code of diff_abi and kmi_enforced
                set +e
                $(rootpath {diff})
                rc=$?
                set -e
              # Prompt for editing the commit message
                if [[ $1 == "--commit" ]]; then
                    echo
                    echo "INFO: git commit created. Execute the following to edit the commit message:"
                    echo "        git -C $(dirname $(rootpath {abi_definition})) commit --amend"
                fi
                exit $rc
            """.format(
            diff = name + "_abi_diff_executable",
            nodiff_update = name + "_abi_nodiff_update",
            abi_definition = abi_definition,
            git_message = name + "_abi_diff_git_message",
        ),
    )

    return default_outputs

def kernel_build_abi_dist(
        name,
        kernel_build_abi,
        **kwargs):
    """A wrapper over `copy_to_dist_dir` for [`kernel_build_abi`](#kernel_build_abi).

    After copying all files to dist dir, return the exit code from `diff_abi`.

    Args:
      name: name of the dist target
      kernel_build_abi: name of the [`kernel_build_abi`](#kernel_build_abi)
        invocation.
    """

    # TODO(b/231647455): Clean up hard-coded name "_abi" and "_abi_diff_executable".

    if kwargs.get("data") == None:
        kwargs["data"] = []

    # Use explicit + to prevent modifying the original list.
    kwargs["data"] = kwargs["data"] + [kernel_build_abi + "_abi"]

    copy_to_dist_dir(
        name = name + "_copy_to_dist_dir",
        **kwargs
    )

    exec(
        name = name,
        data = [
            name + "_copy_to_dist_dir",
            kernel_build_abi + "_abi_diff_executable",
        ],
        script = """
          # Copy to dist dir
            $(rootpath {copy_to_dist_dir}) $@
          # Check return code of diff_abi and kmi_enforced
            $(rootpath {diff})
        """.format(
            copy_to_dist_dir = name + "_copy_to_dist_dir",
            diff = kernel_build_abi + "_abi_diff_executable",
        ),
    )

def _kernel_abi_diff_impl(ctx):
    inputs = [
        ctx.file._diff_abi,
        ctx.file.baseline,
        ctx.file.new,
    ]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    inputs += ctx.files._diff_abi_scripts

    output_dir = ctx.actions.declare_directory("{}/abi_diff".format(ctx.attr.name))
    error_msg_file = ctx.actions.declare_file("{}/error_msg_file".format(ctx.attr.name))
    exit_code_file = ctx.actions.declare_file("{}/exit_code_file".format(ctx.attr.name))
    git_msg_file = ctx.actions.declare_file("{}/git_message.txt".format(ctx.attr.name))
    default_outputs = [output_dir]

    command_outputs = default_outputs + [
        error_msg_file,
        exit_code_file,
        git_msg_file,
    ]

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        set +e
        {diff_abi} --baseline {baseline}                \\
                   --new      {new}                     \\
                   --report   {output_dir}/abi.report   \\
                   --abi-tool delegated > {error_msg_file} 2>&1
        rc=$?
        set -e
        echo $rc > {exit_code_file}

        : > {git_msg_file}
        if [[ -f {output_dir}/abi.report.short ]]; then
          cat >> {git_msg_file} <<EOF
ANDROID: <TODO subject line>

<TODO commit message>

$(cat {output_dir}/abi.report.short)

Bug: <TODO bug number>
EOF
        else
            echo "WARNING: No short report found. Unable to infer the git commit message." >&2
        fi
        if [[ $rc == 0 ]]; then
            echo "INFO: $(cat {error_msg_file})"
        else
            echo "ERROR: $(cat {error_msg_file})" >&2
            echo "INFO: exit code is not checked. 'tools/bazel run {label}' to check the exit code." >&2
        fi
    """.format(
        diff_abi = ctx.file._diff_abi.path,
        baseline = ctx.file.baseline.path,
        new = ctx.file.new.path,
        output_dir = output_dir.path,
        exit_code_file = exit_code_file.path,
        error_msg_file = error_msg_file.path,
        git_msg_file = git_msg_file.path,
        label = ctx.label,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        mnemonic = "KernelDiffAbi",
        progress_message = "Comparing ABI {}".format(ctx.label),
    )

    script = ctx.actions.declare_file("{}/print_results.sh".format(ctx.attr.name))
    script_content = """#!/bin/bash -e
        rc=$(cat {exit_code_file})
        if [[ $rc == 0 ]]; then
            echo "INFO: $(cat {error_msg_file})"
        else
            echo "ERROR: $(cat {error_msg_file})" >&2
        fi
""".format(
        exit_code_file = exit_code_file.short_path,
        error_msg_file = error_msg_file.short_path,
    )
    if ctx.attr.kmi_enforced:
        script_content += """
            exit $rc
        """
    ctx.actions.write(script, script_content, is_executable = True)

    return [
        DefaultInfo(
            files = depset(default_outputs),
            executable = script,
            runfiles = ctx.runfiles(files = command_outputs),
        ),
        OutputGroupInfo(
            executable = depset([script]),
            git_message = depset([git_msg_file]),
        ),
    ]

_kernel_abi_diff = rule(
    implementation = _kernel_abi_diff_impl,
    doc = "Run `diff_abi`",
    attrs = {
        "baseline": attr.label(allow_single_file = True),
        "new": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_diff_abi_scripts": attr.label(default = "//build/kernel:diff-abi-scripts"),
        "_diff_abi": attr.label(default = "//build/kernel:abi/diff_abi", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    executable = True,
)
