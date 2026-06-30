# Copyright (C) 2024 The Android Open Source Project
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

"""Provides alternative declaration to kernel_images()"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":image/or_file.bzl", "OrFileInfo")

visibility("private")

def _quote_opt_str(s):
    """Quote an optional string.

    If None, return a quoted empty string. Otherwise quote.

    Args:
        s: str or None
    """
    if not s:
        s = ""
    return shell.quote(str(s))

def _sanitize_opt_label(label):
    """Sanitize an optional label.

    If None, return None. Otherwise, return sanitized string.

    Args:
        label: str or None
    """
    if not label:
        return None
    return str(label).replace("@@//", "//").replace("@//", "//")

def _kernel_images_replace_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    args = []
    args.extend(["--ban", "generator_name"])
    args.extend(["--ban", "generator_function"])
    args.extend(["--ban", "generator_location"])
    args.extend(["--ban", "avb_sign_boot_img"])
    args.extend(["--ban", "avb_boot_"])
    args.extend(["--replace", "kleaf_internal_legacy_ext4_single", "ext4"])

    # Use repr() to replace the quoted string as a whole with possibly the None repr.
    if ctx.attr.selected_modules_list:
        args.extend([
            "--replace",
            repr(_sanitize_opt_label(ctx.attr.selected_modules_list.label)),
            repr(_sanitize_opt_label(ctx.attr.selected_modules_list[OrFileInfo].selected_label)),
        ])

    if ctx.attr.selected_modules_blocklist:
        args.extend([
            "--replace",
            repr(_sanitize_opt_label(ctx.attr.selected_modules_blocklist.label)),
            repr(_sanitize_opt_label(ctx.attr.selected_modules_blocklist[OrFileInfo].selected_label)),
        ])

    images_name = ctx.label.name.removesuffix("_replace")
    sanitized_images_name = images_name.removesuffix("_images")
    args.extend([
        "--replace",
        _sanitize_opt_label(images_name),
        _sanitize_opt_label(sanitized_images_name),
    ])

    boot_images_name = sanitized_images_name + "_boot_images"
    vendor_boot_name = sanitized_images_name + "_vendor_boot_image"
    args.extend([
        "--replace",
        _sanitize_opt_label(boot_images_name),
        _sanitize_opt_label(vendor_boot_name),
    ])
    args.extend([
        "--replace",
        _sanitize_opt_label(ctx.label).removesuffix(":" + ctx.label.name) + ":",
        ":",
    ])
    args.extend([
        "--replace",
        "boot_images(",
        """\
# FIXME: The script blindly turns boot_images into vendor_boot_image.
# However, if vendor_boot_name is not set, this target should be deleted.
vendor_boot_image(
  # FIXME: If unpack_ramdisk is not set below, you must explicitly set it.
  #   Check value of SKIP_UNPACKING_RAMDISK in your build config. If unsure, use True.
  # unpack_ramdisk = ?,""",
    ])
    args.extend([
        "--replace",
        "build_boot = True",
        "# FIXME: Please file a bug on Kleaf team to support building boot image.\n  # build_boot = True",
    ])

    content = hermetic_tools.setup + """#!/bin/sh -e
        exec {bin} {process_args}
    """.format(
        bin = ctx.executable._bin.short_path,
        process_args = " ".join([_quote_opt_str(arg) for arg in args]),
    )
    file = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.write(file, content)
    runfiles = ctx.runfiles(transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge(ctx.attr._bin[DefaultInfo].default_runfiles)

    return DefaultInfo(
        files = depset([file]),
        executable = file,
        runfiles = runfiles,
    )

kernel_images_replace = rule(
    implementation = _kernel_images_replace_impl,
    attrs = {
        "selected_modules_list": attr.label(providers = [OrFileInfo]),
        "selected_modules_blocklist": attr.label(providers = [OrFileInfo]),
        "_bin": attr.label(
            default = ":image/kernel_images_replace",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    toolchains = [hermetic_toolchain.type],
)
