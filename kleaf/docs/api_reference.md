# API Reference and Documentation for all rules

## android-mainline

You may view the documentation for the aforementioned Bazel rules and macros on
[Android Continuous Integration](https://ci.android.com/builds/latest/branches/aosp_kernel-kleaf-docs/targets/kleaf_docs/view/index.html).

The link redirects to the latest documentation in the android-mainline branch.

## Viewing docs locally

For an API reference for other branches, or your local repository, you may build
the documentation and view it locally by following the example of the
[`kleaf-docs` manifest branch](https://android.googlesource.com/kernel/manifest/+/refs/heads/kleaf-docs/default.xml);
this branch is different to other branches in three regards:

1.  It includes only the Kleaf dependencies to generate the docs.
1.  It includes extra repositores with bazel rules needed for
    [stardoc](https://github.com/bazelbuild/stardoc):
    *   `<project path="prebuilts/bazel/common"
        name="platform/prebuilts/bazel/common" clone-depth="1" />`
1.  It register the above repositories as part of the WORKSPACE setup:
    *   `define_kleaf_workspace(include_remote_java_tools_repo = True)`
    *   See [kleaf/bazel.kleaf-docs.WORKSPACE](../bazel.kleaf-docs.WORKSPACE)
        for reference.

**Note**: Only the last two points are needed for your local docs.

```shell
$ tools/bazel run //build/kernel/kleaf:docs_server
```

Sample output:

```text
Serving HTTP on 0.0.0.0 port 8080 (http://0.0.0.0:8080/) ...
```

Then visit `http://0.0.0.0:8080/` in your browser.

**Alternatively**, you may refer to the documentation in the source code of the
Bazel rules in `build/kernel/kleaf/*.bzl`.
