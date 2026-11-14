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
load("@kernel_toolchain_info//:dict.bzl", "VARS")
load(
    ":common_providers.bzl",
    "DdkConditionalFilegroupInfo",
    "DdkHeadersInfo",
    "DdkIncludeInfo",
    "DdkLibraryInfo",
    "DdkSubmoduleInfo",
    "ModuleSymversFileInfo",
    "ModuleSymversInfo",
)
load(":constants.bzl", "DDK_MODULE_SRCS_ALLOWED_EXTENSIONS")
load(
    ":ddk/ddk_headers.bzl",
    "DDK_INCLUDE_INFO_ORDER",
    "ddk_headers_common_impl",
    "get_ddk_transitive_include_infos",
    "get_headers_depset",
)
load(":utils.bzl", "kernel_utils")

visibility("//build/kernel/kleaf/...")

_DEBUG_INFO_FOR_PROFILING_COPTS = [
    "-fdebug-info-for-profiling",
    "-mllvm",
    "-enable-npm-pgo-inline-deferral=false",
    "-mllvm",
    "-improved-fs-discriminator=true",
]

_PKVM_EL2_OUT = "kvm_nvhe.o"

def _gather_prefixed_includes_common(ddk_include_info, info_attr_name):
    """Calculates -I flags.

    If there are any generated headers in ddk_include_info, the list
    of -I's are duplicated, with each token prepended with the root of the
    generated header.

    This is sometimes an overestimate, but the fs sandbox should ensure that only
    the correct files are visible.

    This can also be problematic if multiple generated headers have conflicting name / include
    paths and they are under different transitions (therefore File.root is different). In that
    unlikely edge case, it is advised that users use individual ddk_headers() to separate them.
    """
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

def _handle_opts(ctx, file_name, opts, pre_opts_json = None):
    """Common function for handling copts, removed_copts, and asopts.

    Args:
        ctx: ctx
        file_name: The declared JSON file name
        opts: list of flags
        pre_opts_json: Additional list prepended to the JSON list.
    """
    # We treat $(location) differently because paths must be relative to the Makefile
    # under {package}, e.g. for -include option.

    expand_targets = []
    expand_targets += ctx.attr.module_srcs
    expand_targets += ctx.attr.module_hdrs
    expand_targets += ctx.attr.module_deps
    if ctx.attr.module_crate_root:
        expand_targets.append(ctx.attr.module_crate_root)

    json_content = list(pre_opts_json) if pre_opts_json else []
    for copt in opts:
        expanded = ctx.expand_location(copt, targets = expand_targets)
        json_content.append({
            "expanded": expanded,
            "orig": copt,
        })
    out = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, file_name))
    ctx.actions.write(
        output = out,
        content = json.encode_indent(json_content, indent = "  "),
    )
    return out

def _get_autofdo_copts(ctx):
    """Returns content in copt_file for AutoFDO."""

    copt_content = []
    if ctx.attr.module_debug_info_for_profiling:
        copt_content += [{
            "expanded": flag,
            "orig": flag,
        } for flag in _DEBUG_INFO_FOR_PROFILING_COPTS]

    if ctx.file.module_autofdo_profile:
        copt_content += [{
            "expanded": "-fprofile-sample-accurate",
            "orig": "-fprofile-sample-accurate",
        }, {
            "expanded": "-fprofile-sample-use={}".format(ctx.file.module_autofdo_profile.path),
            "orig": "-fprofile-sample-use=$(execpath {})".format(ctx.attr.module_autofdo_profile.label),
        }]

    return copt_content

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

    - inputs (including srcs, hdrs, and crate_root),
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
        "crate_root",
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

