# Exports includes

This example demonstrates how a `ddk_module` should include headers that are
also exported to child modules depending on it.

## Explanation

There are several ways to achieve similar results.

### Put `ddk_headers` in `ddk_module.hdrs`

See [parent_1/BUILD.bazel](parent_1/BUILD.bazel) for an example.

In this example, a dedicated `ddk_headers` target is created to hold the
headers, then it is re-exported by the `ddk_module` by placing it in `hdrs`.

The [child module](child/BUILD.bazel) depends on `parent_1`. So, [`child.c`](child/child.c)
can do `#include "parent_1/parent_1_do_thing.h"` without depending on
`parent_1_exported_headers` directly.

### Put `.h` in `ddk_module.hdrs` and add `ddk_module.includes`

See [parent_2/BUILD.bazel](parent_2/BUILD.bazel) for an example.

In this example, the `ddk_module` itself contains the list of header files and
include directories to be exported to child modules.

The [child module](child/BUILD.bazel) depends on `parent_2`. So, [`child.c`](child/child.c)
can do `#include "parent_2/parent_2_do_thing.h"`.

### Expose the `ddk_headers` (not recommended)

See [parent_3/BUILD.bazel](parent_3/BUILD.bazel) for an example.

In this example, a dedicated `ddk_headers` target is created to hold the
headers, with **public** visibility.

The [child module](child/BUILD.bazel) must explicitly depend on
`parent_3_exported_headers` so that [`child.c`](child/child.c) can do
`#include "parent_3/parent_3_do_thing.h"`.

Because extra work is needed in the child module, this method is not
recommended, but it may be suitable to your project.

## Full sources

Full sources of this example are in [this directory](.).

## Re-exporting headers

If `child` should re-export headers from any of its parents, it should put the
dependency in `hdrs` instead of in `deps`.
