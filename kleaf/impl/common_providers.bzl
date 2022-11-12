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

KernelCmdsInfo = provider(
    doc = """Provides a directory of `.cmd` files.""",
    fields = {
        "directories": """A [depset](https://bazel.build/extending/depsets) of directories
                          containing the `.cmd` files""",
    },
)

KernelEnvInfo = provider(
    doc = """Describe a generic environment setup with some dependencies and a setup script.

`KernelEnvInfo` is a legacy name; it is not only provided by `kernel_env`, but
other rules like `kernel_config` and `kernel_build`. Hence, the `KernelEnvInfo`
is in its own extension instead of `kernel_env.bzl`.
    """,
    fields = {
        "dependencies": "dependencies required to use this environment setup",
        "setup": "setup script to initialize the environment",
    },
)

KernelEnvAttrInfo = provider(
    doc = "Provide attributes of `kernel_env`.",
    fields = {
        "kbuild_symtypes": "`KBUILD_SYMTYPES`, after resolving `--kbuild_symtypes` and the static value.",
        "progress_message_note": """A note in the progress message that differentiates multiple
            instances of the same action due to different configs.""",
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
        "modules_prepare_setup": "A command that is equivalent to running `make modules_prepare`. Requires env setup.",
        "modules_prepare_deps": "A list of deps to run `modules_prepare_cmd`.",
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
    doc = "A provider that specifies the expectations of a [`kernel_abi`](#kernel_abi) on a `kernel_build`.",
    fields = {
        "trim_nonlisted_kmi": "Value of `trim_nonlisted_kmi` in [`kernel_build()`](#kernel_build).",
        "combined_abi_symbollist": "The **combined** `abi_symbollist` file from the `_kmi_symbol_list` rule, consist of the source `kmi_symbol_list` and `additional_kmi_symbol_lists`.",
        "module_outs_file": "A file containing `[kernel_build.module_outs]`(#kernel_build-module_outs) and `[kernel_build.module_implicit_outs]`(#kernel_build-module_implicit_outs).",
        "modules_staging_archive": "Archive containing staging kernel modules. ",
        "base_modules_staging_archive": "Archive containing staging kernel modules of the base kernel",
        "src_kmi_symbol_list": """Source file for `kmi_symbol_list` that points to the symbol list
                                  to be updated by `--update_symbol_list`""",
    },
)

KernelBuildInTreeModulesInfo = provider(
    doc = """A provider that specifies the expectations of a [`kernel_build`](#kernel_build) on its
[`base_kernel`](#kernel_build-base_kernel) or [`base_kernel_for_module_outs`](#kernel_build-base_kernel_for_module_outs)
for the list of in-tree modules in the `base_kernel`.""",
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

KernelModuleInfo = provider(
    doc = "A provider that provides installed external modules.",
    fields = {
        "kernel_build": "kernel_build attribute of this module",

        # TODO(b/256688440): Avoid depset[directory_with_structure] to_list
        "modules_staging_dws_depset": """A [depset](https://bazel.build/extending/depsets) of
            `directory_with_structure` containing staging kernel modules.
            Contains the lib/modules/* suffix.""",
        "kernel_uapi_headers_dws_depset": """A [depset](https://bazel.build/extending/depsets) of
            `directory_with_structure` containing UAPI headers to use the module.""",
        "files": "A [depset](https://bazel.build/extending/depsets) of output `*.ko` files.",
    },
)

ModuleSymversInfo = provider(
    doc = "A provider that provides `Module.symvers` for `modpost`.",
    fields = {
        "restore_paths": """A [depset](https://bazel.build/extending/depsets) of
            paths relative to <the root of the output directory> (e.g.
            `<sandbox_root>/out/<branch>`) where the `Module.symvers` files will be
            restored to by `KernelEnvInfo`.""",
    },
)

KernelImagesInfo = provider(
    doc = "A provider that represents the expectation of [`kernel_images`](#kernel_images) to [`kernel_build`](#kernel_build)",
    fields = {
        "base_kernel": "the `base_kernel` target, if exists",
    },
)
