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

### Performance

* For performance optimizations follow the tips in
  [Optimizing Performance](https://bazel.build/rules/performance).
  * E.g. Use `depsets` instead of `lists`; `depsets` are a tree of objects that
  can be concatenated effortlessly.`lists` are concatenated by copying contents.

