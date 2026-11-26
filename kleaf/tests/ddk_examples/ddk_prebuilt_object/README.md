# Adding prebuilt .o files

This example demonstrates how a `ddk_module` may use prebuilt `.o` files.

## Explanation

See [BUILD.bazel](BUILD.bazel) for the example.

In short, wrap the `.o` file with a `ddk_prebuilt_object` target before
feeding it into `ddk_module.deps`.

You may optionally provide a `.o.cmd` file to the `ddk_prebuilt_object` target.
However, see [caveat](#caveat_providing-the-cmd-file) below.

This example uses a custom rule to build the `.o` file. You can use a
`.o` file that is checked into the source tree.

Run the following to see it in live action:

```shell
tools/bazel build \
    //build/kernel/kleaf/tests/ddk_examples/ddk_prebuilt_object:mymod
```

# Caveat: providing the .cmd file

If the outer `ddk_module` has a `MODULE_VERSION()`, `modpost` requires all
sources to be available if the `.cmd` file exist for a `.o` file. This means
the sources of the `ddk_prebuilt_object` also need to be provided, which
defeats the purpose.

You can workaround the issue with any of the following:

*   Do not set the `cmd` attribute of the `ddk_prebuilt_object`. This stops
    modpost from reading into the sources.
*   OR, ship all source files of the prebuilt object and provide the sources
    to the `ddk_module` via a `ddk_headers` target.

For a concrete example, see
`//build/kernel/kleaf/tests/ddk_examples/ddk_prebuilt_object:provide_cmd` and
`:provide_cmd_srcs`.

## Full sources

Full sources of this example are in [this directory](.).
