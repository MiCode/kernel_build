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

"""Helper subrule to handle kernel_dir/KERNEL_DIR"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")

visibility("private")

def _set_kernel_dir_impl(_subrule_ctx, *, makefile):
    if not makefile:
        return struct(
            cmd = "",
            run_cmd = "",
        )

    cmd = """
        KLEAF_INTERNAL_PREFERRED_KERNEL_DIR={quoted_kernel_dir}
    """.format(
        quoted_kernel_dir = shell.quote(makefile.dirname),
    )
    run_cmd = """
        KLEAF_INTERNAL_PREFERRED_KERNEL_DIR={quoted_kernel_dir}
    """.format(
        quoted_kernel_dir = shell.quote(paths.dirname(makefile.short_path)),
    )
    return struct(
        cmd = cmd,
        run_cmd = run_cmd,
    )

set_kernel_dir = subrule(
    implementation = _set_kernel_dir_impl,
)
