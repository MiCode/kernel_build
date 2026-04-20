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

"""Generates Makefile and Kbuild files for a DDK module."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load(
    ":common_providers.bzl",
    "DdkIncludeInfo",
    "DdkSubmoduleInfo",
    "ModuleSymversInfo",
)
load(":ddk/ddk_conditional_filegroup.bzl", "DdkConditionalFilegroupInfo")
load(
    ":ddk/ddk_headers.bzl",
    "DDK_INCLUDE_INFO_ORDER",
    "DdkHeadersInfo",
    "ddk_headers_common_impl",
    "get_ddk_transitive_include_infos",
    "get_headers_depset",
)
load(":utils.bzl", "kernel_utils")

visibility("//build/kernel/kleaf/...")

def _gather_prefixed_includes_common(ddk_include_info, info_attr_name):
    ret = []

    generated_roots = sets.make()

    # This depset.to_list() is evaluated at the execution phase.
    for file in ddk_include_info.direct_files.to_list():
        if file.is_source or file.extension != "h":
            continue
        sets.insert(generated_roots, file.root.path)

    for include_root in [""] + sets.to_list(generated_roots):
        for include_dir in getattr(ddk_include_info, info_attr_name):
            ret.append(paths.normalize(
                paths.join(include_root, ddk_include_info.prefix, include_dir),
            ))
    return ret

def gather_prefixed_includes(ddk_include_info):
    """Returns a list of ddk_include_info.includes prefixed with ddk_include_info.prefix"""
    return _gather_prefixed_includes_common(ddk_include_info, "includes")

def _gather_prefixed_linux_includes(ddk_include_info):
    """Returns a list of ddk_include_info.linux_includes prefixed with ddk_include_info.prefix"""
    return _gather_prefixed_includes_common(ddk_include_info, "linux_includes")

def _handle_copt(ctx):
    # copt values contains prefixing "-", so we must use --copt=-x --copt=-y to avoid confusion.
    # We treat $(location) differently because paths must be relative to the Makefile
    # under {package}, e.g. for -include option.

    expand_targets = []
    expand_targets += ctx.attr.module_srcs
    expand_targets += ctx.attr.module_hdrs
    expand_targets += ctx.attr.module_deps

    copt_content = []
    for copt in ctx.attr.module_copts:
        expanded = ctx.expand_location(copt, targets = expand_targets)

        if copt != expanded:
            if not copt.startswith("$(") or not copt.endswith(")") or \
               copt.count("$(") > 1:
                # This may be an item like "-include=$(location X)", which is
                # not allowed. "$(location X) $(location Y)" is also not allowed.
                # The predicate here may not be accurate, but it is a good heuristic.
                fail(
                    """{}: {} is not allowed. An $(location) expression must be its own item.
                       For example, Instead of specifying "-include=$(location X)",
                       specify two items ["-include", "$(location X)"] instead.""",
                    ctx.label,
                    copt,
                )

        copt_content.append({
            "expanded": expanded,
            "is_path": copt != expanded,
        })
    out = ctx.actions.declare_file("{}/copts.json".format(ctx.attr.name))
    ctx.actions.write(
        output = out,
        content = json.encode_indent(copt_content, indent = "  "),
    )
    return out

def _check_no_ddk_headers_in_srcs(ctx, module_label):
    for target in ctx.attr.module_srcs:
        if DdkHeadersInfo in target:
            fail(("{}: {} is a ddk_headers or ddk_module but specified in srcs. " +
                  "Specify it in deps instead.").format(
                module_label,
                target.label,
            ))

def _check_empty_with_submodules(ctx, module_label, kernel_module_deps):
    """Checks that, if the outer target contains submodules, it should be empty.

    That is, the top level `ddk_module` should not declare any

    - inputs (including srcs and hdrs),
    - outputs (including out, hdrs, includes), or
    - copts (including includes and local_defines).

    They should all be declared in individual `ddk_submodule`'s.
    """

    if kernel_module_deps:
        fail("{}: with submodules, deps on other kernel modules should be specified in individual ddk_submodule: {}".format(
            module_label,
            [dep.label for dep in kernel_module_deps],
        ))

    if not ctx.attr.top_level_makefile:
        fail("{}: with submodules, top_level_makefile must be set. " +
             "(Did you specify another ddk_submodule in the deps?)")

    for attr_name in (
        "srcs",
        "out",
        "hdrs",
        "includes",
        "local_defines",
        "copts",
    ):
        attr_val = getattr(ctx.attr, "module_" + attr_name)
        if attr_val:
            fail("{}: with submodules, {} should be specified in individual ddk_submodule: {}".format(
                module_label,
                attr_name,
                attr_val,
            ))

def _check_non_empty_without_submodules(ctx, module_label):
    """Checks that, if the outer target does not contain submodules, it should not be empty.

    That is, a `ddk_module` without submodules, or a `ddk_submodule`, should declare outputs.
    """

    if not ctx.attr.module_out:
        fail(("{}: out is not specified. Perhaps add\n" +
              "    out = \"{}.ko\"").format(
            module_label,
            module_label.name,
        ))

def _check_submodule_same_package(module_label, submodule_deps):
    """Checks that submodules are in the same package.

    `gen_makefiles.py` assumes that `$(srctree)/$(src)` is the same for both submodules
    and modules, then merge them. Until we resolve the paths properly so
    `$(srctree)/$(src)` is no longer dependent on (b/251526635),
    this assumption needs to be in place.
    """

    # TODO(b/251526635): Remove this assumption.
    bad = []
    for submodule in submodule_deps:
        if submodule.label.workspace_name != module_label.workspace_name or \
           submodule.label.package != module_label.package:
            bad.append(submodule.label)

    if bad:
        fail("{}: submodules must be in the same package: {}".format(module_label, bad))

def _handle_module_srcs(ctx):
    """Parses module_srcs.

    For each item in ddk_module.srcs:
    -   If source file (not .h):
        -   If generated file, add it to srcs_json gen. Put it in gen_srcs_depset.
            This makes it available to gen_makefiles.py so it can be copied into output_makefiles
            directory.
        -   If not generated file, add it to srcs_json files
        -   Regardless of whether it is generated or not, set config/value if it is in
            conditional_srcs
    -   If header (.h):
        -   If not generated file, add it to srcs_json files
        -   If generated file, do not add it to srcs_json. Ignore the file.

    Returns:
        struct of
        -    srcs_json: a file containing the JSON content about sources
        -    gen_srcs_depset: depset of generated, non .h files
    """
    srcs_json_list = []
    gen_srcs_depsets = []
    for target in ctx.attr.module_srcs:
        # TODO(b/353811700): avoid depset expansion
        target_files = target.files.to_list()
        srcs_json_dict = {}

        source_files = []
        generated_sources = []

        for file in target_files:
            if file.is_source:
                source_files.append(file)
            elif file.extension != "h":
                generated_sources.append(file)

            # Generated headers in srcs are handled by _gather_prefixed_includes_common

        if source_files:
            srcs_json_dict["files"] = [file.path for file in source_files]

        if generated_sources:
            srcs_json_dict["gen"] = {file.short_path: file.path for file in generated_sources}

        if DdkConditionalFilegroupInfo in target:
            srcs_json_dict["config"] = target[DdkConditionalFilegroupInfo].config
            srcs_json_dict["value"] = target[DdkConditionalFilegroupInfo].value

        srcs_json_list.append(srcs_json_dict)
        gen_srcs_depsets.append(depset(generated_sources))

    srcs_json = ctx.actions.declare_file("{}/srcs.json".format(ctx.attr.name))
    ctx.actions.write(
        output = srcs_json,
        content = json.encode_indent(srcs_json_list, indent = "  "),
    )

    return struct(
        srcs_json = srcs_json,
        gen_srcs_depset = depset(transitive = gen_srcs_depsets),
    )

def _makefiles_impl(ctx):
    module_label = Label(str(ctx.label).removesuffix("_makefiles"))

    _check_no_ddk_headers_in_srcs(ctx, module_label)

    output_makefiles = ctx.actions.declare_directory("{}/makefiles".format(ctx.attr.name))

    split_deps = kernel_utils.split_kernel_module_deps(ctx.attr.module_deps, module_label)
    kernel_module_deps = split_deps.kernel_modules
    submodule_deps = split_deps.submodules
    hdr_deps = split_deps.hdrs
    module_symvers_deps = split_deps.module_symvers_deps

    if submodule_deps:
        _check_empty_with_submodules(ctx, module_label, kernel_module_deps)
    else:
        _check_non_empty_without_submodules(ctx, module_label)

    _check_submodule_same_package(module_label, submodule_deps)

    direct_include_infos = [DdkIncludeInfo(
        prefix = paths.join(module_label.workspace_root, module_label.package),
        # Applies to headers of this target only but not headers/include_dirs
        # inherited from dependencies.
        direct_files = depset(transitive = [target.files for target in ctx.attr.module_srcs]),
        includes = ctx.attr.module_includes,
        linux_includes = ctx.attr.module_linux_includes,
    )]
    include_infos = depset(
        direct_include_infos,
        transitive = get_ddk_transitive_include_infos(
            ctx.attr.module_deps + ctx.attr.module_hdrs,
        ),
        order = DDK_INCLUDE_INFO_ORDER,
    )

    submodule_linux_includes = {}
    for dep in submodule_deps:
        out = dep[DdkSubmoduleInfo].out
        if not out:
            continue
        dirname = paths.dirname(out)
        submodule_linux_includes.setdefault(dirname, []).append(dep[DdkSubmoduleInfo].linux_includes_include_infos)

    module_symvers_depset = depset(transitive = [
        target[ModuleSymversInfo].restore_paths
        for target in module_symvers_deps
    ])

    module_srcs_ret = _handle_module_srcs(ctx)

    args = ctx.actions.args()

    # Though flag_per_line is designed for the absl flags library and
    # gen_makefiles.py uses absl flags library, this outputs the following
    # in the output params file:
    #   --foo=value1 value2
    # ... which is interpreted as --foo="value1 value2" instead of storing
    # individual values. Hence, use multiline so the output becomes:
    #   --foo
    #   value1
    #   value2
    args.set_param_file_format("multiline")
    args.use_param_file("--flagfile=%s")

    args.add("--kernel-module-srcs-json", module_srcs_ret.srcs_json)
    if ctx.attr.module_out:
        args.add("--kernel-module-out", ctx.attr.module_out)
    args.add("--output-makefiles", output_makefiles.path)
    args.add("--package", paths.join(ctx.label.workspace_root, ctx.label.package))

    if ctx.attr.top_level_makefile:
        args.add("--produce-top-level-makefile")
    if ctx.attr.kbuild_has_linux_include:
        args.add("--kbuild-has-linux-include")

    for dirname, linux_includes_include_infos_list in submodule_linux_includes.items():
        args.add("--submodule-linux-include-dirs", dirname)
        args.add_all(
            depset(transitive = linux_includes_include_infos_list),
            map_each = _gather_prefixed_linux_includes,
            uniquify = True,
        )

    args.add_all(
        "--linux-include-dirs",
        include_infos,
        map_each = _gather_prefixed_linux_includes,
        uniquify = True,
    )
    args.add_all(
        "--include-dirs",
        include_infos,
        map_each = gather_prefixed_includes,
        uniquify = True,
    )

    if ctx.attr.top_level_makefile:
        args.add_all("--module-symvers-list", module_symvers_depset)

    args.add_all("--local-defines", ctx.attr.module_local_defines)

    copt_file = _handle_copt(ctx)
    args.add("--copt-file", copt_file)

    submodule_makefiles = depset(transitive = [dep.files for dep in submodule_deps])
    args.add_all("--submodule-makefiles", submodule_makefiles, expand_directories = False)

    if ctx.attr.internal_target_fail_message:
        args.add("--internal-target-fail-message", ctx.attr.internal_target_fail_message)

    ctx.actions.run(
        mnemonic = "DdkMakefiles",
        inputs = depset([
            copt_file,
            module_srcs_ret.srcs_json,
        ], transitive = [submodule_makefiles, module_srcs_ret.gen_srcs_depset]),
        outputs = [output_makefiles],
        executable = ctx.executable._gen_makefile,
        arguments = [args],
        progress_message = "Generating Makefile {}".format(ctx.label),
    )

    outs_depset_direct = []
    if ctx.attr.module_out:
        outs_depset_direct.append(struct(out = ctx.attr.module_out, src = ctx.label))
    outs_depset_transitive = [dep[DdkSubmoduleInfo].outs for dep in submodule_deps]

    srcs_depset_transitive = [target.files for target in ctx.attr.module_srcs]
    srcs_depset_transitive += [dep[DdkSubmoduleInfo].srcs for dep in submodule_deps]

    # Add targets with DdkHeadersInfo in deps
    srcs_depset_transitive += [hdr[DdkHeadersInfo].files for hdr in hdr_deps]

    # Add all files from hdrs (use DdkHeadersInfo if available,
    #  otherwise use default files).
    srcs_depset_transitive.append(get_headers_depset(ctx.attr.module_hdrs))

    ddk_headers_info = ddk_headers_common_impl(
        ctx.label,
        # hdrs of the ddk_module + hdrs of submodules
        ctx.attr.module_hdrs + submodule_deps,
        # includes of the ddk_module. The includes of submodules are handled by adding
        # them to hdrs.
        ctx.attr.module_includes,
        # linux_includes are not exported to targets depended on this module.
        [],
    )

    return [
        DefaultInfo(files = depset([output_makefiles])),
        DdkSubmoduleInfo(
            outs = depset(outs_depset_direct, transitive = outs_depset_transitive),
            out = ctx.attr.module_out,
            srcs = depset(transitive = srcs_depset_transitive),
            kernel_module_deps = depset(
                [kernel_utils.create_kernel_module_dep_info(target) for target in kernel_module_deps],
                transitive = [dep[DdkSubmoduleInfo].kernel_module_deps for dep in submodule_deps],
            ),
            linux_includes_include_infos = include_infos,
        ),
        ModuleSymversInfo(
            restore_paths = module_symvers_depset,
        ),
        ddk_headers_info,
    ]

makefiles = rule(
    implementation = _makefiles_impl,
    doc = "Generate `Makefile` and `Kbuild` files for `ddk_module`",
    attrs = {
        # module_X is the X attribute of the ddk_module. Prefixed with `module_`
        # because they aren't real srcs / hdrs / deps to the makefiles rule.
        "module_srcs": attr.label_list(allow_files = [".c", ".h", ".S", ".rs"]),
        # allow_files = True because https://github.com/bazelbuild/bazel/issues/7516
        "module_hdrs": attr.label_list(allow_files = True),
        "module_includes": attr.string_list(),
        "module_linux_includes": attr.string_list(),
        "module_deps": attr.label_list(),
        "module_out": attr.string(),
        "module_local_defines": attr.string_list(),
        "module_copts": attr.string_list(),
        "top_level_makefile": attr.bool(),
        "kbuild_has_linux_include": attr.bool(
            doc = "Whether to add LINUXINCLUDE to Kbuild",
            default = True,
        ),
        "internal_target_fail_message": attr.string(
            doc = "For testing only. Assert that this target to fail to build with the given message.",
        ),
        "_gen_makefile": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/gen_makefiles",
            executable = True,
            cfg = "exec",
        ),
    },
)
