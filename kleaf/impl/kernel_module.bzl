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
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    "//build/kernel/kleaf/artifact_tests:kernel_test.bzl",
    "kernel_module_test",
)
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
    "KernelUnstrippedModulesInfo",
)
load(":debug.bzl", "debug")
load(":stamp.bzl", "stamp")

_sibling_names = [
    "notrim",
    "with_vmlinux",
]

def kernel_module(
        name,
        kernel_build,
        outs = None,
        srcs = None,
        kernel_module_deps = None,
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
        kernel_module_deps: A list of other kernel_module dependencies.

          Before building this target, `Modules.symvers` from the targets in
          `kernel_module_deps` are restored, so this target can be built against
          them.
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
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    kwargs.update(
        # This should be the exact list of arguments of kernel_module.
        # Default arguments of _kernel_module go into _kernel_module_set_defaults.
        name = name,
        srcs = srcs,
        kernel_build = kernel_build,
        kernel_module_deps = kernel_module_deps,
        outs = outs,
    )
    kwargs = _kernel_module_set_defaults(kwargs)

    main_kwargs = dict(kwargs)
    main_kwargs["name"] = name
    main_kwargs["outs"] = ["{name}/{out}".format(name = name, out = out) for out in main_kwargs["outs"]]
    _kernel_module(**main_kwargs)

    kernel_module_test(
        name = name + "_test",
        modules = [name],
    )

    # Define external module for sibling kernel_build's.
    # It may be possible to optimize this to alias some of them with the same
    # kernel_build, but we don't have a way to get this information in
    # the load phase right now.
    for sibling_name in _sibling_names:
        sibling_kwargs = dict(kwargs)
        sibling_target_name = name + "_" + sibling_name
        sibling_kwargs["name"] = sibling_target_name
        sibling_kwargs["outs"] = ["{sibling_target_name}/{out}".format(sibling_target_name = sibling_target_name, out = out) for out in outs]

        # This assumes the target is a kernel_build_abi with define_abi_targets
        # etc., which may not be the case. See below for adding "manual" tag.
        # TODO(b/231647455): clean up dependencies on implementation details.
        sibling_kwargs["kernel_build"] = sibling_kwargs["kernel_build"] + "_" + sibling_name
        if sibling_kwargs.get("kernel_module_deps") != None:
            sibling_kwargs["kernel_module_deps"] = [dep + "_" + sibling_name for dep in sibling_kwargs["kernel_module_deps"]]

        # We don't know if {kernel_build}_{sibling_name} exists or not, so
        # add "manual" tag to prevent it from being built by default.
        sibling_kwargs["tags"] = sibling_kwargs.get("tags", []) + ["manual"]

        _kernel_module(**sibling_kwargs)

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

def _kernel_module_impl(ctx):
    _check_kernel_build(ctx.attr.kernel_module_deps, ctx.attr.kernel_build, ctx.label)

    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.attr.kernel_build[KernelBuildExtModuleInfo].module_srcs
    inputs += ctx.files.makefile
    inputs += [
        ctx.file._search_and_cp_output,
        ctx.file._check_declared_output_list,
    ]
    for kernel_module_dep in ctx.attr.kernel_module_deps:
        inputs += kernel_module_dep[KernelEnvInfo].dependencies

    modules_staging_dws = dws.make(ctx, "{}/staging".format(ctx.attr.name))
    kernel_uapi_headers_dws = dws.make(ctx, "{}/kernel-uapi-headers.tar.gz_staging".format(ctx.attr.name))
    outdir = modules_staging_dws.directory.dirname

    unstripped_dir = None
    if ctx.attr.kernel_build[KernelBuildExtModuleInfo].collect_unstripped_modules:
        unstripped_dir = ctx.actions.declare_directory("{name}/unstripped".format(name = ctx.label.name))

    # Original `outs` attribute of `kernel_module` macro.
    original_outs = []

    # apply basename to all of original_outs
    original_outs_base = []

    for out in ctx.outputs.outs:
        # outdir includes target name at the end already. So short_name is the original
        # token in `outs` of `kernel_module` macro.
        # e.g. kernel_module(name = "foo", outs = ["bar"])
        #   => _kernel_module(name = "foo", outs = ["foo/bar"])
        #   => outdir = ".../foo"
        #      ctx.outputs.outs = [File(".../foo/bar")]
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

    module_symvers = ctx.actions.declare_file("{}/Module.symvers".format(ctx.attr.name))
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
    for kernel_module_dep in ctx.attr.kernel_module_deps:
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

    scmversion_ret = stamp.get_ext_mod_scmversion(ctx)
    inputs += scmversion_ret.deps
    command += scmversion_ret.cmd

    command += """
             # Set variables
               if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
                 module_strip_flag="INSTALL_MOD_STRIP=1"
               fi
               ext_mod_rel=$(rel_path ${{ROOT_DIR}}/{ext_mod} ${{KERNEL_DIR}})

             # Actual kernel module build
               make -C {ext_mod} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}
             # Install into staging directory
               make -C {ext_mod} ${{TOOL_ARGS}} DEPMOD=true M=${{ext_mod_rel}} \
                   O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}     \
                   INSTALL_MOD_PATH=$(realpath {modules_staging_dir})          \
                   INSTALL_MOD_DIR=extra/{ext_mod}                             \
                   KERNEL_UAPI_HEADERS_DIR=$(realpath {kernel_uapi_headers_dir}) \
                   INSTALL_HDR_PATH=$(realpath {kernel_uapi_headers_dir}/usr)  \
                   ${{module_strip_flag}} modules_install

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
             # Move Module.symvers
               mv ${{OUT_DIR}}/${{ext_mod_rel}}/Module.symvers {module_symvers}
               """.format(
        label = ctx.label,
        ext_mod = ctx.attr.ext_mod,
        module_symvers = module_symvers.path,
        modules_staging_dir = modules_staging_dws.directory.path,
        outdir = outdir,
        kernel_uapi_headers_dir = kernel_uapi_headers_dws.directory.path,
        check_declared_output_list = ctx.file._check_declared_output_list.path,
        all_module_names_file = all_module_names_file.path,
        grab_unstripped_cmd = grab_unstripped_cmd,
        check_no_remaining = check_no_remaining.path,
    )

    command += dws.record(modules_staging_dws)
    command += dws.record(kernel_uapi_headers_dws)

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelModule",
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        progress_message = "Building external kernel module {}".format(ctx.label),
    )

    # Additional outputs because of the value in outs. This is
    # [basename(out) for out in outs] - outs
    additional_declared_outputs = []
    for short_name, out in zip(original_outs, ctx.outputs.outs):
        if "/" in short_name:
            additional_declared_outputs.append(ctx.actions.declare_file("{name}/{basename}".format(
                name = ctx.attr.name,
                basename = out.basename,
            )))
        original_outs_base.append(out.basename)
    cp_cmd_outputs = ctx.outputs.outs + additional_declared_outputs

    if cp_cmd_outputs:
        command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
             # Copy files into place
               {search_and_cp_output} --srcdir {modules_staging_dir}/lib/modules/*/extra/{ext_mod}/ --dstdir {outdir} {outs}
        """.format(
            search_and_cp_output = ctx.file._search_and_cp_output.path,
            modules_staging_dir = modules_staging_dws.directory.path,
            ext_mod = ctx.attr.ext_mod,
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
               mkdir -p ${{OUT_DIR}}/${{ext_mod_rel}}
               cp {module_symvers} ${{OUT_DIR}}/${{ext_mod_rel}}/Module.symvers
             # New shell ends
               )
    """.format(
        ext_mod = ctx.attr.ext_mod,
        module_symvers = module_symvers.path,
    )

    # Only declare outputs in the "outs" list. For additional outputs that this rule created,
    # the label is available, but this rule doesn't explicitly return it in the info.
    # Also add check_no_remaining in the list of default outputs so that, when
    # outs is empty, the KernelModule action is still executed, and so
    # is check_declared_output_list.
    return [
        DefaultInfo(
            files = depset(ctx.outputs.outs + [check_no_remaining]),
            # For kernel_module_test
            runfiles = ctx.runfiles(files = ctx.outputs.outs),
        ),
        KernelEnvInfo(
            dependencies = [module_symvers],
            setup = setup,
        ),
        KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            modules_staging_dws = modules_staging_dws,
            kernel_uapi_headers_dws = kernel_uapi_headers_dws,
            files = ctx.outputs.outs,
        ),
        KernelUnstrippedModulesInfo(
            directory = unstripped_dir,
        ),
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
        ),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildExtModuleInfo],
        ),
        "kernel_module_deps": attr.label_list(
            providers = [KernelEnvInfo, KernelModuleInfo],
        ),
        "ext_mod": attr.string(mandatory = True),
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
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_module_set_defaults(kwargs):
    """
    Set default values for `_kernel_module` that can't be specified in
    `attr.*(default=...)` in rule().
    """
    if kwargs.get("makefile") == None:
        kwargs["makefile"] = native.glob(["Makefile"])

    if kwargs.get("ext_mod") == None:
        kwargs["ext_mod"] = native.package_name()

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
