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
    "//build/kernel/kleaf:common_kernels_impl.bzl",
    define_common_kernels_impl = "define_common_kernels",
)

define_common_kernels = define_common_kernels_impl
