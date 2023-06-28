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

"""A target that mimics [`kernel_build`](#kernel_build) from a list of prebuilt files."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    ":common_providers.bzl",
    "GcovInfo",
    "KernelBuildAbiInfo",
    "KernelBuildExtModuleInfo",
    "KernelBuildInTreeModulesInfo",
    "KernelBuildMixedTreeInfo",
    "KernelBuildUapiInfo",
    "KernelBuildUnameInfo",
    "KernelEnvAndOutputsInfo",
    "KernelEnvAttrInfo",
    "KernelImagesInfo",
    "KernelToolchainInfo",
    "KernelUnstrippedModulesInfo",
)
load(
    ":constants.bzl",
    "MODULES_STAGING_ARCHIVE",
    "TOOLCHAIN_VERSION_FILENAME",
)
load(":debug.bzl", "debug")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":kernel_config_settings.bzl", "kernel_config_settings")
load(
    ":utils.bzl",
    "kernel_utils",
    "utils",
)

visibility("//build/kernel/kleaf/...")

def _ext_mod_env_and_outputs_info_get_setup_script(data, restore_out_dir_cmd):
    # TODO(b/219112010): need to set up env and restore outputs
    script = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
           tar xf {outdir_tar_gz} -C ${{OUT_DIR}}
           {restore_out_dir_cmd}
    """.format(
        outdir_tar_gz = data.modules_prepare_out_dir_tar_gz,
        restore_out_dir_cmd = restore_out_dir_cmd,
    )
    return script

def _get_mixed_tree_files(target):
    if KernelBuildMixedTreeInfo in target:
        return target[KernelBuildMixedTreeInfo].files
    return target.files

def _get_toolchain_version_info(ctx, all_deps):
    # Traverse all dependencies and look for a file named "toolchain_version".
    # If no file matches, leave it as None so that _kernel_build_check_toolchain prints a
    # warning.
    toolchain_version_file = utils.find_file(name = TOOLCHAIN_VERSION_FILENAME, files = all_deps, what = ctx.label)
    return KernelToolchainInfo(toolchain_version_file = toolchain_version_file)

