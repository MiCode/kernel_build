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

"""
Utility public constants.
"""

load(
    "//build/kernel/kleaf/impl:constants.bzl",
    "DEFAULT_IMAGES",
    "GKI_ARTIFACTS_AARCH64_OUTS",
    "MODULES_STAGING_ARCHIVE",
    "MODULE_OUTS_FILE_SUFFIX",
    "SYSTEM_DLKM_OUTS",
    "TOOLCHAIN_VERSION_FILENAME",
)

_common_outs = [
    "System.map",
    "modules.builtin",
    "modules.builtin.modinfo",
    "vmlinux",
    "vmlinux.symvers",
]

# Common output files for aarch64 kernel builds.
# Sync with build.config.gki.{aarch64,riscv64}
DEFAULT_GKI_OUTS = _common_outs + DEFAULT_IMAGES

# Common output files for x86_64 kernel builds.
X86_64_OUTS = _common_outs + ["bzImage"]

# Deprecated; use AARCH64_GKI_OUTS
aarch64_outs = DEFAULT_GKI_OUTS

# Deprecated; use X86_64_OUTS
x86_64_outs = X86_64_OUTS

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
            "unstripped_modules.tar.gz",
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
        "outs": SYSTEM_DLKM_OUTS,
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
            # _modules_prepare
            "modules_prepare_outdir.tar.gz",
            # _modules_staging_archive
            MODULES_STAGING_ARCHIVE,
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

# Key: Bazel target name in common_kernels.bzl
# repo_name: name of download_artifacts_repo in bazel.WORKSPACE
# outs: list of outs associated with that target name
CI_TARGET_MAPPING = {
    # TODO(b/206079661): Allow downloaded prebuilts for x86_64 and debug targets.
    "kernel_aarch64": {
        "repo_name": "gki_prebuilts",
        "outs": DEFAULT_GKI_OUTS + [
            "kernel_aarch64" + MODULE_OUTS_FILE_SUFFIX,
        ],
        "protected_modules": "gki_aarch64_protected_modules",
        "gki_prebuilts_outs": GKI_ARTIFACTS_AARCH64_OUTS,
    },
}

LTO_VALUES = (
    "default",
    "none",
    "thin",
    "full",
    "fast",
)
