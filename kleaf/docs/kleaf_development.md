# Kleaf Development

This documentation summarizes principles used in Kleaf development.

### Style Guides

* Follow [.bzl style guide](https://bazel.build/rules/bzl-style) for
  [Starlark](https://bazel.build/rules/language) files.
* Follow [BUILD Style Guide](https://bazel.build/build/style-guide) for BUILD
  files.

### Conventions

* Follow these [conventions](https://bazel.build/extending/macros#conventions) for
 Macros, in particular:
  * In most cases, optional parameters should have a default value of `None`.

### Performance

* For performance optimizations follow the tips in [Optimizing Performance](https://bazel.build/rules/performance).
 * E.g. Use `depsets` instead of `lists`; `depsets` are a tree of objects that can be concatenated effortlessly.
    `lists` are concatenated by copying contents.
