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

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":utils.bzl", "utils")

def _gki_artifacts_impl(ctx):
    inputs = [
        ctx.file.mkbootimg,
        ctx.file._build_utils_sh,
    ]
    inputs += ctx.files.srcs
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    tarball = ctx.actions.declare_file("{}/boot-img.tar.gz".format(ctx.label.name))
    dist_dir = tarball.dirname

    outs = [tarball]
    size_cmd = ""
    for image in ctx.files.srcs:
        if image.basename == "Image":
            outs.append(ctx.actions.declare_file("{}/boot.img".format(ctx.label.name)))
            size_key = ""
            var_name = ""
        else:
            compression = utils.removeprefix(image.basename, "Image.")
            outs.append(ctx.actions.declare_file("{}/boot-{}.img".format(ctx.label.name, compression)))
            size_key = compression
            var_name = "_" + compression.upper()

        size = ctx.attr.boot_img_sizes.get(size_key)
        if not size:
            fail("""{}: Missing key "{}" in boot_img_sizes for src {}.""".format(ctx.label, size_key, image.basename))
        size_cmd += """
            export BUILD_GKI_BOOT_IMG{var_name}_SIZE={size}
        """.format(var_name = var_name, size = size)

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        source {build_utils_sh}
        cp -pl -t {dist_dir} {srcs}
        export GKI_KERNEL_CMDLINE={quoted_gki_kernel_cmdline}
        export DIST_DIR=$(readlink -e {dist_dir})
        export MKBOOTIMG_PATH={mkbootimg}
        {size_cmd}
        build_gki_artifacts
    """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
        dist_dir = dist_dir,
        srcs = " ".join([src.path for src in ctx.files.srcs]),
        quoted_gki_kernel_cmdline = shell.quote(ctx.attr.gki_kernel_cmdline),
        mkbootimg = ctx.file.mkbootimg.path,
        size_cmd = size_cmd,
    )

    ctx.actions.run_shell(
        command = command,
        inputs = inputs,
        outputs = outs,
        mnemonic = "GkiArtifacts",
        progress_message = "Building GKI artifacts {}".format(ctx.label),
    )

    return DefaultInfo(files = depset(outs))

gki_artifacts = rule(
    implementation = _gki_artifacts_impl,
    doc = "`BUILD_GKI_ARTIFACTS`. Build boot images and `boot-img.tar.gz` as default outputs.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "A list of `Image` and `Image.*` from [`kernel_build`](#kernel_build).",
        ),
        "mkbootimg": attr.label(
            allow_single_file = True,
            default = "//tools/mkbootimg:mkbootimg.py",
            doc = "path to the `mkbootimg.py` script; `MKBOOTIMG_PATH`.",
        ),
        "boot_img_sizes": attr.string_dict(
            doc = """A dictionary, with key is the compression algorithm, and value
is the size of the boot image.

For example:
```
{
    "":    str(64 * 1024 * 1024), # For Image and boot.img
    "lz4": str(64 * 1024 * 1024), # For Image.lz4 and boot-lz4.img
}
```
""",
        ),
        "gki_kernel_cmdline": attr.string(doc = "`GKI_KERNEL_CMDLINE`."),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils.sh"),
        ),
    },
)
