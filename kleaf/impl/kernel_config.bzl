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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":common_providers.bzl", "KernelEnvInfo")
load(":debug.bzl", "debug")
load(":stamp.bzl", "stamp")

def _determine_raw_symbollist_path(ctx):
    """A local action that stores the path to `abi_symbollist.raw` to a file object."""

    # Use a local action so we get an absolute path in the execroot that
    # does not tear down as sandbxes. Then write the absolute path into the
    # abi_symbollist.raw.abspath.
    #
    # In practice, the absolute path looks something like:
    #    /<workspace_root>/out/bazel/output_user_root/<hash>/execroot/__main__/bazel-out/k8-fastbuild/bin/common/kernel_aarch64_raw_kmi_symbol_list/abi_symbollist.raw
    #
    # Alternatively, we could use a relative path. However, gen_autoksyms.sh
    # interprets relative paths as paths relative to $abs_srctree, which
    # is $(realpath $ROOT_DIR/$KERNEL_DIR). The $abs_srctree is:
    # - A path within the sandbox for sandbox actions
    # - /<workspace_root>/$KERNEL_DIR for local actions
    # Whether KernelConfig is executed in a sandbox may not be consistent with
    # whether a dependant action is executed in a sandbox. This causes the
    # interpretation of CONFIG_UNUSED_KSYMS_WHITELIST inconsistent in the
    # two actions. Hence, we stick with absolute paths.
    #
    # NOTE: This may hurt remote caching for developer builds. We may want to
    # re-visit this when we implement remote caching for developers.
    abspath = ctx.actions.declare_file("{}/abi_symbollist.raw.abspath".format(ctx.attr.name))
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
      # Record the absolute path so we can use in .config
        readlink -e {raw_kmi_symbol_list} > {abspath}
    """.format(
        abspath = abspath.path,
        raw_kmi_symbol_list = ctx.file.raw_kmi_symbol_list.path,
    )
    ctx.actions.run_shell(
        command = command,
        inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + [ctx.file.raw_kmi_symbol_list],
        outputs = [abspath],
        mnemonic = "KernelConfigLocalRawSymbolList",
        progress_message = "Determining raw symbol list path for trimming {}".format(ctx.label),
        execution_requirements = {
            "local": "1",
        },
    )
    return abspath

def _kernel_config_impl(ctx):
    inputs = [
        s
        for s in ctx.files.srcs
        if any([token in s.path for token in [
            "Kbuild",
            "Kconfig",
            "Makefile",
            "configs/",
            "scripts/",
            ".fragment",
        ]])
    ]

    config = ctx.outputs.config
    include_dir = ctx.actions.declare_directory(ctx.attr.name + "_include")

    scmversion_command = stamp.scmversion_config_cmd(ctx)

    lto_config_flag = ctx.attr.lto[BuildSettingInfo].value

    lto_command = ""
    if lto_config_flag != "default":
        # none config
        lto_config = {
            "LTO_CLANG": "d",
            "LTO_NONE": "e",
            "LTO_CLANG_THIN": "d",
            "LTO_CLANG_FULL": "d",
            "THINLTO": "d",
        }
        if lto_config_flag == "thin":
            lto_config.update(
                LTO_CLANG = "e",
                LTO_NONE = "d",
                LTO_CLANG_THIN = "e",
                THINLTO = "e",
            )
        elif lto_config_flag == "full":
            lto_config.update(
                LTO_CLANG = "e",
                LTO_NONE = "d",
                LTO_CLANG_FULL = "e",
            )

        lto_command = """
            ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config {configs}
            make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
        """.format(configs = " ".join([
            "-%s %s" % (value, key)
            for key, value in lto_config.items()
        ]))

    if ctx.attr.trim_nonlisted_kmi and not ctx.file.raw_kmi_symbol_list:
        fail("{}: trim_nonlisted_kmi is set but raw_kmi_symbol_list is empty.".format(ctx.label))

    trim_kmi_command = ""
    if ctx.attr.trim_nonlisted_kmi:
        raw_symbol_list_path_file = _determine_raw_symbollist_path(ctx)
        trim_kmi_command = """
            # Modify .config to trim symbols not listed in KMI
              ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config \\
                  -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \\
                  --set-str UNUSED_KSYMS_WHITELIST $(cat {raw_symbol_list_path_file})
              make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
        """.format(
            raw_symbol_list_path_file = raw_symbol_list_path_file.path,
        )
        inputs.append(raw_symbol_list_path_file)

    command = ctx.attr.env[KernelEnvInfo].setup + """
        # Pre-defconfig commands
          eval ${{PRE_DEFCONFIG_CMDS}}
        # Actual defconfig
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{DEFCONFIG}}
        # Post-defconfig commands
          eval ${{POST_DEFCONFIG_CMDS}}
        # SCM version configuration
          {scmversion_command}
        # LTO configuration
        {lto_command}
        # Trim nonlisted symbols
          {trim_kmi_command}
        # HACK: run syncconfig to avoid re-triggerring kernel_build
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} syncconfig
        # Grab outputs
          rsync -aL ${{OUT_DIR}}/.config {config}
          rsync -aL ${{OUT_DIR}}/include/ {include_dir}/
        """.format(
        config = config.path,
        include_dir = include_dir.path,
        scmversion_command = scmversion_command,
        lto_command = lto_command,
        trim_kmi_command = trim_kmi_command,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelConfig",
        inputs = inputs,
        outputs = [config, include_dir],
        tools = ctx.attr.env[KernelEnvInfo].dependencies,
        progress_message = "Creating kernel config %s" % ctx.attr.name,
        command = command,
    )

    setup_deps = ctx.attr.env[KernelEnvInfo].dependencies + \
                 [config, include_dir]
    setup = ctx.attr.env[KernelEnvInfo].setup + """
         # Restore kernel config inputs
           mkdir -p ${{OUT_DIR}}/include/
           rsync -aL {config} ${{OUT_DIR}}/.config
           rsync -aL {include_dir}/ ${{OUT_DIR}}/include/
           find ${{OUT_DIR}}/include -type d -exec chmod +w {{}} \\;
    """.format(config = config.path, include_dir = include_dir.path)

    if ctx.attr.trim_nonlisted_kmi:
        # Ensure the dependent action uses the up-to-date abi_symbollist.raw
        # at the absolute path specified in abi_symbollist.raw.abspath
        setup_deps.append(ctx.file.raw_kmi_symbol_list)

    return [
        KernelEnvInfo(
            dependencies = setup_deps,
            setup = setup,
        ),
        DefaultInfo(files = depset([config, include_dir])),
    ]

kernel_config = rule(
    implementation = _kernel_config_impl,
    doc = "Defines a kernel config target that runs `make defconfig` etc.",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "config": attr.output(mandatory = True, doc = "the .config file"),
        "lto": attr.label(default = "//build/kernel/kleaf:lto"),
        "trim_nonlisted_kmi": attr.bool(doc = "If true, modify the config to trim non-listed symbols."),
        "raw_kmi_symbol_list": attr.label(
            doc = "Label to abi_symbollist.raw.",
            allow_single_file = True,
        ),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
