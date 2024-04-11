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
        "run_env": """Optional `KernelEnvInfo` to initialize the environment for `bazel run`.

For `kernel_env`, the script only provides a bare-minimum environment after `source build.config`,
without actually modifying any variables suitable for a proper kernel build.
""",
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
        "bin_path": "`PATH` relative to execroot.",
    },
)

KernelToolchainInfo = provider(
    doc = "Provides a single toolchain version.",
    fields = {
        "toolchain_version": "The toolchain version",
        "toolchain_version_file": "A file containing the toolchain version",
    },
)

KernelEnvToolchainsInfo = provider(
    doc = """Provides resolved toolchains information to `kernel_env`.""",
    fields = {
        "compiler_version": "A string representing compiler version",
        "all_files": "A [depset](https://bazel.build/extending/depsets) of all files of all toolchains",
        "target_arch": "arch of target platform",
        "setup_env_var_cmd": "A command to set up environment variables",
    },
)

KernelEnvAndOutputsInfo = provider(
    doc = """Like `KernelEnvInfo` but also restores artifacts.

It is expected to use these infos in the following way:

```
command = ctx.attr.dep[KernelEnvAndOutputsInfo].get_setup_script(
    data = ctx.attr.dep[KernelEnvAndOutputsInfo].data,
    restore_out_dir_cmd = cache_dir_step.cmd, # or utils.get_check_sandbox_cmd(),
)
```
    """,
    fields = {
        "get_setup_script": """A function.

The function should have the following signature:

```
def get_setup_script(data, restore_out_dir_cmd):
```

where:

* `data`: the `data` field of this info.
* `restore_out_dir_cmd`: A string that contains command to adjust the value of `OUT_DIR`.

The function should return a string that contains the setup script.
""",
        "data": "Additional data consumed by `get_setup_script`.",
        "inputs": """A [depset](https://bazel.build/extending/depsets) containing inputs used
                   by `get_setup_script`. Note that dependencies of `restore_out_dir_cmd` is not
                   included. `inputs` are compiled against the target platform.""",
        "tools": """A [depset](https://bazel.build/extending/depsets) containing tools used
                   by `get_setup_script`. Note that dependencies of `restore_out_dir_cmd` is not
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
        "interceptor_output": "`interceptor` log. See [`interceptor`](https://android.googlesource.com/kernel/tools/interceptor/) project.",
        "compile_commands_with_vars": "A file that can be transformed into `compile_commands.json`.",
        "compile_commands_out_dir": "A subset of `$OUT_DIR` for `compile_commands.json`.",
        "kernel_release": "The file `kernel.release`.",
    },
)

KernelBuildExtModuleInfo = provider(
    doc = "A provider that specifies the expectations of a `_kernel_module` (an external module) or a `kernel_modules_install` from its `kernel_build` attribute.",
    fields = {
        "modules_staging_archive": "Archive containing staging kernel modules. " +
                                   "Does not contain the lib/modules/* suffix.",
        "module_hdrs": "A [depset](https://bazel.build/extending/depsets) containing headers for this `kernel_build` for building external modules",
        "module_scripts": "A [depset](https://bazel.build/extending/depsets) containing scripts for this `kernel_build` for building external modules",
        "module_kconfig": "A [depset](https://bazel.build/extending/depsets) containing `Kconfig` for this `kernel_build` for configuring external modules",
        "config_env_and_outputs_info": "`KernelEnvAndOutputsInfo` for configuring external modules.",
        "modules_env_and_minimal_outputs_info": "`KernelEnvAndOutputsInfo` for building external modules, including minimal needed `kernel_build` outputs.",
        "modules_env_and_all_outputs_info": "`KernelEnvAndOutputsInfo` for building external modules, including all `kernel_build` outputs.",
        "modules_install_env_and_outputs_info": "`KernelEnvAndOutputsInfo` for running modules_install.",
        "collect_unstripped_modules": "Whether an external [`kernel_module`](#kernel_module) building against this [`kernel_build`](#kernel_build) should provide unstripped ones for debugging.",
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
    doc = "A provider that specifies ABI-related information of a [`kernel_build`](#kernel_build).",
    fields = {
        "trim_nonlisted_kmi": "Value of `trim_nonlisted_kmi` in [`kernel_build()`](#kernel_build).",
        "combined_abi_symbollist": "The **combined** `abi_symbollist` file from the `_kmi_symbol_list` rule, consist of the source `kmi_symbol_list` and `additional_kmi_symbol_lists`.",
        "module_outs_file": "A file containing `[kernel_build.module_outs]`(#kernel_build-module_outs) and `[kernel_build.module_implicit_outs]`(#kernel_build-module_implicit_outs).",
        "modules_staging_archive": "Archive containing staging kernel modules. ",
        "base_modules_staging_archive": "Archive containing staging kernel modules of the base kernel",
        "src_kmi_symbol_list": """Source file for `kmi_symbol_list` that points to the symbol list
                                  to be updated by `--update_symbol_list`""",
        "src_protected_exports_list": """Source file for protected symbols which are restricted from being exported by unsigned modules to be updated by `--update_protected_exports`""",
        "src_protected_modules_list": """Source file with list of protected modules whose exports are being protected and needs to be updated by `--update_protected_exports`""",
        "kmi_strict_mode_out": "A [`File`](https://bazel.build/rules/lib/File) to force kmi_strict_mode check.",
    },
)

KernelBuildInTreeModulesInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](#kernel_build) on its
[`base_kernel`](#kernel_build-base_kernel) for the list of in-tree modules in the `base_kernel`.""",
    fields = {
        "module_outs_file": "A file containing `[kernel_build.module_outs]`(#kernel_build-module_outs) and `[kernel_build.module_implicit_outs]`(#kernel_build-module_implicit_outs).",
    },
)

KernelBuildMixedTreeInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](#kernel_build) on its
[`base_kernel`](#kernel_build-base_kernel) for constructing `KBUILD_MIXED_TREE`.""",
    fields = {
        "files": """A [depset](https://bazel.build/extending/depsets) containing the list of
files required to build `KBUILD_MIXED_TREE` for the device kernel.""",
    },
)

KernelBuildUnameInfo = provider(
    doc = """A provider providing `kernel.release` of a `kernel_build`.""",
    fields = {
        "kernel_release": "The file `kernel.release`.",
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

For [`kernel_build()`](#kernel_build), this is a directory containing unstripped in-tree modules.
- This is `None` if and only if `collect_unstripped_modules = False`
- Never `None` if and only if `collect_unstripped_modules = True`
- An empty directory if and only if `collect_unstripped_modules = True` and `module_outs` is empty

For an external [`kernel_module()`](#kernel_module), this is a directory containing unstripped external modules.
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
        "env_and_outputs_info": "`KernelEnvAndOutputsInfo`",
        "images_info": "`KernelImagesInfo`",
        "kernel_build_info": "`KernelBuildInfo`",
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
            the target. This corresponds to `EXT_MOD` in `build.sh`.

            For other rules that contains multiple `kernel_module`s, a [depset] containing package
            names of all external modules in an unspecified order. This corresponds to `EXT_MODULES`
            in `build.sh`.""",
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
    doc = "A provider that provides `Module.symvers` for `modpost`.",
    fields = {
        "restore_paths": """A [depset](https://bazel.build/extending/depsets) of
            paths relative to `COMMON_OUT_DIR` where the `Module.symvers` files will be
            restored to by `KernelModuleSetupInfo`.""",
    },
)

KernelImagesInfo = provider(
    doc = "A provider that represents the expectation of [`kernel_images`](#kernel_images) to [`kernel_build`](#kernel_build)",
    fields = {
        "base_kernel_label": "Label of the `base_kernel` target, if exists",
    },
)

DdkSubmoduleInfo = provider(
    doc = "A provider that describes information about a DDK submodule or module.",
    fields = {
        "outs": """A [depset](https://bazel.build/extending/depsets) containing a struct with
            these keys:

            - `out` is the name of an output file
            - `src` is a label containing the label of the target declaring the output
             file.""",
        "srcs": """A [depset](https://bazel.build/extending/depsets) of source files to build the
            submodule.""",
        "kernel_module_deps": """A [depset](https://bazel.build/extending/depsets) of
            `KernelModuleDepInfo` of dependent targets of this submodules that are
            kernel_module's.""",
    },
)

DdkConfigInfo = provider(
    doc = "A provider that describes information of a `_ddk_config` target to dependent `_ddk_config` targets.",
    fields = {
        "kconfig": """A [depset](https://bazel.build/extending/depsets) containing the Kconfig file
            of this and its dependencies. Uses `postorder` ordering (dependencies first).""",
        "defconfig": """A [depset](https://bazel.build/extending/depsets) containing the Kconfig
            file of this and its dependencies. Uses `postorder` ordering (dependencies first).""",
    },
)

ImagesInfo = provider(
    doc = "Provider from individual *_image rule to [`kernel_images`](#kernel_images) rule",
    fields = {
        "files_dict": """A dictionary, where keys are keys in
            [OutputGroupInfo](https://bazel.build/rules/lib/providers/OutputGroupInfo)
            for `kernel_images`,
            and values are [depsets](https://bazel.build/extending/depsets).
        """,
    },
)
