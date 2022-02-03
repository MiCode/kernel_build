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
# TODO(b/217630659): Move contents of _impl.bzl back to this file.
load(
    "//build/kernel/kleaf:kernel_impl.bzl",
    KernelFilesInfo_impl = "KernelFilesInfo",
    kernel_build_config_impl = "kernel_build_config",
    kernel_build_impl = "kernel_build",
    kernel_compile_commands_impl = "kernel_compile_commands",
    kernel_dtstree_impl = "kernel_dtstree",
    kernel_filegroup_impl = "kernel_filegroup",
    kernel_images_impl = "kernel_images",
    kernel_kythe_impl = "kernel_kythe",
    kernel_module_impl = "kernel_module",
    kernel_modules_install_impl = "kernel_modules_install",
)

kernel_build_config = kernel_build_config_impl
KernelFilesInfo = KernelFilesInfo_impl
kernel_build = kernel_build_impl
kernel_dtstree = kernel_dtstree_impl
kernel_module = kernel_module_impl
kernel_modules_install = kernel_modules_install_impl
kernel_images = kernel_images_impl
kernel_filegroup = kernel_filegroup_impl
kernel_compile_commands = kernel_compile_commands_impl
kernel_kythe = kernel_kythe_impl
