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

"""Providers that are provided by multiple rules in different extensions."""

visibility("//build/kernel/kleaf/...")

WrittenDepsetInfo = provider(
    doc = "Describes a depset written to a file",
    fields = {
        "depset_file": "The text file, where each line is a path to an item in the depset",
        "depset_short_file": "Same as depset_file, but each line is the short_path to an item in the depset.",
        "depset": "A depset containing both text files and the original depset",
        "original_depset": "The original depset",
    },
)

StepInfo = provider(
    "Describes a step, part of a run_shell",
    fields = {
        "inputs": "depset of files",
        "outputs": "list of files",
        "tools": """list of any of the following

            - File
            - depset[File]
            - FilesToRunProvider
        """,
        "cmd": "command line",
    },
)

DefconfigInfo = provider(
    "Describes the value of kernel_build.defconfig. At most one of the fields is not None.",
    fields = {
        "file": "a single defconfig file",
        "make_target": "a phony make target",
    },
)

DefconfigFragmentsInfo = provider(
    doc = "Describes kernel_build.pre_defconfig_fragments and kernel_build.post_defconfig_fragments.",
    fields = {
        "pre_defconfig_fragments": """A [depset](https://bazel.build/extending/depsets) of [File](https://bazel.build/rules/lib/File]s
            describing kernel_build.pre_defconfig_fragments""",
        "post_defconfig_fragments": """A [depset](https://bazel.build/extending/depsets) of [File](https://bazel.build/rules/lib/File]s
            describing kernel_build.post_defconfig_fragments""",
        "check_pre_defconfig_fragments": """resolved value of kernel_build.check_defconfig for defconfig and pre_defconfig_fragments.
            This may be None that represents DefconfigFragmentsInfo of the base_kernel if there is no base_kernel.""",
        "check_post_defconfig_fragments": """resolved value of kernel_build.check_defconfig for post_defconfig_fragments.
            This may be None that represents DefconfigFragmentsInfo of the base_kernel if there is no base_kernel.""",
    },
)

KernelCmdsInfo = provider(
    doc = """Provides a directory of `.cmd` files.""",
    fields = {
        "srcs": """A [depset](https://bazel.build/extending/depsets) of sources to build
            the original target.""",
        "directories": """A [depset](https://bazel.build/extending/depsets) of directories
                          containing the `.cmd` files""",
    },
)

KernelBuildConfigInfo = provider(
    doc = """Provides build config dependencies""",
    fields = {
        "deps": "additional dependencies",
    },
)

KernelEnvInfo = provider(
    doc = """Describe a generic environment setup with some dependencies and a setup script.""",
    fields = {
        "inputs": """A [depset](https://bazel.build/extending/depsets) of inputs associated with
            the target platform.""",
        "tools": """A [depset](https://bazel.build/extending/depsets) of tools associated with
            the execution platform.""",
        "setup": "setup script to initialize the environment",
        "toolchains": "See KernelEnvToolchainsInfo",
    },
)

KernelEnvMakeGoalsInfo = provider(
    doc = "Describe the targets for the current build.",
    fields = {
        "make_goals": "A list of strings defining targets for the kernel build.",
    },
)

KernelPlatformToolchainInfo = provider(
    doc = """Provides toolchain information of a single platform (target or execution).""",
    fields = {
        "compiler_version": "A string representing compiler version",
        "toolchain_id": "A string representing toolchain ID for debugging purposes",
        "all_files": "A [depset](https://bazel.build/extending/depsets) of all files of the toolchain",
        "cflags": "flags for C compilation",
        "ldflags": "flags for C linking",
        "ldexpr": "Extra shell expression appended to ldflags",
        "bin_path": "`PATH` relative to execroot.",
        "runpaths": "RUNPATHs. Note this is already in ldexpr.",
        "sysroot": "sysroot",
        "libc": "The libc, one of musl or glibc.",
    },
)

KernelToolchainInfo = provider(
    doc = "Provides a single toolchain version.",
    fields = {
        "toolchain_version": "The toolchain version",
    },
)

KernelEnvToolchainsInfo = provider(
    doc = """Provides resolved toolchains information to `kernel_env`.""",
    fields = {
        "compiler_version": "A string representing compiler version",
        "all_files": "A [depset](https://bazel.build/extending/depsets) of all files of all toolchains",
        "target_arch": "arch of target platform",
        "setup_env_var_cmd": "A command to set up simple environment variables",
        "kernel_setup_env_var_cmd": "A command to set up environment variables for kernel build",
        "host_runpaths": "RUNPATHs for host progs.",
        "host_sysroot": "sysroot for host progs",
    },
)

