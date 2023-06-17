# API Reference and Documentation for all rules

## android-mainline

You may view the documentation for the aforementioned Bazel rules and macros on
Android Continuous Integration:

<!-- Internal link: b/280083894 -->
<!-- Update to use kleaf-docs repo instead -->

[https://ci.android.com/builds/latest/branches/aosp\_kernel-common-android-mainline/targets/kleaf\_docs/view/index.html](https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html)

The link redirects to the latest documentation in the android-mainline branch.

## Viewing docs locally

For an API reference for other branches, or your local repository, you may build
the documentation and view it locally:

```shell
$ tools/bazel run //build/kernel/kleaf:docs_server
```

<!-- Internal link: b/280083894 -->

<!-- This won't work after blocking downloads so this will need rewording. We
need to point to the method used for kleaf-docs repo. i.e. vendoring the extra
repositories needed but with the warning about the size increase. -->

**NOTE**: Running this for the first time, or after `tools/bazel clean
--expunge`, requires Internet. This is a known issue.

<!-- Internal link: b/245624185 -->

Sample output:

```text
Serving HTTP on 0.0.0.0 port 8080 (http://0.0.0.0:8080/) ...
```

Then visit `http://0.0.0.0:8080/` in your browser.

Alternatively, you may refer to the documentation in the source code of the
Bazel rules in `build/kernel/kleaf/*.bzl`.
