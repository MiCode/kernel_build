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
    "KernelEnvInfo",
    "KernelModuleInfo",
    "KernelUnstrippedModulesInfo",
)
load("//build/kernel/kleaf/impl:debug.bzl", "debug")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", _kernel_images = "kernel_images")
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
load(":hermetic_tools.bzl", "HermeticToolsInfo")
load(":update_source_file.bzl", "update_source_file")
load(
    "//build/kernel/kleaf/impl:utils.bzl",
    "find_file",
    "find_files",
    "kernel_utils",
    "utils",
)

# Re-exports
kernel_build = _kernel_build_macro
kernel_build_config = _kernel_build_config
kernel_compile_commands = _kernel_compile_commands
kernel_dtstree = _kernel_dtstree
kernel_filegroup = _kernel_filegroup
kernel_images = _kernel_images
kernel_kythe = _kernel_kythe
kernel_module = _kernel_module_macro
kernel_modules_install = _kernel_modules_install
kernel_unstripped_modules_archive = _kernel_unstripped_modules_archive
merged_kernel_uapi_headers = _merged_kernel_uapi_headers

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