KernelSerializedEnvInfo = provider(
    doc = """Like `KernelEnvInfo` but also restores artifacts.

It is expected to be created like the following:

```
setup_script = ctx.actions.declare_file("{}/setup.sh".format(ctx.attr.name))
ctx.actions.write(
    output = setup_script,
    content = \"""
        {pre_setup}
        {eval_restore_out_dir_cmd}
    \""".format(
        pre_setup = pre_setup, # sets up hermetic toolchain and environment variables
        eval_restore_out_dir_cmd = kernel_utils.eval_restore_out_dir_cmd(),
    )
)

serialized_env_info = KernelSerializedEnvInfo(
    setup_script = setup_script,
    tools = ...,
    inputs = depset([setup_script], ...),
)
```

It is expected to use these infos in the following way:

```
command = \"""
    KLEAF_RESTORE_OUT_DIR_CMD="{restore_out_dir_cmd}"
    . {setup_script}
\""".format(
    restore_out_dir_cmd = cache_dir_step.cmd, # or utils.get_check_sandbox_cmd(),
    setup_script = ctx.attr.dep[KernelSerializedEnvInfo].setup_script.path,
)
```
""",
    fields = {
        "setup_script": "A file containing the setup script.",
        "inputs": """A [depset](https://bazel.build/extending/depsets) containing inputs used
                   by `setup_script`. Note that dependencies of `restore_out_dir_cmd` is not
                   included. `inputs` are compiled against the target platform.

                   For convenience for the caller / user of the info, `inputs` should include
                   `setup_script`.
                   """,
        "tools": """A [depset](https://bazel.build/extending/depsets) containing tools used
                   by `setup_script`. Note that dependencies of `restore_out_dir_cmd` is not
                   included. `tools` are compiled against the execution platform.""",
    },
)

KernelBuildOriginalEnvInfo = provider(
    doc = """For `kernel_build` to expose `KernelEnvInfo` from `kernel_env`.""",
    fields = {
        "env_info": "`KernelEnvInfo` from `kernel_env`",
    },
)

KernelEnvAttrInfo = provider(
    doc = "Provide attributes of `kernel_env`.",
    fields = {
        "kbuild_symtypes": "`KBUILD_SYMTYPES`, after resolving `--kbuild_symtypes` and the static value.",
        "progress_message_note": """A note in the progress message that differentiates multiple
            instances of the same action due to different configs.""",
        "common_config_tags": "A File denoting the configurations that are useful to isolate `OUT_DIR`.",
    },
)

KernelBuildInfo = provider(
    doc = """Generic information provided by a `kernel_build`.""",
    fields = {
        "out_dir_kernel_headers_tar": "Archive containing headers in `OUT_DIR`",
        "outs": "A list of File object corresponding to the `outs` attribute (excluding `module_outs`, `implicit_outs` and `internal_outs`)",
        "base_kernel_files": """A [depset](https://bazel.build/extending/depsets) containing
            [Default outputs](https://docs.bazel.build/versions/main/skylark/rules.html#default-outputs)
            of the rule specified by `base_kernel`""",
        "kernel_release": "The file `kernel.release`.",
    },
)

CompileCommandsSingleInfo = provider(
    doc = """Provides info necessary to build compile_commands.json for a single target.""",
    fields = {
        "compile_commands_with_vars": "A file that can be transformed into `compile_commands.json`.",
        "compile_commands_common_out_dir": "A subset of `$COMMON_OUT_DIR` for `compile_commands.json`.",
    },
)

CompileCommandsInfo = provider(
    doc = """Provides info necessary to build compile_commands.json for multiple targets.""",
    fields = {
        "infos": """A [depset](https://bazel.build/extending/depsets) of CompileCommandsSingleInfo""",
    },
)

