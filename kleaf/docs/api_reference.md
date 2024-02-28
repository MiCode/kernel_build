# API Reference and Documentation for all rules

## For the current branch

You may view the documentation for the aforementioned Bazel rules and macros in
[api_reference](api_reference).

The link redirects to the generated documentation for this branch.

## Updating docs

```sh
tools/bazel run //build/kernel/kleaf/docs:docs_dist \
    --config=bzlmod --config=internet \
    -- --wipe_dist_dir
```
