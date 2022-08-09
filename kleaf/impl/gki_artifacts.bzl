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
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(":common_providers.bzl", "KernelBuildInfo")
load(":constants.bzl", "GKI_ARTIFACTS_AARCH64_OUTS")
load(":utils.bzl", "utils")

def _gki_artifacts_impl(ctx):
    inputs = [
        ctx.file.mkbootimg,
        ctx.file._build_utils_sh,
        ctx.file._testkey,
    ]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    kernel_release = ctx.attr.kernel_build[KernelBuildInfo].kernel_release
    inputs.append(kernel_release)

    outs = []

    # build_gki_artifacts_aarch64 builds boot-img.tar.gz additionally.
    # build_gki_artifacts_x86_64 does not build boot-img.tar.gz.
    if ctx.attr.arch == "arm64":
        tarball = ctx.actions.declare_file("{}/boot-img.tar.gz".format(ctx.label.name))
        outs.append(tarball)
        gki_info = ctx.actions.declare_file("{}/gki-info.txt".format(ctx.label.name))
        outs.append(gki_info)

    size_cmd = ""
    images = []
    for image in ctx.files.kernel_build:
        if image.basename in ("Image", "bzImage"):
            outs.append(ctx.actions.declare_file("{}/boot.img".format(ctx.label.name)))
            size_key = ""
            var_name = ""
        elif image.basename.startswith("Image."):
            compression = image.basename.removeprefix("Image.")
            outs.append(ctx.actions.declare_file("{}/boot-{}.img".format(ctx.label.name, compression)))
            size_key = compression
            var_name = "_" + compression.upper()
        else:
            # Not an image
            continue

        images.append(image)
        size = ctx.attr.boot_img_sizes.get(size_key)
        if not size:
            fail("""{}: Missing key "{}" in boot_img_sizes for image {}.""".format(ctx.label, size_key, image.basename))
        size_cmd += """
            export BUILD_GKI_BOOT_IMG{var_name}_SIZE={size}
        """.format(var_name = var_name, size = size)

    inputs += images

    # All declare_file's above are "<name>/<filename>" without subdirectories,
    # so using outs[0] is good enough.
    dist_dir = outs[0].dirname
    out_dir = paths.join(utils.intermediates_dir(ctx), "out_dir")

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        source {build_utils_sh}
        cp -pl -t {dist_dir} {images}
        mkdir -p {out_dir}/include/config
        cp -pl {kernel_release} {out_dir}/include/config/kernel.release
        export GKI_KERNEL_CMDLINE={quoted_gki_kernel_cmdline}
        export ARCH={quoted_arch}
        export DIST_DIR=$(readlink -e {dist_dir})
        export OUT_DIR=$(readlink -e {out_dir})
        export MKBOOTIMG_PATH={mkbootimg}
        {size_cmd}
        build_gki_artifacts
    """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
        dist_dir = dist_dir,
        images = " ".join([image.path for image in images]),
        out_dir = out_dir,
        kernel_release = kernel_release.path,
        quoted_gki_kernel_cmdline = shell.quote(ctx.attr.gki_kernel_cmdline),
        quoted_arch = shell.quote(ctx.attr.arch),
        mkbootimg = ctx.file.mkbootimg.path,
        size_cmd = size_cmd,
    )

    if ctx.attr.arch == "arm64":
        utils.compare_file_names(
            outs,
            GKI_ARTIFACTS_AARCH64_OUTS,
            what = "{}: Internal error: not producing the expected list of outputs".format(ctx.label),
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
    doc = "`BUILD_GKI_ARTIFACTS`. Build boot images and optionally `boot-img.tar.gz` as default outputs.",
    attrs = {
        "kernel_build": attr.label(
            providers = [KernelBuildInfo],
            doc = "The [`kernel_build`](#kernel_build) that provides all `Image` and `Image.*`.",
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
        "arch": attr.string(doc = "`ARCH`.", values = ["arm64", "x86_64"], mandatory = True),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils.sh"),
        ),
        "_testkey": attr.label(default = "//tools/mkbootimg:gki/testdata/testkey_rsa4096.pem", allow_single_file = True),
    },
)
