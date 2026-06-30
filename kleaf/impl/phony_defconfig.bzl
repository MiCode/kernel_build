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

"""Supports an arbitrary make goal in kernel_build.defconfig"""

load(":common_providers.bzl", "DefconfigInfo")

visibility("//build/kernel/kleaf/...")

def _phony_defconfig_impl(ctx):
    make_target = ctx.attr.make_target or ctx.attr.name
    return DefconfigInfo(file = None, make_target = make_target)

phony_defconfig = rule(
    implementation = _phony_defconfig_impl,
    attrs = {
        "make_target": attr.string(doc = "The make target. Defaults to name."),
    },
)
