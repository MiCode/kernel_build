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

load("//build/kernel/kleaf:directory_with_structure.bzl", dws = "directory_with_structure")
load(
    ":common_providers.bzl",
    "KernelBuildInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "utils")

def _build_modules_image_impl_common(
        ctx,
        what,
        outputs,
        build_command,
        modules_staging_dir,
        restore_modules_install = None,
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
        restore_modules_install: If `True`, restore `ctx.attr.kernel_modules_install`. Default is `True`.
    """

    if restore_modules_install == None:
        restore_modules_install = True

    kernel_build = ctx.attr.kernel_modules_install[KernelModuleInfo].kernel_build
    kernel_build_outs = kernel_build[KernelBuildInfo].outs + kernel_build[KernelBuildInfo].base_kernel_files
    system_map = utils.find_file(
        name = "System.map",
        files = kernel_build_outs,
        required = True,
        what = "{}: outs of dependent kernel_build {}".format(ctx.label, kernel_build),
    )

    if restore_modules_install:
        modules_install_staging_dws = ctx.attr.kernel_modules_install[KernelModuleInfo].modules_staging_dws

    inputs = []
    if additional_inputs != None:
        inputs += additional_inputs
    inputs += [
        system_map,
    ]
    if restore_modules_install:
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
        "vendor_dlkm_modules_list",
        "vendor_dlkm_modules_blocklist",
        "vendor_dlkm_props",
        "system_dlkm_modules_list",
        "system_dlkm_modules_blocklist",
        "system_dlkm_props",
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

image_utils = struct(
    build_modules_image_impl_common = _build_modules_image_impl_common,
    build_modules_image_attrs_common = _build_modules_image_attrs_common,
)
