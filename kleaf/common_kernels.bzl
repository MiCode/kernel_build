# Copyright (C) 2021 The Android Open Source Project
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

load("//build/kleaf:kernel.bzl", "kernel_build")

def define_common_kernels():
    """Defines common build targets for Android Common Kernels.

    This macro expands to the commonly defined common kernels (such as the GKI
    kernels and their variants. They are defined based on the conventionally
    used `BUILD_CONFIG` file and produce usual output files.

    The targets declared:
    - `kernel_aarch64`
    - `kernel_aarch64_debug`
    - `kernel_x86_64`
    - `kernel_x86_64_debug`

    An alias is created to refer to the GKI kernel (`kernel_aarch64`) as "`kernel`".
    """
    common_outs = [
        "System.map",
        "modules.builtin",
        "modules.builtin.modinfo",
        "vmlinux",
        "vmlinux.symvers",
    ]

    aarch64_outs = common_outs + [
        "Image",
        "Image.lz4",
    ]

    x86_64_outs = common_outs + ["bzImage"]

    [kernel_build(
        name = name,
        srcs = native.glob(
            ["**"],
            exclude = [
                "android/*",
                "BUILD.bazel",
                "**/*.bzl",
                ".git/**",
            ],
        ),
        outs = outs,
        build_config = config,
    ) for name, config, outs in [
        (
            "kernel_aarch64",
            "build.config.gki.aarch64",
            aarch64_outs,
        ),
        (
            "kernel_aarch64_debug",
            "build.config.gki-debug.aarch64",
            aarch64_outs,
        ),
        (
            "kernel_x86_64",
            "build.config.gki.x86_64",
            x86_64_outs,
        ),
        (
            "kernel_x86_64_debug",
            "build.config.gki-debug.x86_64",
            x86_64_outs,
        ),
    ]]

    native.alias(
        name = "kernel",
        actual = ":kernel_aarch64",
    )
