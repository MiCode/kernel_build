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

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":common_providers.bzl", "KernelEnvInfo", "ModuleSymversInfo")
load(":debug.bzl", "debug")
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo", "get_include_depset")
load(":utils.bzl", "utils")

def _makefiles_impl(ctx):
    module_label = Label(str(ctx.label).removesuffix("_makefiles"))

    output_makefiles = ctx.actions.declare_directory("{}/makefiles".format(ctx.attr.name))

    kernel_module_deps = []
    for dep in ctx.attr.module_deps:
        if ModuleSymversInfo in dep:
            kernel_module_deps.append(dep)
            continue
        if DdkHeadersInfo not in dep:
            fail("{}: {} is not a valid item in deps. It does not provide ModuleSymversInfo or DdkHeadersInfo".format(
                module_label,
                dep.label,
            ))

    include_dirs = get_include_depset(
        module_label,
        ctx.attr.module_deps + ctx.attr.module_hdrs,
        ctx.attr.module_includes,
    )

    args = ctx.actions.args()

    # Though flag_per_line is designed for the absl flags library and
    # gen_makefiles.py uses absl flags library, this outputs the following
    # in the output params file:
    #   --foo=value1 value2
    # ... which is interpreted as --foo="value1 value2" instead of storing
    # individual values. Hence, use multiline so the output becomes:
    #   --foo
    #   value1
    #   value2
    args.set_param_file_format("multiline")
    args.use_param_file("--flagfile=%s")

    args.add_all("--kernel-module-srcs", ctx.files.module_srcs)
    args.add("--kernel-module-out", ctx.attr.module_out)
    args.add("--output-makefiles", output_makefiles.path)
    args.add("--package", ctx.label.package)

    args.add_all("--include-dirs", include_dirs, uniquify = True)

    args.add_all(
        "--module-symvers-list",
        [kernel_module[ModuleSymversInfo].restore_path for kernel_module in kernel_module_deps],
    )

    ctx.actions.run(
        outputs = [output_makefiles],
        executable = ctx.executable._gen_makefile,
        arguments = [args],
        progress_message = "Generating Makefile {}".format(ctx.label),
    )

    return DefaultInfo(files = depset([output_makefiles]))

makefiles = rule(
    implementation = _makefiles_impl,
    doc = "Generate `Makefile` and `Kbuild` files for `ddk_module`",
    attrs = {
        # module_X is the X attribute of the ddk_module. Prefixed with `module_`
        # because they aren't real srcs / hdrs / deps to the makefiles rule.
        "module_srcs": attr.label_list(allow_files = [".c", ".h", ".s", ".rs"]),
        "module_hdrs": attr.label_list(allow_files = [".h"]),
        "module_includes": attr.string_list(),
        "module_deps": attr.label_list(),
        "module_out": attr.string(),
        "_gen_makefile": attr.label(
            default = "//build/kernel/kleaf/impl:ddk/gen_makefiles",
            executable = True,
            cfg = "exec",
        ),
    },
)
