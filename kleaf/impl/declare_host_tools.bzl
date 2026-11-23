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

"""Symlinks to host tools."""

load(":default_host_tools.scl", "DEFAULT_HOST_TOOLS")

visibility([
    "//build/kernel/kleaf/...",
    "//",  # for root MODULE.bazel
])

def _kleaf_host_tools_repo_impl(repository_ctx):
    repository_ctx.file("WORKSPACE", """\
workspace(name = "{}")
""".format(repository_ctx.name))

    repository_ctx.file("BUILD.bazel", """\
exports_files(
    {files},
    visibility = [{visibility}],
)
""".format(
        files = repr(repository_ctx.attr.host_tools),
        visibility = repr(str(Label("//build/kernel:__subpackages__"))),
    ))

    for host_tool in repository_ctx.attr.host_tools:
        host_path = repository_ctx.which(host_tool)
        if host_path == None:
            fail("Missing host tool {}".format(host_tool))
        repository_ctx.symlink(host_path, host_tool)

# TODO(b/276493276): Hide this once workspace.bzl is deleted.
kleaf_host_tools_repo = repository_rule(
    doc = "Creates symlinks to host tools.",
    implementation = _kleaf_host_tools_repo_impl,
    attrs = {
        "host_tools": attr.string_list(doc = "List of host tools"),
    },
)

def _declare_repos(module_ctx, tag_name):
    host_tools = []
    for module in module_ctx.modules:
        for declared in getattr(module.tags, tag_name):
            host_tools += declared.host_tools

    if not host_tools:
        host_tools = DEFAULT_HOST_TOOLS

    kleaf_host_tools_repo(
        name = "kleaf_host_tools",
        host_tools = host_tools,
    )

_tag_class = tag_class(
    doc = "Declares a list of host tools to be symlinked in the extension `kleaf_host_tools.",
    attrs = {
        "host_tools": attr.string_list(
            doc = """List of host tools.

                If `declare_host_tools` is not called anywhere, or only called
                with empty `host_tools`, the default is `{}`.
            """.format(repr(DEFAULT_HOST_TOOLS)),
        ),
    },
)

declare_host_tools = struct(
    declare_repos = _declare_repos,
    tag_class = _tag_class,
)
