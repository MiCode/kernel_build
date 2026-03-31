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
A rule that runs depmod in the module installation directory.
"""

load("//build/kernel/kleaf:directory_with_structure.bzl", dws = "directory_with_structure")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelBuildInfo",
    "KernelCmdsInfo",
    "KernelEnvAndOutputsInfo",
    "KernelImagesInfo",
    "KernelModuleInfo",
)
load(":debug.bzl", "debug")
load(
    ":utils.bzl",
    "kernel_utils",
    "utils",
)

visibility("//build/kernel/kleaf/...")

def _kernel_modules_install_impl(ctx):
    kernel_build_infos = None
    if ctx.attr.kernel_build:
        kernel_build_infos = kernel_utils.create_kernel_module_kernel_build_info(ctx.attr.kernel_build)
    elif ctx.attr.kernel_modules:
        kernel_build_infos = ctx.attr.kernel_modules[0][KernelModuleInfo].kernel_build_infos

    if not kernel_build_infos:
        fail("No `kernel_build` or `kernel_modules` provided.")

    kernel_utils.check_kernel_build(
        [target[KernelModuleInfo] for target in ctx.attr.kernel_modules],
        kernel_build_infos.label,
        ctx.label,
    )

    # A list of declared files for outputs of kernel_module rules
    external_modules = []

    # TODO(b/256688440): Avoid depset[directory_with_structure] to_list
    modules_staging_dws_depset = depset(transitive = [
        kernel_module[KernelModuleInfo].modules_staging_dws_depset
        for kernel_module in ctx.attr.kernel_modules
    ])
    modules_staging_dws_list = modules_staging_dws_depset.to_list()

    inputs = []
    inputs.append(
        kernel_build_infos.ext_module_info.modules_staging_archive,
    )

    for input_modules_staging_dws in modules_staging_dws_list:
        inputs += dws.files(input_modules_staging_dws)

    module_files = depset(transitive = [
        kernel_module[KernelModuleInfo].files
        for kernel_module in ctx.attr.kernel_modules
    ]).to_list()
    for module_file in module_files:
        declared_file = ctx.actions.declare_file("{}/{}".format(ctx.label.name, module_file.basename))
        external_modules.append(declared_file)

    transitive_inputs = [
        kernel_build_infos.ext_module_info.module_scripts,
        kernel_build_infos.ext_module_info.modules_install_env_and_outputs_info.inputs,
    ]

    tools = [
        ctx.executable._check_duplicated_files_in_archives,
        ctx.executable._search_and_cp_output,
    ]
    transitive_tools = [kernel_build_infos.ext_module_info.modules_install_env_and_outputs_info.tools]

    modules_staging_dws = dws.make(ctx, "{}/staging".format(ctx.label.name))

    command = kernel_build_infos.ext_module_info.modules_install_env_and_outputs_info.get_setup_script(
        data = kernel_build_infos.ext_module_info.modules_install_env_and_outputs_info.data,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += """
             # create dirs for modules
               mkdir -p {modules_staging_dir}
             # Restore modules_staging_dir from kernel_build
               tar xf {kernel_build_modules_staging_archive} -C {modules_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dws.directory.path,
        kernel_build_modules_staging_archive =
            kernel_build_infos.ext_module_info.modules_staging_archive.path,
    )
    for input_modules_staging_dws in modules_staging_dws_list:
        # Allow directories to be written because we are merging multiple directories into one.
        # However, don't allow files to be written because we don't expect modules to produce
        # conflicting files. check_duplicated_files_in_archives further enforces this.
        command += dws.restore(
            input_modules_staging_dws,
            dst = modules_staging_dws.directory.path,
            options = "-aL --chmod=D+w",
        )

    # TODO(b/194347374): maybe run depmod.sh with CONFIG_SHELL?
    command += """
             # Check if there are duplicated files in modules_staging_archive of
             # depended kernel_build and kernel_module's
               {check_duplicated_files_in_archives} {modules_staging_archives}
             # Set variables
               if [[ ! -f ${{OUT_DIR}}/include/config/kernel.release ]]; then
                   echo "ERROR: No ${{OUT_DIR}}/include/config/kernel.release" >&2
                   exit 1
               fi
               kernelrelease=$(cat ${{OUT_DIR}}/include/config/kernel.release 2> /dev/null)
               mixed_build_prefix=
               if [[ ${{KBUILD_MIXED_TREE}} ]]; then
                   mixed_build_prefix=${{KBUILD_MIXED_TREE}}/
               fi
               real_modules_staging_dir=$(realpath {modules_staging_dir})
             # Run depmod
               (
                 cd ${{OUT_DIR}} # for System.map when mixed_build_prefix is not set
                 INSTALL_MOD_PATH=${{real_modules_staging_dir}} ${{ROOT_DIR}}/${{KERNEL_DIR}}/scripts/depmod.sh depmod ${{kernelrelease}} ${{mixed_build_prefix}}
               )
             # Remove symlinks that are dead outside of the sandbox
               (
                 symlink="$(ls {modules_staging_dir}/lib/modules/*/source)"
                 if [[ -n "$symlink" ]] && [[ -L "$symlink" ]]; then rm "$symlink"; fi
                 symlink="$(ls {modules_staging_dir}/lib/modules/*/build)"
                 if [[ -n "$symlink" ]] && [[ -L "$symlink" ]]; then rm "$symlink"; fi
               )
    """.format(
        modules_staging_archives = " ".join(
            [kernel_build_infos.ext_module_info.modules_staging_archive.path] +
            [input_modules_staging_dws.directory.path for input_modules_staging_dws in modules_staging_dws_list],
        ),
        modules_staging_dir = modules_staging_dws.directory.path,
        check_duplicated_files_in_archives = ctx.executable._check_duplicated_files_in_archives.path,
    )

    if external_modules:
        external_module_dir = external_modules[0].dirname
        command += """
                 # Move external modules to declared output location
                   {search_and_cp_output} --srcdir {modules_staging_dir}/lib/modules/*/extra --dstdir {outdir} {filenames}
        """.format(
            modules_staging_dir = modules_staging_dws.directory.path,
            outdir = external_module_dir,
            filenames = " ".join([declared_file.basename for declared_file in external_modules]),
            search_and_cp_output = ctx.executable._search_and_cp_output.path,
        )

    command += dws.record(modules_staging_dws)

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelModulesInstall",
        inputs = depset(inputs, transitive = transitive_inputs),
        tools = depset(tools, transitive = transitive_tools),
        outputs = external_modules + dws.files(modules_staging_dws),
        command = command,
        progress_message = "Running depmod {}".format(ctx.label),
    )

    # Only analyze headers on external modules.
    # To analyze headers on in-tree modules, just run analyze_inputs on the kernel_build directly.
    cmds_info_targets = ctx.attr.kernel_modules
    cmds_info_srcs = [target[KernelCmdsInfo].srcs for target in cmds_info_targets]
    cmds_info_directories = [target[KernelCmdsInfo].directories for target in cmds_info_targets]
    cmds_info = KernelCmdsInfo(
        srcs = depset(transitive = cmds_info_srcs),
        directories = depset(transitive = cmds_info_directories),
    )

    return [
        DefaultInfo(files = depset(external_modules)),
        KernelModuleInfo(
            kernel_build_infos = kernel_build_infos,
            modules_staging_dws_depset = depset([modules_staging_dws]),
            packages = depset(transitive = [
                target[KernelModuleInfo].packages
                for target in ctx.attr.kernel_modules
            ]),
            label = ctx.label,
            modules_order = depset(transitive = [
                target[KernelModuleInfo].modules_order
                for target in ctx.attr.kernel_modules
            ], order = "postorder"),
        ),
        cmds_info,
    ]

