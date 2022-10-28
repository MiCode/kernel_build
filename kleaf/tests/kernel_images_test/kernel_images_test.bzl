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
 Test Ramdisk Options.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", "kernel_images")
load("//build/kernel/kleaf:kernel.bzl", "kernel_build", "kernel_modules_install")

# Check effect of ramdisk_options -- compress format and arguments.
def _initramfs_test_impl(ctx):
    env = analysistest.begin(ctx)
    found_action = False
    for action in analysistest.target_actions(env):
        if action.mnemonic == "Initramfs":
            for arg in action.argv:
                if ctx.attr.expected_compress_args in arg:
                    found_action = True
                    break

    asserts.equals(
        env,
        actual = found_action,
        expected = True,
        msg = "expected_compress_args = {} not found.".format(
            ctx.attr.expected_compress_args,
        ),
    )
    return analysistest.end(env)

_initramfs_test = analysistest.make(
    impl = _initramfs_test_impl,
    attrs = {
        "expected_compress_args": attr.string(),
    },
)

# Check effect of ramdisk_options -- ramdisk extension in boot image.
def _boot_image_test_impl(ctx):
    env = analysistest.begin(ctx)
    file_expected = "ramdisk.{}".format(ctx.attr.expected_compress_ext)
    found_file = False
    for action in analysistest.target_actions(env):
        if action.mnemonic == "BootImages":
            for arg in action.argv:
                if file_expected in arg:
                    found_file = True
                    break

    asserts.equals(
        env,
        actual = found_file,
        expected = True,
        msg = "file_expected = {} not found.".format(file_expected),
    )
    return analysistest.end(env)

_boot_image_test = analysistest.make(
    impl = _boot_image_test_impl,
    attrs = {
        "expected_compress_ext": attr.string(),
    },
)

def initramfs_test(name):
    """Define tests for `ramdisk_options`.

    Args:
      name: Name of this test suite.
    """

    # Test setup
    kernel_build(
        name = name + "build",
        build_config = "build.config.fake",
        outs = [
            # This is a requirement (for more, see initramfs.bzl).
            "System.map",
        ],
        tags = ["manual"],
    )
    kernel_modules_install(
        name = name + "modules_install",
        kernel_build = name + "build",
        tags = ["manual"],
    )

    tests = []

    # Fallback to config values.
    kernel_images(
        name = name + "fallback_image",
        kernel_modules_install = name + "modules_install",
        build_initramfs = True,
        kernel_build = name + "build",
        build_boot = True,
        tags = ["manual"],
    )
    _initramfs_test(
        name = name + "fallback_test",
        target_under_test = name + "fallback_image_initramfs",
        expected_compress_args = "${RAMDISK_COMPRESS}",
    )
    tests.append(name + "fallback_test")
    _boot_image_test(
        name = name + "fallback_boot_test",
        target_under_test = name + "fallback_image_boot_images",
        expected_compress_ext = "lz4",
    )
    tests.append(name + "fallback_boot_test")

    # Explicitly using GZIP
    kernel_images(
        name = name + "gzip_image",
        kernel_modules_install = name + "modules_install",
        build_initramfs = True,
        kernel_build = name + "build",
        build_boot = True,
        ramdisk_compression = "gzip",
        tags = ["manual"],
    )
    _initramfs_test(
        name = name + "gzip_test",
        target_under_test = name + "gzip_image_initramfs",
        expected_compress_args = "gzip -c -f",
    )
    tests.append(name + "gzip_test")
    _boot_image_test(
        name = name + "gzip_boot_test",
        target_under_test = name + "gzip_image_boot_images",
        expected_compress_ext = "gz",
    )
    tests.append(name + "gzip_boot_test")

    # Explicitly using LZ4 with default arguments
    kernel_images(
        name = name + "lz4_default_image",
        kernel_modules_install = name + "modules_install",
        build_initramfs = True,
        kernel_build = name + "build",
        build_boot = True,
        ramdisk_compression = "lz4",
        tags = ["manual"],
    )
    _initramfs_test(
        name = name + "lz4_default_test",
        target_under_test = name + "lz4_default_image_initramfs",
        expected_compress_args = "-12 --favor-decSpeed",
    )
    tests.append(name + "lz4_default_test")
    _boot_image_test(
        name = name + "lz4_default_boot_test",
        target_under_test = name + "lz4_default_image_boot_images",
        expected_compress_ext = "lz4",
    )
    tests.append(name + "lz4_default_boot_test")

    # Explicitly using LZ4 with custom arguments
    kernel_images(
        name = name + "lz4_custom_image",
        kernel_modules_install = name + "modules_install",
        build_initramfs = True,
        kernel_build = name + "build",
        build_boot = True,
        ramdisk_compression = "lz4",
        ramdisk_compression_args = "-foo --bar",
        tags = ["manual"],
    )
    _initramfs_test(
        name = name + "lz4_custom_test",
        target_under_test = name + "lz4_custom_image_initramfs",
        expected_compress_args = "-foo --bar",
    )
    tests.append(name + "lz4_custom_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
