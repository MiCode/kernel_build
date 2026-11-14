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
Common utilities for working with kernel images.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/kernel/kleaf:directory_with_structure.bzl", dws = "directory_with_structure")
load(
    ":common_providers.bzl",
    "KernelModuleInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

SYSTEM_DLKM_STAGING_ARCHIVE_NAME = "system_dlkm_staging_archive.tar.gz"
SYSTEM_DLKM_MODULES_LOAD_NAME = "system_dlkm.modules.load"

VENDOR_DLKM_STAGING_ARCHIVE_NAME = "vendor_dlkm_staging_archive.tar.gz"

def _build_modules_image_impl(
        subrule_ctx,
        kernel_modules_install,
        deps,
        create_modules_order,
        what,
        outputs,
        build_command,
        modules_staging_dir,
        *,
        _set_ext_modules,
        restore_modules_install = None,
        set_ext_modules = None,
        implicit_outputs = None,
        additional_inputs = None,
        mnemonic = None):
    """Command implementation for building images that directly contain modules.

    Args:
        subrule_ctx: subrule_ctx.
        kernel_modules_install: `kernel_modules_install`
        deps: List of dependencies provided to the image building process,
        create_modules_order: Whether to create and keep a modules.order file generated
            by a postorder traversal of the `kernel_modules_install` sources.
        what: what is being built, for logging.
        outputs: list of `ctx.actions.declare_file`
        build_command: the command to build `outputs` and `implicit_outputs`.
        modules_staging_dir: a staging directory for module installation.
        restore_modules_install: If `True`, restore `kernel_modules_install`.
         Default is `True`.
        set_ext_modules: If `True`, set variable `EXT_MODULES` before invoking script
          in `build_utils.sh`
        implicit_outputs: like `outputs`, but not installed to `DIST_DIR` (not
         returned in `DefaultInfo`).
        additional_inputs: Additional files to be included.
        mnemonic: string to reference the build operation.
        _set_ext_modules: bool_flag that specifies whether to set EXT_MODULES.
    """

    if restore_modules_install == None:
        restore_modules_install = True

    kernel_build_infos = kernel_modules_install[KernelModuleInfo].kernel_build_infos
    kernel_build_outs = depset(
        transitive = [
            # Prefer device kernel_build, then base kernel_build
            kernel_build_infos.images_info.outs,
            kernel_build_infos.images_info.base_kernel_files,
        ],
        order = "preorder",
    )

    # depset.to_list() required for find_file.
    # TODO(b/256688440): providers should provide System.map directly
    kernel_build_outs = kernel_build_outs.to_list()
    system_map = utils.find_file(
        name = "System.map",
        files = kernel_build_outs,
        required = True,
        what = "{}: outs of dependent kernel_build {}".format(subrule_ctx.label, kernel_build_infos.label),
    )

    modules_install_staging_dws = None
    if restore_modules_install:
        modules_install_staging_dws_list = kernel_modules_install[KernelModuleInfo].modules_staging_dws_depset.to_list()
        if len(modules_install_staging_dws_list) != 1:
            fail("{}: {} is not a `kernel_modules_install`.".format(
                subrule_ctx.label,
                kernel_modules_install.label,
            ))
        modules_install_staging_dws = modules_install_staging_dws_list[0]

    inputs = []
    if additional_inputs != None:
        inputs += additional_inputs
    inputs.append(system_map)
    if restore_modules_install:
        inputs += dws.files(modules_install_staging_dws)
    transitive_inputs = [kernel_build_infos.serialized_env_info.inputs]
    transitive_inputs += [target.files for target in deps]
    tools = kernel_build_infos.serialized_env_info.tools

    command_outputs = []
    command_outputs += outputs
    if implicit_outputs != None:
        command_outputs += implicit_outputs

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = kernel_build_infos.serialized_env_info,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )

    # Allow writing to files because create_modules_staging wants to overwrite modules.order.
    if restore_modules_install:
        command += dws.restore(
            modules_install_staging_dws,
            dst = modules_staging_dir,
            options = "-aL --chmod=F+w --exclude=source --exclude=build",
        )

        # source/ and build/ are symlinks to the source tree and $OUT_DIR, respectively,
        # so they are copied as links.
        command += dws.restore(
            modules_install_staging_dws,
            dst = modules_staging_dir,
            options = "-al --chmod=F+w --include=source --include=build --exclude='*'",
        )

    modules_order_cmd = ""
    if create_modules_order:
        modules_order_depset = kernel_modules_install[KernelModuleInfo].modules_order
        modules_order_depset_list = modules_order_depset.to_list()
        inputs += modules_order_depset_list
        modules_order_cmd = """
            cat {modules_order} > kleaf_modules.order
            KLEAF_MODULES_ORDER=kleaf_modules.order
        """.format(
            modules_order = " ".join([modules_order.path for modules_order in modules_order_depset_list]),
        )

    if set_ext_modules and _set_ext_modules[BuildSettingInfo].value:
        ext_modules = kernel_modules_install[KernelModuleInfo].packages.to_list()
        command += """EXT_MODULES={quoted_ext_modules}""".format(
            quoted_ext_modules = shell.quote(" ".join(ext_modules)),
        )

    if not _set_ext_modules[BuildSettingInfo].value:
        # buildifier: disable=print
        print("""\nWARNING: This is a temporary flag to mitigate issues on migrating away from
setting EXT_MODULES in build.config. If you need --noset_ext_modules, please
file a bug.""")

    command += """
             # Restore System.map to DIST_DIR for run_depmod in create_modules_staging
               mkdir -p ${{DIST_DIR}}
               cp {system_map} ${{DIST_DIR}}/System.map

               {modules_order_cmd}
               {build_command}
    """.format(
        system_map = system_map.path,
        modules_order_cmd = modules_order_cmd,
        build_command = build_command,
    )

    debug.print_scripts_subrule(command)
    subrule_ctx.actions.run_shell(
        mnemonic = mnemonic,
        inputs = depset(inputs, transitive = transitive_inputs),
        tools = tools,
        outputs = command_outputs,
        progress_message = "Building {} %{{label}}".format(what),
        command = command,
    )
    return DefaultInfo(files = depset(outputs))

