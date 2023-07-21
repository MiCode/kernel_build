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
"""
Provide tools for a hermetic build.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//build/kernel/kleaf/impl:hermetic_exec.bzl",
    _hermetic_exec = "hermetic_exec",
    _hermetic_exec_test = "hermetic_exec_test",
)
load("//build/kernel/kleaf/impl:hermetic_genrule.bzl", _hermetic_genrule = "hermetic_genrule")
load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", _hermetic_toolchain = "hermetic_toolchain")

# Re-export functions
hermetic_exec = _hermetic_exec
hermetic_exec_test = _hermetic_exec_test
hermetic_genrule = _hermetic_genrule
hermetic_toolchain = _hermetic_toolchain

_PY_TOOLCHAIN_TYPE = "@bazel_tools//tools/python:toolchain_type"

# Deprecated.
HermeticToolsInfo = provider(
    doc = """Legacy information provided by [hermetic_tools](#hermetic_tools).

Deprecated:
    Use `hermetic_toolchain` instead. See `build/kernel/kleaf/docs/hermeticity.md`.
""",
    fields = {
        "deps": "A list containing the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
        # TODO(b/250646733): Delete this field
        "additional_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

Alternative setup script that preserves original `PATH`.

After using this script, the shell environment prioritizes using hermetic tools, but falls
back on tools from the original `PATH` if a tool cannot be found.

Use with caution. Using this script does not provide hermeticity. Consider using `setup` instead.
""",
        "run_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

setup script to initialize the environment to only use the hermetic tools in
[execution phase](https://docs.bazel.build/versions/main/skylark/concepts.html#evaluation-model),
e.g. for generated executables and tests""",
        "run_additional_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

Like `run_setup` but preserves original `PATH`.""",
    },
)