KernelBuildExtModuleInfo = provider(
    doc = "A provider that specifies the expectations of a `_kernel_module` (an external module) or a `kernel_modules_install` from its `kernel_build` attribute.",
    fields = {
        "modules_staging_archive": "Archive containing staging kernel modules. " +
                                   "Does not contain the lib/modules/* suffix.",
        "module_hdrs": "A [depset](https://bazel.build/extending/depsets) containing headers for this `kernel_build` for building external modules",
        "ddk_config_env": "`KernelSerializedEnvInfo` for configuring DDK modules (excl. legacy `kernel_module`).",
        "ddk_module_defconfig_fragments": "A [depset](https://bazel.build/extending/depsets) containing additional defconfig fragments for DDK modules.",
        "mod_min_env": "`KernelSerializedEnvInfo` for building external modules, including minimal needed `kernel_build` outputs.",
        "mod_full_env": "`KernelSerializedEnvInfo` for building external modules, including all `kernel_build` outputs.",
        "modinst_env": "`KernelSerializedEnvInfo` for running `modules_install`.",
        "collect_unstripped_modules": "Whether an external [`kernel_module`](kernel.md#kernel_module) building against this [`kernel_build`](kernel.md#kernel_build) should provide unstripped ones for debugging.",
        "strip_modules": "Whether debug information for distributed modules is stripped",
    },
)

KernelBuildUapiInfo = provider(
    doc = "A provider that specifies the expecation of a `merged_uapi_headers` rule from its `kernel_build` attribute.",
    fields = {
        "kernel_uapi_headers": """A [depset](https://bazel.build/extending/depsets) containing
            kernel UAPI headers archive.

            Order matters; earlier elements in the traverse order has higher priority. Hence,
            this depset must have `order` argument specified.
            """,
    },
)

KernelBuildAbiInfo = provider(
    doc = "A provider that specifies ABI-related information of a [`kernel_build`](kernel.md#kernel_build).",
    fields = {
        "trim_nonlisted_kmi": "Value of `trim_nonlisted_kmi` in [`kernel_build()`](kernel.md#kernel_build).",
        "combined_abi_symbollist": "The **combined** `abi_symbollist` file from the `_kmi_symbol_list` rule, consist of the source `kmi_symbol_list` and `additional_kmi_symbol_lists`.",
        "modules_staging_archive": "Archive containing staging kernel modules. ",
        "base_modules_staging_archive": "Archive containing staging kernel modules of the base kernel",
        "src_kmi_symbol_list": """Source file for `kmi_symbol_list` that points to the symbol list
                                  to be updated by `--update_symbol_list`""",
        "kmi_strict_mode_out": "A [`File`](https://bazel.build/rules/lib/File) to force kmi_strict_mode check.",
    },
)

KernelBuildInTreeModulesInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](kernel.md#kernel_build) on its
[`base_kernel`](kernel.md#kernel_build-base_kernel) for the list of in-tree modules in the `base_kernel`.""",
    fields = {
        "all_module_names": """`[kernel_build.module_outs]`(kernel.md#kernel_build-module_outs)
            and `[kernel_build.module_implicit_outs]`(kernel.md#kernel_build-module_implicit_outs).
        """,
    },
)

KernelBuildMixedTreeInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](kernel.md#kernel_build) on its
[`base_kernel`](kernel.md#kernel_build-base_kernel) for constructing `KBUILD_MIXED_TREE`.""",
    fields = {
        "files": """A [depset](https://bazel.build/extending/depsets) containing the list of
files required to build `KBUILD_MIXED_TREE` for the device kernel.""",
    },
)

KernelBuildGeneratedHeadersForModuleInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](kernel.md#kernel_build) on its
[`base_kernel`](kernel.md#kernel_build-base_kernel) for providing generated headers for external modules.""",
    fields = {
        "archive": """An archive that contains list of generated headers to be extracted to
            $OUT_DIR prior to module builds. May be None.""",
    },
)

KernelBuildUnameInfo = provider(
    doc = """A provider providing `kernel.release` of a `kernel_build`.""",
    fields = {
        "kernel_release": "The file `kernel.release`.",
    },
)

KernelBuildFilegroupDeclInfo = provider(
    doc = """A provider providing information of a `kernel_build` to generate `kernel_filegroup`
        declaration.""",
    fields = {
        "filegroup_srcs": """[depset](https://bazel.build/extending/depsets) of
            [`File`](https://bazel.build/rules/lib/File)s that the
            `kernel_filegroup` should return as default outputs.""",
        "all_module_names": """
            `[kernel_build.module_outs]`(kernel.md#kernel_build-module_outs) and
            `[kernel_build.module_implicit_outs]`(kernel.md#kernel_build-module_implicit_outs).""",
        "modules_staging_archive": "Archive containing staging kernel modules. ",
        "toolchain_version": "The toolchain version",
        "kernel_release": "The file `kernel.release`.",
        "modules_prepare_archive": """Archive containing the file built by
            [`modules_prepare`](#modules_prepare)""",
        "collect_unstripped_modules": "[`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules)",
        "strip_modules": "[`kernel_build.strip_modules`](#kernel_build-strip_modules)",
        "ddk_module_defconfig_fragments": """[depset](https://bazel.build/extending/depsets) of
            [`File`](https://bazel.build/rules/lib/File)s containing
            [`kernel_build.ddk_module_defconfig_fragments`](#kernel_build-ddk_module_defconfig_fragments).""",
        "kernel_uapi_headers": """[depset](https://bazel.build/extending/depsets) of
            [`File`](https://bazel.build/rules/lib/File)s containing
            archives of UAPI headers.""",
        "arch": "[`kernel_build.arch`](#kernel_build-arch)",
        "env_setup_script": """A [depset](https://bazel.build/extending/depsets) of
            [`File`](https://bazel.build/rules/lib/File)s to replay the `kernel_config` environment.

            See [`KernelConfigInfo`](#KernelConfigInfo).""",
        "config_out_dir": """The output directory of `kernel_config`.""",
        "outs": """[depset](https://bazel.build/extending/depsets) of `kernel_build`'s
            `outs`.""",
        "internal_outs": """[depset](https://bazel.build/extending/depsets) of `kernel_build`'s
            `internal_outs`.""",
        "ruledir": """`ruledir` from `kernel_build` that signifies the root for
            `outs`, `implcit_outs`, `internal_outs`.""",
        "module_env_archive": "Archive preparing an environment to build modules. May be `None`.",
        "has_base_kernel": "Whether the original `kernel_build()` has a not-None `base_kernel`.",
        "copy_module_symvers_outputs": "The output `<name>_Module.symvers` file.",
        "generated_headers_for_module_archive": """An archive that contains list of generated headers to be extracted to
            $OUT_DIR prior to module builds. May be None.""",
        "defconfig_info": "DefconfigInfo",
        "defconfig_fragments_info": "DefconfigFragmentsInfo",
    },
)

GcovInfo = provider(
    doc = """A provider providing information about --gcov.""",
    fields = {
        "gcno_mapping": "`gcno_mapping.json`",
        "gcno_dir": """A [`File`](https://bazel.build/rules/lib/File) directory;
        With the generated gcno files.
        """,
    },
)

KernelUnstrippedModulesInfo = provider(
    doc = "A provider that provides unstripped modules",
    fields = {
        "directories": """A [depset](https://bazel.build/extending/depsets) of
[`File`](https://bazel.build/rules/lib/File)s, where
each item points to a directory containing unstripped modules.

Order matters; earlier elements in the traverse order has higher priority. Hence,
this depset must have `order` argument specified.

For [`kernel_build()`](kernel.md#kernel_build), this is a directory containing unstripped in-tree modules.
- This is `None` if and only if `collect_unstripped_modules = False`
- Never `None` if and only if `collect_unstripped_modules = True`
- An empty directory if and only if `collect_unstripped_modules = True` and `module_outs` is empty

For an external [`kernel_module()`](kernel.md#kernel_module), this is a directory containing unstripped external modules.
- This is `None` if and only if the `kernel_build` argument has `collect_unstripped_modules = False`
- Never `None` if and only if the `kernel_build` argument has `collect_unstripped_modules = True`
""",
    },
)

KernelModuleKernelBuildInfo = provider(
    doc = "Information about the `kernel_build` that an external module builds upon.",
    fields = {
        "label": "Label of the `kernel_build` target",
        "ext_module_info": "`KernelBuildExtModuleInfo`",
        "serialized_env_info": "`KernelSerializedEnvInfo`",
        "images_info": "`KernelImagesInfo`",
    },
)

KernelModuleInfo = provider(
    doc = "A provider that provides installed external modules.",
    fields = {
        "kernel_build_infos": """`KernelModuleKernelBuildInfo` containing info about
            the `kernel_build` attribute of this module""",

        # TODO(b/256688440): Avoid depset[directory_with_structure] to_list
        "modules_staging_dws_depset": """A [depset](https://bazel.build/extending/depsets) of
            `directory_with_structure` containing staging kernel modules.
            Contains the lib/modules/* suffix.""",
        "kernel_uapi_headers_dws_depset": """A [depset](https://bazel.build/extending/depsets) of
            `directory_with_structure` containing UAPI headers to use the module.""",
        "files": "A [depset](https://bazel.build/extending/depsets) of output `*.ko` files.",
        "packages": """For `kernel_module` / `ddk_module`s, a
            [depset](https://bazel.build/extending/depsets) containing package name of
            the target.

            For other rules that contains multiple `kernel_module`s, a [depset] containing package
            names of all external modules in an unspecified order.""",
        "label": "Label to the `kernel_module` target.",
        "modules_order": """A [depset](https://bazel.build/extending/depsets) of `modules.order`
            files from ddk_module's, kernel_module, etc.
            It uses [`postorder`](https://bazel.build/rules/lib/builtins/depset) ordering (dependencies
            first).""",
    },
)

KernelModuleSetupInfo = provider(
    doc = """Like `KernelEnvInfo` but the setup script is a fragment.

    The setup script requires some pre-setup environment before running it.
    """,
    fields = {
        "inputs": """A [depset](https://bazel.build/extending/depsets) of inputs associated with
            the target platform.""",
        "setup": "setup script fragment to initialize the environment",
    },
)

KernelModuleDepInfo = provider(
    doc = "Info that a `kernel_module` expects on a `kernel_module` dependency.",
    fields = {
        "label": "Label of the target where the infos are from.",
        "kernel_module_setup_info": "`KernelModuleSetupInfo`",
        "module_symvers_info": "`ModuleSymversInfo`",
        "kernel_module_info": "`KernelModuleInfo`",
    },
)

ModuleSymversInfo = provider(
    doc = """A provider that provides `Module.symvers` for `modpost`.

    This is  used for **external modules only** for correctly setting up these files.
    """,
    fields = {
        "restore_paths": """A [depset](https://bazel.build/extending/depsets) of
            paths relative to `COMMON_OUT_DIR` where the `Module.symvers` files will be
            restored to by `KernelModuleSetupInfo`.""",
    },
)

ModuleSymversFileInfo = provider(
    doc = "A provider that provides generated `Module.symvers`",
    fields = {
        "module_symvers": """A [depset](https://bazel.build/extending/depsets) of
            [`File`](https://bazel.build/rules/lib/File)s with generated
            Module.symvers file.""",
    },
)

KernelImagesInfo = provider(
    doc = "A provider that represents the expectation of [`kernel_images`](kernel.md#kernel_images) to [`kernel_build`](kernel.md#kernel_build)",
    fields = {
        "base_kernel_label": "Label of the `base_kernel` target, if exists",
        "outs": "A list of File object corresponding to the `outs` attribute (excluding `module_outs`, `implicit_outs` and `internal_outs`)",
        "base_kernel_files": """A [depset](https://bazel.build/extending/depsets) containing
            [Default outputs](https://docs.bazel.build/versions/main/skylark/rules.html#default-outputs)
            of the rule specified by `base_kernel`""",
    },
)

DdkSubmoduleInfo = provider(
    doc = "A provider that describes information about a DDK submodule or module.",
    fields = {
        "outs": """A [depset](https://bazel.build/extending/depsets) containing a struct with
            these keys:

            - `out` is the name of an output file
            - `src` is a label containing the label of the target declaring the output
             file.

            For `ddk_submodule` and regular `ddk_module`, this contains a single struct.
            For the top-level `ddk_module` with submodules, this contains all structs from its
            submodules.""",
        "srcs": """A [depset](https://bazel.build/extending/depsets) of source files to build the
            submodule.""",
        "out": """A single `out` of this `ddk_submodule` or regular `ddk_module`. None for the
            top-level `ddk_module` with submodules""",
        "kernel_module_deps": """A [depset](https://bazel.build/extending/depsets) of
            `KernelModuleDepInfo` of dependent targets of this submodules that are
            kernel_module's.""",
        "linux_includes_include_infos": """
            For `ddk_submodule`, this is set to let the top-level `ddk_module` properly
            generates the `LINUXINCLUDE` in the Kbuild file. This contains a
            [depset](https://bazel.build/extending/depsets) of `DdkIncludeInfo` constructed from
            deps, hdrs, texture_hdrs, kernel_build, etc, to build the top-level `ddk_module`.

            Only `linux_includes` in this field should be read; hence the name. `includes` are set
            in a per-submodule basis and handled within the implementation of `ddk_submodule`. Files
            to build the submodule are sent to the top-level `ddk_module` via `srcs`.
        """,
    },
)

DdkConditionalFilegroupInfo = provider(
    "Provides attributes for [`ddk_conditional_filegroup`](#ddk_conditional_filegroup)",
    fields = {
        "config": "`ddk_conditional_filegroup.config`",
        "value": """bool or str. `ddk_conditional_filegroup.value`

This may be a special value `True` when it is set to `True` in `ddk_module`.
        """,
    },
)

DdkConfigInfo = provider(
    doc = "Describes a pair of kconfig/defconfig depsets.",
    fields = {
        "kconfig": """A [depset](https://bazel.build/extending/depsets) containing the Kconfig file
            of this and its dependencies. Uses `postorder` ordering (dependencies first).""",
        "kconfig_written": "WrittenDepsetInfo representing kconfig",
        "defconfig": """A [depset](https://bazel.build/extending/depsets) containing the Kconfig
            file of this and its dependencies. Uses `postorder` ordering (dependencies first).""",
        "defconfig_written": "WrittenDepsetInfo representing defconfig",
        "kernel_build_ddk_config_env": """
            Optional `ddk_config_env` from `kernel_build`.
            This should be None if the rule doesn't have a reference to the `kernel_build`,
            and not None otherwise.

            This environment itself is not used in the subrule, but it is kept as a reference
            to ensure the `kernel_build` of this target and `deps` are consistent.
        """,
    },
)

DdkConfigOutputsInfo = provider(
    doc = "Describes output of a `ddk_config` target.",
    fields = {
        "out_dir": "Output directory. None if using OUT_DIR from kernel_build directly.",
        "kconfig_ext": "The directory for KCONFIG_EXT. None if using KCONFIG_EXT_PREFIX from kernel_build directly.",
    },
)

DdkHeadersInfo = provider(
    "Information for a target that provides DDK headers to a dependent target.",
    fields = {
        "include_infos": """A [depset](https://bazel.build/rules/lib/depset) of DdkIncludeInfo

            The direct list contains DdkIncludeInfos for the current target.

            The transitive list contains DdkHeadersInfo.includes from dependencies.

            Depset order must be `DDK_INCLUDE_INFO_ORDER`.
        """,
        "files": "A [depset](https://bazel.build/rules/lib/depset) of header files of this target and dependencies",
    },
)

DdkIncludeInfo = provider(
    """Describes include info of current target, excluding dependencies.

    This info represents a list of include paths relative to execroot. It is
    interpreted as follows:

    ```
    [prefix + include for include in includes]
    ```

    If there are generated files in `direct_files`, the list further expands to:

    ```
    [root + prefix + include for include in includes for root in
        [file.root for file in <generated .h files in direct_files>]]
    ```
    """,
    fields = {
        "prefix": """When prepended to an item in `includes` or `linux_includes`,
            the item becomes the path below execroot.""",
        "direct_files": "depset of direct file dependencies of this target.",
        "includes": "A list of `includes` attribute of this target. Not prefixed.",
        "linux_includes": "Like `includes` but added to `LINUXINCLUDE`. Not prefixed.",
    },
)

DdkLibraryInfo = provider(
    """Describes info from a ddk_library""",
    fields = {
        "files": "A depset of .o_shipped/.o.cmd_shipped files",
    },
)

ImagesInfo = provider(
    doc = "Provider from individual *_image rule to [`kernel_images`](kernel.md#kernel_images) rule",
    fields = {
        "files_dict": """A dictionary, where keys are keys in
            [OutputGroupInfo](https://bazel.build/rules/lib/providers/OutputGroupInfo)
            for `kernel_images`,
            and values are [depsets](https://bazel.build/extending/depsets).
        """,
    },
)

KernelConfigInfo = provider(
    doc = "For `kernel_config` to provide files to replay the environment",
    fields = {
        "env_setup_script": "script from `kernel_env`",
    },
)

DtstreeInfo = provider(
    doc = "DTS tree info",
    fields = {
        "srcs": "depset of DTS tree sources",
        "makefile": "DTS tree makefile",
    },
)