def _handle_module_srcs(ctx, ddk_library_deps):
    """Parses module_srcs and module_crate_root, and ddk_library module_deps.

    For each item in ddk_module.srcs and ddk_module.crate_root:
    -   If source file (.c .S .o_shipped .o.cmd_shipped, and .rs):
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
        -   srcs_json: a file containing the JSON content about sources
        -   gen_srcs_depset: depset of generated, non .h files
        -   src_matrix: list of list of files. The sum of values is the list of files from:
            - srcs
            - ddk_library deps
            - crate_root
    """
    src_matrix = []
    srcs_json_list = []
    gen_srcs_depsets = []

    crate_root_targets = [ctx.attr.module_crate_root] if ctx.attr.module_crate_root else []

    for targets, info, dep_type in (
        (ctx.attr.module_srcs, DefaultInfo, "srcs"),
        (crate_root_targets, DefaultInfo, "crate_root"),
        (ddk_library_deps, DdkLibraryInfo, "library"),
    ):
        for target in targets:
            # TODO(b/353811700): avoid depset expansion
            target_files = target[info].files.to_list()
            src_matrix.append(target_files)
            ret = _handle_target_files_as_srcs(target, target_files, dep_type)
            srcs_json_list.append(ret.srcs_json_dict)
            gen_srcs_depsets.append(ret.gen_srcs_depset)

    srcs_json = ctx.actions.declare_file("{}/srcs.json".format(ctx.attr.name))
    ctx.actions.write(
        output = srcs_json,
        content = json.encode_indent(srcs_json_list, indent = "  "),
    )

    return struct(
        srcs_json = srcs_json,
        gen_srcs_depset = depset(transitive = gen_srcs_depsets),
        src_matrix = src_matrix,
    )

def _handle_target_files_as_srcs(target, target_files, dep_type):
    """Processes `target` as a source.

    Args:
        target: the dependency
        target_files: the list of files from the dependency
        dep_type: Type of the dependency:
            * srcs
            * crate_root
            * library, for deps with DdkLibraryInfo

    Returns:
        A struct with these fields:
            * srcs_json_dict: Dictionary of metadata for the list of files for this target,
                provided to gen_makefiles.py
            * gen_srcs_depset: depset of generated files
    """
    srcs_json_dict = {}

    source_files = []
    generated_sources = []

    for file in target_files:
        # Headers in srcs are not passed to gen_makefiles.py.
        # Generated headers handled by _gather_prefixed_includes_common.
        #   They are not appended to the source list, but additional -I are added.
        # Non-generated headers don't need any special handling.
        if file.extension == "h" and dep_type == "srcs":
            continue

        # For the remaining files in srcs / crate_root / ddk_library deps etc.,
        # pass them to gen_makefiles.py to generate proper rules. Generated
        # files needs special handling so put them in a different list.
        if file.is_source:
            source_files.append(file)
        else:
            generated_sources.append(file)

    if source_files:
        srcs_json_dict["files"] = [file.path for file in source_files]

    if generated_sources:
        srcs_json_dict["gen"] = {file.short_path: file.path for file in generated_sources}

    if DdkConditionalFilegroupInfo in target:
        srcs_json_dict["config"] = target[DdkConditionalFilegroupInfo].config
        srcs_json_dict["value"] = target[DdkConditionalFilegroupInfo].value

    if dep_type != "srcs":
        srcs_json_dict["type"] = dep_type

    return struct(
        srcs_json_dict = srcs_json_dict,
        gen_srcs_depset = depset(generated_sources),
    )

def _get_ddk_library_out_list_impl(subrule_ctx, src_rel_pkg):
    """Returns a list of outputs for ddk_library.

    Args:
        subrule_ctx: subrule_ctx
        src_rel_pkg: path to the source file, relative to the package.
            The suffix doesn't matter. <stem>.o_shipped and .<stem>.o.cmd_shipped is returned.
    """
    object = paths.replace_extension(src_rel_pkg, ".o_shipped")
    cmd_file_basename = "." + paths.replace_extension(paths.basename(src_rel_pkg), ".o.cmd_shipped")
    cmd_file = paths.join(paths.dirname(src_rel_pkg), cmd_file_basename)
    return [
        struct(out = object, src = subrule_ctx.label),
        struct(out = cmd_file, src = subrule_ctx.label),
    ]

_get_ddk_library_out_list = subrule(implementation = _get_ddk_library_out_list_impl)