_HermeticToolchainInfo = provider(
    doc = "Toolchain information provided by [hermetic_tools](#hermetic_tools).",
    fields = {
        "deps": "a depset containing the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
        "run_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

setup script to initialize the environment to only use the hermetic tools in
[execution phase](https://docs.bazel.build/versions/main/skylark/concepts.html#evaluation-model),
e.g. for generated executables and tests""",
        "run_additional_setup": """**IMPLEMENTATION DETAIL; DO NOT USE.**

Like `run_setup` but preserves original `PATH`.""",
    },
)

def _handle_python(ctx, py_outs, runtime):
    if not py_outs:
        return struct(
            hermetic_outs_dict = {},
            info_deps = [],
        )

    for out in py_outs:
        ctx.actions.symlink(
            output = out,
            target_file = runtime.interpreter,
            is_executable = True,
            progress_message = "Creating symlink for {}: {}".format(
                paths.basename(out.path),
                ctx.label,
            ),
        )
    return struct(
        hermetic_outs_dict = {out.basename: out for out in py_outs},
        # TODO(b/247624301): Use depset in HermeticToolsInfo.
        info_deps = runtime.files.to_list(),
    )

def _handle_hermetic_tools(ctx):
    hermetic_outs_dict = {out.basename: out for out in ctx.outputs.outs}

    tar_src = None
    tar_out = hermetic_outs_dict.pop("tar")

    for src in ctx.files.srcs:
        if src.basename == "tar" and ctx.attr.tar_args:
            tar_src = src
            continue
        out = hermetic_outs_dict[src.basename]
        ctx.actions.symlink(
            output = out,
            target_file = src,
            is_executable = True,
            progress_message = "Creating symlinks to in-tree tools {}/{}".format(
                ctx.label,
                src.basename,
            ),
        )

    _handle_tar(
        ctx = ctx,
        src = tar_src,
        out = tar_out,
        hermetic_base = hermetic_outs_dict.values()[0].dirname,
        deps = hermetic_outs_dict.values(),
    )
    hermetic_outs_dict["tar"] = tar_out

    return hermetic_outs_dict

def _handle_tar(ctx, src, out, hermetic_base, deps):
    if not ctx.attr.tar_args:
        return

    command = """
        set -e
        PATH={hermetic_base}
        (
            toybox=$(realpath {src})
            if [[ $(basename $toybox) != "toybox" ]]; then
                echo "Expects toybox for tar" >&2
                exit 1
            fi

            cat > {out} << EOF
#!/bin/sh

$toybox tar "\\$@" {tar_args}
EOF
        )
    """.format(
        src = src.path,
        out = out.path,
        hermetic_base = hermetic_base,
        tar_args = " ".join([shell.quote(arg) for arg in ctx.attr.tar_args]),
    )

    ctx.actions.run_shell(
        inputs = deps + [src],
        outputs = [out],
        command = command,
        mnemonic = "HermeticToolsTar",
        progress_message = "Creating wrapper for tar: {}".format(ctx.label),
    )

def _get_single_file(ctx, target):
    files_list = target.files.to_list()
    if len(files_list) != 1:
        fail("{}: {} does not contain a single file".format(
            ctx.label,
            target.label,
        ))
    return files_list[0]

def _handle_hermetic_symlinks(ctx):
    hermetic_symlinks_dict = {}
    for actual_target, tool_names in ctx.attr.symlinks.items():
        for tool_name in tool_names.split(":"):
            out = ctx.actions.declare_file("{}/{}".format(ctx.attr.name, tool_name))
            target_file = _get_single_file(ctx, actual_target)
            ctx.actions.symlink(
                output = out,
                target_file = target_file,
                is_executable = True,
                progress_message = "Creating symlinks to in-tree tools {}/{}".format(
                    ctx.label,
                    tool_name,
                ),
            )
            hermetic_symlinks_dict[tool_name] = out

    return hermetic_symlinks_dict

def _hermetic_tools_impl(ctx):
    deps = [] + ctx.files.srcs + ctx.files.deps
    all_outputs = []

    hermetic_outs_dict = _handle_hermetic_tools(ctx)
    hermetic_outs_dict.update(_handle_hermetic_symlinks(ctx))

    py3 = _handle_python(
        ctx = ctx,
        py_outs = ctx.outputs.py3_outs,
        runtime = ctx.toolchains[_PY_TOOLCHAIN_TYPE].py3_runtime,
    )
    hermetic_outs_dict.update(py3.hermetic_outs_dict)

    hermetic_outs = hermetic_outs_dict.values()
    all_outputs += hermetic_outs
    deps += hermetic_outs

    deps += py3.info_deps

    if ctx.attr._disable_symlink_source[BuildSettingInfo].value:
        transitive_deps = []
    else:
        transitive_deps = [target.files for target in ctx.attr.symlinks]

    deps_depset = depset(deps, transitive = transitive_deps)

    fail_hard = """
         # error on failures
           set -e
           set -o pipefail
    """

    hermetic_base = paths.join(
        ctx.bin_dir.path,
        paths.dirname(ctx.build_file_path),
        ctx.attr.name,
    )
    hermetic_base_short = paths.join(
        paths.dirname(ctx.build_file_path),
        ctx.attr.name,
    )

    hashbang = """#!/bin/bash -e
"""

    setup = fail_hard + """
                export PATH=$({path}/readlink -m {path})
                # Ensure _setup_env.sh keeps the original items in PATH
                export KLEAF_INTERNAL_BUILDTOOLS_PREBUILT_BIN={path}
""".format(path = hermetic_base)
    additional_setup = """
                export PATH=$({path}/readlink -m {path}):$PATH
""".format(path = hermetic_base)
    run_setup = hashbang + fail_hard + """
                export PATH=$({path}/readlink -m {path})
""".format(path = hermetic_base_short)
    run_additional_setup = fail_hard + """
                export PATH=$({path}/readlink -m {path}):$PATH
""".format(path = hermetic_base_short)

    hermetic_toolchain_info = _HermeticToolchainInfo(
        deps = deps_depset,
        setup = setup,
        run_setup = run_setup,
        run_additional_setup = run_additional_setup,
    )

    infos = [
        DefaultInfo(files = depset(all_outputs)),
        platform_common.ToolchainInfo(
            hermetic_toolchain_info = hermetic_toolchain_info,
        ),
        OutputGroupInfo(
            **{file.basename: depset([file]) for file in all_outputs}
        ),
    ]

    if not ctx.attr._disable_hermetic_tools_info[BuildSettingInfo].value:
        hermetic_tools_info = HermeticToolsInfo(
            deps = deps_depset.to_list(),
            setup = setup,
            additional_setup = additional_setup,
            run_setup = run_setup,
            run_additional_setup = run_additional_setup,
        )
        infos.append(hermetic_tools_info)

    return infos

_hermetic_tools = rule(
    implementation = _hermetic_tools_impl,
    doc = "",
    attrs = {
        "unregistered_host_tools": attr.string_list(),
        "outs": attr.output_list(),
        "py3_outs": attr.output_list(),
        "srcs": attr.label_list(doc = "Hermetic tools in the tree", allow_files = True),
        "deps": attr.label_list(doc = "Additional_deps", allow_files = True),
        "tar_args": attr.string_list(),
        "symlinks": attr.label_keyed_string_dict(
            doc = "symlinks to labels",
            allow_files = True,
        ),
        "_disable_hermetic_tools_info": attr.label(
            default = "//build/kernel/kleaf/impl:incompatible_disable_hermetic_tools_info",
        ),
        "_disable_symlink_source": attr.label(
            default = "//build/kernel/kleaf:incompatible_disable_hermetic_tools_symlink_source",
        ),
    },
    toolchains = [
        config_common.toolchain_type(_PY_TOOLCHAIN_TYPE, mandatory = True),
    ],
)

def hermetic_tools(
        name,
        srcs,
        deps = None,
        tar_args = None,
        py3_outs = None,
        symlinks = None,
        aliases = None,
        **kwargs):
    """Provide tools for a hermetic build.

    Args:
        name: Name of the target.
        srcs: A list of labels referring to tools for hermetic builds. This is usually a `glob()`.

          Each item in `{srcs}` is treated as an executable that are added to the `PATH`.
        symlinks: A dictionary, where keys are labels to an executable, and
          values are names to the tool, separated with `:`. e.g.

          ```
          {"//label/to:toybox": "cp:realpath"}
          ```
        py3_outs: List of tool names that are resolved to Python 3 binary.
        deps: additional dependencies. Unlike `srcs`, these aren't added to the `PATH`.
        tar_args: List of fixed arguments provided to `tar` commands.
        aliases: [nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).

          List of aliases to create to refer to a single tool.

          For example, if `aliases = ["cp"],` then `<name>/cp` refers to a
          `cp`.

          **Note**: Items in `srcs`, `host_tools` and `py3_outs` already have
          `<name>/<tool>` target created.
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common
    """

    if aliases == None:
        aliases = []

    outs = None
    if srcs:
        outs = ["{}/{}".format(
            name,
            paths.basename(native.package_relative_label(src).name),
        ) for src in srcs]

    if py3_outs:
        py3_outs = ["{}/{}".format(name, paths.basename(py3_name)) for py3_name in py3_outs]

    _hermetic_tools(
        name = name,
        srcs = srcs,
        outs = outs,
        py3_outs = py3_outs,
        deps = deps,
        tar_args = tar_args,
        symlinks = symlinks,
        **kwargs
    )

    alias_kwargs = kwargs

    for alias in aliases:
        native.filegroup(
            name = name + "/" + alias,
            srcs = [name],
            output_group = alias,
            **alias_kwargs
        )
