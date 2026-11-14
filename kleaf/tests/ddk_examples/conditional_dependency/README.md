# Conditional dependency

This example demonstrates how a `ddk_module` may be conditionally enabled based
on a Bazel flag.

## Explanation

See [parent/BUILD.bazel](parent/BUILD.bazel) for the example.

With this setup, you may conditionally enabled the `parent` module based on a
`bool_flag`. If the flag is unset, the `child` module uses the empty inline
function defined in the header. Otherwise, it links to the function
implemented by `parent.ko`.

Run the following to see it in live action:

```shell
tools/bazel build \
    --//build/kernel/kleaf/tests/ddk_examples/conditional_dependency/parent:enable_parent \
    //build/kernel/kleaf/tests/ddk_examples/conditional_dependency/child

tools/bazel build \
    --no//build/kernel/kleaf/tests/ddk_examples/conditional_dependency/parent:enable_parent \
    //build/kernel/kleaf/tests/ddk_examples/conditional_dependency/child
```

You may put a `--flag_alias` in your `device.bazelrc` to reduce typing. For example:

```
# device.bazelrc
common --flag_alias=enable_parent=//build/kernel/kleaf/tests/ddk_examples/conditional_dependency/parent:enable_parent
common --flag_alias=noenable_parent=no//build/kernel/kleaf/tests/ddk_examples/conditional_dependency/parent:enable_parent
```

```shell
tools/bazel build --enable_parent \
    //build/kernel/kleaf/tests/ddk_examples/conditional_dependency/child

tools/bazel build --noenable_parent \
    //build/kernel/kleaf/tests/ddk_examples/conditional_dependency/child
```

## Full sources

Full sources of this example are in [this directory](.).

## See also

[Bazel Configurations](https://bazel.build/extending/config)

[Writing bazelrc configuration files](https://bazel.build/run/bazelrc)
