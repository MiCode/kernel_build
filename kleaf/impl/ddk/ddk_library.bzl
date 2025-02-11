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

"""Rules for defining a DDK (Driver Development Kit) library."""

load(":ddk/ddk_module_config.bzl", "ddk_module_config")
load(":ddk/makefiles.bzl", "makefiles")
load(":kernel_module.bzl", "kernel_module")

visibility("//build/kernel/kleaf/...")

def ddk_library(
        name,
        kernel_build,
        srcs = None,
        deps = None,
        hdrs = None,
        includes = None,
        linux_includes = None,
        local_defines = None,
        copts = None,
        removed_copts = None,
        asopts = None,
        config = None,
        kconfig = None,
        defconfig = None,
        autofdo_profile = None,
        debug_info_for_profiling = None,
        pkvm_el2 = None,
        **kwargs):
    """**EXPERIMENTAL**. A library that may be used by a DDK module.

    The library has its own list of dependencies, flags that are usually local, and
    not exported to the `ddk_module` using it. However, `hdrs`, `includes`,
    kconfig and defconfig are exported.

    Known issues:
        - (b/392186874) The generated .o.cmd files contain absolute paths and are not reproducible.
        - (b/394411899) kernel_compile_commands() doesn't work on ddk_library yet.
        - (b/395014894) All ddk_module() dependency in ddk_library.deps must be duplicated
            in the ddk_module() that depends on this ddk_library.

    Args:
        name: name of module
        kernel_build: [`kernel_build`](#kernel_build)
        srcs: see [`ddk_module.srcs`](#ddk_module-srcs)
        deps: see [`ddk_module.deps`](#ddk_module-deps).
            [`ddk_submodule`](#ddk_submodule)s are not allowed.
        hdrs: see [`ddk_module.hdrs`](#ddk_module-hdrs)
        includes: see [`ddk_module.includes`](#ddk_module-includes)
        linux_includes: see [`ddk_module.linux_includes`](#ddk_module-linux_includes)
        local_defines: see [`ddk_module.local_defines`](#ddk_module-local_defines)
        copts: see [`ddk_module.copts`](#ddk_module-copts)
        removed_copts: see [`ddk_module.removed_copts`](#ddk_module-removed_copts)
        asopts: see [`ddk_module.asopts`](#ddk_module-asopts)
        config: see [`ddk_module.config`](#ddk_module-config)
        kconfig: see [`ddk_module.kconfig`](#ddk_module-kconfig)
        defconfig: see [`ddk_module.defconfig`](#ddk_module-defconfig)
        autofdo_profile: see [`ddk_module.autofdo_profile`](#ddk_module-autofdo_profile)
        debug_info_for_profiling: see [`ddk_module.debug_info_for_profiling`](#ddk_module-debug_info_for_profiling)
        pkvm_el2: **EXPERIMENTAL**. If True, builds EL2 hypervisor code.

            If True:
            - The output list is the fixed `["kvm_nvhe.o"]`, plus relevant .o.cmd files
            - The generated Makefile is modified to build EL2 hypervisor code.

            Note: This is only supported in selected branches.
        **kwargs: Additional attributes to the internal rule.
            See complete list
            [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    private_kwargs = dict(kwargs)
    private_kwargs["visibility"] = ["//visibility:private"]

    makefiles(
        name = name + "_makefiles",
        kernel_build = kernel_build,
        module_srcs = srcs,
        module_hdrs = hdrs,
        module_includes = includes,
        module_linux_includes = linux_includes,
        module_out = name + ".ko",  # fake value
        module_deps = deps,
        module_local_defines = local_defines,
        module_copts = copts,
        module_removed_copts = removed_copts,
        module_asopts = asopts,
        module_autofdo_profile = autofdo_profile,
        module_debug_info_for_profiling = debug_info_for_profiling,
        module_pkvm_el2 = pkvm_el2,
        top_level_makefile = True,
        kbuild_has_linux_include = True,
        target_type = "library",
        **private_kwargs
    )

    ddk_module_config(
        name = name + "_config",
        parent = config,
        defconfig = defconfig,
        kconfig = kconfig,
        kernel_build = kernel_build,
        module_deps = deps,
        module_hdrs = hdrs,
        **private_kwargs
    )

    kernel_module(
        name = name,
        kernel_build = kernel_build,
        srcs = [],
        # Set it to empty list, not None, so kernel_module() doesn't fallback to {name}.ko.
        # _kernel_module_impl infers the list of outs from internal_ddk_makefiles_dir.
        outs = [],
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        internal_exclude_kernel_build_module_srcs = True,
        internal_ddk_config = name + "_config",
        internal_is_ddk_library = True,
        internal_extra_make_goals = ["kleaf-objects"],
        internal_compdb = "skip",
        internal_modules_install = False,
        internal_mnemonic = "DDK library",
        **kwargs
    )
