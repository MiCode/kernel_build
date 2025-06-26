# Build `compile_commands.json`

The `compile_commands.json` file helps you enable cross-references
in your editor. Follow these instructions to place `compile_commands.json`
at the root of your repository.

## GKI

Run the following to place `compile_commands.json` at the root of your
repository:

```shell
$ tools/bazel run //common:kernel_aarch64_compile_commands
```

Or, to place the file somewhere else, you may provide the **absolute** path
to the destination as an argument to the script after `--`:

```shell
$ tools/bazel run //common:kernel_aarch64_compile_commands -- /tmp/compile_commands.json
```

## Device kernel

If you want to build `compile_commands.json` for in-tree modules, create a
`kernel_compile_commands` target with `deps` set to the `kernel_build` and
external module targets (`kernel_module`, `ddk_module` and/or
`kernel_module_group`). Then `tools/bazel run` the target.

See `kernel_compile_commands` in
[documentation for all rules](api_reference.md) for details.

**NOTE:** For out-of-tree modules built with the `kernel_module` macro, make
sure your `Makefile`s supports the `compile_commands.json` target.

## See also

See also the following links to incorporate clangd to your editor.

[clangd - Getting started](https://clangd.llvm.org/installation)

See the following for the schema of `compile_commands.json`.

[JSON Compilation Database Format Specification](https://clang.llvm.org/docs/JSONCompilationDatabase.html)
