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

load("@bazel_skylib//lib:paths.bzl", "paths")

_TRIPLES = [paths.basename(path) for path in glob(
    ["toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/*"],
    exclude_directories = 0,
)]

_SYSROOT_TRIPLE_COMMON_FILES = [
    "libc.a",
    "libdl.a",
    "libm.a",
]

_SYSROOT_TRIPLE_LEVEL_FILES = [
    "libc.so",
    "libdl.so",
    "libm.so",
    "crtbegin_dynamic.o",
    "crtbegin_static.o",
    "crtend_android.o",
]

filegroup(
    name = "sysroot_dir",
    srcs = ["toolchains/llvm/prebuilt/linux-x86_64/sysroot"],
    visibility = ["@kleaf_clang_toolchain//:__subpackages__"],
)

filegroup(
    name = "sysroot_include",
    srcs = glob(
        ["toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/**"],
        allow_empty = False,
    ),
    visibility = ["//visibility:private"],
)

[filegroup(
    name = "sysroot_{}_common".format(triple),
    srcs = [
        "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{}/{}".format(triple, filename)
        for filename in _SYSROOT_TRIPLE_COMMON_FILES
    ],
    visibility = ["//visibility:private"],
) for triple in _TRIPLES]

[filegroup(
    name = "sysroot_{}{}_files".format(triple, level),
    srcs = [
        "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{}/{}/{}".format(triple, level, filename)
        for filename in _SYSROOT_TRIPLE_LEVEL_FILES
    ] + [
        ":sysroot_{}_common".format(triple),
        ":sysroot_include",
    ],
    visibility = ["@kleaf_clang_toolchain//:__subpackages__"],
) for triple in _TRIPLES for level in [
    paths.basename(path)
    for path in glob(
        ["toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{}/*".format(triple)],
        exclude_directories = 0,
    )
]]