def _get_outs_list_impl(
        subrule_ctx,
        *,
        module_pkvm_el2,
        target_type,
        src_matrix,
        module_out,
        submodule_deps):
    """Figures out the list of outputs from the action.

    Args:
        subrule_ctx: subrule_ctx
        module_pkvm_el2: building pKVM EL2 ddk_library
        target_type: type of outer target
        src_matrix: list of list of sources
        module_out: out of outer target
        submodule_deps: list of ddk_submodule deps.
    """
    if module_pkvm_el2:
        return depset(_get_ddk_library_out_list(_PKVM_EL2_OUT))

    if target_type == "library":
        my_pkg_path = paths.join(subrule_ctx.label.workspace_root, subrule_ctx.label.package)
        outs_depset_direct = []
        for srcs_list in src_matrix:
            for src in srcs_list:
                # All sources must be below this package.
                # Use short_path here because we don't care about bin_dir for generated sources.
                # path/to/foo.c -> [path/to/foo.o_shipped, path/to/.foo.o.cmd_shipped]
                src_rel_pkg = paths.relativize(src.short_path, my_pkg_path)
                outs_depset_direct += _get_ddk_library_out_list(src_rel_pkg)
        return depset(outs_depset_direct)

    if target_type in ("module", "submodule"):
        outs_depset_direct = []
        if module_out:
            outs_depset_direct.append(struct(out = module_out, src = subrule_ctx.label))
        outs_depset_transitive = [dep[DdkSubmoduleInfo].outs for dep in submodule_deps]
        return depset(outs_depset_direct, transitive = outs_depset_transitive)

    fail("Unrecognized type {}".format(target_type))

