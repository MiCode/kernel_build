# Configuring kernel\_build

## Modify defconfig

To run `make *config` or `config.sh` in Kleaf, follow the following steps.

### Step 0: Try the old `config.sh` command to guess the Kleaf equivalent

If you already know what `kernel_build` you need to run on, go to step 1.

Run the old `config.sh` command with appropriate environment variables
and arguments. The `config.sh` guesses an equivalent command for you.
You may execute this command directly in the future.

Example:

```shell
$ BUILD_CONFIG=common/build.config.gki.aarch64 build/kernel/config.sh
Inferring equivalent Bazel command...
*****************************************************************************
* WARNING: build.sh is deprecated for this branch. Please migrate to Bazel.
*   See build/kernel/kleaf/README.md
*          Possibly equivalent Bazel command:
*
*   $ tools/bazel run //common:kernel_aarch64_config --
*
* To suppress this warning, set KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1
*****************************************************************************
```

### Step 1: Run the following Kleaf command

The command you may run to replace `config.sh` is:

```shell
$ tools/bazel run <name_of_kernel_build>_config [-- [menuconfig|nconfig|savedefconfig...]]
```

... where `<name_of_kernel_build>` is the name of the `kernel_build` target with
the requested build config.

The menu command (`menuconfig`, `xconfig`, etc.) must be provided to the
underlying executable, so they need to be provided after `--`. See
[Running executables](https://bazel.build/docs/user-manual#running-executables).
If nothing is provided, the default is `menuconfig`.

Example:

```shell
# BUILD_CONFIG=common/build.config.gki.aarch64 build/kernel/config.sh
$ tools/bazel run //common:kernel_aarch64_config

# BUILD_CONFIG=common/build.config.gki.x86_64 build/kernel/config.sh nconfig
$ tools/bazel run //common:kernel_x86_64_config -- nconfig
```

## Defconfig fragments

When building a `kernel_build` target, the following list of defconfig
fragments are applied on `.config`.

*   `kernel_build.defconfig_fragments`
*   `--defconfig_fragment`
*   defconfig fragments from other command line flags and other `kernel_build`
    attributes

See `kernel_build` in [documentation for all rules](api_reference.md) for
details.

The order does not matter. After `.config` is built, `.config` is checked
against each defconfig fragment to ensure that all defconfig fragments are
properly applied.

### kernel\_build.defconfig\_fragments

The convention is that the files should be named `X_defconfig`, where
`X` describes what the defconfig fragment does.

Example:

```python
# path/to/tuna/BUILD.bazel
kernel_build(
    name = "tuna",
    defconfig_fragments = ["tuna_defconfig"],
    ...
)
```
```shell
# path/to/tuna/tuna_defconfig

# Precondition:
#   CONFIG_TUNA_GRAPHICS must already be declared in kernel_build.kconfig_ext
CONFIG_TUNA_GRAPHICS=y
```

### --defconfig_fragment flag

You may specify a **single** target in the `--defconfig_fragment` flag to
add defconfig fragment(s) via the command line. To refer to a file in the
source tree, the file must already be exported via
[exports_files](https://bazel.build/reference/be/functions#exports_files)
or included in a
[filegroup](https://bazel.build/reference/be/general#filegroup).

**NOTE**: If multiple `--defconfig_fragment` are supplied, only the last
one takes effect.

The convention is that the files should be named `X_defconfig`, where
`X` describes what the defconfig fragment does.

Example:

```python
# path/to/tuna/BUILD.bazel
exports_files([
    "gcov_defconfig",
])
kernel_build(name = "tuna", ...)
```
```shell
# gcov_defconfig
CONFIG_GCOV_KERNEL=y
CONFIG_GCOV_PROFILE_ALL=y
```
```shell
$ tools/bazel build \
    --defconfig_fragment=//path/to/tuna:gcov_defconfig \
    //path/to/tuna:tuna
```

To specify multiple fragments in the flag, use a
[filegroup](https://bazel.build/reference/be/general#filegroup).

Example:

```python
# path/to/tuna/BUILD.bazel
filegroup(
    name = "all_kasan_defconfigs",
    srcs = ["kasan_defconfig", "lto_none_defconfig"]
)
kernel_build(name = "tuna", ...)
```
```shell
$ tools/bazel build \
    --defconfig_fragment=//path/to/tuna:all_kasan_defconfigs \
    //path/to/tuna:tuna
```

### Other pre-defined flags

There are a few pre-defined command-line flags and attributes on `kernel_build`
that are commonly used. When these flags and/or attributes are set, additional
defconfig fragments are applied on `.config`, and checked after `.config` is
built. It is recommended to use these common flags instead of defining your
own defconfig fragments to avoid fragmentation in the ecosystem (pun intended).

*   `--btf_debug_info`
*   `--page_size`

### User-defined flags

To control `kernel_build.defconfig_fragments` with command line flags,
you may use
[configurable build attributes](https://bazel.build/docs/configurable-attributes)
(sometimes referred to as `select()`).

Example:

```python
bool_flag(
    name = "khwasan",
    build_setting_default = False,
)

config_setting(
    name = "khwasan_is_set",
    flag_values = {":khwasan": "true"},
)

kernel_build(
    name = "tuna",
    defconfig_fragments = select({
        ":khwasan_is_set": ["khwasan_defconfig"],
        "//conditions:default": []
    }) + [...],
    ...
)
```
```shell
$ tools/bazel build --//path/to/tuna:khwasan //path/to/tuna:tuna
```

Use [device.bazelrc](impl.md#bazelrc-files) to shorten flags:

```text
# device.bazelrc
build --flag_alias=khwasan=--//path/to/tuna:khwasan
```

```shell
$ tools/bazel build --khwasan //path/to/tuna:tuna
```

To shorten `--defconfig_fragment` flags, you may use
[`--config`](https://bazel.build/run/bazelrc#config) in `device.bazelrc`:

```text
# device.bazelrc
build:gcov --defconfig_fragment=//path/to/tuna:gcov_defconfig
```
```shell
$ tools/bazel build --config=gcov //path/to/tuna:tuna
```
