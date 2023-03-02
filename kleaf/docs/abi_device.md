# Supporting ABI monitoring with Bazel (device kernel)

## Enable ABI monitoring

ABI monitoring only needs to be configured for core kernel build targets. Mixed
build configurations (ones that define `base_kernel`) that compile directly
with the GKI kernel only need to add support for tracking the device symbol
list. The ABI definition can be updated using the GKI build.

To setup the device symbol list, update the relevant targets in `BUILD.bazel`.

### Update the `kernel_build` target

Add these attributes to the `kernel_build` target for KMI symbol list support:

- `kmi_symbol_list`: The KMI symbol list for the device, e.g.
  `"//common:android/abi_gki_aarch64_db845c"`.

### Define a `kernel_abi` target

Add a new `kernel_abi` target. The target should usually be named `{name}_abi`
by convention, where `{name}` is the name of the `kernel_build` target.

Add these attributes to the `kernel_abi` target for KMI symbol list support:

- `kernel_build`: point to the `kernel_build` target.
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

See documentation for explanation of the `kernel_abi` rule and its
attributes: [API Reference and Documentation for all rules](api_reference.md).

See `define_db845c()` in [common\_kernels.bzl](../common_kernels.bzl) for an
example.

<!-- TODO(b/260913198): we need a better example that uses kernel_abi -->

### Define `kernel_unstripped_modules_archive` target {#unstripped}

The target contains all unstripped in-tree and external kernel modules for ABI
monitoring and debugging purposes.

Its definition should be similar to the `kernel_modules_install` target.

See documentation for explanation of the `kernel_unstripped_modules_archive`
rule and its attributes:
[API Reference and Documentation for all rules](api_reference.md).

See `define_db845c()` in [common\_kernels.bzl](../common_kernels.bzl) for an
example.

<!-- TODO(b/260913198): we need a better example that uses kernel_abi -->

### Define a `kernel_abi_dist` target

Define a `kernel_abi_dist` target named `{name}_abi_dist`, where `{name}`
is the name of the `kernel_build()`. Its attributes should be similar to the
existing `copy_to_dist_dir` target named `{name}_dist` defined
in [impl.md#step-5](impl.md#step-5).

The `kernel_abi` attribute should be set to the label of the
`kernel_abi()` target.

Set `kernel_build_add_vmlinux` to `True` and remove the GKI `kernel_build`
target (likely `//common:kernel_aarch64`) from `data` to avoid building
`kernel_build`s twice.

See `define_db845c()` in [common\_kernels.bzl](../common_kernels.bzl) for an
example.

<!-- TODO(b/260913198): we need a better example that uses kernel_abi -->

See [Build kernel and ABI artifacts](#build-dist) below for invoking this target
to build artifacts for distribution.

### Example for db845c

<!-- TODO(b/260913198): we need a better example that uses kernel_abi -->

See `define_db845c()` in [common\_kernels.bzl](../common_kernels.bzl) for an
example.

## Build kernel and ABI artifacts {#build-dist}

```shell
$ tools/bazel run //path/to/package:{name}_abi_dist
```

In the above example for db845c, the command is

```shell
$ tools/bazel run //common:db845c_abi_dist
```

## Update the KMI symbol list {#update-symbol-list}

Similar to [updating the KMI symbol list for GKI](abi.md#update-symbol-list),
you may update the `kmi_symbol_list` defined previously with the following.

```shell
$ tools/bazel run //path/to/package:{name}_abi_update_symbol_list
```

In the above example for db845c, the command is

```shell
$ tools/bazel run //common:db845c_abi_update_symbol_list
```

This updates `common/android/abi_gki_aarch64_db845c`.

## Update the protected exports list {#update-protected-exports}

Similar to [updating the KMI symbol list for GKI](abi.md#update-symbol-list),
you may update the `protected_exports_list` defined previously with the
following.

```shell
$ tools/bazel run //path/to/package:{name}_abi_update_protected_exports
```

In the above example for kernel_aarch64, the command is

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update_protected_exports
```

This updates `common/android/abi_gki_protected_exports`.

## Update the ABI definition

After the [KMI symbol list updated](#update-symbol-list) and
[the protected exports list updated](#update-protected-exports), you may
update the ABI definition at `common/android/abi_gki_aarch64.stg` with the
following command:

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update
```

See [abi.md#update-abi](abi.md#update-abi).

**NOTE**: Do not update the ABI definition via the `db845c_abi_update` target!
The ABI definition should always be updated via the GKI
`kernel_aarch64_abi_update` target.

