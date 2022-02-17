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

GKI_MODULES = [
]

# See common_kernels.bzl.
GKI_DOWNLOAD_CONFIGS = [
    {
        "target_suffix": "uapi_headers",
        "outs": [
            "kernel-uapi-headers.tar.gz",
        ],
    },
    {
        "target_suffix": "additional_artifacts",
        "outs": [
            # _headers
            "kernel-headers.tar.gz",
            # _images
            "system_dlkm.img",
        ] + GKI_MODULES,  # corresponding to _modules_install
    },
]

TOOLCHAIN_VERSION_FILENAME = "toolchain_version"

# Key: Bazel target name in common_kernels.bzl
# repo_name: name of download_artifacts_repo in bazel.WORKSPACE
# outs: list of outs associated with that target name
CI_TARGET_MAPPING = {
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    "kernel_aarch64": {
        "repo_name": "gki_prebuilts",
        "outs": aarch64_outs + [
            TOOLCHAIN_VERSION_FILENAME,
        ],
    },
}
