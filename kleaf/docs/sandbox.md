# Sandboxing

## TL;DR

To reduce sandboxes and boost build time, build with `--config=local`.

Example:

```shell
$ tools/bazel run --config=local //common:kernel_aarch64 -- --dist_dir=out/dist
```

Or add to `user.bazelrc`:

```text
# user.bazelrc
build --config=local
```

## How does this work?

By default, all [actions](https://bazel.build/reference/glossary#action) runs
within a sandbox. Sandboxes ensures hermeticity, but also introduced extra
overhead at build time:

- Creating the sandbox needs time, especially when there are too many inputs
- Using sandboxes disallows caching of `$OUT_DIR`

To overcome this and boost build time, a few types of actions are executed
without the sandbox when `--config=local`. The exact list of types of actions
are an implementation detail. If other types of actions were executed without
the sandbox, they might interfere with each other when executed in parallel.

When building with `--config=local`, `$OUT_DIR` is cached. This is approximately
equivalent to building with `SKIP_MRPROPER=1 build/build.sh`.

To clean the cache, run

```shell
$ tools/bazel clean
```

**NOTE**: It is recommended to execute `tools/bazel clean` whenever you switch
from and to `--config=fast`. Otherwise, you may get surprising cache hits or
misses because changing `--strategy` does **NOT** trigger rebuilding of an
action.

## Naming

The name of the config `local` comes from the value `local` in `--strategy`. See
Bazel's official documentation on `--strategy`
[here](https://bazel.build/reference/command-line-reference#flag--strategy).

## SCM version

When `--config=local`, some actions run in the sandbox and some
does not. To ensure that both kinds of actions get consistent values,
SCM versions and `SOURCE_DATE_EPOCH` should be set to empty or
0 values; i.e. `--config=stamp` should not be set.
If you specify `--config=local` and `--config=stamp` simultaneously,
you'll get a build error.

See [scmversion.md](scmversion.md).

## Other flags

The flag `--config=local` is also implied by other flags, e.g.:

* `--config=fast`. See [fast.md](fast.md).

## Common issues

It is possible to see `Read-only file system` errors if a previous
`--config=local` build was interrupted, especially when it was
building the defconfig file.

See [errors.md#defconfig-readonly](errors.md#defconfig-readonly) for solutions.
