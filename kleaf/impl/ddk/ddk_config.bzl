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

"""A public target that can later be used to configure a [`ddk_module`](#ddk_module)."""

load(
    ":common_providers.bzl",
    "DdkConfigOutputsInfo",
    "KernelBuildExtModuleInfo",
)
load(":ddk/ddk_config/ddk_config_info_subrule.bzl", "ddk_config_info_subrule")
load(":ddk/ddk_config/ddk_config_main_action_subrule.bzl", "ddk_config_main_action_subrule")
load(":ddk/ddk_config/ddk_config_script_subrule.bzl", "ddk_config_script_subrule")

visibility("//build/kernel/kleaf/...")

def _ddk_config_impl(ctx):
    ddk_config_info = ddk_config_info_subrule(
        kconfig_targets = ctx.attr.kconfigs,
        defconfig_targets = [ctx.attr.defconfig] if ctx.attr.defconfig else [],
        deps = ctx.attr.deps,
        extra_defconfigs = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_module_defconfig_fragments,
        kernel_build_ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
    )

    main_action_ret = ddk_config_main_action_subrule(
        ddk_config_info = ddk_config_info,
        # ddk_config has no parent.
        parent = None,
        kernel_build_ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        defconfig_files = ctx.files.defconfig,
        override_parent = "deny",
    )

    menuconfig_ret = ddk_config_script_subrule(
        kernel_build_ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        out_dir = main_action_ret.out_dir,
        main_action_ret = main_action_ret,
        src_defconfig = ctx.file.defconfig,
    )

    default_info_files = []
    if main_action_ret.out_dir:
        default_info_files.append(main_action_ret.out_dir)
    if main_action_ret.kconfig_ext:
        default_info_files.append(main_action_ret.kconfig_ext)

    return [
        DefaultInfo(
            files = depset(default_info_files),
            executable = menuconfig_ret.executable,
            runfiles = ctx.runfiles(transitive_files = menuconfig_ret.runfiles_depset),
        ),
        ddk_config_info,
        DdkConfigOutputsInfo(
            out_dir = main_action_ret.out_dir,
            kconfig_ext = main_action_ret.kconfig_ext,
        ),
    ]

ddk_config = rule(
    implementation = _ddk_config_impl,
    doc = "**EXPERIMENTAL.** A target that can later be used to configure a [`ddk_module`](#ddk_module).",
    attrs = {
        "kernel_build": attr.label(
            doc = "[`kernel_build`](#kernel_build).",
            providers = [
                KernelBuildExtModuleInfo,
            ],
            mandatory = True,
        ),
        "kconfigs": attr.label_list(
            allow_files = True,
            doc = """The extra `Kconfig` files for external modules that use this config.

See
[`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
for its format.
""",
        ),
        "defconfig": attr.label(
            allow_single_file = True,
            doc = "The `defconfig` file.",
        ),
        # Needed to compose DdkConfigInfo
        "deps": attr.label_list(
            doc = "See [ddk_module.deps](#ddk_module-deps).",
        ),
    },
    subrules = [
        ddk_config_info_subrule,
        ddk_config_main_action_subrule,
        ddk_config_script_subrule,
    ],
    executable = True,
)
