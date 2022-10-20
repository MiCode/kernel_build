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

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
)
load(":kernel_module.bzl", "kernel_module")
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo", "ddk_headers")
load(":ddk/makefiles.bzl", "makefiles")

def ddk_module(
        name,
        kernel_build,
        srcs,
        deps = None,
        hdrs = None,
        includes = None,
        out = None,
        **kwargs):
    """
    Defines a DDK (Driver Development Kit) module.

    Example:

    ```
    ddk_module(
        name = "my_module",
        srcs = ["my_module.c", "private_header.h"],
        # Exported headers
        hdrs = ["include/my_module_exported.h"],
        includes = ["include"],
    )
    ```

    Note: Local headers should be specified in one of the following ways:

    - In a `ddk_headers` target in the same package, if you need to auto-generate `-I` ccflags.
      In that case, specify the `ddk_headers` target in `deps`.
    - Otherwise, in `srcs` if you don't need the `-I` ccflags.

    Exported headers should be specified in one of the following ways:

    - In a separate `ddk_headers` target in the same package. Then specify the
      target in `hdrs`. This is recommended if there
      are multiple `ddk_module`s depending on a
      [`glob`](https://bazel.build/reference/be/functions#glob) of headers or a large list
      of headers.
    - Using `hdrs` and `includes` of this target.

    `hdrs` and `includes` have the same semantics as [`ddk_headers`](#ddk_headers). That is,
    this target effectively acts as a `ddk_headers` target when specified in the `deps` attribute
    of another `ddk_module`. In other words, the following code snippet:

    ```
    ddk_module(name = "module_A", hdrs = [...], includes = [...], ...)
    ddk_module(name = "module_B", deps = ["module_A"], ...)
    ```

    ... is effectively equivalent to the following:

    ```
    ddk_headers(name = "module_A_hdrs, hdrs = [...], includes = [...], ...)
    ddk_module(name = "module_A", ...)
    ddk_module(name = "module_B", deps = ["module_A", "module_A_hdrs"], ...)
    ```

    Args:
        name: Name of target. This should usually be name of the output `.ko` file without the
          suffix.
        srcs: sources and local headers.
        deps: A list of dependent targets. Each of them must be one of the following:

            - [`kernel_module`](#kernel_module)
            - [`ddk_module`](#ddk_module)
            - [`ddk_headers`](#ddk_headers).
        hdrs: See [`ddk_headers.hdrs`](#ddk_headers-hdrs)
        includes: See [`ddk_headers.includes`](#ddk_headers-includes)
        kernel_build: [`kernel_build`](#kernel_build)
        out: The output module file. By default, this is `"{name}.ko"`.
        kwargs: Additional attributes to the internal rule.
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if out == None:
        out = "{}.ko".format(name)

    kernel_module(
        name = name,
        kernel_build = kernel_build,
        srcs = srcs,
        deps = deps,
        outs = [out],
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_module_symvers_name = "{name}_Module.symvers".format(name = name),
        internal_drop_modules_order = True,
        internal_exclude_kernel_build_module_srcs = True,
        internal_hdrs = hdrs,
        internal_includes = includes,
        **kwargs
    )

    private_kwargs = dict(kwargs)
    private_kwargs["visibility"] = ["//visibility:private"]

    makefiles(
        name = name + "_makefiles",
        module_srcs = srcs,
        module_hdrs = hdrs,
        module_includes = includes,
        module_out = out,
        module_deps = deps,
        **private_kwargs
    )
