# Release builds

Release builds on automated build servers **must** have `--config=release` set.
Example:

```shell
$ tools/bazel run --config=release //common:kernel_aarch64_dist -- --dist_dir=out/dist
```

**NOTE**: The flag is set for builds on [ci.android.com](http://ci.android.com).
