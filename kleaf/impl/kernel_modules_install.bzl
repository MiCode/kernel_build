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
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
)
load(":debug.bzl", "debug")
load(
    ":utils.bzl",
    "kernel_utils",
)

def _kernel_modules_install_impl(ctx):
    kernel_utils.check_kernel_build(ctx.attr.kernel_modules, ctx.attr.kernel_build, ctx.label)

    # A list of declared files for outputs of kernel_module rules
    external_modules = []

    inputs = []
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_srcs
    inputs += [
        ctx.file._search_and_cp_output,
        ctx.file._check_duplicated_files_in_archives,
        ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_staging_archive,
    ]
    for kernel_module in ctx.attr.kernel_modules:
        inputs += dws.files(kernel_module[KernelModuleInfo].modules_staging_dws)

        for module_file in kernel_module[KernelModuleInfo].files:
            declared_file = ctx.actions.declare_file("{}/{}".format(ctx.label.name, module_file.basename))
            external_modules.append(declared_file)

    modules_staging_dws = dws.make(ctx, "{}/staging".format(ctx.label.name))

    command = ""
    command += ctx.attr.kernel_build[KernelEnvInfo].setup
    command += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_setup
    command += """
             # create dirs for modules
               mkdir -p {modules_staging_dir}
             # Restore modules_staging_dir from kernel_build
               tar xf {kernel_build_modules_staging_archive} -C {modules_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dws.directory.path,
        kernel_build_modules_staging_archive =
            ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_staging_archive.path,
    )
    for kernel_module in ctx.attr.kernel_modules:
        # Allow directories to be written because we are merging multiple directories into one.
        # However, don't allow files to be written because we don't expect modules to produce
        # conflicting files. check_duplicated_files_in_archives further enforces this.
        command += dws.restore(
            kernel_module[KernelModuleInfo].modules_staging_dws,
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
            [ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_staging_archive.path] +
            [kernel_module[KernelModuleInfo].modules_staging_dws.directory.path for kernel_module in ctx.attr.kernel_modules],
        ),
        modules_staging_dir = modules_staging_dws.directory.path,
        check_duplicated_files_in_archives = ctx.file._check_duplicated_files_in_archives.path,
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
            search_and_cp_output = ctx.file._search_and_cp_output.path,
        )

    command += dws.record(modules_staging_dws)

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelModulesInstall",
        inputs = inputs,
        outputs = external_modules + dws.files(modules_staging_dws),
        command = command,
        progress_message = "Running depmod {}".format(ctx.label),
    )

    return [
        DefaultInfo(files = depset(external_modules)),
        KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            modules_staging_dws = modules_staging_dws,
        ),
    ]

kernel_modules_install = rule(
    implementation = _kernel_modules_install_impl,
    doc = """Generates a rule that runs depmod in the module installation directory.

When including this rule to the `data` attribute of a `copy_to_dist_dir` rule,
all external kernel modules specified in `kernel_modules` are included in
distribution. This excludes `module_outs` in `kernel_build` to avoid conflicts.

Example:
```
kernel_modules_install(
    name = "foo_modules_install",
    kernel_build = ":foo",           # A kernel_build rule
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
            providers = [KernelEnvInfo, KernelModuleInfo],
            doc = "A list of labels referring to `kernel_module`s to install. Must have the same `kernel_build` as this rule.",
        ),
        "kernel_build": attr.label(
            providers = [KernelEnvInfo, KernelBuildExtModuleInfo],
            doc = "Label referring to the `kernel_build` module.",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_check_duplicated_files_in_archives": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:check_duplicated_files_in_archives.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
            doc = "Label referring to the script to process outputs",
        ),
    },
)
