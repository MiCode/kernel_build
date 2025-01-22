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

"""Creates a summary report from the kernel modules provided."""

load(":common_providers.bzl", "KernelBuildExtModuleInfo")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":utils.bzl", "utils")

visibility("//build/kernel/...")

def _modinfo_summary_report_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    modinfo_summary_xml = ctx.actions.declare_file(
        "{}/modinfo_summary.xml".format(ctx.label.name),
    )
    intermediates_dir = utils.intermediates_dir(ctx)
    inputs = [ctx.executable._modinfo_summary]
    modules_staging_archive_cmd = ""
    for slot, dep in enumerate(ctx.attr.deps):
        modules_staging_archive = dep[KernelBuildExtModuleInfo].modules_staging_archive
        modules_staging_archive_cmd += """
        mkdir -p {intermediates_dir}/temp_{slot}
        tar xf {modules_staging_archive} -C {intermediates_dir}/temp_{slot}
        """.format(
            modules_staging_archive = modules_staging_archive.path,
            intermediates_dir = intermediates_dir,
            slot = slot,
        )
        inputs.append(modules_staging_archive)
    command = hermetic_tools.setup + """
        {modules_staging_archive_cmd}
        # Run the reporter
        {modinfo_summary} --directory {intermediates_dir} --output {modinfo_summary_xml}
        rm -rf {intermediates_dir}
    """.format(
        modinfo_summary = ctx.executable._modinfo_summary.path,
        modules_staging_archive_cmd = modules_staging_archive_cmd,
        modinfo_summary_xml = modinfo_summary_xml.path,
        intermediates_dir = intermediates_dir,
    )

    ctx.actions.run_shell(
        mnemonic = "ModinfoSummary",
        inputs = inputs,
        command = command,
        outputs = [modinfo_summary_xml],
        progress_message = "Creating modinfo summary %{label}",
        tools = [ctx.executable._modinfo_summary, hermetic_tools.deps],
    )
    return DefaultInfo(files = depset([modinfo_summary_xml]))

modinfo_summary_report = rule(
    implementation = _modinfo_summary_report_impl,
    doc = "Generate a report from kernel modules of the given kernel build.",
    attrs = {
        "deps": attr.label_list(providers = [KernelBuildExtModuleInfo]),
        "_modinfo_summary": attr.label(
            default = "//build/kernel:modinfo_summary",
            cfg = "exec",
            executable = True,
        ),
    },
    toolchains = [hermetic_toolchain.type],
)
