# Build `compile_commands.json`

## GKI

Run the following to place `compile_commands.json` at the root of your
repository:

```shell
$ tools/bazel run //common:kernel_aarch64_compile_commands
```

## Device kernel

If you want to build `compile_commands.json` for in-tree modules, create a
`kernel_compile_commands` target with `kernel_build` set accordingly,
then `tools/bazel run` the target.

See `kernel_compile_commands` in
[documentation for all rules](api_reference.md) for details.
