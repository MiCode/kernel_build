# Adding prebuilt .o files

This example demonstrates how a `ddk_module` may use prebuilt `.o` files.

## Explanation

See [BUILD.bazel](BUILD.bazel) for the example.

In short, wrap the `.o` file with a `ddk_prebuilt_object` target before
feeding it into `ddk_module.deps`.

You may optionally provide a `.o.cmd` file to the `ddk_prebuilt_object` target.

This example uses a custom rule to build the `.o` file. You can use a
`.o` file that is checked into the source tree.

Run the following to see it in live action:

```shell
tools/bazel build \
    //build/kernel/kleaf/tests/ddk_examples/ddk_prebuilt_object:mymod
```

## Full sources

Full sources of this example are in [this directory](.).
