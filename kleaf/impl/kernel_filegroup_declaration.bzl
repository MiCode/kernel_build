# Copyright (C) 2024 The Android Open Source Project
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

"""Given a kernel_build, generates corresponding kernel_filegroup target declaration."""

load(":common_providers.bzl", "KernelBuildFilegroupDeclInfo")
load(
    ":constants.bzl",
    "FILEGROUP_DEF_ARCHIVE_SUFFIX",
    "FILEGROUP_DEF_TEMPLATE_NAME",
)
load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _kernel_filegroup_declaration_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    info = ctx.attr.kernel_build[KernelBuildFilegroupDeclInfo]

    file_to_label = lambda file: repr("//{}".format(file.basename) if file else None)
    file_to_pkg_label = lambda file: repr(file.path if file else None)
    files_to_label = lambda lst: repr(["//{}".format(file.basename) for file in lst])
    files_to_pkg_label = lambda lst: repr([file.path for file in lst])

    # ddk_artifacts
    deps_files = [
        # _modules_prepare
        info.modules_prepare_archive,
        info.modules_staging_archive,
        info.toolchain_version_file,
    ]

    deps_repr = repr([file.path for file in deps_files] +
                     ["//{}".format(file.basename) for file in ctx.files.extra_deps])

    kernel_uapi_headers_lst = info.kernel_uapi_headers.to_list()
    if not kernel_uapi_headers_lst:
        fail("{}: {} does not have kernel_uapi_headers.".format(ctx.label, ctx.attr.kernel_build.label))
    if len(kernel_uapi_headers_lst) > 1:
        fail("{}: kernel_filegroup_declaration on kernel_build {} with base_kernel is not supported yet.".format(
            ctx.label,
            ctx.attr.kernel_build.label,
        ))
    kernel_uapi_headers = kernel_uapi_headers_lst[0]

    fragment = """\
platform(
    name = {target_platform_repr},
    constraint_values = [
        "@platforms//os:android",
        "@platforms//cpu:{arch}",
    ],
    visibility = ["//visibility:private"],
)

platform(
    name = {exec_platform_repr},
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    visibility = ["//visibility:private"],
)

kernel_filegroup(
    name = {name_repr},
    srcs = {srcs_repr},
    deps = {deps_repr},
    kernel_uapi_headers = {uapi_headers_repr},
    collect_unstripped_modules = {collect_unstripped_modules_repr},
    module_outs_file = {module_outs_repr},
    kernel_release = {kernel_release_repr},
    protected_modules_list = {protected_modules_repr},
    ddk_module_defconfig_fragments = {ddk_module_defconfig_fragments_repr},
    target_platform = {target_platform_repr},
    exec_platform = {exec_platform_repr},
    visibility = ["//visibility:public"],
)
""".format(
        name_repr = repr(ctx.attr.kernel_build.label.name),
        srcs_repr = files_to_label(info.filegroup_srcs),
        deps_repr = deps_repr,
        uapi_headers_target_repr = repr(ctx.attr.kernel_build.label.name + "_uapi_headers"),
        uapi_headers_repr = file_to_label(kernel_uapi_headers),
        collect_unstripped_modules_repr = repr(info.collect_unstripped_modules),
        module_outs_repr = file_to_pkg_label(info.module_outs_file),
        kernel_release_repr = file_to_pkg_label(info.kernel_release),
        protected_modules_repr = file_to_pkg_label(info.src_protected_modules_list),
        ddk_module_defconfig_fragments_repr = files_to_pkg_label(
            info.ddk_module_defconfig_fragments.to_list(),
        ),
        target_platform_repr = repr(ctx.attr.kernel_build.label.name + "_platform_target"),
        exec_platform_repr = repr(ctx.attr.kernel_build.label.name + "_platform_exec"),
        arch = info.arch,
    )

    filegroup_decl_file = ctx.actions.declare_file("{}/{}".format(
        ctx.attr.kernel_build.label.name,
        FILEGROUP_DEF_TEMPLATE_NAME,
    ))
    ctx.actions.write(filegroup_decl_file, fragment)

    filegroup_decl_archive = ctx.actions.declare_file("{name}/{name}{suffix}".format(
        name = ctx.attr.kernel_build.label.name,
        suffix = FILEGROUP_DEF_ARCHIVE_SUFFIX,
    ))
    direct_inputs = deps_files + [
        filegroup_decl_file,
        info.module_outs_file,
        info.kernel_release,
        kernel_uapi_headers,
    ]
    if info.src_protected_modules_list:
        direct_inputs.append(info.src_protected_modules_list)
    transitive_inputs = [info.ddk_module_defconfig_fragments]
    inputs = depset(
        direct_inputs,
        transitive = transitive_inputs,
    )

    # filegroup_decl_template.txt stays at root so that
    # kernel_prebuilt_repo can find it.
    command = hermetic_tools.setup + """
        tar cf {archive} --dereference \\
            --transform 's:.*/filegroup_decl_template.txt:filegroup_decl_template.txt:g' \\
            "$@"
    """.format(
        archive = filegroup_decl_archive.path,
    )
    args = ctx.actions.args()
    args.add_all(inputs)
    ctx.actions.run_shell(
        inputs = inputs,
        tools = hermetic_tools.deps,
        outputs = [filegroup_decl_archive],
        command = command,
        arguments = [args],
        progress_message = "Creating archive of kernel_filegroup declaration {}".format(ctx.label),
        mnemonic = "KernelfilegroupDeclaration",
    )

    return DefaultInfo(files = depset([filegroup_decl_archive]))

kernel_filegroup_declaration = rule(
    implementation = _kernel_filegroup_declaration_impl,
    doc = "Given a kernel_build, generates corresponding kernel_filegroup target declaration.",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelBuildFilegroupDeclInfo],
        ),
        "extra_deps": attr.label_list(
            doc = """Extra files to be placed in the `deps` of the generated `kernel_filegroup`.

                These files are downloaded separately by `kernel_prebuilt_repo`.

                These files are not included in the generated archive.
            """,
            allow_files = True,
        ),
    },
    toolchains = [hermetic_toolchain.type],
)
