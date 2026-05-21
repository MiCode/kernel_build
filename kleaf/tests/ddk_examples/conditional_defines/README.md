# Conditional defines

This example demonstrates how you may conditionally have `-Dxxx` based on a
`CONFIG_`. It may be helpful if you are converting a legacy `kernel_module` with
`Kbuild` containing lines like this:

```
ccflags-$(CONFIG_DDK_EXAMPLE_FOO_DEBUG) := -DDEBUG
```

## Explanation

To achieve the above result, do the following:

1.  Add a file, [debug.h](debug.h), that contains the shown content.
2.  In [BUILD.bazel](BUILD.bazel), do the following:
    1.  Add `debug.h` to `srcs`
    2.  Include `debug.h`. There are two ways to do this:
        1.  Add `["-include", "$(location debug.h)"]` to `copts`; OR
        2.  Add `#include "debug.h"` to [foo.c](foo.c) directly. See
            [local_includes](../local_includes/README.md) for details on
            including local headers.

## Full sources

Full sources of this example are in [this directory](.).
