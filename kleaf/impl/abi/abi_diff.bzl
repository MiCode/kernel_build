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

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":debug.bzl", "debug")

def _abi_diff_impl(ctx):
    inputs = [
        ctx.file._diff_abi,
        ctx.file.baseline,
        ctx.file.new,
    ]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    inputs += ctx.files._diff_abi_scripts

    output_dir = ctx.actions.declare_directory("{}/abi_diff".format(ctx.attr.name))
    error_msg_file = ctx.actions.declare_file("{}/error_msg_file".format(ctx.attr.name))
    exit_code_file = ctx.actions.declare_file("{}/exit_code_file".format(ctx.attr.name))
    git_msg_file = ctx.actions.declare_file("{}/git_message.txt".format(ctx.attr.name))
    default_outputs = [output_dir]

    command_outputs = default_outputs + [
        error_msg_file,
        exit_code_file,
        git_msg_file,
    ]

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        set +e
        {diff_abi} --baseline {baseline}                \\
                   --new      {new}                     \\
                   --report   {output_dir}/abi.report   \\
                   --abi-tool delegated > {error_msg_file} 2>&1
        rc=$?
        set -e
        echo $rc > {exit_code_file}

        : > {git_msg_file}
        if [[ -f {output_dir}/abi.report.short ]]; then
          cat >> {git_msg_file} <<EOF
ANDROID: <TODO subject line>

<TODO commit message>

$(cat {output_dir}/abi.report.short)

Bug: <TODO bug number>
EOF
        else
            echo "WARNING: No short report found. Unable to infer the git commit message." >&2
        fi
        if [[ $rc == 0 ]]; then
            echo "INFO: $(cat {error_msg_file})"
        else
            echo "ERROR: $(cat {error_msg_file})" >&2
            echo "INFO: exit code is not checked. 'tools/bazel run {label}' to check the exit code." >&2
        fi
    """.format(
        diff_abi = ctx.file._diff_abi.path,
        baseline = ctx.file.baseline.path,
        new = ctx.file.new.path,
        output_dir = output_dir.path,
        exit_code_file = exit_code_file.path,
        error_msg_file = error_msg_file.path,
        git_msg_file = git_msg_file.path,
        label = ctx.label,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        mnemonic = "KernelDiffAbi",
        progress_message = "Comparing ABI {}".format(ctx.label),
    )

    script = ctx.actions.declare_file("{}/print_results.sh".format(ctx.attr.name))
    script_content = """#!/bin/bash -e
        rc=$(cat {exit_code_file})
        if [[ $rc == 0 ]]; then
            echo "INFO: $(cat {error_msg_file})"
        else
            echo "ERROR: $(cat {error_msg_file})" >&2
        fi
""".format(
        exit_code_file = exit_code_file.short_path,
        error_msg_file = error_msg_file.short_path,
    )
    if ctx.attr.kmi_enforced:
        script_content += """
            exit $rc
        """
    ctx.actions.write(script, script_content, is_executable = True)

    return [
        DefaultInfo(
            files = depset(default_outputs),
            executable = script,
            runfiles = ctx.runfiles(files = command_outputs),
        ),
        OutputGroupInfo(
            executable = depset([script]),
            git_message = depset([git_msg_file]),
        ),
    ]

abi_diff = rule(
    implementation = _abi_diff_impl,
    doc = "Run `diff_abi`",
    attrs = {
        "baseline": attr.label(allow_single_file = True),
        "new": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_diff_abi_scripts": attr.label(default = "//build/kernel:diff-abi-scripts"),
        "_diff_abi": attr.label(default = "//build/kernel:abi/diff_abi", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    executable = True,
)
