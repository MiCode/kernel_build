# Build faster

## TL;DR

For local developing workflow, build with `--config=fast`.

Example:

```shell
$ tools/bazel run --config=fast //common:kernel_aarch64 -- --dist_dir=out/dist
```

Or add to `user.bazelrc`:
```text
# user.bazelrc
build --config=fast
```

## How does this work?

This config implies:

- `--lto=thin`. See [LTO](#lto).
- `--config=local`. See [sandbox.md](sandbox.md).

## LTO

By default, `--config=fast` implies `--lto=thin`. If you want to specify
otherwise, you may override its value in the command line,
e.g.

```shell
$ tools/bazel run --config=fast --lto=none //common:kernel_aarch64 -- --dist_dir=out/dist
```

... or in `user.bazelrc`, e.g.

```text
# user.bazelrc

# When `--config=fast` is set, disable LTO
build:fast --lto=none

# When no config is set, disable LTO
build --lto=none
```

You may build the following to confirm the value of LTO setting:

```shell
$ tools/bazel build //build/kernel/kleaf:print_flags
```
