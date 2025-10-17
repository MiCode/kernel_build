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

"""Utilities to define a repository for kernel prebuilts."""

load(
    "//build/kernel/kleaf:constants.bzl",
    "DEFAULT_GKI_OUTS",
)
load(
    ":constants.bzl",
    "FILEGROUP_DEF_ARCHIVE_SUFFIX",
    "GKI_ARTIFACTS_AARCH64_OUTS",
    "SYSTEM_DLKM_COMMON_OUTS",
    "TOOLCHAIN_VERSION_FILENAME",
    "UNSTRIPPED_MODULES_ARCHIVE",
)

visibility("//build/kernel/kleaf/...")

# See common_kernels.bzl and download_repo.bzl.
# - mandatory: If False, download errors are ignored. Default is True; see workspace.bzl
GKI_DOWNLOAD_CONFIGS = [
    {
        "target_suffix": "uapi_headers",
        "outs": [
            "kernel-uapi-headers.tar.gz",
        ],
    },
    {
        "target_suffix": "unstripped_modules_archive",
        "outs": [
            UNSTRIPPED_MODULES_ARCHIVE,
        ],
    },
    {
        "target_suffix": "headers",
        "outs": [
            "kernel-headers.tar.gz",
        ],
    },
    {
        "target_suffix": "images",
        # TODO(b/297934577): Update GKI prebuilts to download system_dlkm.<fs>.img
        "outs": SYSTEM_DLKM_COMMON_OUTS,
    },
    {
        "target_suffix": "toolchain_version",
        "outs": [
            TOOLCHAIN_VERSION_FILENAME,
        ],
    },
    {
        "target_suffix": "boot_img_archive",
        # We only download GKI for arm64, not riscv64 or x86_64
        # TODO(b/206079661): Allow downloaded prebuilts for risc64/x86_64/debug targets.
        "outs": [
            "boot-img.tar.gz",
            # The others can be found by extracting the archive, see gki_artifacts_prebuilts
        ],
    },
    {
        "target_suffix": "boot_img_archive_signed",
        # Do not fail immediately if this file cannot be downloaded, because it does not
        # exist for unsigned builds. A build error will be emitted by gki_artifacts_prebuilts
        # if --use_signed_prebuilts and --use_gki_prebuilts=<an unsigned build number>.
        "mandatory": False,
        # We only download GKI for arm64, not riscv64 or x86_64
        # TODO(b/206079661): Allow downloaded prebuilts for risc64/x86_64/debug targets.
        "outs_mapping": {
            # The basename is kept boot-img.tar.gz so it works with
            # gki_artifacts_prebuilts. It is placed under the signed/
            # directory to avoid conflicts with boot_img_archive in
            # download_artifacts_repo.
            # The others can be found by extracting the archive, see gki_artifacts_prebuilts
            "signed/boot-img.tar.gz": "signed/certified-boot-img-{build_number}.tar.gz",
        },
    },
    {
        "target_suffix": "ddk_artifacts",
        "outs": [
            "kernel_aarch64" + FILEGROUP_DEF_ARCHIVE_SUFFIX,
        ],
    },
    {
        "target_suffix": "kmi_symbol_list",
        "mandatory": False,
        "outs": [
            "abi_symbollist",
            "abi_symbollist.report",
        ],
    },
]

# Key: name of repository in bazel.WORKSPACE
# target: Bazel target name in common_kernels.bzl
# outs: list of outs associated with that target name
# arch: Architecture associated with this mapping.
CI_TARGET_MAPPING = {
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    "gki_prebuilts": {
        "arch": "arm64",
        # TODO: Rename this when more architectures are added.
        "target": "kernel_aarch64",
        "outs": DEFAULT_GKI_OUTS,
        "protected_modules": "gki_aarch64_protected_modules",
        "gki_prebuilts_outs": GKI_ARTIFACTS_AARCH64_OUTS,
    },
}
