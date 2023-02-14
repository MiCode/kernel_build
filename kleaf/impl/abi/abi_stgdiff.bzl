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

"""
Run `stgdiff` tool.
"""

load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":debug.bzl", "debug")

STGDIFF_FORMATS = ["plain", "flat", "small", "short", "viz"]
STGDIFF_CHANGE_CODE = 4

def _stgdiff_impl(ctx):
    inputs = [
        ctx.file._stgdiff,
        ctx.file.baseline,
        ctx.file.new,
    ]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    output_dir = ctx.actions.declare_directory("{}/abi_stgdiff".format(ctx.attr.name))
    error_msg_file = ctx.actions.declare_file("{}/error_msg_file.txt".format(ctx.attr.name))
    exit_code_file = ctx.actions.declare_file("{}/exit_code_file.txt".format(ctx.attr.name))

    default_outputs = [output_dir]
    command_outputs = default_outputs + [
        error_msg_file,
        exit_code_file,
    ]
    basename = "{output_dir}/abi.report".format(output_dir = output_dir.path)
    short_report = basename + ".short"
    outputs = " ".join(["--format {ext} --output {basename}.{ext}".format(
        basename = basename,
        ext = ext,
    ) for ext in STGDIFF_FORMATS])

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        set +e
        {stgdiff}  --stg {baseline} {new} {outputs} > {error_msg_file}
        rc=$?
        set -e
        echo $rc > {exit_code_file}
        if [[ $rc == 0 ]]; then
            echo "INFO: $(cat {error_msg_file})"
        elif [[ $rc == {change_code} ]]; then
            echo "INFO: ABI DIFFERENCES HAVE BEEN DETECTED!"
            echo "INFO: $(cat {short_report})"
        else
            echo "ERROR: $(cat {error_msg_file})" >&2
            echo "INFO: exit code is not checked. 'tools/bazel run {label}' to check the exit code." >&2
        fi
    """.format(
        stgdiff = ctx.file._stgdiff.path,
        baseline = ctx.file.baseline.path,
        new = ctx.file.new.path,
        output_dir = output_dir.path,
        exit_code_file = exit_code_file.path,
        error_msg_file = error_msg_file.path,
        short_report = short_report,
        outputs = outputs,
        label = ctx.label,
        change_code = STGDIFF_CHANGE_CODE,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        mnemonic = "KernelDiffAbiStg",
        progress_message = "[stg] Comparing Kernel ABI {}".format(ctx.label),
    )

    script = ctx.actions.declare_file("{}/print_results.sh".format(ctx.attr.name))

    # TODO(b/265020068) Remove duplicate code here.
    short_report = "{output_dir}/abi.stg_report.short".format(output_dir = output_dir.short_path)
    script_content = """#!/bin/bash -e
        rc=$(cat {exit_code_file})
        if [[ $rc == 0 ]]; then
            echo "INFO: $(cat {error_msg_file})"
        elif [[ $rc == 4 ]]; then
            echo "INFO: ABI DIFFERENCES HAVE BEEN DETECTED!"
            echo "INFO: $(cat {short_report})"
        else
            echo "ERROR: $(cat {error_msg_file})" >&2
        fi
""".format(
        exit_code_file = exit_code_file.short_path,
        error_msg_file = error_msg_file.short_path,
        short_report = short_report,
    )
    if ctx.attr.kmi_enforced:
        script_content += """
            exit $rc
        """
    else:
        script_content += """
            if [[ $rc != 0 ]]; then
                echo "WARN: KMI is not enforced, return code of stgdiff is not checked" >&2
            fi
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
        ),
    ]

stgdiff = rule(
    implementation = _stgdiff_impl,
    doc = "Run `stgdiff`",
    attrs = {
        "baseline": attr.label(allow_single_file = True),
        "new": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
        "_hermetic_tools": attr.label(
            default = "//build/kernel:hermetic-tools",
            providers = [HermeticToolsInfo],
        ),
        "_stgdiff": attr.label(
            default = "//prebuilts/kernel-build-tools:linux-x86/bin/stgdiff",
            allow_single_file = True,
            cfg = "exec",
            executable = True,
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    executable = True,
)
