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

"""An external kernel module.

Makefile and Kbuild files are required.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//build/kernel/kleaf:directory_with_structure.bzl", dws = "directory_with_structure")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    "//build/kernel/kleaf/artifact_tests:kernel_test.bzl",
    "kernel_module_test",
)
load(
    ":common_providers.bzl",
    "DdkSubmoduleInfo",
    "KernelBuildExtModuleInfo",
    "KernelCmdsInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
    "KernelUnstrippedModulesInfo",
    "ModuleSymversInfo",
)
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo")
load(":debug.bzl", "debug")
load(":kernel_build.bzl", "get_grab_cmd_step")
load(":stamp.bzl", "stamp")
load(":utils.bzl", "kernel_utils")

def kernel_module(
        name,
        kernel_build,
        outs = None,
        srcs = None,
        deps = None,
        makefile = None,
        **kwargs):
    """Generates a rule that builds an external kernel module.

    Example:
    ```
    kernel_module(
        name = "nfc",
        srcs = glob([
            "**/*.c",
            "**/*.h",

            # If there are Kbuild files, add them
            "**/Kbuild",
            # If there are additional makefiles in subdirectories, add them
            "**/Makefile",
        ]),
        outs = ["nfc.ko"],
        kernel_build = "//common:kernel_aarch64",
    )
    ```

    Args:
        name: Name of this kernel module.
        srcs: Source files to build this kernel module. If unspecified or value
          is `None`, it is by default the list in the above example:
          ```
          glob([
            "**/*.c",
            "**/*.h",
            "**/Kbuild",
            "**/Makefile",
          ])
          ```
        kernel_build: Label referring to the kernel_build module.
        deps: A list of other `kernel_module` or `ddk_module` dependencies.

          Before building this target, `Modules.symvers` from the targets in
          `deps` are restored, so this target can be built against
          them.

          It is an undefined behavior to put targets of other types to this list
          (e.g. `ddk_headers`).
        outs: The expected output files. If unspecified or value is `None`, it
          is `["{name}.ko"]` by default.

          For each token `out`, the build rule automatically finds a
          file named `out` in the legacy kernel modules staging
          directory. The file is copied to the output directory of
          this package, with the label `name/out`.

          - If `out` doesn't contain a slash, subdirectories are searched.

            Example:
            ```
            kernel_module(name = "nfc", outs = ["nfc.ko"])
            ```

            The build system copies
            ```
            <legacy modules staging dir>/lib/modules/*/extra/<some subdir>/nfc.ko
            ```
            to
            ```
            <package output dir>/nfc.ko
            ```

            `nfc/nfc.ko` is the label to the file.

          - If `out` contains slashes, its value is used. The file is
            also copied to the top of package output directory.

            For example:
            ```
            kernel_module(name = "nfc", outs = ["foo/nfc.ko"])
            ```

            The build system copies
            ```
            <legacy modules staging dir>/lib/modules/*/extra/foo/nfc.ko
            ```
            to
            ```
            foo/nfc.ko
            ```

            `nfc/foo/nfc.ko` is the label to the file.

            The file is also copied to `<package output dir>/nfc.ko`.

            `nfc/nfc.ko` is the label to the file.

            See `search_and_cp_output.py` for details.
        makefile: `Makefile` for the module. By default, this is `Makefile` in the current package.

            This file determines where `make modules` is executed.

            This is useful when the Makefile is located in a different package or in a subdirectory.
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if kwargs.get("kernel_module_deps"):
        fail("//{}:{}: kernel_module_deps is deprecated. Use deps instead.".format(
            native.package_name(),
            name,
        ))

    kwargs.update(
        # This should be the exact list of arguments of kernel_module.
        # Default arguments of _kernel_module go into _kernel_module_set_defaults.
        name = name,
        srcs = srcs,
        kernel_build = kernel_build,
        deps = deps,
        outs = outs,
        makefile = makefile,
    )
    kwargs = _kernel_module_set_defaults(kwargs)

    main_kwargs = dict(kwargs)
    main_kwargs["name"] = name
    main_kwargs["outs"] = ["{name}/{out}".format(name = name, out = out) for out in main_kwargs["outs"]]
    _kernel_module(**main_kwargs)

    kernel_module_test(
        name = name + "_test",
        modules = [name],
        tags = kwargs.get("tags"),
    )

