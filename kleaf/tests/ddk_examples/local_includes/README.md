# Local includes

This example demonstrates how a `ddk_module` should include headers that are
only available for the current module, but not child modules depending on it.

## Explanation

See [BUILD.bazel](BUILD.bazel) for the example code.

This is done by defining a separate `ddk_headers` target.

The `foo` target has `deps = [":foo_local_headers"]` so it is not exported
to child modules.

The `foo_local_headers` target has private visibility, preventing other modules
from using these headers.

## Full sources

Full sources of this example are in [this directory](.).

## Why not copts?

You may also set `copts = ["-I..."]` and add `srcs = ["includes/foo.h"]`
on the `foo` target to achive a similar outcome.

This approach is not recommended because `copts` are free-formed. It is also
subject to `$(location)` expansion so you can calculate paths in copts.
However, calculating paths to directories with `$(location)` requires a
dependency on the include directory itself, and dependencies on directories are
unsound in Bazel.

Instead, always place the `ddk_headers` next to the headers. Use
`ddk_module.deps` to indicate that the headers are not exported, and use
`ddk_headers.visibility` to limit the visibility of the headers.
