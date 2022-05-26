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
load(
    ":common_providers.bzl",
    "KernelUnstrippedModulesInfo",
)
load(":debug.bzl", "debug")

def _kernel_unstripped_modules_archive_impl(ctx):
    kernel_build = ctx.attr.kernel_build
    base_kernel = kernel_build[KernelUnstrippedModulesInfo].base_kernel if kernel_build else None

    # Early elements = higher priority. In-tree modules from base_kernel has highest priority,
    # then in-tree modules of the device kernel_build, then external modules (in an undetermined
    # order).
    # TODO(b/228557644): kernel module names should not collide. Detect collsions.
    srcs = []
    for kernel_build_object in (base_kernel, kernel_build):
        if not kernel_build_object:
            continue
        directory = kernel_build_object[KernelUnstrippedModulesInfo].directory
        if not directory:
            fail("{} does not have collect_unstripped_modules = True.".format(kernel_build_object.label))
        srcs.append(directory)
    for kernel_module in ctx.attr.kernel_modules:
        srcs.append(kernel_module[KernelUnstrippedModulesInfo].directory)

    inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + srcs

    out_file = ctx.actions.declare_file("{}/unstripped_modules.tar.gz".format(ctx.attr.name))
    unstripped_dir = ctx.genfiles_dir.path + "/unstripped"

    command = ""
    command += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    command += """
        mkdir -p {unstripped_dir}
    """.format(unstripped_dir = unstripped_dir)

    # Copy the source ko files in low to high priority order.
    for src in reversed(srcs):
        # src could be empty, so use find + cp
        command += """
            find {src} -name '*.ko' -exec cp -l -t {unstripped_dir} {{}} +
        """.format(
            src = src.path,
            unstripped_dir = unstripped_dir,
        )

    command += """
        tar -czhf {out_file} -C $(dirname {unstripped_dir}) $(basename {unstripped_dir})
    """.format(
        out_file = out_file.path,
        unstripped_dir = unstripped_dir,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Compressing unstripped modules {}".format(ctx.label),
        command = command,
        mnemonic = "KernelUnstrippedModulesArchive",
    )
    return DefaultInfo(files = depset([out_file]))

kernel_unstripped_modules_archive = rule(
    implementation = _kernel_unstripped_modules_archive_impl,
    doc = """Compress the unstripped modules into a tarball.

This is the equivalent of `COMPRESS_UNSTRIPPED_MODULES=1` in `build.sh`.

Add this target to a `copy_to_dist_dir` rule to copy it to the distribution
directory, or `DIST_DIR`.
""",
    attrs = {
        "kernel_build": attr.label(
            doc = """A [`kernel_build`](#kernel_build) to retrieve unstripped in-tree modules from.

It requires `collect_unstripped_modules = True`. If the `kernel_build` has a `base_kernel`, the rule
also retrieves unstripped in-tree modules from the `base_kernel`, and requires the
`base_kernel` has `collect_unstripped_modules = True`.
""",
            providers = [KernelUnstrippedModulesInfo],
        ),
        "kernel_modules": attr.label_list(
            doc = """A list of external [`kernel_module`](#kernel_module)s to retrieve unstripped external modules from.

It requires that the base `kernel_build` has `collect_unstripped_modules = True`.
""",
            providers = [KernelUnstrippedModulesInfo],
        ),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
