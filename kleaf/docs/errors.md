# Resolving Common Errors when Writing Bazel Rules

This document explains how to deal with common errors when
[building your kernels and drivers with Kleaf](impl.md).

## /bin/sh: line 1: clang: command not found

This error may happen after the clang version and `CLANG_PREBUILT_BIN` is
updated, but corresponding Bazel rules aren't.

To fix, check clang version. Specifically, check the attribute
`toolchain_version` of `kernel_build` against the value in `CLANG_PREBUILT_BIN`
(usually in `build.config.common` or `build.config.constants`).

Example:
[CL 1918433](https://android-review.googlesource.com/c/kernel/common/+/1918433/3/BUILD.bazel)
updates `toolchain_version` to be `CLANG_VERSION`, which is loaded from
[build.config.constants](https://android-review.googlesource.com/c/kernel/common/+/1918432/3/build.config.constants)
.

## fatal error: '[some\_header\_file].h' file not found {#header-not-found}

This means the header file is not visible to the kernel module build.

If there are multiple matches, first determine which one is needed by examining
the `Makefile` / `Kbuild` file.

Try to find this header file in the kernel module source tree. Example (for
Pixel):

```sh
$ find gs/google-modules -name some_header_file.h
```

If the header file is in the same directory as the kernel module or a
subdirectory, check that `srcs` include the header file. Example:

```bazel
# Adds the file explicitly
srcs = [
  "some_header_file.h"
],

# Adds header files from the same directory as the BUILD.bazel file,
# but NOT subdirectories
srcs = glob(["*.h"]),

# Adds header files from the same directory as the BUILD.bazel file
# INCLUDING matches from subdirectories
srcs = glob(["**/*.h"]),
```

If the header file is in the directory of a different kernel module:

*   Declare a `filegroup` for headers in the other directory, and add this
    module to the `visibility` attribute
*   Add the `filegroup` to `srcs` (as a label)

Example:
[Export headers from BMS](https://android.googlesource.com/kernel/google-modules/bms/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel),
[Use BMS headers for Power Reset module](https://android.googlesource.com/kernel/google-modules/power/reset/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

## WARNING: Symbol version dump "[...]/foo/Module.symvers" is missing. {#module-symvers-missing}

This means a kernel module dependency is missing.

Solution: Add the `kernel_module` in `foo` to `kernel_module_deps` of the build
rule.

Example:
[Power Reset module depends on BMS](https://android.googlesource.com/kernel/google-modules/power/reset/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel).

## Exception: Unable to find \[some file\] in any of the following directories: ... {#no-files-match}

First, check whether `[some_module].ko` should be an output of the
`kernel_module` rule or not by checking the `Makefile` / `Kbuild` files.

If not, remove its declaration in `BUILD.bazel` in the `outs` attribute of the
`kernel_module` rule.

If it should be an output, it is likely that a previous error prevents it from
being built. Check previous error messages.

If you can't see any errors, run with `--sandbox_debug` to prevent the sandbox
to be teared down.

**Note**: Using `--sandbox_debug` may leave a huge amount of symlinks undeleted,
and prevent sandbox from being unmounted. Repeat use of `--sandbox_debug` may
affect the performance of your host machine. Use sparingly with caution.

Example:

```sh
$ bazel build --verbose_failures --sandbox_debug //gs/google-modules/foo/..
```

With that option, you should see where the sandbox is mounted. Example:

```
<timestamp>: src/main/tools/linux-sandbox-pid1.cc:279: remount rw: <workspace_root>/out/bazel/output_user_root/<hash>/sandbox/linux-sandbox/<sandbox_number>/execroot/__main__
```

Concatenate the sandbox root and the file mentioned in the error message to see
why it is not there. For example, if the error message was

```
Exception: In bazel-out/k8-fastbuild/bin/gs/google-modules/foo/staging/lib/modules/5.10.43/extra, no files match foo_module.ko, expected 1
```

Go to the directory and search for the file:

```sh
$ find \
<workspace_root>/out/bazel/output_user_root/<hash>/sandbox/linux-sandbox/<sandbox_number>/execroot/__main__/bazel-out/k8-fastbuild/bin/private/google-modules/foo/staging/lib/modules/5.10.43/extra \
-name foo_module.ko
```

Check why it is missing.

## Exception: In \[some directory\], multiple files match \[some file\], expected at most 1 {#multiple-files-match}

Same as above section ([no files match](#no-files-match)), except that in the
last step, check which installed files have the given name. For example, you may
see:

```
foo/my_module.ko
bar/my_module.ko
```

In the `outs` attribute, instead of specifying a vague `my_module.ko`, try to
specify the full path so the build system knows which file you are referring to:

```bazel
outs = [
  # This is confusing to the build system. Avoid this.
  # "my_module.ko",

  # Do this instead.
  "for/my_module.ko",
  "bar/my_module.ko",
],
```

## There's an internal problem with your device / Missing SHA in `/proc/version`

If `/proc/version` shows something like

```
5.14.0-mainline
```

without a SHA, this is a known issue.

[comment]: <> (Bug 202077908)

This is also the cause of the following dialog on the phone screen with Android
12 userspace:

```
There's an internal problem with your device. Contact your manufacturer for details.
```

The dialog should not show if your device is running Android 13 in userspace
with
[CL 1843574](https://android-review.googlesource.com/c/platform/system/libvintf/+/1843574/)
.

## error: unable to open output file [...]: 'Operation not permitted' {#operation-not-permitted}

Check what the path of the file is. If it looks like this, continue reading:

```text
/<workspace_root>/out/bazel/output_user_root/<hash>/sandbox/linux-sandbox/<sandbox_number>/execroot/__main__/<some_SOURCE_directory>/<some_output_file>
```

`<some_SOURCE_directory>` means that it **does NOT start with `out/`**. For
example:

*   `gs/`
*   `common/`
*   `private/`
*   etc.

`<some_output_file>` means that it is an output file, not a source file. For
example:

*   `*.ko`
*   `*.o`
*   etc.

This is likely because `make` has been invoked in `<some_SOURCE_directory>`
without the proper `O=` argument, or Kbuild did not respect the `O=` argument
and put output files under the source directory.

However, the Bazel build system treats them as a source file because it is part
of the `glob()`. When the Bazel build system invokes Kbuild, Kbuild tries to
write those files. But within the sandbox, the source tree is readonly,
triggering the permission denial.

You may verify that this is the case by checking the existance of the output
file in the source tree:

```sh
$ ls /<workspace_root>/<some_SOURCE_directory>/<some_output_file>
```

To restore your repository to the normal state in the short term, try one of the
following under `<workspace_root>/<some_SOURCE_directory>`, or a parent
directory:

*   `make clean`
*   `git clean -fdx` (Be careful! This deletes all git ignored files.)

There should not be any output files in the source tree, other than in `out/`.

To properly fix this, investigate the Kbuild definition to see why `O=` is not
respected. Output files should be contained into the directory pointed at `O=`.

## WARNING: Unable to determine EXT_MODULES; scmversion for external modules may be incorrect. [...] <workspace_root>/build.config: No such file or directory

If your device builds external modules, create the top-level `build.config`
symlink to point to the `build.config` file so scmversions for external
modules are inferred correctly.

You may ignore this warning:
- if your device does not build external modules;
- if you are building GKI.

For details, see [scmversion.md](scmversion.md).

## fatal: not a git repository: '[...]/.git' {#not-git}

This is a harmless warning message.

[comment]: <> (Bug 194427140)

## date: invalid date '@' {#invalid-date}

This is a harmless warning message.

[comment]: <> (Bug 194427140)

## date: bad date +%s {#bad-date}

This is a harmless warning message.

[comment]: <> (Bug 194427140)
