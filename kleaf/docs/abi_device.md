# Supporting ABI monitoring with Bazel (device kernel)

## Enable ABI monitoring

Update relevant targets in `BUILD.bazel`.

### Migrate from `kernel_build` to a `kernel_build_abi` target

Migrate the existing `kernel_build` target to a `kernel_build_abi` target by
changing the type of the macro invocation.

Add additional attributes to the target for ABI monitoring. This includes:

- `abi_definition`: The ABI definition, usually
  `"//common:android/abi_gki_aarch64.xml"`.
- `kmi_symbol_list`: The KMI symbol list for the device, e.g.
  `"//common:android/abi_gki_aarch64_pixel"`.
- `additional_kmi_symbol_lists`: Other KMI symbol lists, usually
  `["//common:kernel_aarch64_all_kmi_symbol_lists"]`.
- `kernel_modules`: The list of external modules. This should be consistent with
  the `kernel_modules_install` target.
- `unstripped_modules_archive`: The `kernel_unstripped_modules_archive` target,
  defined [below](#unstripped). This is needed to build `abi.prop`.

You may optionally define the following:

- `define_abi_targets`
    - This is `True` by default. If `False`, ABI monitoring is disabled.
    - This is useful to minimize the difference in the source tree between
      `android-mainline` and a KMI frozen branch.
- `module_grouping`
- `kmi_symbol_list_add_only`
- `kmi_enforced`

See documentation for explanation of the `kernel_build_abi` rule and its
attributes:

[https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html](https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html)

See [Change 2022075](https://r.android.com/2022075) for an example on Pixel 2021.

### Define `kernel_unstripped_modules_archive` target {#unstripped}

The target contains all unstripped in-tree and external kernel modules for ABI
monitoring and debugging purposes.

Its definition should be similar to the `kernel_modules_install` target.

See documentation for explanation of the `kernel_unstripped_modules_archive`
rule and its attributes:

[https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html](https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html)

See [Change 2087286](https://r.android.com/2087286) for an example on Pixel 2021.

### Define a `kernel_build_abi_dist` target

Define a `kernel_build_abi_dist` target named `{name}_abi_dist`, where `name`
is the name of the `kernel_build_abi()`. Its attributes should be similar to the
existing `copy_to_dist_dir` target named `{name}_dist` defined
in [impl.md#step-5](impl.md#step-5).

The `kernel_build_abi` attribute should be set to the label of the
`kernel_build_abi()` target.

See [Change 2022075](https://r.android.com/2022075) for an example on Pixel 2021.

See [Build kernel and ABI artifacts](#build-dist) below for invoking this target
to build artifacts for distribution.

### Example for Pixel 2021

See the following changes for an example on Pixel 2021.

- [Change 2022075: "kleaf: build abi for slider"](https://r.android.com/2022075)
- [Change 2087286: "kleaf: Add slider_unstripped_modules_archive."](https://r.android.com/2087286)

## Build kernel and ABI artifacts {#build-dist}

```shell
$ tools/bazel run //path/to/package:{name}_abi_dist
```

In the above example for Pixel 2021, the command is

```shell
$ tools/bazel run //gs/google-modules/soc-modules:slider_abi_dist
```

## Update the KMI symbol list {#update-symbol-list}

Similar to [updating the KMI symbol list for GKI](abi.md#update-symbol-list),
you may update the `kmi_symbol_list` defined previously with the following.

```shell
$ tools/bazel run //path/to/package:{name}_abi_update_symbol_list
```

... where `{name}` is the `name` attribute of `kernel_build_abi()`.

In the above example for Pixel 2021, the command is

```shell
$ tools/bazel run //gs/google-modules/soc-modules:slider_abi_update_symbol_list
```

This updates `common/android/abi_gki_aarch64_pixel`.

## Update the ABI definition

After the KMI symbol list is [updated](#update-symbol-list), you may update the
ABI definition at `common/android/abi_gki_aarch64.xml` with the following
command:

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update
```

See [abi.md#update-abi](abi.md#update-abi).

**NOTE**: Do not update the ABI definition via the `slider_update` target! The
ABI definition should always be updated via the GKI `kernel_aarch64_abi_update`
target.

