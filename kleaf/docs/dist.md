# Creating distributions

## Creating a distribution for a kernel build

To create a distribution with the kernel image, modules,
partition images, etc., see [impl.md#step-5](impl.md#step-5).

# Creating a distribution for a single module

To create a distribution for a single `kernel_module` or `ddk_module`,
define a separate `pkg_install` rule that contains just the target:

```py
kernel_module(
    name = "foo",
    # ...
)

pkg_files(
    name = "foo_files",
    srcs = [":foo"],
    # ...
)

pkg_install(
    name = "foo_dist",
    srcs = [":foo_files"],
    # ...
)
```

**NOTE**: It is not recommended to do the following because it contradicts
the ["DAMP" rule](kleaf_development.md#damp). All targets that are visible to
users should be defined in `BUILD.bazel` files, not wrapped in macros.

Yet sometimes, you may want to be less repetitive on `BUILD.bazel` files. For that
reason, you may define a small macro that glues the three targets together:

```py
# NOTE: This is discouraged.
# kernel_module_dist.bzl

def kernel_module_dist(
    name,
    **kwargs
):
    kernel_module(
        name = name,
        **kwargs
    )

    pkg_files(
        name = name + "_files",
        srcs = [name],
        strip_prefix = strip_prefix.files_only(),
        **(kwargs | dict(
            visibility = ["://visibility:private"],
        ))
    )

    pkg_install(
        name = name + "_dist",
        srcs = [name + "_files"],
        **kwargs
    )
```

```py
# BUILD.bazel

load(":kernel_module_dist.bzl", "kernel_module_dist")

kernel_module_dist(
    name = foo,
    # ...
)
```
