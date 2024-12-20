# Copyright (C) 2023 The Android Open Source Project
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

"""A target that configures a [`ddk_module`](#ddk_module)."""

load(
    ":common_providers.bzl",
    "KernelBuildExtModuleInfo",
    "KernelSerializedEnvInfo",
)
load(":ddk/ddk_config/ddk_config_info_subrule.bzl", "ddk_config_info_subrule")
load(":ddk/ddk_config/ddk_config_main_action_subrule.bzl", "ddk_config_main_action_subrule")
load(":ddk/ddk_config/ddk_config_restore_out_dir_step.bzl", "ddk_config_restore_out_dir_step")
load(":ddk/ddk_config/ddk_config_script_subrule.bzl", "ddk_config_script_subrule")

visibility("//build/kernel/kleaf/...")

def _ddk_config_impl(ctx):
    ddk_config_info = ddk_config_info_subrule(
        kconfig_targets = [ctx.attr.kconfig] if ctx.attr.kconfig else [],
        defconfig_targets = [ctx.attr.defconfig] if ctx.attr.defconfig else [],
        deps = ctx.attr.module_deps + ctx.attr.module_hdrs,
        extra_defconfigs = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_module_defconfig_fragments,
    )

    main_action_ret = ddk_config_main_action_subrule(
        bin_dir_path = ctx.bin_dir.path,
        ddk_config_info = ddk_config_info,
        kernel_build_ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        defconfig_files = ctx.files.defconfig,
    )

    serialized_env_info = _create_serialized_env_info(
        ctx = ctx,
        out_dir = main_action_ret.out_dir,
    )

    menuconfig_ret = ddk_config_script_subrule(
        kernel_build_ddk_config_env = ctx.attr.kernel_build[KernelBuildExtModuleInfo].ddk_config_env,
        out_dir = main_action_ret.out_dir,
        main_action_ret = main_action_ret,
        src_defconfig = ctx.file.defconfig,
    )

    return [
        DefaultInfo(
            files = depset([main_action_ret.out_dir]),
            executable = menuconfig_ret.executable,
            runfiles = ctx.runfiles(transitive_files = menuconfig_ret.runfiles_depset),
        ),
        serialized_env_info,
        ddk_config_info,
    ]

def _create_serialized_env_info(ctx, out_dir):
    """Creates info for module build."""

    # Info from kernel_build
    if ctx.attr.generate_btf:
        # All outputs are required for BTF generation, including vmlinux image
        pre_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].mod_full_env
    else:
        pre_info = ctx.attr.kernel_build[KernelBuildExtModuleInfo].mod_min_env

    restore_out_dir_step = ddk_config_restore_out_dir_step(out_dir)

    # Overlay module-specific configs
    setup_script_cmd = """
        . {pre_setup_script}
        {restore_out_dir_cmd}
    """.format(
        pre_setup_script = pre_info.setup_script.path,
        restore_out_dir_cmd = restore_out_dir_step.cmd,
    )
    setup_script = ctx.actions.declare_file("{name}/{name}_setup.sh".format(name = ctx.attr.name))
    ctx.actions.write(
        output = setup_script,
        content = setup_script_cmd,
    )

    # KernelSerializedEnvInfo.tools is a depset[File] but restore_out_dir_step.tools is
    # a list of depset, File or FilesToRunProvider. Hence they can't be combined here. For now,
    # just assume restore_out_dir_step.tools is empty.
    # TODO: Properly combine them once KernelSerializedEnvInfo.tools is a list too.
    if restore_out_dir_step.tools:
        fail("restore_out_dir_step.tools should be empty, but is {}".format(restore_out_dir_step.tools))

    return KernelSerializedEnvInfo(
        setup_script = setup_script,
        inputs = depset([setup_script], transitive = [pre_info.inputs, restore_out_dir_step.inputs]),
        tools = pre_info.tools,
    )

ddk_config = rule(
    implementation = _ddk_config_impl,
    doc = "A target that configures a [`ddk_module`](#ddk_module).",
    attrs = {
        "kernel_build": attr.label(
            doc = "[`kernel_build`](#kernel_build).",
            providers = [
                KernelBuildExtModuleInfo,
            ],
            mandatory = True,
        ),
        "kconfig": attr.label(
            allow_single_file = True,
            doc = """The `Kconfig` file for this external module.

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
        "module_deps": attr.label_list(),
        # allow_files = True because https://github.com/bazelbuild/bazel/issues/7516
        "module_hdrs": attr.label_list(allow_files = True),
        "generate_btf": attr.bool(
            default = False,
            doc = "See [kernel_module.generate_btf](#kernel_module-generate_btf)",
        ),
    },
    subrules = [
        ddk_config_info_subrule,
        ddk_config_main_action_subrule,
        ddk_config_script_subrule,
        ddk_config_restore_out_dir_step,
    ],
    executable = True,
)
