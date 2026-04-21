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

"""Headers target for DDK."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load(":common_providers.bzl", "DdkIncludeInfo")
load(":ddk/ddk_config_subrule.bzl", "ddk_config_subrule")

visibility("//build/kernel/kleaf/...")

# At this time of writing (2022-11-01), this is what cc_library does;
# includes of this target, then includes of deps
DDK_INCLUDE_INFO_ORDER = "preorder"

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

def get_extra_include_roots(headers):
    """Given a list of headers, return a list of include roots.

    For each header in headers, drop short_path from path to get an include_root.
    Then return all include_roots.

    Args:
        headers: A list of headers.
    Returns:
        include roots to be prepended to include_dirs.
    """

    return sets.to_list(sets.make([header.root.path for header in headers]))

def get_ddk_transitive_include_infos(deps):
    """Returns a depset containing include directories from the list of dependencies.

    Args:
        deps: A list of depended targets. If [`DdkHeadersInfo`](#DdkHeadersInfo) is in the target,
          their `includes` are included in the returned depset.
    Returns:
        A depset containing include directories from the list of dependencies.
    """

    transitive = []
    for dep in deps:
        if DdkHeadersInfo in dep:
            transitive.append(dep[DdkHeadersInfo].include_infos)
    return transitive

def _check_includes(includes):
    for include_dir in includes:
        if paths.normalize(include_dir) != include_dir:
            fail(
                "include directory {} is not normalized to {}".format(
                    include_dir,
                    paths.normalize(include_dir),
                ),
            )
        if paths.is_absolute(include_dir):
            fail("Absolute directories not allowed in includes: {}".format(include_dir))
        if include_dir == ".." or include_dir.startswith("../"):
            fail("Invalid include directory: {}".format(include_dir))

def get_headers_depset(deps):
    """Returns a depset containing headers from the list of dependencies

    Args:
        deps: A list of depended targets. If [`DdkHeadersInfo`](#DdkHeadersInfo) is in the target,
          `target[DdkHeadersInfo].files` are included in the returned depset. Otherwise
          the default output files are included in the returned depset.
    Returns:
        A depset containing headers from the list of dependencies.
    """
    transitive_deps = []

    for dep in deps:
        if DdkHeadersInfo in dep:
            transitive_deps.append(dep[DdkHeadersInfo].files)
        else:
            transitive_deps.append(dep.files)

    return depset(transitive = transitive_deps)

def ddk_headers_common_impl(label, hdrs, includes, linux_includes):
    """Common implementation for rules that returns `DdkHeadersInfo`.

    Args:
        label: Label of this target.
        hdrs: The list of exported headers, e.g. [`ddk_headers.hdrs`](#ddk_headers-hdrs)
        includes: The list of exported include directories, e.g. [`ddk_headers.includes`](#ddk_headers-includes)
        linux_includes: Like `includes` but added to `LINUXINCLUDE`.
    Returns:
        DdkHeadersInfo
    """

    _check_includes(includes)
    _check_includes(linux_includes)

    direct_include_infos = []
    if includes or linux_includes:
        direct_include_infos.append(DdkIncludeInfo(
            prefix = paths.join(label.workspace_root, label.package),
            direct_files = depset(),

            # Turn lists into tuples because lists are mutable, making DdkIncludeInfo
            # mutable and unable to be placed in a depset.
            includes = tuple(includes),
            linux_includes = tuple(linux_includes),
        ))

    return DdkHeadersInfo(
        files = get_headers_depset(hdrs),
        include_infos = depset(
            direct_include_infos,
            transitive = get_ddk_transitive_include_infos(hdrs),
            order = DDK_INCLUDE_INFO_ORDER,
        ),
    )

def _ddk_headers_impl(ctx):
    ddk_headers_info = ddk_headers_common_impl(
        ctx.label,
        ctx.attr.hdrs + ctx.attr.textual_hdrs,
        ctx.attr.includes,
        ctx.attr.linux_includes,
    )

    ddk_config_info = ddk_config_subrule(
        kconfig_targets = ctx.attr.kconfigs,
        defconfig_targets = ctx.attr.defconfigs,
        deps = ctx.attr.hdrs + ctx.attr.textual_hdrs,
    )

    return [
        DefaultInfo(files = ddk_headers_info.files),
        ddk_headers_info,
        ddk_config_info,
    ]

ddk_headers = rule(
    implementation = _ddk_headers_impl,
    doc = """A rule that exports a list of header files to be used in DDK.

Example:

```
ddk_headers(
   name = "headers",
   hdrs = ["include/module.h", "template.c"],
   includes = ["include"],
)
```

`ddk_headers` can be chained; that is, a `ddk_headers` target can re-export
another `ddk_headers` target. For example:

```
ddk_headers(
   name = "foo",
   hdrs = ["include_foo/foo.h"],
   includes = ["include_foo"],
)
ddk_headers(
   name = "headers",
   hdrs = [":foo", "include/module.h"],
   includes = ["include"],
)
```
""",
    attrs = {
        # allow_files = True because https://github.com/bazelbuild/bazel/issues/7516
        "hdrs": attr.label_list(allow_files = True, doc = """One of the following:

- Local header files to be exported. You may also need to set the `includes` attribute.
- Other `ddk_headers` targets to be re-exported.
"""),
        # TODO: remove textual_hdrs in future
        "textual_hdrs": attr.label_list(
            allow_files = True,
            doc = """DEPRECATED. Use `hdrs` instead.

The list of header files to be textually included by sources.

This is the location for declaring header files that cannot be compiled on their own;
that is, they always need to be textually included by other source files to build valid code.
""",
        ),
        "includes": attr.string_list(
            doc = """A list of directories, relative to the current package, that are re-exported as include directories.

[`ddk_module`](#ddk_module) with `deps` including this target automatically
adds the given include directory in the generated `Kbuild` files.

You still need to add the actual header files to `hdrs`.
""",
        ),
        "linux_includes": attr.string_list(
            doc = """Like `includes` but specified in `LINUXINCLUDES` instead.

Setting this attribute allows you to override headers from `${KERNEL_DIR}`. See "Order of includes"
in [`ddk_module`](#ddk_module) for details.

Like `includes`, `linux_includes` is applied to dependent `ddk_module`s.
""",
        ),
        "kconfigs": attr.label_list(
            allow_files = True,
            doc = """Kconfig files.

                See
                [`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
                for its format.

                Kconfig is optional for a `ddk_module`. The final Kconfig known by
                this module consists of the following:

                - Kconfig from `kernel_build`
                - Kconfig from dependent modules, if any
                - Kconfig of this module, if any
          """,
        ),
        "defconfigs": attr.label_list(
            allow_files = True,
            doc = """`defconfig` files.

                Items must already be declared in `kconfigs`. An item not declared
                in Kconfig and inherited Kconfig files is silently dropped.

                An item declared in `kconfigs` without a specific value in `defconfigs`
                uses default value specified in `kconfigs`.
            """,
        ),
    },
    subrules = [ddk_config_subrule],
)
