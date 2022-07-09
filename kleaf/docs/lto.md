# Disable LTO during development

**Warning**: You may want to re-enable LTO in production.

Building with link-time optimization (LTO) may take a very long time that brings
little benefit during development. You may disable LTO to shorten the build time
for development purposes.

## Option 1: One-time build without LTO

For example:

```shell
$ tools/bazel build --lto=none //private/path/to/sources:tuna_dist
```

The `--lto` option is applied to the build, not the `copy_to_dist_dir` step.
Hence, put it before the `--` delimiter when running a `*_dist` target. For
example:

```shell
$ tools/bazel run --lto=none //private/path/to/sources:tuna_dist -- --dist_dir=out/dist
```

If you are using `--lto` with `--config=fast`, the value of
`--lto` in the command line is ignored as of 2022-06-15 due to
[Issue 15679](https://github.com/bazelbuild/bazel/issues/15679). Until the issue
is resolved, using `--config=local` instead, or choose Option 2 below. For
example:

```shell
# DO NOT USE: --lto may be set to thin due to Issue 15679
# tools/bazel run --config=fast --lto=none //common:kernel_dist

# Instead, use:
$ tools/bazel run --config=local --lto=none //common:kernel_dist
```

## Option 2: Disable LTO for this workspace

You only need to **do this once** per workspace.

```shell
# Do this at workspace root next to the file WORKSPACE
$ test -f WORKSPACE && echo 'build --lto=none' >> user.bazelrc
# Future builds in this workspace always disables LTO.
$ tools/bazel build //private/path/to/sources:tuna_dist
```

If you are using `--config=fast`, you need to add `build:fast --lto=none` as
well, because `--config=fast` implies thin LTO. See [fast.md](fast.md#lto).

## Confirming the value of --lto

You may build the following to confirm the value of LTO setting:

```shell
$ tools/bazel build [flags] //build/kernel/kleaf:print_flags
```

Note: `print_flags` shows values specified in the command line. For LTO, the
above command may show `default` or `none`. However, if `--kasan` is specified,
`--lto` is coerced into `none`, no matter if `--lto` is specified in the command
line.

## See also

[kasan](kasan.md)

[Build faster](fast.md)
