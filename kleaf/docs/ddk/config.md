# Configuring a DDK module

[TOC]

The following presents different ways to configure DDK modules according to
different needs and highlights when it is appropriate to use one approach vs
another to ensure the most efficient method is used.

## Distributed kconfig / defconfig {#distributed}

This is the original approach where individual `kconfig` and / or `defconfig`
are specified for each DDK module via [`ddk_module.kconfig`](#kconfig) and
[`ddk_module.defconfig`](#defconfig) attributes (as documented below).

### Pros

*   As the original DDK design, this makes each DDK module standalone. That is,
    a `ddk_module` is responsible for managing its own `Kconfig` and `defconfig`
    fragments.
*   A child module can still get the values from parent modules.
*   Because DDK modules are standalone, it is now possible to do multi-device
    builds that may share some modules.
    *   You can build these device builds simultaneously, and the shared modules
        are only built once.
    *   This setup utilizes Bazel’s native caching mechanism by defining the
        exact inputs for each target.
*   The benefit of this setup is more obvious if there are no device
    `kernel_build` to build in-tree modules and device tree.

### Cons

*   **N** internal targets are created, each one invoking `make olddefconfig`
    (where **N** is the number of `ddk_module`’s).
    *   The sandbox for these targets is huge (contains a lot of symlinks
     <!-- KI: http://b/400795231 -->).
    *   Because all these sandboxes are slightly different due to the additional
    `Kconfig`/`defconfig` fragments, the majority of time is spent creating these
    slightly different sandboxes. Using the `--reuse_sandbox_directories` flag
    won't improve performance here, as the differences prevent effective reuse,
    and it may actually consume significant disk space by stashing each unique
    version.

Due to this, the **build time** and **disk usage** are negatively impacted for
large values of **N**.  For example, when the number of modules is greater than
100, we see a significant build time increase (~2 minutes) and disk space
usage (> 10 GB) due to the overhead of creating these sandboxes.

## Centralized kconfig / defconfig {#centralized}

Since the beginning Kleaf has supported centralized `Kconfig`/`defconfig` for
device builds. This means each module sees the same `.config` (they are
distinguished at the device level).

With the introduction of [`ddk_config`](../api_reference/kernel.md#ddk_config),
it is now possible to have a similar architecture even if the `ddk_module`’s are
building against the GKI directly.

### Example

```python
# path/to/tuna/BUILD.bazel
ddk_config(
    name = "tuna_common_config",
    defconfig =  "tuna_defconfig",
    kconfigs = [
        "//path/to/camera:Kconfig.camera",
        "//path/to/camera:Kconfig.nfc",
    ],
)
```

```python
# path/to/camera/BUILD.bazel
ddk_module(
    name = "camera",
    config = "//path/to/tuna:tuna_common_config",
    kernel_build = "@kleaf//common:kernel_aarch64",
)
exports_files(["camera_defconfig", "Kconfig.camera"])
```

```python
# path/to/nfc/BUILD.bazel
ddk_module(
    name = "nfc",
    config = "//path/to/tuna:tuna_common_config",
    kernel_build = "@kleaf//common:kernel_aarch64",
)
exports_files(["nfc_defconfig", "Kconfig.nfc"])
```

### Pros

*   Because all modules share the same `ddk_config`, invoking `make
    olddefconfig` happens only once, which greatly reduces build time.

### Cons

*   Each `ddk_module()` configured target is now device specific; that means
    there have to be two camera configured targets for `tuna` and `shellfish`.
    *   This also means that multi-device builds are not only harder to
        configure (one will likely need transitions), but also takes longer to
        build (because there are two copies of camera to build, even though they
        are effectively the same!).
*   Unnecessary dependencies are added, which may hurt incremental build time,
    e.g. if you modify `CONFIG_CAMERA`, the central `.config` changes, and nfc
    would need to be rebuilt, even though nfc does not semantically depend on
    `CONFIG_CAMERA`.
*   Each package is no longer so standalone. For example, the `//path/to/camera`
    package at least needs to export `Kconfig.camera` for the central/common
    config to use.

## Somewhere in between: One ddk_config() per subsystem

The idea is to use a central `ddk_config()` per subsystem.

### Example architecture

```python
# path/to/camera/BUILD.bazel
ddk_config(
    name = "camera_common_config",
    kconfigs = ["Kconfig.camera"],
    defconfig = "camera_defconfig",
    kernel_build = "@kleaf//common:kernel_aarch64",
)
ddk_module(name = "front_camera", config = ":camera_common_config", ...)
ddk_module(name = "back_camera",  config = ":camera_common_config", ...)
```

```python
# path/to/nfc/BUILD.bazel
ddk_module(
    name = "nfc",
    kernel_build = "@kleaf//common:kernel_aarch64",
    kconfig = "Kconfig.nfc",
    defconfig = "nfc_defconfig",
)
```

### Pros & Cons

The mix of the two architectures has half the pros and cons from both
architectures.

Compared to the [distributed](#distributed) approach, this setup saves some
build time and disk space. The performance improvement could be large if a
subsystem has a lot of modules. However, you still need to pay the cost of `make
defconfig` and creating numerous large sandboxes if you have a lot of
subsystems. The key is to group modules and subsystems so that your devices can
pick and choose from them, without going too granular.

Compared to the [centralized](#centralized) approach, this setup improves
incremental build time if you switch between device builds (assuming that
individual modules depend on the GKI directly) or modify irrelevant configs, and
may improve overall build time if you build multiple devices simultaneously.
However, a full build starting from scratch could become slower with extra disk
space used.

### optimize_ddk_config_actions

The `--optimize_ddk_config_actions` flag was introduced as
an alternative way to optimize (best effort) the sandbox creation for
`ddk_config()`s and `ddk_module()`s.

It works by moving some calculations to Bazel's analysis phase and performing
depset comparisons to check for extra `defconfig`/`kconfig` files. This allows
skipping the sandbox creation action entirely if the `ddk_module` **does not**
have extra `defconfig` / `kconfigs`. In such cases, the extra `DdkConfig` action
is deleted, and the internal `_kernel_module()` target gets the `.config`
directly from `kernel_build` or its parent target.

**Note:** As of May 2025, this option is enabled by default.

## Kconfig

The `kconfig` attribute points to a `Kconfig` file that allows to declare
additional `CONFIG_` options for this module, without affecting the main
`kernel_build`.

The format of the file is specified in
[`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
in the kernel source tree.

These `CONFIG_` options are only meaningful in the context of the current module
and its dependants.

The final `Kconfig` file seen by a module consists of the following:

*   `Kconfig` from `kernel_build`
*   `Kconfig`s of its dependencies, if any exist
*   `Kconfig` of this module, if it exists.

## defconfig

The `defconfig` attribute defines the actual values of the `CONFIG_` options
declared in `Kconfig`. This feature may be useful when multiple device targets
compile the same module with different `CONFIG_` options.

It is recommended that all `CONFIG_` options in the `defconfig` of the current
module are declared in the `Kconfig` of the current module. Overriding `CONFIG_`
options from `kernel_build` or dependencies is not recommended and **may even
break** in the future, because the module becomes less self-contained.

Implementation detail: The final `.config` file seen by a module consists of the
following. Earlier items have higher priority.

*   `defconfig` of this module, if it exists
*   `defconfig`s of its dependencies, if any exist
*   Dependencies are traversed in postorder (See
    [Depsets](https://bazel.build/extending/depsets)).
*   `DEFCONFIG` of the `kernel_build`.

## Example

```text
# tuna/Kconfig.ext: Kconfig of the kernel_build
config TUNA_LOW_MEM
	bool "Does the device have low memory?"
```

```sh
# tuna/tuna_defconfig: DEFCONFIG of the kernel_build
CONFIG_TUNA_LOW_MEM=y
```

```python
# tuna/BUILD.bazel
kernel_build(
    name = "tuna",
    kconfig_ext = "Kconfig.ext",
    build_config = "build.config.tuna",
    # build.config.tuna Contains variables to merge tuna_defconfig into
    # gki_defconfig
)

kernel_modules_install(
    name = "tuna_modules_install",
    kernel_modules = [
        "//tuna/graphics",
        "//tuna/display",
    ],
)
```

```
# tuna/graphics/Kconfig: Kconfig of the graphics driver
config TUNA_GRAPHICS_DEBUG
	bool "Enable debug options for tuna graphics driver"
```

```sh
# tuna/graphics/defconfig: defconfig of the graphics driver
# CONFIG_TUNA_GRAPHICS_DEBUG is not set
```

```python
# tuna/graphics/BUILD.bazel

ddk_module(
    name = "graphics",
    kernel_build = "//tuna",
    kconfig = "Kconfig",
    defconfig = "defconfig",
    out = "tuna-graphics.ko",
    srcs = ["tuna-graphics.c"],
)
```

```c
// tuna/graphics/tuna-graphics.c

#if IS_ENABLED(CONFIG_TUNA_GRAPHICS_DEBUG)
// You may check configs declared in this module
#endif

#if IS_ENABLED(CONFIG_TUNA_LOW_MEM)
// You may check configs declared in kernel_build
#endif
```

```text
# tuna/display/Kconfig: Kconfig of the display driver

config TUNA_HAS_SECONDARY_DISPLAY
	bool "Does the device have a secondary display?"
```

```sh
# tuna/display/defconfig: defconfig of the display driver

CONFIG_TUNA_HAS_SECONDARY_DISPLAY=y
```

```python
# tuna/display/BUILD.bazel

ddk_module(
    name = "display",
    kernel_build = "//tuna",
    kconfig = "Kconfig",
    defconfig = "defconfig",
    deps = ["//tuna/graphics"],
    out = "tuna-display.ko",
    srcs = ["tuna-display.c"],
)
```

```c
// tuna/display/tuna-display.c

#if IS_ENABLED(CONFIG_TUNA_HAS_SECONDARY_DISPLAY)
// You may check configs declared in this module
#endif

#if IS_ENABLED(CONFIG_TUNA_GRAPHICS_DEBUG)
// You may check configs declared in dependencies
#endif

#if IS_ENABLED(CONFIG_TUNA_LOW_MEM)
// You may check configs declared in kernel_build
#endif
```
