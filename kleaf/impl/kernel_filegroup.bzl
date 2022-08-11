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

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    ":common_providers.bzl",
    "KernelBuildAbiInfo",
    "KernelBuildExtModuleInfo",
    "KernelBuildInTreeModulesInfo",
    "KernelBuildUapiInfo",
    "KernelImagesInfo",
    "KernelUnstrippedModulesInfo",
)
load(":debug.bzl", "debug")
load(
    ":utils.bzl",
    "kernel_utils",
    "utils",
)

def _kernel_filegroup_impl(ctx):
    all_deps = ctx.files.srcs + ctx.files.deps

    # TODO(b/219112010): implement KernelEnvInfo for the modules_prepare target
    modules_prepare_out_dir_tar_gz = utils.find_file("modules_prepare_outdir.tar.gz", all_deps, what = ctx.label)
    modules_prepare_setup = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
           tar xf {outdir_tar_gz} -C ${{OUT_DIR}}
    """.format(outdir_tar_gz = modules_prepare_out_dir_tar_gz)
    modules_prepare_deps = [modules_prepare_out_dir_tar_gz]

    kernel_module_dev_info = KernelBuildExtModuleInfo(
        modules_staging_archive = utils.find_file("modules_staging_dir.tar.gz", all_deps, what = ctx.label),
        modules_prepare_setup = modules_prepare_setup,
        modules_prepare_deps = modules_prepare_deps,
        # TODO(b/211515836): module_srcs might also be downloaded
        module_srcs = kernel_utils.filter_module_srcs(ctx.files.kernel_srcs),
        collect_unstripped_modules = ctx.attr.collect_unstripped_modules,
    )
    uapi_info = KernelBuildUapiInfo(
        kernel_uapi_headers = ctx.attr.kernel_uapi_headers,
    )

    unstripped_modules_info = None
    for target in ctx.attr.srcs:
        if KernelUnstrippedModulesInfo in target:
            unstripped_modules_info = target[KernelUnstrippedModulesInfo]
            break
    if unstripped_modules_info == None:
        # Reverse of kernel_unstripped_modules_archive
        unstripped_modules_archive = utils.find_file("unstripped_modules.tar.gz", all_deps, what = ctx.label, required = True)
        unstripped_dir = ctx.actions.declare_directory("{}/unstripped".format(ctx.label.name))
        command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
            tar xf {unstripped_modules_archive} -C $(dirname {unstripped_dir}) $(basename {unstripped_dir})
        """
        debug.print_scripts(ctx, command, what = "unstripped_modules_archive")
        ctx.actions.run_shell(
            command = command,
            inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + [
                unstripped_modules_archive,
            ],
            outputs = [unstripped_dir],
            progress_message = "Extracting unstripped_modules_archive {}".format(ctx.label),
            mnemonic = "KernelFilegroupUnstrippedModulesArchive",
        )
        unstripped_modules_info = KernelUnstrippedModulesInfo(directory = unstripped_dir)

    abi_info = KernelBuildAbiInfo(module_outs_file = ctx.file.module_outs_file)
    in_tree_modules_info = KernelBuildInTreeModulesInfo(module_outs_file = ctx.file.module_outs_file)

    images_info = KernelImagesInfo(base_kernel = None)

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        kernel_module_dev_info,
        # TODO(b/219112010): implement KernelEnvInfo for kernel_filegroup
        uapi_info,
        unstripped_modules_info,
        abi_info,
        in_tree_modules_info,
        images_info,
    ]

kernel_filegroup = rule(
    implementation = _kernel_filegroup_impl,
    doc = """Specify a list of kernel prebuilts.

This is similar to [`filegroup`](https://docs.bazel.build/versions/main/be/general.html#filegroup)
that gives a convenient name to a collection of targets, which can be referenced from other rules.

It can be used in the `base_kernel` attribute of a [`kernel_build`](#kernel_build).
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = """The list of labels that are members of this file group.

This usually contains a list of prebuilts, e.g. `vmlinux`, `Image.lz4`, `kernel-headers.tar.gz`,
etc.

Not to be confused with [`kernel_srcs`](#kernel_filegroup-kernel_srcs).""",
        ),
        "deps": attr.label_list(
            allow_files = True,
            doc = """A list of additional labels that participates in implementing the providers.

This usually contains a list of prebuilts.

Unlike srcs, these labels are NOT added to the [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html)""",
        ),
        "kernel_srcs": attr.label_list(
            allow_files = True,
            doc = """A list of files that would have been listed as `srcs` if this rule were a [`kernel_build`](#kernel_build).

This is usually a `glob()` of source files.

Not to be confused with [`srcs`](#kernel_filegroup-srcs).
""",
        ),
        "kernel_uapi_headers": attr.label(
            allow_files = True,
            doc = """The label pointing to `kernel-uapi-headers.tar.gz`.

This attribute should be set to the `kernel-uapi-headers.tar.gz` artifact built by the
[`kernel_build`](#kernel_build) macro if the `kernel_filegroup` rule were a `kernel_build`.

Setting this attribute allows [`merged_kernel_uapi_headers`](#merged_kernel_uapi_headers) to
work properly when this `kernel_filegroup` is set to the `base_kernel`.

For example:
```
kernel_filegroup(
    name = "kernel_aarch64_prebuilts",
    srcs = [
        "vmlinux",
        # ...
    ],
    kernel_uapi_headers = "kernel-uapi-headers.tar.gz",
)

kernel_build(
    name = "tuna",
    base_kernel = ":kernel_aarch64_prebuilts",
    # ...
)

merged_kernel_uapi_headers(
    name = "tuna_merged_kernel_uapi_headers",
    kernel_build = "tuna",
    # ...
)
```
""",
        ),
        "collect_unstripped_modules": attr.bool(
            default = True,
            doc = """See [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).

Unlike `kernel_build`, this has default value `True` because
[`kernel_build_abi`](#kernel_build_abi) sets
[`define_abi_targets`](#kernel_build_abi-define_abi_targets) to `True` by
default, which in turn sets `collect_unstripped_modules` to `True` by default.
""",
        ),
        "module_outs_file": attr.label(
            allow_single_file = True,
            doc = """A file containing `module_outs` of the original [`kernel_build`](#kernel_build) target.""",
        ),
        "images": attr.label(
            allow_files = True,
            doc = """A label providing files similar to a [`kernel_images`](#kernel_images) target.""",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
    },
)
