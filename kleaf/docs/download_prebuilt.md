# Build against downloaded prebuilt GKI

**WARNING**: Building against downloaded prebuilts is currently experimental. If
you encounter any errors, see [common errors](#common-errors).

## Step 1: Replace reference to GKI targets with downloaded targets

Replace all references to `//common:kernel_aarch64` with
`//common:kernel_aarch64_download_or_build`.

Replace all references to `//common:kernel_aarch64_additional_artifacts` with
`//common:kernel_aarch64_additional_artifacts_download_or_build`.

In particular, look out for these places:

* `kernel_build()`: `base_kernel`
* Any target: `kernel_build`
* `copy_to_dist_dir`: `data`
* `kernel_build_abi_dist`: `data`

See Pixel 2021 mainline for an example (search for `//common:kernel_aarch64`):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

## Step 2: Build with `--use_prebuilt_gki=<BUILD_ID>`

In the build command, specify `--use_prebuilt_gki=<BUILD_ID>` to build against
downloaded prebuilts.

The build ID must have a build target named `kernel_kleaf`.

It is recommended to select the latest build ID from the branch.

Sample branches:

- [aosp_kernel-common-android-mainline](https://ci.android.com/builds/branches/aosp_kernel-common-android-mainline/grid)
- [aosp_kernel-common-android14-5.15](https://ci.android.com/builds/branches/aosp_kernel-common-android14-5.15/grid)
- [aosp_kernel-common-android13-5.15](https://ci.android.com/builds/branches/aosp_kernel-common-android13-5.15/grid)
- [aosp_kernel-common-android13-5.10](https://ci.android.com/builds/branches/aosp_kernel-common-android13-5.10/grid)

Other unspecified branches with a build target named `kernel_kleaf` may also
work.

Sample command to build `raviole-android13-5.15` against prebuilts from
`android13-5.15`:

```shell
# On raviole-5.15 branch, build against prebuilts from android13-5.15.
# Build with --use_prebuilt_gki=<build_ID>. Example:
$ tools/bazel run --use_prebuilt_gki=8728678 //gs/google-modules/soc-modules:slider_dist
```

## Common errors

You may see an error about failing to download a file because it does not
exist ("404 Not Found"). For example:

```text
ERROR: An error occurred during the fetch of repository '<filename>':
   Traceback (most recent call last):
        File "/mnt/sdc/android/raviole-mainline/build/kernel/kleaf/download_repo.bzl", line 128, column 48, in _download_artifact_repo_impl
                download_info = repository_ctx.download(
Error in download: java.io.IOException: Error downloading [<url>] to <path>: GET returned 404 Not Found
```

To resolve this, try using the latest build ID from the branch.

If you are still unable to resolve the issue, you may:
- contact [owners](../OWNERS) or [kernel-team@android.com](mailto:kernel-team@android.com)
- contact your Technical Account Manager to file a bug
