# DDK Library

**Note**: `ddk_library` is experimental. Its API is subject to change.

This example demonstrates how a `ddk_library` should be used.

`ddk_library` is useful if you have specific flags for certain source files.

## Explanation

See [BUILD.bazel](BUILD.bazel) and [libfoo/BUILD.bazel](libfoo/BUILD.bazel)
for the example.

Flags in `libfoo` only affect the compilation of `foo.c`, not `mod.c` in the
`ddk_module`.

`hdrs` and `includes` of `libfoo` are exported to the `ddk_module`.

Run the following to see it in live action:

```shell
tools/bazel build \
    //build/kernel/kleaf/tests/ddk_examples/ddk_library:mymod
```

## Full sources

Full sources of this example are in [this directory](.).
