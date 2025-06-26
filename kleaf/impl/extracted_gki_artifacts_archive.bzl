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

"""Extract GKI artifacts from the boot.img archive."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")
load(":utils.bzl", "utils")

# Visible to repositories of kernel_prebuilt_repo
visibility("public")

def _extracted_gki_artifacts_archive_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    out_files = {}
    for out_rel_path in ctx.attr.outs:
        out_files[out_rel_path] = ctx.actions.declare_file(paths.join(ctx.attr.name, out_rel_path))

    intermediates_dir = utils.intermediates_dir(ctx)

    cmd = hermetic_tools.setup + """
        mkdir -p {intermediates_dir}
        tar xf {src} -C {intermediates_dir}
    """.format(
        intermediates_dir = intermediates_dir,
        src = ctx.file.src.path,
    )

    for out_rel_path, out_file in out_files.items():
        cmd += """
            mkdir -p $(dirname {out_file})
            cp {intermediates_dir}/{out_rel_path} {out_file}
        """.format(
            out_file = out_file.path,
            intermediates_dir = intermediates_dir,
            out_rel_path = out_rel_path,
        )

    ctx.actions.run_shell(
        mnemonic = "ExtractedGkiArtifactsArchive",
        inputs = [ctx.file.src],
        outputs = out_files.values(),
        tools = hermetic_tools.deps,
        progress_message = "Extracting GKI artifacts from boot-img.tar.gz %{label}",
        command = cmd,
    )

    return [DefaultInfo(files = depset(out_files.values()))]

extracted_gki_artifacts_archive = rule(
    doc = """Extract artifacts from the boot.img archive.""",
    implementation = _extracted_gki_artifacts_archive_impl,
    attrs = {
        "src": attr.label(
            doc = "boot-img.tar.gz",
            allow_single_file = True,
            mandatory = True,
        ),
        "outs": attr.string_list(doc = "output files"),
        "_search_and_cp_output": attr.label(
            default = Label("//build/kernel/kleaf:search_and_cp_output"),
            cfg = "exec",
            executable = True,
            doc = "label referring to the script to process outputs",
        ),
    },
    toolchains = [hermetic_toolchain.type],
)
