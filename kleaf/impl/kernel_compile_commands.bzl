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

"""Support `compile_commands.json`."""

load(
    ":abi/abi_transitions.bzl",
    "FORCE_IGNORE_BASE_KERNEL_SETTING",
)
load(
    ":common_providers.bzl",
    "CompileCommandsInfo",
    "KernelEnvToolchainsInfo",
)
load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _kernel_compile_commands_transition_impl(_settings, _attr):
    return {
        FORCE_IGNORE_BASE_KERNEL_SETTING: True,
        "//build/kernel/kleaf/impl:build_compile_commands": True,
    }

_kernel_compile_commands_transition = transition(
    implementation = _kernel_compile_commands_transition_impl,
    inputs = [],
    outputs = [
        FORCE_IGNORE_BASE_KERNEL_SETTING,
        "//build/kernel/kleaf/impl:build_compile_commands",
    ],
)

def _kernel_compile_commands_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    if ctx.attr.kernel_build:
        # buildifier: disable=print
        print("WARNING: {}: kernel_compile_commands.kernel_build is deprecated. Use deps instead.".format(
            ctx.label,
        ))

    script = ctx.actions.declare_file(ctx.attr.name + ".sh")

    script_content = hermetic_tools.setup
    script_content += ctx.attr._toolchains[KernelEnvToolchainsInfo].setup_env_var_cmd

    # Handle rewritting clang path under user request
    #  using the option --real_clang_path
    script_content += """
        # Default values
        full_clang_path=0
        destination=

        # Parse command-line options
        while [[ ${#} -gt 0 ]]; do
          opt=${1}
          case "${opt}" in
            --real_clang_path)
              full_clang_path=1
              shift
              ;;
            *) # Positional argument
              if [[ -z "${destination}" ]]; then
                destination="${1}"
                shift
              else
                echo "ERROR: Too many positional arguments." >&2
                exit 1
              fi
              ;;
          esac
        done
    """

    script_content += """
        OUTPUT=${destination:-${BUILD_WORKSPACE_DIRECTORY}/compile_commands.json}
        : > ${OUTPUT}.tmp
    """

    direct_runfiles = []
    for dep in [ctx.attr.kernel_build] + ctx.attr.deps:
        if dep == None:  # ctx.attr.kernel_build may be None
            continue

        # This depset.to_list could be avoided with a dedicated script taking
        # arguments describing CompileCommandsInfo. However, for simplicity,
        # expand it at the analysis phase. The list shouldn't be more than
        # 1 + num(kernel_module).
        for info in dep[CompileCommandsInfo].infos.to_list():
            # A more robust way would be to parse the JSON list to concatenate them.
            # But this is good enough for now, and more efficient because you
            # don't need to load the whole JSON list to memory.
            script_content += """
                if [[ -s ${{OUTPUT}}.tmp ]]; then
                    echo ',' >> ${{OUTPUT}}.tmp
                fi
                sed -e '1d;$d' \\
                    -e "s:\\${{COMMON_OUT_DIR}}:${{BUILD_WORKSPACE_DIRECTORY}}/{compile_commands_common_out_dir}:g" \\
                    -e "s:\\${{ROOT_DIR}}:${{BUILD_WORKSPACE_DIRECTORY}}:g" \\
                    {compile_commands_with_vars} >> ${{OUTPUT}}.tmp
            """.format(
                compile_commands_with_vars = info.compile_commands_with_vars.short_path,
                compile_commands_common_out_dir = info.compile_commands_common_out_dir.path,
            )
            direct_runfiles.append(info.compile_commands_with_vars)

    # Handle full clang path rewrite if requested.
    script_content += """
        if [[ "${full_clang_path}" == "1" ]]; then
            real_clang_path=$(realpath $(which clang))
            sed -i "s:\\"command\\"\\: \\"clang:\\"command\\"\\: \\"${real_clang_path}:g" ${OUTPUT}.tmp
        fi
    """

    script_content += """
        echo '[' > ${OUTPUT}
        cat ${OUTPUT}.tmp >> ${OUTPUT}
        echo ']' >> ${OUTPUT}
        rm -f ${OUTPUT}.tmp
        echo "Written to ${OUTPUT}"
    """
    ctx.actions.write(script, script_content, is_executable = True)

    return DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(
            files = direct_runfiles,
            transitive_files = depset(
                transitive = [
                    hermetic_tools.deps,
                    ctx.attr._toolchains[KernelEnvToolchainsInfo].all_files,
                ],
            ),
        ),
    )

kernel_compile_commands = rule(
    implementation = _kernel_compile_commands_impl,
    doc = """Define an executable that creates `compile_commands.json` from kernel targets.""",
    attrs = {
        "kernel_build": attr.label(
            doc = """The `kernel_build` rule to extract from.

                Deprecated:
                    Use `deps` instead.
            """,
            providers = [CompileCommandsInfo],
        ),
        "deps": attr.label_list(
            doc = """The targets to extract from. The following are allowed:

                - [`kernel_build`](#kernel_build)
                - [`kernel_module`](#kernel_module)
                - [`ddk_module`](#ddk_module)
                - [`kernel_module_group`](#kernel_module_group)
            """,
            providers = [CompileCommandsInfo],
        ),
        # Allow any package to use kernel_compile_commands because it is a public API.
        # The ACK source tree may be checked out anywhere; it is not necessarily //common
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
        "_toolchains": attr.label(
            default = "//build/kernel/kleaf/impl:kernel_toolchains",
            providers = [KernelEnvToolchainsInfo],
            cfg = "exec",
        ),
    },
    executable = True,
    cfg = _kernel_compile_commands_transition,
    toolchains = [hermetic_toolchain.type],
)
