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

"""Internal constants."""

visibility("//build/kernel/kleaf/...")

TOOLCHAIN_VERSION_FILENAME = "toolchain_version"

# The suffix of the file in the default outputs of kernel_build that stores
# the list of `module_outs` for that kernel_build.
MODULE_OUTS_FILE_SUFFIX = "_modules"

# The output group of the file of a kernel_build that stores
# the list of `module_outs` for that kernel_build.
MODULE_OUTS_FILE_OUTPUT_GROUP = "module_outs_file"

# List of images produced by non-x86 kernels.
DEFAULT_IMAGES = [
    "Image",
    "Image.lz4",
    "Image.gz",
]

# List of output files from gki_artifacts()
GKI_ARTIFACTS_AARCH64_OUTS = [
    "boot-img.tar.gz",
    "gki-info.txt",
] + [
    "boot.img" if e == "Image" else "boot-{}.img".format(e[len("Image."):])
    for e in DEFAULT_IMAGES
]

SYSTEM_DLKM_COMMON_OUTS = [
    "system_dlkm_staging_archive.tar.gz",
    "system_dlkm.modules.load",
    "system_dlkm.modules.blocklist",
]

MODULES_STAGING_ARCHIVE = "modules_staging_dir.tar.gz"
