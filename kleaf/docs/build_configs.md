# Build configs

This document provides reference to the Bazel equivalent or alternative for
the legacy build configs.

For build configs with a Bazel equivalent / alternative, a code snippet and a
link to the [documentation for all rules] is provided. You may look up the
relevant macros, rules and attributes in the documentation.

For build configs that should be kept in `build.config` files, the text
_"Specify in the build config"_ is displayed.

For build configs that are set to a fixed value in Bazel, the text
_"Not customizable in Bazel"_ is displayed. Contact [owners](../OWNERS) if you
need to customize this.

For build configs that are not used in Bazel with alternatives provided, the
text _"Not used in Bazel."_ is displayed.

For build configs that are not supported, the text
_"Not supported"_ is displayed. Contact [owners](../OWNERS) if you need support.

[TOC]

- [Build configs](#build-configs)
  - [BUILD\_CONFIG](#build_config)
  - [BUILD\_CONFIG\_FRAGMENTS](#build_config_fragments)
  - [FAST\_BUILD](#fast_build)
  - [KERNEL\_DIR](#kernel_dir)
  - [OUT\_DIR](#out_dir)
  - [DIST\_DIR](#dist_dir)
  - [MAKE\_GOALS](#make_goals)
  - [EXT\_MODULES](#ext_modules)
  - [EXT\_MODULES\_MAKEFILE](#ext_modules_makefile)
  - [KCONFIG\_EXT\_PREFIX](#kconfig_ext_prefix)
  - [UNSTRIPPED\_MODULES](#unstripped_modules)
  - [COMPRESS\_UNSTRIPPED\_MODULES](#compress_unstripped_modules)
  - [COMPRESS\_MODULES](#compress_modules)
  - [LD](#ld)
  - [HERMETIC\_TOOLCHAIN](#hermetic_toolchain)
  - [ADDITIONAL\_HOST\_TOOLS](#additional_host_tools)
  - [ABI\_DEFINITION](#abi_definition)
  - [KMI\_SYMBOL\_LIST](#kmi_symbol_list)
  - [ADDITIONAL\_KMI\_SYMBOL\_LISTS](#additional_kmi_symbol_lists)
  - [KMI\_ENFORCED](#kmi_enforced)
  - [GENERATE\_VMLINUX\_BTF](#generate_vmlinux_btf)
  - [SKIP\_MRPROPER](#skip_mrproper)
  - [SKIP\_DEFCONFIG](#skip_defconfig)
  - [SKIP\_IF\_VERSION\_MATCHES](#skip_if_version_matches)
  - [DEFCONFIG](#defconfig)
  - [PRE\_DEFCONFIG\_CMDS](#pre_defconfig_cmds)
  - [FRAGMENT\_CONFIG](#fragment_config)
  - [POST\_DEFCONFIG\_CMDS](#post_defconfig_cmds)
  - [POST\_KERNEL\_BUILD\_CMDS](#post_kernel_build_cmds)
  - [LTO](#lto)
  - [TAGS\_CONFIG](#tags_config)
  - [IN\_KERNEL\_MODULES](#in_kernel_modules)
  - [SKIP\_EXT\_MODULES](#skip_ext_modules)
  - [DO\_NOT\_STRIP\_MODULES](#do_not_strip_modules)
  - [EXTRA\_CMDS](#extra_cmds)
  - [DIST\_CMDS](#dist_cmds)
  - [SKIP\_CP\_KERNEL\_HDR](#skip_cp_kernel_hdr)
  - [BUILD\_BOOT\_IMG](#build_boot_img)
  - [BUILD\_VENDOR\_BOOT\_IMG](#build_vendor_boot_img)
  - [SKIP\_VENDOR\_BOOT](#skip_vendor_boot)
  - [VENDOR\_RAMDISK\_CMDS](#vendor_ramdisk_cmds)
  - [SKIP\_UNPACKING\_RAMDISK](#skip_unpacking_ramdisk)
  - [AVB\_SIGN\_BOOT\_IMG](#avb_sign_boot_img)
  - [AVB\_BOOT\_PARTITION\_SIZE](#avb_boot_partition_size)
  - [AVB\_BOOT\_KEY](#avb_boot_key)
  - [AVB\_BOOT\_ALGORITHM](#avb_boot_algorithm)
  - [AVB\_BOOT\_PARTITION\_NAME](#avb_boot_partition_name)
  - [BUILD\_INITRAMFS](#build_initramfs)
  - [MODULES\_OPTIONS](#modules_options)
  - [MODULES\_ORDER](#modules_order)
  - [GKI\_MODULES\_LIST](#gki_modules_list)
  - [VENDOR\_DLKM\_FS\_TYPE](#vendor_dlkm_fs_type)
  - [VENDOR\_DLKM\_ETC\_FILES](#vendor_dlkm_etc_files)
  - [VENDOR\_DLKM\_MODULES\_LIST](#vendor_dlkm_modules_list)
  - [VENDOR\_DLKM\_MODULES\_BLOCKLIST](#vendor_dlkm_modules_blocklist)
  - [VENDOR\_DLKM\_PROPS](#vendor_dlkm_props)
  - [SYSTEM\_DLKM\_FS\_TYPE](#system_dlkm_fs_type)
  - [SYSTEM\_DLKM\_MODULES\_LIST](#system_dlkm_modules_list)
  - [SYSTEM\_DLKM\_MODULES\_BLOCKLIST](#system_dlkm_modules_blocklist)
  - [SYSTEM\_DLKM\_PROPS](#system_dlkm_props)
  - [LZ4\_RAMDISK](#lz4_ramdisk)
  - [LZ4\_RAMDISK\_COMPRESS\_ARGS](#lz4_ramdisk_compress_args)
  - [TRIM\_NONLISTED\_KMI](#trim_nonlisted_kmi)
  - [KMI\_SYMBOL\_LIST\_STRICT\_MODE](#kmi_symbol_list_strict_mode)
  - [KMI\_STRICT\_MODE\_OBJECTS](#kmi_strict_mode_objects)
  - [GKI\_DIST\_DIR](#gki_dist_dir)
  - [GKI\_BUILD\_CONFIG](#gki_build_config)
  - [GKI\_PREBUILTS\_DIR](#gki_prebuilts_dir)
  - [BUILD\_DTBO\_IMG](#build_dtbo_img)
  - [DTS\_EXT\_DIR](#dts_ext_dir)
  - [BUILD\_GKI\_CERTIFICATION\_TOOLS](#build_gki_certification_tools)
  - [BUILD\_VENDOR\_KERNEL\_BOOT](#build_vendor_kernel_boot)
  - [MKBOOTIMG\_PATH](#mkbootimg_path)
  - [BUILD\_GKI\_ARTIFACTS](#build_gki_artifacts)
  - [GKI\_KERNEL\_CMDLINE](#gki_kernel_cmdline)
  - [KBUILD\_SYMTYPES](#kbuild_symtypes)
  - [KMI\_SYMBOL\_LIST\_ADD\_ONLY](#kmi_symbol_list_add_only)
  - [KCFLAGS](#kcflags)
  - [VENDOR\_BOOTCONFIG](#vendor_bootconfig)

## BUILD\_CONFIG

```python
kernel_build(build_config=...)
```

See [documentation for all rules].

## BUILD\_CONFIG\_FRAGMENTS

```python
kernel_build_config()
```

See [documentation for all rules].

## FAST\_BUILD

Not used in Bazel. Alternatives:

You may disable LTO or use thin LTO; see [`LTO`](#LTO).

You may use `--config=fast` to build faster.
See [fast.md](fast.md) for details.

You may build just the kernel binary and GKI modules, without headers and
installing modules by building the `kernel_build` target, e.g.

```shell
$ bazel build //common:kernel_aarch64
```

## KERNEL\_DIR

```python
kernel_build(makefile = ...)
```

If you set `KERNEL_DIR=common` in your build config, set
`makefile = "//common:Makefile"` instead.

If you did not set `KERNEL_DIR` in your build config, then set `kernel_dir` to
the `Makefile` next to the build config file.

If your use case is different from any of the above, or you would like to
understand the mechanics of this attribute, see
[kernel_build.makefile](api_reference/kernel.md#kernel_build-makefile).

## OUT\_DIR

Not used in Bazel. Alternatives:

You may customize [`DIST_DIR`](#dist_dir). See below.

## DIST\_DIR

You may specify it statically with

```python
pkg_install(destdir=...)
```

You may override it in the command line with `--destdir`:

```shell
$ bazel run ..._dist -- --destdir=...
```

See [documentation for all rules].

## MAKE\_GOALS

```python
kernel_build(
  make_goals = ...
)
```

See [documentation for all rules].

## EXT\_MODULES

```python
ddk_module()
```

NOTE: Prefer `ddk_module` over the legacy `kernel_module`.

See [documentation for all rules].

## EXT\_MODULES\_MAKEFILE

Not used in Bazel.

Reason: `EXT_MODULES_MAKEFILE` supports building external kernel modules in
parallel. This is naturally supported in Bazel.

## KCONFIG\_EXT\_PREFIX

```python
kernel_build(kconfig_ext=...)
```

See [documentation for all rules].

## UNSTRIPPED\_MODULES

```python
kernel_build(collect_unstripped_modules=...)
kernel_filegroup(collect_unstripped_modules=...)
```

See [documentation for all rules].

## COMPRESS\_UNSTRIPPED\_MODULES

```python
kernel_unstripped_modules_archive()
```

See [documentation for all rules].

## COMPRESS\_MODULES

Not supported. Contact [owners](../OWNERS) if you need support for this config.

## LD

Not customizable in Bazel. Alternatives: use `--user_clang_toolchain` to specify
a custom clang toolchain.

## HERMETIC\_TOOLCHAIN

Not customizable in Bazel.

Reason: This is the default for Bazel builds. Its value cannot be changed.

See [Ensuring hermeticity](hermeticity.md) for details about ensuring
hermeticity.

See [documentation for all rules].

## ADDITIONAL\_HOST\_TOOLS

Not customizable in Bazel.

Reason: The list of host tools are fixed and specified in `hermetic_tools()`.

See [documentation for all rules].

## ABI\_DEFINITION

Not used in Bazel. Alternatives:

The XML format of ABI definition is no longer supported. The STG format
of ABI definition may be set with the following:

```python
kernel_abi(abi_definition_stg=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## KMI\_SYMBOL\_LIST

```python
kernel_build(kmi_symbol_list=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## ADDITIONAL\_KMI\_SYMBOL\_LISTS

```python
kernel_build(additional_kmi_symbol_lists=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## KMI\_ENFORCED

```python
kernel_abi(kmi_enforced=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## GENERATE\_VMLINUX\_BTF

```python
kernel_build(generate_vmlinux_btf=...)
```

See [documentation for all rules].

## SKIP\_MRPROPER

Not used in Bazel. Alternatives:

- For sandbox builds, the `$OUT_DIR` always starts with no contents (as if
  `SKIP_MRPROPER=`).
- For non-sandbox builds, the `$OUT_DIR` is always cached (as if
  `SKIP_MRPROPER=1`). You may clean its contents with `bazel clean`.

See [sandbox.md](sandbox.md).

## SKIP\_DEFCONFIG

Not used in Bazel.

Reason: Bazel automatically rebuild `make defconfig` when its relevant sources
change, as if `SKIP_DEFCONFIG` is determined automatically.

## SKIP\_IF\_VERSION\_MATCHES

Not used in Bazel.

Reason: Incremental builds are supported by default.

## DEFCONFIG

If this is an actual file below `$KERNEL_DIR/arch/$SRCARCH/configs`, use

```python
kernel_build(defconfig = ...)
```

Otherwise, if it is generated by `PRE\_DEFCONFIG\_CMDS`, see
[`PRE\_DEFCONFIG\_CMDS`](#pre_defconfig_cmds).

See [documentation for all rules].

## PRE\_DEFCONFIG\_CMDS

```python
kernel_build(
    defconfig = ...
    pre_defconfig_fragments = ...
)
```

`defconfig` should be set to the base config (e.g.
`//common:arch/arm64/configs/gki_defconfig`). `pre_defconfig_fragments` should
be set to the list of fragments you are applying, usually
[`FRAGMENT_CONFIG`](#fragment_config).

See [documentation for all rules].

## FRAGMENT_CONFIG

This is usually applied at PRE\_DEFCONFIG\_CMDS. If so, use

```python
kernel_build(pre_defconfig_fragments = ...)
```

See [documentation for all rules].

## POST\_DEFCONFIG\_CMDS

```python
kernel_build(post_defconfig_fragments = ...)
```

If your `POST_DEFCONFIG_CMDS` contains `check_defconfig`, you may also set

```python
kernel_build(check_defconfig_minimized = True)
```

See [documentation for all rules].

## POST\_KERNEL\_BUILD\_CMDS

Not supported.

Reason: commands are disallowed in general because of unclear dependency.

You may define a `genrule` target with appropriate inputs (possibly from a
`kernel_build` macro), then add the target to your `pkg_files` macro.

## LTO

```shell
$ bazel build --lto={default,none,thin,full} TARGETS
$ bazel run   --lto={default,none,thin,full} TARGETS
```

See [disable LTO during development](lto.md).

## TAGS\_CONFIG

Not supported. Contact [owners](../OWNERS) if you need support for this config.

## IN\_KERNEL\_MODULES

Not customizable in Bazel.

Reason: This is set by default in `build.config.common`. Its value cannot be
changed.

## SKIP\_EXT\_MODULES

Not used in Bazel. Alternatives:

You may skip building external modules by leaving them out in the
`bazel build` command.

## DO\_NOT\_STRIP\_MODULES

```python
kernel_build(strip_modules=...)
```

See [documentation for all rules].

## EXTRA\_CMDS

Not used in Bazel.

Reason: commands are disallowed in general because of unclear dependency.

Alternatives: You may define a `genrule` or `exec` target with appropriate
inputs, then add the target to your `pkg_files` macro.

See [documentation for `genrule`].

## DIST\_CMDS

Not used in Bazel.

Reason: commands are disallowed in general because of unclear dependency.

Alternatives: You may define a `genrule` or `exec` target with appropriate
inputs, then add the target to your `pkg_files` macro.

See [documentation for `genrule`].

## SKIP\_CP\_KERNEL\_HDR

Not used in Bazel. Alternatives:

You may skip building headers by leaving them out in the
`bazel build` command.

## BUILD\_BOOT\_IMG

Building a device-specific boot image is not supported.

**NOTE**: As an implementation detail, GKI targets invoke `gki_artifacts()`
to build the boot images.

## BUILD\_VENDOR\_BOOT\_IMG

```python
vendor_boot_image(...)
```

See [documentation for all rules].

## SKIP\_VENDOR\_BOOT

Simply remove the `vendor_boot_image()` from your dependency graph.

See [Default outputs](https://bazel.build/extending/rules#default_outputs)
for details.

## VENDOR\_RAMDISK\_CMDS

Not used in Bazel.

Reason: Commands are disallowed in general because of unclear dependency.

Alternatives: you may define a `genrule` or `exec` target with appropriate
inputs, then add the target to your `pkg_files` macro.

## SKIP\_UNPACKING\_RAMDISK

```python
vendor_boot_image(unpack_ramdisk=...)
```

See [documentation for all rules].

## AVB\_SIGN\_BOOT\_IMG

Building a device-specific boot image is not supported.

**NOTE**: As an implementation detail, GKI targets invoke `gki_artifacts()`
to build the boot images.

## AVB\_BOOT\_PARTITION\_SIZE

Building a device-specific boot image is not supported.

**NOTE**: As an implementation detail, GKI targets invoke `gki_artifacts()`
to build the boot images.

## AVB\_BOOT\_KEY
Building a device-specific boot image is not supported.

**NOTE**: As an implementation detail, GKI targets invoke `gki_artifacts()`
to build the boot images.

## AVB\_BOOT\_ALGORITHM

Building a device-specific boot image is not supported.

**NOTE**: As an implementation detail, GKI targets invoke `gki_artifacts()`
to build the boot images.

## AVB\_BOOT\_PARTITION\_NAME

Building a device-specific boot image is not supported.

**NOTE**: As an implementation detail, GKI targets invoke `gki_artifacts()`
to build the boot images.

## BUILD\_INITRAMFS

```python
initramfs(...)
```

See [documentation for all rules].

## MODULES\_OPTIONS

```python
initramfs(modules_options=...)
```

See [documentation for all rules].

## MODULES\_ORDER

Not customizable in Bazel.

Reason: The Bazel build already sets the order of loading modules for you, and
`build_utils.sh` uses it generate the `modules.load` files already.

## GKI\_MODULES\_LIST

**Note**: This config has been deprecated.
List is being generated by checking the presence of the signature instead.

Not customizable in Bazel.

Reason: This is set to a fixed value in the `module_implicit_outs` attribute of
`//common:kernel_aarch64`.

See [documentation for all rules].

## VENDOR\_DLKM\_FS\_TYPE

```python
vendor_dlkm_image(fs_type=[ext4, erofs])
```

See [documentation for all rules].

## VENDOR\_DLKM\_ETC\_FILES

```python
vendor_dlkm_image(etc_files=[...])
```

See [documentation for all rules].

## VENDOR\_DLKM\_MODULES\_LIST

```python
vendor_dlkm_image(modules_list=...)
```

See [documentation for all rules].

## VENDOR\_DLKM\_MODULES\_BLOCKLIST

```python
vendor_dlkm_image(modules_blocklist=...)
```

See [documentation for all rules].

## VENDOR\_DLKM\_PROPS

```python
vendor_dlkm_image(props=...)
```

See [documentation for all rules].

## SYSTEM\_DLKM\_FS\_TYPE

```python
system_dlkm_image(fs_types=["ext4", "erofs"])
```

See [documentation for all rules].

## SYSTEM\_DLKM\_MODULES\_LIST

```python
system_dlkm_image(modules_list=...)
```

See [documentation for all rules].

## SYSTEM\_DLKM\_MODULES\_BLOCKLIST

```python
system_dlkm_image(modules_blocklist=...)
```

See [documentation for all rules].

## SYSTEM\_DLKM\_PROPS

```python
system_dlkm_image(props=...)
```

See [documentation for all rules].

## LZ4\_RAMDISK

**NOTE**: Rather than specifying if `lz4` is used or not, kleaf expects you to
 specify the value as one of the strings `lz4` or `gzip`.

* If `ramdisk_compression =` `lz4` or `gzip`, do not specify `LZ4_RAMDISK` in
  build configs, as the value will be ignored.
* If `ramdisk_compression =` `None` or unspecified, the value in build configs
 will be respected.

```python
initramfs(ramdisk_compression="lz4",...)
```

See [documentation for all rules].

## LZ4\_RAMDISK\_COMPRESS\_ARGS

**NOTE**: Use in combination with [`LZ4_RAMDISK`](#lz4_ramdisk).

```python
initramfs(ramdisk_compression_args=...)
```

See [documentation for all rules].

## TRIM\_NONLISTED\_KMI

```python
kernel_build(trim_nonlisted_kmi=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## KMI\_SYMBOL\_LIST\_STRICT\_MODE

```python
kernel_build(kmi_symbol_list_strict_mode=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## KMI\_STRICT\_MODE\_OBJECTS

Not customizable in Bazel.

Reason: This is always `vmlinux` (regardless of whether it is in `outs`) and
the list of `module_outs` from the `kernel_build` attribute of the `kernel_abi`
macro invocation.

See [documentation for all rules].

See [documentation for ABI monitoring].

## GKI\_DIST\_DIR

Not used in Bazel. Alternatives:

Mixed builds are supported by

```python
kernel_build(base_build=...)
```

See [documentation for implementing Kleaf].

## GKI\_BUILD\_CONFIG

Not used in Bazel. Alternatives:

Mixed builds are supported by

```python
kernel_build(base_build=...)
```

See [documentation for implementing Kleaf].

## GKI\_PREBUILTS\_DIR

See [Setting up DDK workspace](ddk/workspace.md#declare-prebuilts-repository)
for details on setting up the repository for prebuilts.

## BUILD\_DTBO\_IMG

```python
dtbo(...)
```

See [documentation for all rules].

## DTS\_EXT\_DIR

```python
kernel_dtstree()
kernel_build(dtstree=...)
```

Define `kernel_dtstree()` in `DTS_EXT_DIR`, then set the `dtstree` argument of
the `kernel_build()` macro invocation to the `kernel_dtstree()` target.

See [documentation for all rules].

## BUILD\_GKI\_CERTIFICATION\_TOOLS

Add `//build/kernel:gki_certification_tools` to your `pkg_files()` macro
invocation.

See [build/kernel/BUILD.bazel](../../BUILD.bazel).

## BUILD\_VENDOR\_KERNEL\_BOOT

```python
vendor_boot_image(vendor_boot_name = "vendor_kernel_boot")
```

See [documentation for all rules].

## MKBOOTIMG\_PATH

```python
vendor_boot_image(mkbootimg=...)
gki_artifacts(mkbootimg=...)
```

See [documentation for all rules] for `vendor_boot_image`.

**NOTE**: `gki_artifacts` is an implementation detail, and it should only be
invoked by GKI targets.

## BUILD\_GKI\_ARTIFACTS

```python
gki_artifacts()
```

**NOTE**: `gki_artifacts` is an implementation detail, and it should only be
invoked by GKI targets.

For GKI targets, it may be configured via the following:

```python
define_common_kernels(
  target_configs = {
    "kernel_aarch64": {
      "build_gki_artifacts": True,
      "gki_boot_img_sizes": {
        "": "67108864",
        "lz4": "53477376",
      },
    },
  },
)
```

See [documentation for all rules].

## GKI\_KERNEL\_CMDLINE

```python
gki_artifacts(gki_kernel_cmdline=...)
```

**NOTE**: `gki_artifacts` is an implementation detail, and it should only be
invoked by GKI targets.

## KBUILD\_SYMTYPES

If `KBUILD_SYMTYPES=1` is specified in build configs:

```python
kernel_build(kbuild_symtypes="true")
```

See [documentation for all rules].

To specify `KBUILD_SYMTYPES=1` at build time:

```shell
$ bazel build --kbuild_symtypes ...
```

See [symtypes.md](symtypes.md) for details.

## KMI\_SYMBOL\_LIST\_ADD\_ONLY

```python
kernel_abi(kmi_symbol_list_add_only=...)
```

See [documentation for all rules].

See [documentation for ABI monitoring].

## KCFLAGS

```python
kernel_build(kcflags=[...])
```

See [kernel_build.kcflags](api_reference/kernel.md#kernel_build-kcflags).

## VENDOR\_BOOTCONFIG

```python
vendor_boot_image(vendor_bootconfig = [...])
```

See [vendor_boot_image](api_reference/kernel.md#vendor_boot_image).

[documentation for all rules]: api_reference.md

[documentation for ABI monitoring]: abi.md

[documentation for implementing Kleaf]: impl.md