def _get_kernel_release(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    gki_info = utils.find_file(
        name = "gki-info.txt",
        files = ctx.files.gki_artifacts,
        what = "{} gki_artifacts".format(ctx.label),
        required = True,
    )
    kernel_release = ctx.actions.declare_file("{}/kernel.release".format(ctx.label.name))
    command = hermetic_tools.setup + """
        kernel_release=$(cat {gki_info} | sed -nE 's/^kernel_release=(.*)$/\\1/p')
        if [[ -z "${{kernel_release}}" ]]; then
            echo "ERROR: Unable to determine kernel_release from {gki_info}" >&2
            exit 1
        fi
        echo "${{kernel_release}}" > {kernel_release_file}
    """.format(
        gki_info = gki_info.path,
        kernel_release_file = kernel_release.path,
    )
    debug.print_scripts(ctx, command, what = "kernel.release")
    ctx.actions.run_shell(
        command = command,
        inputs = [gki_info],
        outputs = [kernel_release],
        tools = hermetic_tools.deps,
        progress_message = "Extracting kernel.release {}".format(ctx.label),
        mnemonic = "KernelFilegroupKernelRelease",
    )
    return kernel_release

def _kernel_filegroup_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    all_deps = ctx.files.srcs + ctx.files.deps

    modules_prepare_out_dir_tar_gz = utils.find_file("modules_prepare_outdir.tar.gz", all_deps, what = ctx.label)

    module_srcs = kernel_utils.filter_module_srcs(ctx.files.kernel_srcs)

    ext_mod_env_and_outputs_info = KernelEnvAndOutputsInfo(
        get_setup_script = _ext_mod_env_and_outputs_info_get_setup_script,
        inputs = depset([modules_prepare_out_dir_tar_gz]),
        tools = depset(),
        data = struct(modules_prepare_out_dir_tar_gz = modules_prepare_out_dir_tar_gz),
    )

    kernel_module_dev_info = KernelBuildExtModuleInfo(
        modules_staging_archive = utils.find_file(MODULES_STAGING_ARCHIVE, all_deps, what = ctx.label),
        modules_env_and_minimal_outputs_info = ext_mod_env_and_outputs_info,
        modules_env_and_all_outputs_info = ext_mod_env_and_outputs_info,
        modules_install_env_and_outputs_info = ext_mod_env_and_outputs_info,
        # TODO(b/211515836): module_hdrs / module_scripts might also be downloaded
        module_hdrs = module_srcs.module_hdrs,
        module_scripts = module_srcs.module_scripts,
        collect_unstripped_modules = ctx.attr.collect_unstripped_modules,
    )

    kernel_uapi_depsets = []
    if ctx.attr.kernel_uapi_headers:
        kernel_uapi_depsets.append(ctx.attr.kernel_uapi_headers.files)
    uapi_info = KernelBuildUapiInfo(
        kernel_uapi_headers = depset(transitive = kernel_uapi_depsets, order = "postorder"),
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
        command = hermetic_tools.setup + """
            tar xf {unstripped_modules_archive} -C $(dirname {unstripped_dir}) $(basename {unstripped_dir})
        """.format(
            unstripped_modules_archive = unstripped_modules_archive.path,
            unstripped_dir = unstripped_dir.path,
        )
        debug.print_scripts(ctx, command, what = "unstripped_modules_archive")
        ctx.actions.run_shell(
            command = command,
            inputs = [
                unstripped_modules_archive,
            ],
            outputs = [unstripped_dir],
            tools = hermetic_tools.deps,
            progress_message = "Extracting unstripped_modules_archive {}".format(ctx.label),
            mnemonic = "KernelFilegroupUnstrippedModulesArchive",
        )
        unstripped_modules_info = KernelUnstrippedModulesInfo(
            directories = depset([unstripped_dir], order = "postorder"),
        )

    protected_modules_list = None
    if ctx.files.protected_modules_list:
        if len(ctx.files.protected_modules_list) != 1:
            fail("{}: protected_modules_list {} produces multiple files, expected 0 or 1".format(
                ctx.label,
                ctx.attr.protected_modules_list,
            ))
        protected_modules_list = ctx.files.protected_modules_list[0]

    abi_info = KernelBuildAbiInfo(
        src_protected_modules_list = protected_modules_list,
        module_outs_file = ctx.file.module_outs_file,
        modules_staging_archive = utils.find_file(MODULES_STAGING_ARCHIVE, all_deps, what = ctx.label),
    )
    in_tree_modules_info = KernelBuildInTreeModulesInfo(module_outs_file = ctx.file.module_outs_file)

    images_info = KernelImagesInfo(base_kernel_label = None)
    gcov_info = GcovInfo(gcno_mapping = None, gcno_dir = None)

    # kernel_filegroup does not have any defconfig_fragments because the .config is fixed from prebuilts.
    config_tags_out = kernel_config_settings.kernel_env_get_config_tags(
        ctx = ctx,
        mnemonic_prefix = "KernelFilegroup",
        defconfig_fragments = [],
    )
    progress_message_note = kernel_config_settings.get_progress_message_note(
        ctx,
        defconfig_fragments = [],
    )
    kernel_env_attr_info = KernelEnvAttrInfo(
        common_config_tags = config_tags_out.common,
        progress_message_note = progress_message_note,
    )

    srcs_depset = depset(transitive = [target.files for target in ctx.attr.srcs])
    mixed_tree_files = depset(transitive = [_get_mixed_tree_files(target) for target in ctx.attr.srcs])
    kernel_release = _get_kernel_release(ctx)

    return [
        DefaultInfo(files = srcs_depset),
        KernelBuildMixedTreeInfo(files = mixed_tree_files),
        KernelBuildUnameInfo(kernel_release = kernel_release),
        kernel_module_dev_info,
        # TODO(b/219112010): implement KernelEnvAndOutputsInfo properly for kernel_filegroup
        uapi_info,
        unstripped_modules_info,
        abi_info,
        in_tree_modules_info,
        images_info,
        kernel_env_attr_info,
        gcov_info,
        _get_toolchain_version_info(ctx, all_deps),
    ]

def _kernel_filegroup_additional_attrs():
    return dicts.add(
        kernel_config_settings.of_kernel_env(),
    )

kernel_filegroup = rule(
    implementation = _kernel_filegroup_impl,
    doc = """**EXPERIMENTAL.** The API of `kernel_filegroup` rapidly changes and
is not backwards compatible with older builds. The usage of `kernel_filegroup`
is limited to the implementation detail of Kleaf (in particular,
[`define_common_kernels`](#define_common_kernels)). Do not use
`kernel_filegroup` directly. See `download_prebuilt.md` for details.

Specify a list of kernel prebuilts.

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
[`kernel_abi`](#kernel_abi) sets
[`define_abi_targets`](#kernel_abi-define_abi_targets) to `True` by
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
        "protected_modules_list": attr.label(allow_files = True),
        "gki_artifacts": attr.label(
            allow_files = True,
            doc = """A list of files that were built from the [`gki_artifacts`](#gki_artifacts) target.""",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_cache_dir_config_tags": attr.label(
            default = "//build/kernel/kleaf/impl:cache_dir_config_tags",
            executable = True,
            cfg = "exec",
        ),
    } | _kernel_filegroup_additional_attrs(),
    toolchains = [hermetic_toolchain.type],
)
