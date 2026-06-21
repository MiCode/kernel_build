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

load(
    ":common_providers.bzl",
    "KernelBuildInfo",
    "KernelEnvInfo",
)
load(":srcs_aspect.bzl", "SrcsInfo", "srcs_aspect")
load(":utils.bzl", "utils")

def _kernel_kythe_impl(ctx):
    compile_commands = ctx.file.compile_commands
    all_kzip = ctx.actions.declare_file(ctx.attr.name + "/all.kzip")
    runextractor_error = ctx.actions.declare_file(ctx.attr.name + "/runextractor_error.log")
    intermediates_dir = utils.intermediates_dir(ctx)
    kzip_dir = intermediates_dir + "/kzip"
    extracted_kzip_dir = intermediates_dir + "/extracted"
    transitive_inputs = [src.files for src in ctx.attr.kernel_build[SrcsInfo].srcs]
    inputs = [compile_commands]
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    command = ctx.attr.kernel_build[KernelEnvInfo].setup
    command += """
             # Copy compile_commands.json to root
               cp {compile_commands} ${{ROOT_DIR}}
             # Prepare directories
               mkdir -p {kzip_dir} {extracted_kzip_dir} ${{OUT_DIR}}
             # Define env variables
               export KYTHE_ROOT_DIRECTORY=${{ROOT_DIR}}
               export KYTHE_OUTPUT_DIRECTORY={kzip_dir}
               export KYTHE_CORPUS="{corpus}"
             # Generate kzips
               runextractor compdb -extractor $(which cxx_extractor) 2> {runextractor_error} || true

             # Package it all into a single .kzip, ignoring duplicates.
               for zip in $(find {kzip_dir} -name '*.kzip'); do
                   unzip -qn "${{zip}}" -d {extracted_kzip_dir}
               done
               soong_zip -C {extracted_kzip_dir} -D {extracted_kzip_dir} -o {all_kzip}
             # Clean up directories
               rm -rf {kzip_dir}
               rm -rf {extracted_kzip_dir}
    """.format(
        compile_commands = compile_commands.path,
        kzip_dir = kzip_dir,
        extracted_kzip_dir = extracted_kzip_dir,
        corpus = ctx.attr.corpus,
        all_kzip = all_kzip.path,
        runextractor_error = runextractor_error.path,
    )
    ctx.actions.run_shell(
        mnemonic = "KernelKythe",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [all_kzip, runextractor_error],
        command = command,
        progress_message = "Building Kythe source code index (kzip) {}".format(ctx.label),
    )

    return DefaultInfo(files = depset([
        all_kzip,
        runextractor_error,
    ]))

kernel_kythe = rule(
    implementation = _kernel_kythe_impl,
    doc = """
Extract Kythe source code index (kzip file) from a `kernel_build`.
    """,
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            doc = "The `kernel_build` target to extract from.",
            providers = [KernelEnvInfo, KernelBuildInfo],
            aspects = [srcs_aspect],
        ),
        "compile_commands": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The `compile_commands.json`, or a `kernel_compile_commands` target.",
        ),
        "corpus": attr.string(
            default = "android.googlesource.com/kernel/superproject",
            doc = "The value of `KYTHE_CORPUS`. See [kythe.io/examples](https://kythe.io/examples).",
        ),
    },
)
