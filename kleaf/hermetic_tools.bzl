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

load("@bazel_skylib//lib:paths.bzl", "paths")

HermeticToolsInfo = provider(
    doc = "Information provided by [hermetic_tools](#hermetic_tools).",
    fields = {
        "deps": "the hermetic tools",
        "setup": "setup script to initialize the environment to only use the hermetic tools",
        "additional_setup": """Alternative setup script that preserves original `PATH`.

After using this script, the shell environment prioritizes using hermetic tools, but falls
back on tools from the original `PATH` if a tool cannot be found.

Use with caution. Using this script does not provide hermeticity. Consider using `setup` instead.
""",
        "run_setup": """setup script to initialize the environment to only use the hermetic tools in
[execution phase](https://docs.bazel.build/versions/main/skylark/concepts.html#evaluation-model),
e.g. for generated executables and tests""",
    },
)

def _hermetic_tools_impl(ctx):
    deps = [] + ctx.files.srcs + ctx.files.deps
    all_outputs = []

    hermetic_outs_dict = {out.basename: out for out in ctx.outputs.outs}
    for src in ctx.files.srcs:
        out = hermetic_outs_dict[src.basename]
        ctx.actions.symlink(
            output = out,
            target_file = src,
            is_executable = True,
            progress_message = "Creating symlinks to in-tree tools",
        )
    hermetic_outs = hermetic_outs_dict.values()
    all_outputs += hermetic_outs
    deps += hermetic_outs

    for attr in ("host_tools", "test_host_tools"):
        host_outs = getattr(ctx.outputs, attr)
        command = """
            set -e
          # export PATH so which can work
            export PATH
            for i in {host_outs}; do
                {hermetic_base}/ln -s $({hermetic_base}/which $({hermetic_base}/basename $i)) $i
            done
        """.format(
            host_outs = " ".join([f.path for f in host_outs]),
            hermetic_base = hermetic_outs[0].dirname,
        )
        ctx.actions.run_shell(
            inputs = deps,
            outputs = host_outs,
            command = command,
            progress_message = "Creating symlinks to {}".format(attr),
            mnemonic = "HermeticTools",
            execution_requirements = {
                "no-remote": "1",
            },
        )
        all_outputs += host_outs

    deps += ctx.outputs.host_tools

    fail_hard = """
         # error on failures
           set -e
           set -o pipefail
    """

    setup = fail_hard + """
                export PATH=$({path}/readlink -m {path})
""".format(path = all_outputs[0].dirname)
    additional_setup = """
                export PATH=$({path}/readlink -m {path}):$PATH
""".format(path = all_outputs[0].dirname)
    run_setup = fail_hard + """
                export PATH=$({path}/readlink -m {path})
""".format(path = paths.dirname(all_outputs[0].short_path))

    return [
        DefaultInfo(files = depset(all_outputs)),
        HermeticToolsInfo(
            deps = deps,
            setup = setup,
            additional_setup = additional_setup,
            run_setup = run_setup,
        ),
    ]

_hermetic_tools = rule(
    implementation = _hermetic_tools_impl,
    doc = "",
    attrs = {
        "host_tools": attr.output_list(),
        "test_host_tools": attr.output_list(),
        "outs": attr.output_list(),
        "srcs": attr.label_list(doc = "Hermetic tools in the tree", allow_files = True),
        "deps": attr.label_list(doc = "Additional_deps", allow_files = True),
    },
)

def hermetic_tools(
        name,
        srcs,
        host_tools = None,
        test_host_tools = None,
        deps = None):
    """Provide tools for a hermetic build.

    Args:
        name: Name of the target.
        srcs: A list of labels referring to tools for hermetic builds. This is usually a `glob()`.

          Each item in `{srcs}` is treated as an executable that are added to the `PATH`.
        host_tools: An allowlist of names of tools that are allowed to be used from the host.

          For each token `{tool}`, the label `{name}/{tool}` is created to refer to the tool.
        test_host_tools: An allowlist of names of tools that are allowed to be used from the host for testing only.

          For each token `{tool}`, the label `{name}/{tool}` is created to refer to the tool.
        deps: additional dependencies. Unlike `srcs`, these aren't added to the `PATH`.
    """

    if host_tools:
        host_tools = ["{}/{}".format(name, tool) for tool in host_tools]

    if test_host_tools:
        test_host_tools = ["{}/{}".format(name, tool) for tool in test_host_tools]

    outs = None
    if srcs:
        outs = ["{}/{}".format(name, paths.basename(src)) for src in srcs]

    _hermetic_tools(
        name = name,
        srcs = srcs,
        outs = outs,
        host_tools = host_tools,
        test_host_tools = test_host_tools,
        deps = deps,
    )