def _check_kernel_build(kernel_modules, kernel_build, this_label):
    """Check that kernel_modules have the same kernel_build as the given one.

    Args:
        kernel_modules: the attribute of kernel_module dependencies. Should be
          an attribute of a list of labels.
        kernel_build: the attribute of kernel_build. Should be an attribute of
          a label.
        this_label: label of the module being checked.
    """

    for kernel_module in kernel_modules:
        if kernel_module[KernelModuleInfo].kernel_build.label != \
           kernel_build.label:
            fail((
                "{this_label} refers to kernel_build {kernel_build}, but " +
                "depended kernel_module {dep} refers to kernel_build " +
                "{dep_kernel_build}. They must refer to the same kernel_build."
            ).format(
                this_label = this_label,
                kernel_build = kernel_build.label,
                dep = kernel_module.label,
                dep_kernel_build = kernel_module[KernelModuleInfo].kernel_build.label,
            ))

def _check_module_symvers_restore_path(kernel_modules, this_label):
    all_restore_paths = dict()
    for kernel_module in kernel_modules:
        for restore_path in kernel_module[ModuleSymversInfo].restore_paths.to_list():
            if restore_path not in all_restore_paths:
                all_restore_paths[restore_path] = []
            all_restore_paths[restore_path].append(str(kernel_module.label))

    dups = dict()
    for key, values in all_restore_paths.items():
        if len(values) > 1:
            dups[key] = values

    if dups:
        fail("""{this_label}: Conflicting dependencies. Dependencies from a package must either be a list of `ddk_module`s only, or a single `kernel_module`.
{conflicts}
        """.format(
            this_label = this_label,
            conflicts = json.encode_indent(list(dups.values()), indent = "  "),
        ))

def _get_implicit_outs(ctx):
    """Gets the list of implicit output files from makefile targets."""
    implicit_outs = ctx.attr.internal_ddk_makefiles_dir[DdkSubmoduleInfo].outs.to_list()

    implicit_outs_to_srcs = {}
    for implicit_out in implicit_outs:
        if implicit_out.out not in implicit_outs_to_srcs:
            implicit_outs_to_srcs[implicit_out.out] = []
        implicit_outs_to_srcs[implicit_out.out].append(implicit_out.src)

    duplicated_implicit_outs = {}
    for out, srcs in implicit_outs_to_srcs.items():
        if len(srcs) > 1:
            duplicated_implicit_outs[out] = srcs

    if duplicated_implicit_outs:
        fail("{}: Multiple submodules define the same output file: {}".format(
            ctx.label,
            json.encode_indent(duplicated_implicit_outs, indent = "  "),
        ))

    return list(implicit_outs_to_srcs.keys())