_get_outs_list = subrule(
    implementation = _get_outs_list_impl,
    subrules = [
        _get_ddk_library_out_list,
    ],
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
    ddk_library_deps = split_deps.ddk_library_deps

    if submodule_deps:
        _check_empty_with_submodules(ctx, module_label, kernel_module_deps)
    else:
        _check_non_empty_without_submodules(ctx, module_label)

    _check_submodule_same_package(module_label, submodule_deps)

    # Depset of files from module_srcs
    srcs_files = depset(transitive = [target.files for target in ctx.attr.module_srcs])
    crate_root_files = ctx.attr.module_crate_root.files if ctx.attr.module_crate_root else depset()

    direct_include_infos = [DdkIncludeInfo(
        prefix = paths.join(module_label.workspace_root, module_label.package),
        # Applies to headers of this target only but not headers/include_dirs
        # inherited from dependencies.
        direct_files = depset(transitive = [srcs_files, crate_root_files]),
        includes = ctx.attr.module_includes,
        linux_includes = ctx.attr.module_linux_includes,
    )]

    # Because of left-to-right ordering (DDK_INCLUDE_INFO_ORDER), kernel_build with
    # lowest priority is placed at the end of the list.
    transitive_include_info_targets = ctx.attr.module_deps + ctx.attr.module_hdrs
    if ctx.attr.kernel_build:
        transitive_include_info_targets.append(ctx.attr.kernel_build)

    include_infos = depset(
        direct_include_infos,
        transitive = get_ddk_transitive_include_infos(transitive_include_info_targets),
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

    module_srcs_ret = _handle_module_srcs(ctx, ddk_library_deps)

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

    copts_file = _handle_opts(
        ctx = ctx,
        file_name = "copts.json",
        opts = ctx.attr.module_copts,
        pre_opts_json = _get_autofdo_copts(ctx),
    )
    args.add("--copts-file", copts_file)

    removed_copts_file = _handle_opts(ctx, "removed_copts.json", ctx.attr.module_removed_copts)
    args.add("--removed-copts-file", removed_copts_file)

    asopts_file = _handle_opts(ctx, "asopts.json", ctx.attr.module_asopts)
    args.add("--asopts-file", asopts_file)

    linkopts_file = _handle_opts(ctx, "linkopts.json", ctx.attr.module_linkopts)
    args.add("--linkopts-file", linkopts_file)

    submodule_makefiles = depset(transitive = [dep.files for dep in submodule_deps])
    args.add_all("--submodule-makefiles", submodule_makefiles, expand_directories = False)

    if ctx.attr.internal_target_fail_message:
        args.add("--internal-target-fail-message", ctx.attr.internal_target_fail_message)

    if ctx.attr.target_type == "library":
        args.add("--is-library")

    if ctx.attr.module_pkvm_el2:
        args.add("--pkvm-el2-out", _PKVM_EL2_OUT)

    if VARS.get("KLEAF_INTERNAL_COPY_RULE_HACK") == "1":
        args.add("--copy-rule-hack")

    ctx.actions.run(
        mnemonic = "DdkMakefiles",
        inputs = depset([
            copts_file,
            removed_copts_file,
            asopts_file,
            linkopts_file,
            module_srcs_ret.srcs_json,
        ], transitive = [submodule_makefiles, module_srcs_ret.gen_srcs_depset]),
        outputs = [output_makefiles],
        executable = ctx.executable._gen_makefile,
        arguments = [args],
        progress_message = "Generating Makefile %{label}",
    )

    outs_depset = _get_outs_list(
        module_pkvm_el2 = ctx.attr.module_pkvm_el2,
        target_type = ctx.attr.target_type,
        src_matrix = module_srcs_ret.src_matrix,
        module_out = ctx.attr.module_out,
        submodule_deps = submodule_deps,
    )

    # All files needed to build this .ko file
    srcs_depset_transitive = [srcs_files, crate_root_files]
    srcs_depset_transitive += [dep[DdkSubmoduleInfo].srcs for dep in submodule_deps]

    # Add targets with DdkHeadersInfo in deps
    srcs_depset_transitive += [hdr[DdkHeadersInfo].files for hdr in hdr_deps]

    # Add all files from hdrs (use DdkHeadersInfo if available,
    #  otherwise use default files).
    srcs_depset_transitive.append(get_headers_depset(ctx.attr.module_hdrs))

    # Add ddk_module_headers files from kernel_build
    if ctx.attr.kernel_build:
        srcs_depset_transitive.append(ctx.attr.kernel_build[DdkHeadersInfo].files)

    if ctx.attr.module_autofdo_profile:
        srcs_depset_transitive.append(ctx.attr.module_autofdo_profile.files)

    ddk_headers_info = ddk_headers_common_impl(
        ctx.label,
        # hdrs of the ddk_module + hdrs of submodules.
        # Don't export kernel_build[DdkHeadersInfo] to avoid raising its priority;
        # dependent makefiles() target will put kernel_build[DdkHeadersInfo] at the end.
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
            outs = outs_depset,
            out = None if ctx.attr.target_type == "library" else ctx.attr.module_out,
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
        ModuleSymversFileInfo(
            module_symvers = depset(transitive = [
                target[ModuleSymversFileInfo].module_symvers
                for target in module_symvers_deps
            ]),
        ),
        ddk_headers_info,
    ]

makefiles = rule(
    implementation = _makefiles_impl,
    doc = "Generate `Makefile` and `Kbuild` files for `ddk_module`",
    attrs = {
        "kernel_build": attr.label(
            providers = [DdkHeadersInfo],
            # This is not set on ddk_submodule, but only on the overarching ddk_module.
            mandatory = False,
        ),
        # module_X is the X attribute of the ddk_module. Prefixed with `module_`
        # because they aren't real srcs / hdrs / deps to the makefiles rule.
        "module_srcs": attr.label_list(allow_files = DDK_MODULE_SRCS_ALLOWED_EXTENSIONS),
        # allow_files = True because https://github.com/bazelbuild/bazel/issues/7516
        "module_crate_root": attr.label(allow_single_file = True),
        "module_hdrs": attr.label_list(allow_files = True),
        "module_includes": attr.string_list(),
        "module_linux_includes": attr.string_list(),
        "module_deps": attr.label_list(),
        "module_out": attr.string(),
        "module_local_defines": attr.string_list(),
        "module_copts": attr.string_list(),
        "module_removed_copts": attr.string_list(),
        "module_asopts": attr.string_list(),
        "module_linkopts": attr.string_list(),
        "module_autofdo_profile": attr.label(allow_single_file = True),
        "module_debug_info_for_profiling": attr.bool(),
        "module_pkvm_el2": attr.bool(),
        "top_level_makefile": attr.bool(),
        "kbuild_has_linux_include": attr.bool(
            doc = "Whether to add LINUXINCLUDE to Kbuild",
            default = True,
        ),
        "internal_target_fail_message": attr.string(
            doc = "For testing only. Assert that this target to fail to build with the given message.",
        ),
        "target_type": attr.string(
            default = "module",
            values = [
                "module",
                "submodule",
                "library",
            ],
        ),
        "_gen_makefile": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/gen_makefiles",
            executable = True,
            cfg = "exec",
        ),
    },
    subrules = [
        _get_outs_list,
    ],
)
