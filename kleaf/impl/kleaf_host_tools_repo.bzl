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

visibility("//build/kernel/kleaf/...")

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
        repository_ctx.symlink(repository_ctx.which(host_tool), host_tool)

kleaf_host_tools_repo = repository_rule(
    doc = "Creates symlinks to host tools.",
    implementation = _kleaf_host_tools_repo_impl,
    attrs = {
        "host_tools": attr.string_list(doc = "List of host tools"),
    },
)
