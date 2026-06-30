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

"""Resolves to the first not-None file."""

visibility("private")

OrFileInfo = provider(
    "Provides info for or_file",
    fields = {
        "selected_label": "label of selected target",
    },
)

def _or_file_impl(ctx):
    if ctx.file.first:
        files = ctx.files.first
        selected_label = ctx.attr.first.label
    elif ctx.file.second:
        files = ctx.files.second
        selected_label = ctx.attr.second.label
    else:
        files = []
        selected_label = None
    return [
        DefaultInfo(files = depset(files)),
        OrFileInfo(selected_label = selected_label),
    ]

or_file = rule(
    implementation = _or_file_impl,
    attrs = {
        "first": attr.label(allow_single_file = True),
        "second": attr.label(allow_single_file = True),
    },
)
