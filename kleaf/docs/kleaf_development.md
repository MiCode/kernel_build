# Kleaf Development

This documentation summarizes principles used in Kleaf development.

### Style Guides

* Follow [.bzl style guide](https://bazel.build/rules/bzl-style) for
  [Starlark](https://bazel.build/rules/language) files.
* Follow [BUILD Style Guide](https://bazel.build/build/style-guide) for BUILD
  files.

### Conventions

* Follow these [conventions](https://bazel.build/extending/macros#conventions)
  for Macros, in particular:
  * In most cases, optional parameters should have a default value of `None`.
* Avoid using
  [`unittest.suite`](https://github.com/bazelbuild/bazel-skylib/blob/main/docs/unittest_doc.md#unittestsuite)
  . Reasons:
  * Individual test names are tagged with indices, not descriptive names. This
    makes failures hard to triage.
  * When items are reordered or inserted into the list, the indicies change,
    and thus individual test names change as well. Continuous testing processes
    may be confused and show incomplete test histories because of name changes.

#### "DAMP" BUILD.bazel files {#damp}

`BUILD.bazel` files should apply the "DAMP" (descriptive and meaningful
phrases) rule, as opposed to the "DRY" (do not repeat yourself) rule that is
otherwise often applied to production code.

In practice, this rule encourages all targets visible to the user to be
declared in `BUILD.bazel` files instead of being wrapped in macros.

Usually, this means the implementation of a macro should only declare one
target public to the user, named with the same name of the macro
invocation. Private targets should usually be named `name + "_<suffix>"`,
unknown to the user and not guaranteed through the contract of the interface.

Example:

```py
# GOOD

# BUILD.bazel
foo_library(name = "my_target_lib", ...)
foo_binary(name = "my_target", ...)
```

```py
# BAD

# my_target.bzl
def my_rule(name, ...)
    foo_library(name = name + "_lib", ...)
    foo_binary(name = name, ...)

# BUILD.bazel
my_rule(name = "my_target", ...)
```

If you expect users to know about both `my_target` and `my_target_lib`; that
is, a user can do `bazel build :my_target :my_target_lib`, it is
encouraged that both are declared explicitly in the `BUILD.bazel` file. There
might be some repitition in the list of attributes shared between `my_target`
and `my_target_lib`, but the overall maintenance cost is lower in the long run.

A notable exception for macros is when the additional targets are implementation
details and not visible to users. For example:

```py
# GOOD

# my_target.bzl
def my_rule(name, ...)
    foo_library(
        name = name + "_internal_lib",
        visibility = ["//visibility:private"],
        # ...
    )
    foo_binary(
        name = name,
        deps = [name + "_internal_lib"]
        # ...
    )

# BUILD.bazel
my_rule(name = "my_target", ...)
```

In this case, the user is expected to only do `bazel build :my_target`,
not `bazel build :my_target_internal_lib`, because the library is an
implementation detail of `my_rule`.

**NOTE**: There are multiple violations of the "DAMP" rule even within
Kleaf's code base, notably the following. They require some cleanup, but
due to backwards compatibility of the API, they might not be completely
"DAMP" even in the future.

- `kernel_build`
- `kernel_module` (it calls `kernel_module_test`)
- `define_common_kernels`
- etc.

### Performance

* For performance optimizations follow the tips in
  [Optimizing Performance](https://bazel.build/rules/performance).
  * E.g. Use `depsets` instead of `lists`; `depsets` are a tree of objects that
  can be concatenated effortlessly.`lists` are concatenated by copying contents.