kernel_modules_install = rule(
    implementation = _kernel_modules_install_impl,
    doc = """Generates a rule that runs depmod in the module installation directory.

When including this rule to the `data` attribute of a `copy_to_dist_dir` rule,
all external kernel modules specified in `kernel_modules` are included in
distribution.  This excludes `module_outs` in `kernel_build` to avoid conflicts.

Example:
```
kernel_modules_install(
    name = "foo_modules_install",
    kernel_modules = [               # kernel_module rules
        "//path/to/nfc:nfc_module",
    ],
)
kernel_build(
    name = "foo",
    outs = ["vmlinux"],
    module_outs = ["core_module.ko"],
)
copy_to_dist_dir(
    name = "foo_dist",
    data = [
        ":foo",                      # Includes core_module.ko and vmlinux
        ":foo_modules_install",      # Includes nfc_module
    ],
)
```
In `foo_dist`, specifying `foo_modules_install` in `data` won't include
`core_module.ko`, because it is already included in `foo` in `data`.
""",
    attrs = {
        "kernel_modules": attr.label_list(
            providers = [KernelModuleInfo],
            doc = "A list of labels referring to `kernel_module`s to install.",
        ),
        "kernel_build": attr.label(
            providers = [
                KernelBuildExtModuleInfo,
                # Needed by KernelModuleInfo.kernel_build
                # TODO(b/247622808): Should put the info in KernelModuleInfo directly.
                KernelEnvAndOutputsInfo,
                KernelBuildInfo,
                KernelImagesInfo,
            ],
            doc = "Label referring to the `kernel_build` module. Otherwise, it" +
                  " is inferred from `kernel_modules`.",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_check_duplicated_files_in_archives": attr.label(
            default = Label("//build/kernel/kleaf:check_duplicated_files_in_archives"),
            doc = "Label referring to the script to process outputs",
            cfg = "exec",
            executable = True,
        ),
        "_search_and_cp_output": attr.label(
            default = Label("//build/kernel/kleaf:search_and_cp_output"),
            cfg = "exec",
            executable = True,
            doc = "Label referring to the script to process outputs",
        ),
    },
)
