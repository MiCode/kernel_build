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
    "//build/kernel/kleaf:constants.bzl",
    "GKI_DOWNLOAD_CONFIGS",
    "aarch64_outs",
)
load("//build/kernel/kleaf:download_repo.bzl", "download_artifacts_repo")
load("//build/kernel/kleaf:key_value_repo.bzl", "key_value_repo")

toplevel_output_directories(paths = ["out"])

local_repository(
    name = "bazel_skylib",
    path = "external/bazel-skylib",
)

local_repository(
    name = "io_bazel_stardoc",
    path = "external/stardoc",
)

key_value_repo(
    name = "kernel_toolchain_info",
    srcs = ["//common:build.config.constants"],
)

download_artifacts_repo(
    name = "gki_prebuilts",
    target = "kernel_kleaf",
    files = aarch64_outs + [out for config in GKI_DOWNLOAD_CONFIGS for out in config["outs"]],
)
