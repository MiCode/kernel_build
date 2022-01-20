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

    Targets declared for kernel build (parent list item depends on child list item):
    - `kernel_aarch64_sources`
    - `kernel_aarch64_dist`
      - `kernel_aarch64`
      - `kernel_aarch64_uapi_headers`
      - `kernel_aarch64_additional_artifacts`
    - `kernel_aarch64_debug_dist`
      - `kernel_aarch64_debug`
    - `kernel_x86_64_sources`
    - `kernel_x86_64_dist`
      - `kernel_x86_64`
      - `kernel_x86_64_uapi_headers`
      - `kernel_x86_64_additional_artifacts`
    - `kernel_x86_64_debug_dist`
      - `kernel_x86_64_debug`

    `<name>` (aka `kernel_{aarch64,x86}{_debug,}`) targets build the
    main kernel build artifacts, e.g. `vmlinux`, etc.

    `<name>_sources` are convenience filegroups that refers to all sources required to
    build `<name>` and related targets.

    `<name>_uapi_headers` targets build `kernel-uapi-headers.tar.gz`.

    `<name>_additional_artifacts` contains additional artifacts that may be added to
    a distribution. This includes:
      - Images, including `system_dlkm`, etc.
      - `kernel-headers.tar.gz`

    `<name>_dist` targets can be run to obtain a distribution outside the workspace.

    Aliases are created to refer to the GKI kernel (`kernel_aarch64`) as
    "`kernel`" and the corresponding dist target (`kernel_aarch64_dist`) as
    "`kernel_dist`".

    Targets declared for cross referencing:
    - `kernel_aarch64_kythe_dist`
      - `kernel_aarch64_kythe`

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
            implicit_outs = [
                # Kernel build time module signining utility and keys
                # Only available during GKI builds
                # Device fragments need to add: '# CONFIG_MODULE_SIG_ALL is not set'
                    "scripts/sign-file",
                    "certs/signing_key.pem",
                    "certs/signing_key.x509"
            ],
            module_outs = [
                    "test_stackinit.ko",
            ],
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
            deps = [
                 # Keep the following in sync with build.config.gki* MODULES_LIST
                 "android/gki_system_dlkm_modules",
             ],
        )

        # Everything in name + "_dist", minus UAPI headers, because
        # device-specific external kernel modules may install different headers.
        native.filegroup(
            name = name + "_additional_artifacts",
            srcs = [
                name + "_headers",
                name + "_modules_install",
                name + "_images",
            ],
        )

        copy_to_dist_dir(
            name = name + "_dist",
            data = [
                name,
                name + "_uapi_headers",
                name + "_additional_artifacts",
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