def _kernel_module_impl(ctx):
    split_deps = kernel_utils.split_kernel_module_deps(ctx.attr.deps, ctx.label)
    kernel_module_deps = split_deps.kernel_modules
    if ctx.attr.internal_ddk_makefiles_dir:
        kernel_module_deps += ctx.attr.internal_ddk_makefiles_dir[DdkSubmoduleInfo].kernel_module_deps.to_list()

    _check_kernel_build(kernel_module_deps, ctx.attr.kernel_build, ctx.label)
    _check_module_symvers_restore_path(kernel_module_deps, ctx.label)

    # Define where to build the external module (default to the package name)
    ext_mod = ctx.attr.makefile[0].label.package if ctx.attr.makefile else ctx.label.package

    if ctx.files.makefile and ctx.file.internal_ddk_makefiles_dir:
        fail("{}: must not define `makefile` for `ddk_module`")

    inputs = []
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.files.makefile
    inputs += ctx.files.internal_ddk_makefiles_dir
    inputs += [
        ctx.file._search_and_cp_output,
        ctx.file._check_declared_output_list,
    ]
    for kernel_module_dep in kernel_module_deps:
        inputs += kernel_module_dep[KernelEnvInfo].dependencies

    transitive_inputs = [target.files for target in ctx.attr.srcs]
    transitive_inputs.append(ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_scripts)
    if not ctx.attr.internal_exclude_kernel_build_module_srcs:
        transitive_inputs.append(ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_hdrs)

    if ctx.attr.internal_ddk_makefiles_dir:
        transitive_inputs.append(ctx.attr.internal_ddk_makefiles_dir[DdkSubmoduleInfo].srcs)

    modules_staging_dws = dws.make(ctx, "{}/staging".format(ctx.attr.name))
    kernel_uapi_headers_dws = dws.make(ctx, "{}/kernel-uapi-headers.tar.gz_staging".format(ctx.attr.name))
    outdir = modules_staging_dws.directory.dirname

    unstripped_dir = None
    if ctx.attr.kernel_build[KernelBuildExtModuleInfo].collect_unstripped_modules:
        unstripped_dir = ctx.actions.declare_directory("{name}/unstripped".format(name = ctx.label.name))

    output_files = [] + ctx.outputs.outs
    if ctx.attr.internal_ddk_makefiles_dir:
        for out in _get_implicit_outs(ctx):
            output_files.append(ctx.actions.declare_file("{}/{}".format(ctx.label.name, out)))

    # Original `outs` attribute of `kernel_module` macro.
    original_outs = []

    # apply basename to all of original_outs
    original_outs_base = []

    for out in output_files:
        # outdir includes target name at the end already. So short_name is the original
        # token in `outs` of `kernel_module` macro.
        # e.g. kernel_module(name = "foo", outs = ["bar"])
        #   => _kernel_module(name = "foo", outs = ["foo/bar"])
        #   => outdir = ".../foo"
        #      output_files = [File(".../foo/bar")]
        #   => short_name = "bar"
        short_name = out.path[len(outdir) + 1:]
        original_outs.append(short_name)
        original_outs_base.append(out.basename)

    all_module_names_file = ctx.actions.declare_file("{}/all_module_names.txt".format(ctx.label.name))
    ctx.actions.write(
        output = all_module_names_file,
        content = "\n".join(original_outs) + "\n",
    )
    inputs.append(all_module_names_file)

    module_symvers = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, ctx.attr.internal_module_symvers_name))
    check_no_remaining = ctx.actions.declare_file("{name}/{name}.check_no_remaining".format(name = ctx.attr.name))
    command_outputs = [
        module_symvers,
        check_no_remaining,
    ]
    command_outputs += dws.files(modules_staging_dws)
    command_outputs += dws.files(kernel_uapi_headers_dws)
    if unstripped_dir:
        command_outputs.append(unstripped_dir)

    command = ""
    command += ctx.attr.kernel_build[KernelEnvInfo].setup
    command += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_setup
    command += """
             # create dirs for modules
               mkdir -p {kernel_uapi_headers_dir}/usr
    """.format(
        kernel_uapi_headers_dir = kernel_uapi_headers_dws.directory.path,
    )
    for kernel_module_dep in kernel_module_deps:
        command += kernel_module_dep[KernelEnvInfo].setup

    grab_unstripped_cmd = ""
    if unstripped_dir:
        grab_unstripped_cmd = """
            mkdir -p {unstripped_dir}
            {search_and_cp_output} --srcdir ${{OUT_DIR}}/${{ext_mod_rel}} --dstdir {unstripped_dir} {outs}
        """.format(
            search_and_cp_output = ctx.file._search_and_cp_output.path,
            unstripped_dir = unstripped_dir.path,
            # Use basenames to flatten the unstripped directory, even though outs may contain items with slash.
            outs = " ".join(original_outs_base),
        )

    drop_modules_order_cmd = ""
    if ctx.attr.internal_drop_modules_order:
        drop_modules_order_cmd = """
            # Delete unnecessary modules.order.*, which will be re-generated by depmod.
              rm -f {modules_staging_dir}/lib/modules/*/extra/{ext_mod}/modules.order.*
        """.format(
            ext_mod = ext_mod,
            modules_staging_dir = modules_staging_dws.directory.path,
        )

    grab_cmd_step = get_grab_cmd_step(ctx, "${OUT_DIR}/${ext_mod_rel}")
    inputs += grab_cmd_step.inputs
    command_outputs += grab_cmd_step.outputs

    scmversion_ret = stamp.get_ext_mod_scmversion(ctx, ext_mod)
    inputs += scmversion_ret.deps
    command += scmversion_ret.cmd

    if ctx.file.internal_ddk_makefiles_dir:
        command += """
             # Restore Makefile and Kbuild
               cp -r -l {ddk_makefiles}/* {ext_mod}/
        """.format(
            ddk_makefiles = ctx.file.internal_ddk_makefiles_dir.path,
            ext_mod = ext_mod,
        )

    module_strip_flag = "INSTALL_MOD_STRIP="
    if ctx.attr.kernel_build[KernelBuildExtModuleInfo].strip_modules:
        module_strip_flag += "1"

    modpost_warn = debug.modpost_warn(ctx)
    command += modpost_warn.cmd
    command_outputs += modpost_warn.outputs

    command += """
             # Set variables
               ext_mod_rel=$(rel_path ${{ROOT_DIR}}/{ext_mod} ${{KERNEL_DIR}})

             # Actual kernel module build
               make -C {ext_mod} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} {make_redirect}
             # Install into staging directory
               make -C {ext_mod} ${{TOOL_ARGS}} DEPMOD=true M=${{ext_mod_rel}} \
                   O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}     \
                   INSTALL_MOD_PATH=$(realpath {modules_staging_dir})          \
                   INSTALL_MOD_DIR=extra/{ext_mod}                             \
                   KERNEL_UAPI_HEADERS_DIR=$(realpath {kernel_uapi_headers_dir}) \
                   INSTALL_HDR_PATH=$(realpath {kernel_uapi_headers_dir}/usr)  \
                   {module_strip_flag} modules_install

             # Check if there are remaining *.ko files
               remaining_ko_files=$({check_declared_output_list} \\
                    --declared $(cat {all_module_names_file}) \\
                    --actual $(cd {modules_staging_dir}/lib/modules/*/extra/{ext_mod} && find . -type f -name '*.ko' | sed 's:^[.]/::'))
               if [[ ${{remaining_ko_files}} ]]; then
                 echo "ERROR: The following kernel modules are built but not copied. Add these lines to the outs attribute of {label}:" >&2
                 for ko in ${{remaining_ko_files}}; do
                   echo '    "'"${{ko}}"'",' >&2
                 done
                 echo "Alternatively, install buildozer and execute:" >&2
                 echo "  $ buildozer 'add outs ${{remaining_ko_files}}' {label}" >&2
                 echo "See https://github.com/bazelbuild/buildtools/blob/master/buildozer/README.md for reference" >&2
                 exit 1
               fi
               touch {check_no_remaining}

             # Grab unstripped modules
               {grab_unstripped_cmd}
             # Grab *.cmd
               {grab_cmd_cmd}
             # Move Module.symvers
               mv ${{OUT_DIR}}/${{ext_mod_rel}}/Module.symvers {module_symvers}

               {drop_modules_order_cmd}
               """.format(
        label = ctx.label,
        ext_mod = ext_mod,
        make_redirect = modpost_warn.make_redirect,
        module_symvers = module_symvers.path,
        modules_staging_dir = modules_staging_dws.directory.path,
        outdir = outdir,
        kernel_uapi_headers_dir = kernel_uapi_headers_dws.directory.path,
        module_strip_flag = module_strip_flag,
        check_declared_output_list = ctx.file._check_declared_output_list.path,
        all_module_names_file = all_module_names_file.path,
        grab_unstripped_cmd = grab_unstripped_cmd,
        check_no_remaining = check_no_remaining.path,
        drop_modules_order_cmd = drop_modules_order_cmd,
        grab_cmd_cmd = grab_cmd_step.cmd,
    )

    command += dws.record(modules_staging_dws)
    command += dws.record(kernel_uapi_headers_dws)

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelModule",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = command_outputs,
        command = command,
        progress_message = "Building external kernel module {}".format(ctx.label),
    )

    # Additional outputs because of the value in outs. This is
    # [basename(out) for out in outs] - outs
    additional_declared_outputs = []
    for short_name, out in zip(original_outs, output_files):
        if "/" in short_name:
            additional_declared_outputs.append(ctx.actions.declare_file("{name}/{basename}".format(
                name = ctx.attr.name,
                basename = out.basename,
            )))
        original_outs_base.append(out.basename)
    cp_cmd_outputs = output_files + additional_declared_outputs

    if cp_cmd_outputs:
        command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
             # Copy files into place
               {search_and_cp_output} --srcdir {modules_staging_dir}/lib/modules/*/extra/{ext_mod}/ --dstdir {outdir} {outs}
        """.format(
            search_and_cp_output = ctx.file._search_and_cp_output.path,
            modules_staging_dir = modules_staging_dws.directory.path,
            ext_mod = ext_mod,
            outdir = outdir,
            outs = " ".join(original_outs),
        )
        debug.print_scripts(ctx, command, what = "cp_outputs")
        ctx.actions.run_shell(
            mnemonic = "KernelModuleCpOutputs",
            inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + [
                # We don't need structure_file here because we only care about files in the directory.
                modules_staging_dws.directory,
                ctx.file._search_and_cp_output,
            ],
            outputs = cp_cmd_outputs,
            command = command,
            progress_message = "Copying outputs {}".format(ctx.label),
        )

    setup = """
             # Use a new shell to avoid polluting variables
               (
             # Set variables
               # rel_path requires the existence of ${{ROOT_DIR}}/{ext_mod}, which may not be the case for
               # _kernel_modules_install. Make that.
               mkdir -p ${{ROOT_DIR}}/{ext_mod}
               ext_mod_rel=$(rel_path ${{ROOT_DIR}}/{ext_mod} ${{KERNEL_DIR}})
             # Restore Modules.symvers
               mkdir -p $(dirname ${{OUT_DIR}}/${{ext_mod_rel}}/{internal_module_symvers_name})
               cp {module_symvers} ${{OUT_DIR}}/${{ext_mod_rel}}/{internal_module_symvers_name}
             # New shell ends
               )
    """.format(
        ext_mod = ext_mod,
        module_symvers = module_symvers.path,
        internal_module_symvers_name = ctx.attr.internal_module_symvers_name,
    )

    if ctx.attr.internal_ddk_makefiles_dir:
        ddk_headers_info = ctx.attr.internal_ddk_makefiles_dir[DdkHeadersInfo]
    else:
        ddk_headers_info = DdkHeadersInfo(
            files = depset(),
            includes = depset(),
            linux_includes = depset(),
        )

    # Only declare outputs in the "outs" list. For additional outputs that this rule created,
    # the label is available, but this rule doesn't explicitly return it in the info.
    # Also add check_no_remaining in the list of default outputs so that, when
    # outs is empty, the KernelModule action is still executed, and so
    # is check_declared_output_list.
    return [
        # Sync list of infos with kernel_module_group.
        DefaultInfo(
            files = depset(output_files + [check_no_remaining]),
            # For kernel_module_test
            runfiles = ctx.runfiles(files = output_files),
        ),
        KernelEnvInfo(
            dependencies = [module_symvers],
            setup = setup,
        ),
        KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            modules_staging_dws_depset = depset([modules_staging_dws]),
            kernel_uapi_headers_dws_depset = depset([kernel_uapi_headers_dws]),
            files = depset(output_files),
        ),
        KernelUnstrippedModulesInfo(
            directories = depset([unstripped_dir], order = "postorder"),
        ),
        ModuleSymversInfo(
            # path/to/package/target_name/Module.symvers -> path/to/package/Module.symvers;
            # path/to/package/target_name/target_name_Module.symvers -> path/to/package/target_name_Module.symvers;
            # This is similar to ${{OUT_DIR}}/${{ext_mod_rel}}
            # It is needed to remove the `target_name` because we declare_file({name}/{internal_module_symvers_name}) above.
            restore_paths = depset([paths.join(ctx.label.package, ctx.attr.internal_module_symvers_name)]),
        ),
        ddk_headers_info,
        KernelCmdsInfo(directories = depset([grab_cmd_step.cmd_dir])),
    ]

_kernel_module = rule(
    implementation = _kernel_module_impl,
    doc = """
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "makefile": attr.label_list(
            allow_files = True,
            doc = "Used internally. The makefile for this module.",
        ),
        "internal_ddk_makefiles_dir": attr.label(
            allow_single_file = True,  # A single directory
            doc = "A `makefiles` target that denotes a list of makefiles to restore",
        ),
        "internal_module_symvers_name": attr.string(default = "Module.symvers"),
        "internal_drop_modules_order": attr.bool(),
        "internal_exclude_kernel_build_module_srcs": attr.bool(),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildExtModuleInfo],
        ),
        "deps": attr.label_list(),
        # Not output_list because it is not a list of labels. The list of
        # output labels are inferred from name and outs.
        "outs": attr.output_list(),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_check_declared_output_list": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:check_declared_output_list.py"),
        ),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_preserve_cmd": attr.label(default = "//build/kernel/kleaf/impl:preserve_cmd"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_debug_modpost_warn": attr.label(default = "//build/kernel/kleaf:debug_modpost_warn"),
    },
)

def _kernel_module_set_defaults(kwargs):
    """Set default values for `_kernel_module` that can't be specified in `attr.*(default=...)` in rule()."""
    if kwargs.get("makefile") == None and kwargs.get("internal_ddk_makefiles_dir") == None:
        kwargs["makefile"] = native.glob(["Makefile"])

    if kwargs.get("outs") == None:
        kwargs["outs"] = ["{}.ko".format(kwargs["name"])]

    if kwargs.get("srcs") == None:
        kwargs["srcs"] = native.glob([
            "**/*.c",
            "**/*.h",
            "**/Kbuild",
            "**/Makefile",
        ])

    return kwargs