_build_modules_image = subrule(
    implementation = _build_modules_image_impl,
    attrs = {
        "_set_ext_modules": attr.label(
            default = "//build/kernel/kleaf:set_ext_modules",
        ),
    },
    subrules = [debug.print_scripts_subrule],
)

def _ramdisk_options(ramdisk_compression, ramdisk_compression_args):
    """Options for how to treat ramdisk images.

    Args:
        ramdisk_compression: If provided it specfies the format used for any ramdisks generated.
         If not provided a fallback value from build.config is used.
         Possible values are `lz4`, `gzip`, None.
        ramdisk_compression_args: Command line arguments passed to lz4 command
         to control compression level (defaults to `-12 --favor-decSpeed`).
         For iterative kernel development where faster compression is more
         desirable than a high compression ratio, it can be useful to control
         the compression ratio.
    """

    # Initially fallback to values from build.config.* files.
    _ramdisk_compress = "${RAMDISK_COMPRESS}"
    _ramdisk_decompress = "${RAMDISK_DECOMPRESS}"
    _ramdisk_ext = "lz4"

    if ramdisk_compression == "lz4":
        _ramdisk_compress = "lz4 -c -l "
        if ramdisk_compression_args:
            _ramdisk_compress += ramdisk_compression_args
        else:
            _ramdisk_compress += "-12 --favor-decSpeed"
        _ramdisk_decompress = "lz4 -c -d -l"
    if ramdisk_compression == "gzip":
        _ramdisk_compress = "gzip -c -f"
        _ramdisk_decompress = "gzip -c -d"
        _ramdisk_ext = "gz"

    return struct(
        ramdisk_compress = _ramdisk_compress,
        ramdisk_decompress = _ramdisk_decompress,
        ramdisk_ext = _ramdisk_ext,
    )

image_utils = struct(
    build_modules_image = _build_modules_image,
    ramdisk_options = _ramdisk_options,
)
