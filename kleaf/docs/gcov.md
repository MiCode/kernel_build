# `GCOV`

When the flag `--gcov` is set, the build is reconfigured to produce (and keep)
`*.gcno` files.

For example:

```shell
$ bazel build --gcov //common:kernel_aarch64
```

You may find the `*.gcno` files under the
`bazel-bin/<package_name>/<target_name>/gcno` directory,
where `<target_name>` is the name of the `kernel_build()`
macro. In the above example, the `.gcno` files can be found at

```
bazel-bin/common/kernel_aarch64/gcno/
```
