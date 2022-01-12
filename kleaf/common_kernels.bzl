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

load(
    "//build/kleaf:kernel.bzl",
    "kernel_build",
    "kernel_compile_commands",
    "kernel_images",
    "kernel_kythe",
    "kernel_modules_install",
)
load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")

_common_outs = [
    "System.map",
    "modules.builtin",
    "modules.builtin.modinfo",
    "vmlinux",
    "vmlinux.symvers",
]

# Common output files for aarch64 kernel builds.
aarch64_outs = _common_outs + [
    "Image",
    "Image.lz4",
]

# Common output files for x86_64 kernel builds.
x86_64_outs = _common_outs + ["bzImage"]

_ARCH_CONFIGS = [
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
]

def define_common_kernels(
        toolchain_version = None,
        visibility = [
            "//visibility:public",
        ]):
    """Defines common build targets for Android Common Kernels.

    This macro expands to the commonly defined common kernels (such as the GKI
    kernels and their variants. They are defined based on the conventionally
    used `BUILD_CONFIG` file and produce usual output files.

    The targets declared:
    - `kernel_aarch64`
      - `kernel_aarch64_sources`
      - `kernel_aarch64_dist`
    - `kernel_aarch64_debug`
      - `kernel_aarch64_debug_dist`
    - `kernel_x86_64`
      - `kernel_x86_64_sources`
      - `kernel_x86_64_dist`
    - `kernel_x86_64_debug`
      - `kernel_x86_64_debug_dist`
    - `kernel_aarch64_kythe`
      - `kernel_aarch64_kythe_dist`

    `<name>_dist` targets can be run to obtain a distribution outside the workspace.

    Aliases are created to refer to the GKI kernel (`kernel_aarch64`) as
    "`kernel`" and the corresponding dist target (`kernel_aarch64_dist`) as
    "`kernel_dist`".

    Args:
      toolchain_version: If not set, use default value in `kernel_build`.
      visibility: visibility of the kernel build.

        See [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
    """

    kernel_build_kwargs = {}
    if toolchain_version:
        kernel_build_kwargs["toolchain_version"] = toolchain_version

    for name, config, outs in _ARCH_CONFIGS:
        native.filegroup(
            name = name + "_sources",
            srcs = native.glob(
                ["**"],
                exclude = [
                    "BUILD.bazel",
                    "**/*.bzl",
                    ".git/**",
                ],
            ),
        )

        kernel_build(
            name = name,
            srcs = [name + "_sources"],
            outs = outs,
            build_config = config,
            visibility = visibility,
            **kernel_build_kwargs
        )

        kernel_modules_install(
            name = name + "_modules_install",
            kernel_build = name,
        )

        kernel_images(
            name = name + "_images",
            kernel_build = name,
            kernel_modules_install = name + "_modules_install",
            build_system_dlkm = True,
        )

        copy_to_dist_dir(
            name = name + "_dist",
            data = [
                name + "_for_dist",
                name + "_modules_install",
                name + "_images",
            ],
            flat = True,
        )

    native.alias(
        name = "kernel",
        actual = ":kernel_aarch64",
    )

    native.alias(
        name = "kernel_dist",
        actual = ":kernel_aarch64_dist",
    )

    kernel_compile_commands(
        name = "kernel_aarch64_compile_commands",
        kernel_build = ":kernel_aarch64",
    )

    kernel_kythe(
        name = "kernel_aarch64_kythe",
        kernel_build = ":kernel_aarch64",
        compile_commands = ":kernel_aarch64_compile_commands",
    )

    copy_to_dist_dir(
        name = "kernel_aarch64_kythe_dist",
        data = [
            ":kernel_aarch64_compile_commands",
            ":kernel_aarch64_kythe",
        ],
        flat = True,
    )
