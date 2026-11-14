# Configuring kernel\_build

[TOC]

## Modify defconfig

To run `make *config` or `config.sh` in Kleaf, run

```shell
$ tools/bazel run <name_of_kernel_build>_config [-- [menuconfig|nconfig|savedefconfig...]]
```

... where `<name_of_kernel_build>` is the name of the `kernel_build` target with
the requested build config.

The menu command (`menuconfig`, `xconfig`, etc.) must be provided to the
underlying executable, so they need to be provided after `--`. See
[Running executables](https://bazel.build/docs/user-manual#running-executables).
If nothing is provided, the default is `savedefconfig`.

Example:

```shell
$ tools/bazel run //common:kernel_aarch64_config

$ tools/bazel run //common:kernel_x86_64_config -- nconfig
```

### Conditions

The above command works if the following conditions are satisified:

*   `kernel_build.defconfig` is set or implicitly inherited from
    `base_kernel`.
*   `kernel_build.pre_defconfig_fragments` (including the ones inherited
    from `base_kernel`) has at most one element.

For `nconfig` etc. to work, `ncurses` may also be required on the host machine.

If these conditions are not satisified, the command may or may not work.

If `kernel_build.pre_defconfig_fragments` contains more than one element, the
above command prints the path to the generated configs. You may need to apply
the generated configs on `pre_defconfig_fragments` manually.

### Effects

After the developer goes through the `menuconfig` / `nconfig` / `xconfig` etc.
to configure the the kernel, Kleaf does the following:

If `kernel_build.pre_defconfig_fragments` (including the ones inherited
from `base_kernel`) is empty, Kleaf calls
`make savedefconfig` and copies the minimized defconfig to the source file
pointed by `kernel_build.defconfig`. The path to the updated file is printed.

If `kernel_build.pre_defconfig_fragments` (including the ones inherited
from `base_kernel`) has a single element, the difference
of the `.config` after and before the developer invokes `menuconfig` is
calculated, and then applied to the pre defconfig fragment. The path to the
updated file is printed.

If `kernel_build.pre_defconfig_fragments` (including the ones inherited
from `base_kernel`) has more than one element,
the difference of the `.config` after and before the developer invokes
`menuconfig` is calculated. Then, the command cowardly fails, with the path to
the temporary difference file printed. The developer is expected to move the
differences to the correct `pre_defconfig_fragments`.

**NOTE**: `post_defconfig_fragments` does not participate in any of these
calculations.

## Internals of configuring the kernel

When a `kernel_build` is built, Kleaf configures the kernel by applying the
following steps:

1.  The `kernel_build.defconfig` file is used as a base. If unspecified, the
    one from `base_kernel` is used.
2.  The `kernel_build.pre_defconfig_fragments` from `base_kernel` are applied.
3.  The `kernel_build.pre_defconfig_fragments` are applied.
4.  Calls `make ..._defconfig` to build `.config`
5.  If `kernel_build.check_defconfig` is set, compares `.config` against
    `defconfig` and `pre_defconfig_fragments`. See [Checks](#checks)
6.  The `kernel_build.post_defconfig_fragments`, `--defconfig_fragment` and
    other command line flags (e.g. `--kasan`) are applied on `.config`. If
    anything is applied, calls `make olddefconfig`.
7.  Enforces that `.config` contains all
    configurations in `post_defconfig_fragments`; see [Checks](#checks).

See `kernel_build` in [documentation for all rules](api_reference.md) for
details.

### Defconfig

This is the base defconfig.

For GKI, this is usually
the `gki_defconfig` for the architecture, e.g.
`//common:arch/arm64/configs/gki_defconfig`.

For mixed device builds that sets `base_kernel` to GKI, this is inherited from
the `base_kernel`. There is usually no need to specify `defconfig` explicitly.

### Pre Defconfig fragments

This usually contains a **single item** so that `tools/bazel run XXX_config`
works. see [Modify defconfig: Conditions](#conditions).

This usually contains configs to build in-tree modules that are not built in
the base kernel, e.g. `CONFIG_SOME_MODULE=m`.

A `kernel_build()` applies `pre_defconfig_fragments` from the `base_kernel`
before applying `pre_defconfig_fragments` of itself.

At step 2, When pre defconfig fragments are applied, items in
`defconfig` are overridden. In addition, **order matters**; items appearing
later in the `pre_defconfig_fragments` list overrides items appearing earlier.

At step 5, [Checks](#checks) are applied with the above in consideration, so
you don't have to manually add `# nocheck` for conflicting items. However, if
a `CONFIG_FOO` in `pre_defconfig_fragments` implicilty changed the value of
`CONFIG_BAR` in the `defconfig`, Kleaf may report an error. In this case,
explicitly specify the value of `CONFIG_BAR` in `pre_defconfig_fragments`, or
simply set `check_defconfig = "disabled"`.

Example:

```
# foo_defconfig
CONFIG_A=y
```

```
# set_a_defconfig
CONFIG_A=y
```

```
# unset_a_defconfig
# CONFIG_A is not set
```

```
# CONFIG_A=y
kernel_build(
    defconfig = "foo_defconfig",
    pre_defconfig_fragments = [],
    # ...
)

# CONFIG_A is not set
kernel_build(
    defconfig = "foo_defconfig",
    pre_defconfig_fragments = ["unset_a_defconfig"],
    # ...
)

# CONFIG_A=y
kernel_build(
    defconfig = "foo_defconfig",
    pre_defconfig_fragments = ["unset_a_defconfig", "set_a_defconfig"],
    # ...
)
```

### Post Defconfig fragments

This usually contains debug configs to build a variant of the kernel and
modules.

Post defconfig fragments consist of the following, in this order:

6.  Apply post defconfig fragments:
    1.  `kernel_build.post_defconfig_fragments`
    2.  `--defconfig_fragment`
    3.  Other pre-defined flags, e.g., `--kasan`, in an unspecified order.

At step 6, When pre defconfig fragments are applied, items in
`defconfig` and `pre_defconfig_fragments` are overridden by these
post defconfig fragments. Then at step 7, [Checks](#checks) are applied with the
above in consideration, so you don't have to manually add `# nocheck` on
`defconfig` and `pre_defconfig_fragments` even if their values are overridden by
post defconfig fragments later.

At step 6, **order matters** when post defconfig fragments are applied.
Items appearing later in the post defconfig fragments list overrides items
appearing earlier. However, at step 7,
**the order in post defconfig fragments does not matter in [Checks](#checks)**;
all items must exist in the final `.config` file. As a result, unless you have
`# nocheck` that suppresses conflicts, order usually does not matter.

Example (using `foo_defconfig` and other files from the previous example):

```
# CONFIG_A is not set
kernel_build(
    defconfig = "foo_defconfig",
    post_defconfig_fragments = ["unset_a_defconfig"],
    # ...
)

# Build error
# Because unset_a_defconfig conflicts with set_defconfig
kernel_build(
    post_defconfig_fragments = ["unset_a_defconfig", "set_defconfig"],
    # ...
)
```

#### kernel\_build.post\_defconfig\_fragments

The convention is that the files should be named `X_defconfig`, where
`X` describes what the defconfig fragment does.

Example:

```python
# path/to/tuna/BUILD.bazel
kernel_build(
    name = "tuna",
    post_defconfig_fragments = ["tuna_defconfig"],
    ...
)
```
```shell
# path/to/tuna/tuna_defconfig

# Precondition:
#   CONFIG_TUNA_DEBUG must already be declared in kernel_build.kconfig_ext
CONFIG_TUNA_DEBUG=y
```

#### --defconfig_fragment flag

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
    "kasan_hw_tags_defconfig",
])
kernel_build(name = "tuna", ...)
```
```shell
# kasan_hw_tags_defconfig
CONFIG_KASAN=y
CONFIG_KASAN_HW_TAGS=y
# CONFIG_KASAN_SW_TAGS is not set
# etc. Add your configs!
```
```shell
$ tools/bazel build \
    --defconfig_fragment=//path/to/tuna:kasan_hw_tags_defconfig \
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

#### Other pre-defined flags

There are a few pre-defined command-line flags and attributes on `kernel_build`
that are commonly used. When these flags and/or attributes are set, additional
defconfig fragments are applied on `.config`, and checked after `.config` is
built. It is recommended to use these common flags instead of defining your
own defconfig fragments to avoid fragmentation in the ecosystem (pun intended).

*   `--btf_debug_info`
*   `--debug`
*   `--gcov`
*   `--kcov`
*   `--kasan`
*   `--kasan_sw_tags`
*   `--kasan_generic`
*   `--kcsan`
*   `--notrim`
*   `--page_size`
*   `--rust` / `--norust`
*   `--rust_ashmem` / `--norust_ashmem`

**NOTE**: w.r.t. to KMI, the following flags will disable both `TRIM_UNUSED_KSYMS`
(by not setting it) and `MODULE_SIG_PROTECT`(by explicitly turning it off):
(`--notrim`, `--debug`, `--gcov`, `--kcov`, `--k*san`, `--kgdb`).

#### User-defined flags

To control `kernel_build.post_defconfig_fragments` with command line flags,
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
    post_defconfig_fragments = select({
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
build:kasan_hw_tags --defconfig_fragment=//path/to/tuna:kasan_hw_tags_defconfig
```
```shell
$ tools/bazel build --config=kasan_hw_tags //path/to/tuna:tuna
```

### Checks

All requirements in `defconfig` and `pre_defconfig_fragments` must be present
in the intermediate `.config` before post defconfig fragments are applied,
**unless**:

-   A `CONFIG_` in `defconfig` is overridden by `pre_defconfig_fragments`.
-   A `CONFIG_` in `pre_defconfig_fragments` is overridden by a later value in
    `pre_defconfig_fragments`.
-   The line in `defconfig`, `pre_defconfig_fragments` has a `# nocheck`
    comment appended to it.

All `post_defconfig_fragments` must be present in the final `.config`,
**unless** the line in `post_defconfig_fragments` has a `# nocheck` comment
appended to it.

The checks are in place to prevent typos and mistakes. For example, if an item
is not declared in `Kconfig`, then `make ..._defconfig` silently drops it, but
these checks properly flags potential issues.

Example:

```
# bar_defconfig
CONFIG_BASE=y
CONFIG_BASE_MODULE=m
# CONFIG_MODULE_1 is not set
# CONFIG_MODULE_2 is not set
# CONFIG_DEBUG_1 is not set
# CONFIG_DEBUG_2 is not set
```

```
# pre_defconfig
CONFIG_MODULE_2=m
```

```
# post_1_defconfig
CONFIG_DEBUG_1=y
CONFIG_DEBUG_2=y # nocheck: (b/12345678) a device does not support this
```

```
# post_2_defconfig
# CONFIG_DEBUG_2 is not set
```

```
kernel_build(
    name = "bar",
    defconfig = "bar_defconfig",
    pre_defconfig_fragments = ["pre_defconfig"],
    post_defconfig_fragments = ["post_1_defconfig", "post_2_defconfig"],
)
```

The resulting `.config` contains the following, and the check passes:

```
CONFIG_BASE=y
CONFIG_BASE_MODULE=m
# CONFIG_MODULE_1 is not set
CONFIG_MODULE_2=m
CONFIG_DEBUG_1=y
# CONFIG_DEBUG_2 is not set
```
