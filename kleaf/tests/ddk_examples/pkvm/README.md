# Build a pKVM module with DDK

**Note**: This feature is experimental. Its API is subject to change.

This example demonstrates how to build a pKVM module with DDK.

## Explanation

The EL2 hypervisor code may be built with a `ddk_library` target with
`pkvm_el2 = True`. See [hyp/BUILD.bazel](hyp/BUILD.bazel).

Then, the EL1 kernel code may be built with a regular `ddk_module` target,
with the `ddk_library` target in `deps`. See [BUILD.bazel](BUILD.bazel).

## Full sources

Full sources of this example are in [this directory](.).

## Reference

To build an in-tree pKVM module, see
[Implement a pKVM vendor module](https://source.android.com/docs/core/virtualization/pkvm-modules).
