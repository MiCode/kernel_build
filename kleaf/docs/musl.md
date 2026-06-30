# Use musl libc for host binaries

This page discuss various flags to use musl libc for host binaries.

## --config=musl

Implies all of the following flags:

- --musl_prebuilts
- --musl_tools_from_sources
- --musl_kbuild
- --config=musl_platform

## --musl_prebuilts

For prebuilt tools, use the variant that links agianst musl libc.

This includes:

- `prebuilts/build-tools/linux_musl-x86`
- `prebuilts/kernel-build-tools/linux_musl-x86`

## --musl_tools_from_sources

For the list of `cc_binary`s used for `//build/kernel:hermetic-tools`, link
against musl libc.

This includes:

- A binary to embed arguments for certain tools (`rsync` and `tar`, etc.)
- A list of tools built from sources due to `--toolchain_from_sources`

## --musl_kbuild

In `kernel_build()`, Kbuild builds host binaries against musl libc. This
includes fixdep, objtool, kconfig, etc.

## --config=musl_platform

Switches the --host_platform to a label that contains the `constraint_value`
`//build/kernel/kleaf/platforms/libc:musl`.

This has at least the following effects:
- `py_binary` etc. uses a musl-built Python toolchain. The interpreter links
  against musl libc.
- `cc_binary` is linked against musl libc.
  - As a side-effect, you may see Kleaf behaves as if all of `--musl_prebuilts`,
    `--musl_tools_from_sources`, `--musl_kbuild`, is set. Hence, we recommend
    testing your build with the above sub-flags before enabling
    `--config=musl_platform`.
  - Your `cc_binary` may stop building. See below.

### Resolving errors in `cc_binary`

When using `--config=musl_platform`, under the hood, the linux_musl-x86_64 clang
cc toolchain does the following:

- If a `cc_binary` has `linkstatic = True` (the default), it also enables the
  `fully_static_link` feature, which adds `-static` to linkopts.
- If a `cc_binary` has `linkstatic = False`, it automatically adds
  `libc_musl.so` to library search paths (`-L`) and runtime library search paths
  (`-rpath`).

Because of this, your `cc_binary` building against the execution platform may
encounter errors. If you get errors about missing libraries like the following:

```
ld.lld: error: unable to find library -lbase
```

It is likely because your binary used to have `linkstatic = True` (the default),
which preferred using static libraries but was still permitted to link to
dynamic libraries. In the first case, without `--config=host_platform`, the
binary preferred using `libbase.a` (which might not exist) but were still
allowed to link to `libbase.so`. However, with `--config=host_platform`,
`linkstatic = True` implies `-static`, causing `libbase.so` to be dropped from
linkopts.

If you get error about missing `libgcc_s.so` like:

```
Error loading shared library libgcc_s.so.1: No such file or directory (needed by <omitted>/libbase.so)
```

It is likely because you are building against libraries that was prebuilt
against glibc.

The solutions of these errors involve doing one or more of following:

- Check that your `cc_binary` has `linkstatic = False`. This will link
  dependencies dynamically, resolving errors like the first one when the
  dependency (`libbase`) only provides the shared variant.
- If the failure is on a custom library (`cc_library` or `cc_import`), ensure it
  provides the static and/or shared variant depending on the value of
  `linkstatic` in the `cc_binary`.
- If the failure is on a custom prebuilt library (`cc_import`), ensure that
  the prebuilt library links against musl libc. In the second error above,
  switching from `//prebuilts/kernel-build-tools:linux_x86_imported_libs`
  to `//prebuilts/kernel-build-tools:imported_libs` resolves the error.

See `//build/kernel/kleaf/tests/cc_testing` for a list of supported use cases.

## See also

[Platforms](https://bazel.build/extending/platforms)

[C++ Toolchain Configuration](https://bazel.build/docs/cc-toolchain-config-reference)
