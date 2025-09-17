# Handling SCM version

## What is SCM version?

SCM version refers to the result of the `scripts/setlocalversion` script.

- For the kernel binary `vmlinux`, SCM version can be found in the kernel
  release string, after the kernel version.
- For kernel modules `*.ko`, SCM version can be found using `modinfo(8)`.

## The `stamp` config

Embedding the SCM version:
- Introduces extra overhead for every `bazel` command
- Unnecessarily triggers rebuilds when unrelated code changes

The SCM version is only embedded when `--config=stamp` is set.

On a developer's machine, the configuration is not set by default.

### Other flags

The flag `--config=stamp` is also implied by other flags, e.g.:

* `--config=release`. See [release.md](release.md).

## Handling SCM version in `kernel_build`

For `kernel_build()` that produces `vmlinux`, the following is required to embed
SCM version properly.

A symlink under the repository root named `.source_date_epoch_dir` should point
to the package that invokes the `kernel_build()` macro.

The symlink also ensures that `SOURCE_DATE_EPOCH` is calculated correctly. For
details, see [Manifest changes](impl.md#manifest-changes).

Example for Pixel 2021 Mainline build:
[https://android.googlesource.com/kernel/manifest/+/refs/heads/gs-android-gs-raviole-mainline/default.xml](https://android.googlesource.com/kernel/manifest/+/refs/heads/gs-android-gs-raviole-mainline/default.xml)
. Because Pixel 2021 Mainline build uses "mixed build", `vmlinux` comes from the
GKI build `//common:kernel_aarch64`. Hence, `.source_date_epoch_dir`
is a symlink to `common/`.

If your device does not use "mixed build" and builds `vmlinux` in the
`kernel_build()` macro, the `.source_date_epoch_dir` symlink should point to the
package defining your device's `kernel_build()`.

### Testing

To ensure the artifact `vmlinux` contains SCM version properly, you may check
the following.

- Run `{name of kernel_build}_test`. For example, you may check the GKI vmlinux
  with `bazel test //common:kernel_aarch64_test`. For details, see
  [testing.md#gki](testing.md#gki).
- `strings vmlinux | grep "Linux version"`
- Boot the device kernel, and call `uname -r`.

To ensure the in-tree kernel modules contains SCM version properly, you may
check the following.

- Run `{name of kernel_build}_modules_test`. For example, for Pixel 2021
  mainline, you may check the in-tree kernel modules with
  `bazel test //gs/google-modules/soc-modules:slider_modules_test`. For details,
  see [testing.md#device-kernel](testing.md#device-kernel).
- `modinfo -F scmversion <modulename>.ko`
- Boot the device, and check `/sys/module/<MODULENAME>/scmversion`.

## Handling SCM version for external `kernel_module`s

For external `kernel_module`s, the following is required to embed SCM version
properly.

A symlink under the repository root named `build.config` should point to the
build config of the `kernel_build()`.

Example for Pixel 2021 Mainline build:

[https://android.googlesource.com/kernel/manifest/+/refs/heads/gs-android-gs-raviole-mainline/default.xml](https://android.googlesource.com/kernel/manifest/+/refs/heads/gs-android-gs-raviole-mainline/default.xml)

**Note**: The key is that the file must define `EXT_MODULES` to be a (super)set
of external modules.

### Testing

To ensure the external kernel modules contains SCM version properly, you may
check the following.

- Run `{name of kernel_module}_test`. For example, for Pixel 2021 mainline, you
  may check the NFC kernel modules with
  `bazel test //gs/google-modules/nfc:nfc.slider_test`. For details,
  see [testing.md#external-kernel_module](testing.md#external-kernel_module).
- `modinfo -F scmversion <modulename>.ko`
- Boot the device, and check `/sys/module/<MODULENAME>/scmversion`.

