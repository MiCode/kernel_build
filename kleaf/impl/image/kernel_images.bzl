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

load(":image/boot_images.bzl", "boot_images")
load(":image/dtbo.bzl", "dtbo")
load(":image/initramfs.bzl", "initramfs")
load(":image/system_dlkm_image.bzl", "system_dlkm_image")
load(":image/vendor_dlkm_image.bzl", "vendor_dlkm_image")

def kernel_images(
        name,
        kernel_modules_install,
        kernel_build = None,
        base_kernel_images = None,
        build_initramfs = None,
        build_vendor_dlkm = None,
        build_boot = None,
        build_vendor_boot = None,
        build_vendor_kernel_boot = None,
        build_system_dlkm = None,
        build_dtbo = None,
        dtbo_srcs = None,
        mkbootimg = None,
        deps = None,
        boot_image_outs = None,
        modules_list = None,
        modules_blocklist = None,
        modules_options = None,
        vendor_ramdisk_binaries = None,
        system_dlkm_modules_list = None,
        system_dlkm_modules_blocklist = None,
        system_dlkm_props = None,
        vendor_dlkm_modules_list = None,
        vendor_dlkm_modules_blocklist = None,
        vendor_dlkm_props = None):
    """Build multiple kernel images.

    Args:
        name: name of this rule, e.g. `kernel_images`,
        kernel_modules_install: A `kernel_modules_install` rule.

          The main kernel build is inferred from the `kernel_build` attribute of the
          specified `kernel_modules_install` rule. The main kernel build must contain
          `System.map` in `outs` (which is included if you use `aarch64_outs` or
          `x86_64_outs` from `common_kernels.bzl`).
        kernel_build: A `kernel_build` rule. Must specify if `build_boot`.
        mkbootimg: Path to the mkbootimg.py script which builds boot.img.
          Keep in sync with `MKBOOTIMG_PATH`. Only used if `build_boot`. If `None`,
          default to `//tools/mkbootimg:mkbootimg.py`.
        deps: Additional dependencies to build images.

          This must include the following:
          - For `initramfs`:
            - The file specified by `MODULES_LIST`
            - The file specified by `MODULES_BLOCKLIST`, if `MODULES_BLOCKLIST` is set
          - For `vendor_dlkm` image:
            - The file specified by `VENDOR_DLKM_MODULES_LIST`
            - The file specified by `VENDOR_DLKM_MODULES_BLOCKLIST`, if set
            - The file specified by `VENDOR_DLKM_PROPS`, if set
            - The file specified by `selinux_fc` in `VENDOR_DLKM_PROPS`, if set

        boot_image_outs: A list of output files that will be installed to `DIST_DIR` when
          `build_boot_images` in `build/kernel/build_utils.sh` is executed.

          You may leave out `vendor_boot.img` from the list. It is automatically added when
          `build_vendor_boot = True`.

          If `build_boot` is equal to `False`, the default is empty.

          If `build_boot` is equal to `True`, the default list assumes the following:
          - `BOOT_IMAGE_FILENAME` is not set (which takes default value `boot.img`), or is set to
            `"boot.img"`
          - `vendor_boot.img` if `build_vendor_boot`
          - `RAMDISK_EXT=lz4`. If the build configuration has a different value, replace
            `ramdisk.lz4` with `ramdisk.{RAMDISK_EXT}` accordingly.
          - `BOOT_IMAGE_HEADER_VERSION >= 4`, which creates `vendor-bootconfig.img` to contain
            `VENDOR_BOOTCONFIG`
          - The list contains `dtb.img`
        build_initramfs: Whether to build initramfs. Keep in sync with `BUILD_INITRAMFS`.
        build_system_dlkm: Whether to build system_dlkm.img an image with GKI modules.
        build_vendor_dlkm: Whether to build `vendor_dlkm` image. It must be set if
          `vendor_dlkm_modules_list` is set.

          Note: at the time of writing (Jan 2022), unlike `build.sh`,
          `vendor_dlkm.modules.blocklist` is **always** created
          regardless of the value of `VENDOR_DLKM_MODULES_BLOCKLIST`.
          If `build_vendor_dlkm()` in `build_utils.sh` does not generate
          `vendor_dlkm.modules.blocklist`, an empty file is created.
        build_boot: Whether to build boot image. It must be set if either `BUILD_BOOT_IMG`
          or `BUILD_VENDOR_BOOT_IMG` is set.

          This depends on `initramfs` and `kernel_build`. Hence, if this is set to `True`,
          `build_initramfs` is implicitly true, and `kernel_build` must be set.

          If `True`, adds `boot.img` to `boot_image_outs` if not already in the list.
        build_vendor_boot: Whether to build `vendor_boot.img`. It must be set if either
          `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set,
          and `BUILD_VENDOR_KERNEL_BOOT` is not set.

          At most **one** of `build_vendor_boot` and `build_vendor_kernel_boot` may be set to
          `True`.

          If `True`, adds `vendor_boot.img` to `boot_image_outs` if not already in the list.

        build_vendor_kernel_boot: Whether to build `vendor_kernel_boot.img`. It must be set if either
          `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set,
          and `BUILD_VENDOR_KERNEL_BOOT` is set.

          At most **one** of `build_vendor_boot` and `build_vendor_kernel_boot` may be set to
          `True`.

          If `True`, adds `vendor_kernel_boot.img` to `boot_image_outs` if not already in the list.
        build_dtbo: Whether to build dtbo image. Keep this in sync with `BUILD_DTBO_IMG`.

          If `dtbo_srcs` is non-empty, `build_dtbo` is `True` by default. Otherwise it is `False`
          by default.
        dtbo_srcs: list of `*.dtbo` files used to package the `dtbo.img`. Keep this in sync
          with `MKDTIMG_DTBOS`; see example below.

          If `dtbo_srcs` is non-empty, `build_dtbo` must not be explicitly set to `False`.

          Example:
          ```
          kernel_build(
              name = "tuna_kernel",
              outs = [
                  "path/to/foo.dtbo",
                  "path/to/bar.dtbo",
              ],
          )
          kernel_images(
              name = "tuna_images",
              kernel_build = ":tuna_kernel",
              dtbo_srcs = [
                  ":tuna_kernel/path/to/foo.dtbo",
                  ":tuna_kernel/path/to/bar.dtbo",
              ]
          )
          ```
        base_kernel_images: The `kernel_images()` corresponding to the `base_kernel` of the
          `kernel_build`. This is necessary for building a device-specific `system_dlkm` image.
          For example, if `base_kernel` of `kernel_build()` is `//common:kernel_aarch64`,
          then `base_kernel_images` is `//common:kernel_aarch64_images`.
        modules_list: A file containing list of modules to use for `vendor_boot.modules.load`.

          This corresponds to `MODULES_LIST` in `build.config` for `build.sh`.
        modules_blocklist: A file containing a list of modules which are
          blocked from being loaded.

          This file is copied directly to staging directory, and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        modules_options: Label to a file copied to `/lib/modules/<kernel_version>/modules.options` on the ramdisk.

          Lines in the file should be of the form:
          ```
          options <modulename> <param1>=<val> <param2>=<val> ...
          ```

          This corresponds to `MODULES_OPTIONS` in `build.config` for `build.sh`.
        system_dlkm_modules_list: location of an optional file
          containing the list of kernel modules which shall be copied into a
          system_dlkm partition image.

          This corresponds to `SYSTEM_DLKM_MODULES_LIST` in `build.config` for `build.sh`.
        system_dlkm_modules_blocklist: location of an optional file containing a list of modules
          which are blocked from being loaded.

          This file is copied directly to the staging directory and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `SYSTEM_DLKM_MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        system_dlkm_props: location of a text file containing
          the properties to be used for creation of a `system_dlkm` image
          (filesystem, partition size, etc). If this is not set (and
          `build_system_dlkm` is), a default set of properties will be used
          which assumes an ext4 filesystem and a dynamic partition.

          This corresponds to `SYSTEM_DLKM_PROPS` in `build.config` for `build.sh`.
        vendor_dlkm_modules_list: location of an optional file
          containing the list of kernel modules which shall be copied into a
          `vendor_dlkm` partition image. Any modules passed into `MODULES_LIST` which
          become part of the `vendor_boot.modules.load` will be trimmed from the
          `vendor_dlkm.modules.load`.

          This corresponds to `VENDOR_DLKM_MODULES_LIST` in `build.config` for `build.sh`.
        vendor_dlkm_modules_blocklist: location of an optional file containing a list of modules
          which are blocked from being loaded.

          This file is copied directly to the staging directory and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `VENDOR_DLKM_MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        vendor_dlkm_props: location of a text file containing
          the properties to be used for creation of a `vendor_dlkm` image
          (filesystem, partition size, etc). If this is not set (and
          `build_vendor_dlkm` is), a default set of properties will be used
          which assumes an ext4 filesystem and a dynamic partition.

          This corresponds to `VENDOR_DLKM_PROPS` in `build.config` for `build.sh`.
        vendor_ramdisk_binaries: List of vendor ramdisk binaries
          which includes the device-specific components of ramdisk like the fstab
          file and the device-specific rc files. If specifying multiple vendor ramdisks
          and identical file paths exist in the ramdisks, the file from last ramdisk is used.

          Note: **order matters**. To prevent buildifier from sorting the list, add the following:
          ```
          # do not sort
          ```

          This corresponds to `VENDOR_RAMDISK_BINARY` in `build.config` for `build.sh`.
    """
    all_rules = []

    build_any_boot_image = build_boot or build_vendor_boot or build_vendor_kernel_boot
    if build_any_boot_image:
        if kernel_build == None:
            fail("{}: Must set kernel_build if any of these are true: build_boot={}, build_vendor_boot={}, build_vendor_kernel_boot={}".format(name, build_boot, build_vendor_boot, build_vendor_kernel_boot))

    # Set default value for boot_image_outs according to build_boot
    if boot_image_outs == None:
        if not build_any_boot_image:
            boot_image_outs = []
        else:
            boot_image_outs = [
                "dtb.img",
                "ramdisk.lz4",
                "vendor-bootconfig.img",
            ]

    boot_image_outs = list(boot_image_outs)

    if build_boot and "boot.img" not in boot_image_outs:
        boot_image_outs.append("boot.img")

    if build_vendor_boot and "vendor_boot.img" not in boot_image_outs:
        boot_image_outs.append("vendor_boot.img")

    if build_vendor_kernel_boot and "vendor_kernel_boot.img" not in boot_image_outs:
        boot_image_outs.append("vendor_kernel_boot.img")

    vendor_boot_modules_load = None
    if build_initramfs:
        if build_vendor_boot:
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name)
        elif build_vendor_kernel_boot:
            vendor_boot_modules_load = "{}_initramfs/vendor_kernel_boot.modules.load".format(name)

        initramfs(
            name = "{}_initramfs".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
            vendor_boot_modules_load = vendor_boot_modules_load,
            modules_list = modules_list,
            modules_blocklist = modules_blocklist,
            modules_options = modules_options,
        )
        all_rules.append(":{}_initramfs".format(name))

    if build_system_dlkm:
        system_dlkm_image(
            name = "{}_system_dlkm_image".format(name),
            # For GKI system_dlkm
            kernel_modules_install = kernel_modules_install,
            # For device system_dlkm, give GKI's system_dlkm_staging_archive.tar.gz
            base_kernel_images = base_kernel_images,
            deps = deps,
            modules_list = modules_list,
            modules_blocklist = modules_blocklist,
            system_dlkm_modules_list = system_dlkm_modules_list,
            system_dlkm_modules_blocklist = system_dlkm_modules_blocklist,
            system_dlkm_props = system_dlkm_props,
        )
        all_rules.append(":{}_system_dlkm_image".format(name))

    if build_vendor_dlkm:
        vendor_dlkm_image(
            name = "{}_vendor_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            vendor_boot_modules_load = vendor_boot_modules_load,
            deps = deps,
            vendor_dlkm_modules_list = vendor_dlkm_modules_list,
            vendor_dlkm_modules_blocklist = vendor_dlkm_modules_blocklist,
            vendor_dlkm_props = vendor_dlkm_props,
        )
        all_rules.append(":{}_vendor_dlkm_image".format(name))

    if build_any_boot_image:
        if build_vendor_kernel_boot:
            vendor_boot_name = "vendor_kernel_boot"
        elif build_vendor_boot:
            vendor_boot_name = "vendor_boot"
        else:
            vendor_boot_name = None
        boot_images(
            name = "{}_boot_images".format(name),
            kernel_build = kernel_build,
            outs = ["{}_boot_images/{}".format(name, out) for out in boot_image_outs],
            deps = deps,
            initramfs = ":{}_initramfs".format(name) if build_initramfs else None,
            mkbootimg = mkbootimg,
            vendor_ramdisk_binaries = vendor_ramdisk_binaries,
            build_boot = build_boot,
            vendor_boot_name = vendor_boot_name,
        )
        all_rules.append(":{}_boot_images".format(name))

    if build_dtbo == None:
        build_dtbo = bool(dtbo_srcs)

    if dtbo_srcs:
        if not build_dtbo:
            fail("{}: build_dtbo must be True if dtbo_srcs is non-empty.")

    if build_dtbo:
        dtbo(
            name = "{}_dtbo".format(name),
            srcs = dtbo_srcs,
            kernel_build = kernel_build,
        )
        all_rules.append(":{}_dtbo".format(name))

    native.filegroup(
        name = name,
        srcs = all_rules,
    )
