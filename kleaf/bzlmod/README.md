# Bzlmod support for Kleaf

## Migrate to bzlmod

### Use @kleaf as root module

Set up your repo manifest to conform with the following filesystem layout.

```text
<workspace_root>/
    |- WORKSPACE               -> build/kernel/kleaf/bazel.WORKSPACE # Note 1
    |- WORKSPACE.bzlmod        -> build/kernel/kleaf/bzlmod/bazel.WORKSPACE.bzlmod
    |- MODULE.bazel            -> build/kernel/kleaf/bzlmod/bazel.MODULE.bazel
    |- build/
    |    |- BUILD.bazel              -> kernel/kleaf/bzlmod/empty_BUILD.bazel
    |    |- kernel_toolchain_ext.bzl -> kernel/kleaf/bzlmod/default_kernel_toolchain_ext.bzl # Note 2
    |    `- kernel/
    |- common/                 # Note 2
    |    `- build.config.constants
    `- external/
         |- bazelbuild-bazel-central-registry
         `- <other external repositories>       # Note 3
```

**Note 1**: The root `WORKSPACE` file is present to support pre-bzlmod builds.
After bzlmod migration, this file may be removed.

**Note 2**: If `build.config.constants` exists elsewhere other than `common/`,
the `build/kernel_toolchain_ext.bzl` should link to a file that
contains different content. See comments in
[default_kernel_toolchain_ext.bzl](default_kernel_toolchain_ext.bzl)
for details.

**Note 3**: A list of external repositories are required for bzlmod to work.
For the up-to-date list, refer to the repo manifest of the ACK branch.

### Use @kleaf as dependency

This will be supported in the near future. Stay tuned!

## Versions of dependent modules

### Cheatsheet

```text
bazel_dep version <= single_version_override version <= versions in local registry <= actual version in external/
```

### bazel\_dep version

This refers to the version of a given module declared in `bazel_dep` in [MODULE.bazel](MODULE.bazel).

This is the version that `@kleaf` expects from the dependent module. For
example, if `@kleaf` uses feature A from `rules_cc@1.5`, then the `bazel_dep`
declaration should have at least `rules_cc@1.5`.

In theory, only the following constraint is needed so that `@kleaf` functions
properly:

```text
bazel_dep version <= single_version_override version
```

When `@kleaf` is the root module, the following stricter constraint is used
when the local registry
is updated in order to avoid confusion of inconsistent values. That is,
`@kleaf` updates its `bazel_dep()` statements when the local registry is updated
with the update script.

```text
bazel_dep version == single_version_override version
```

When `@kleaf` is not the root module, the root module may specify
alternative `single_version_override()`. The `single_version_override()`
declaration in `@kleaf` is ignored.

### single\_version\_override version

This refers to the pinned version used at build time. Refer to the definition
[here](https://bazel.build/rules/lib/globals/module#single_version_override).

At build time, Bazel looks up the version declared in `single_version_override`
from the registry, and resolve accordingly.

**Note**: `single_version_override` statements are ignored when `@kleaf` is used
as a dependent module of the root module.

In the local registry, the `single_version_override` version must also set
`"type": "local"` and `"path": "external/<module_name>` to avoid reaching out to
the Internet. Alternatively, simply use `--config=internet`. See
[Internet Access](../docs/network.md).

### Local registry

For a given module, one or more (usually one) versions may have `"type": "local"`
under `external/bazelbuild-bazel-central-registry`. To prevent network access,
the `single_version_override` version must specify `"type": "local"`.

All these versions must be less than or equal to the actual version in
`external/`. Otherwise, if a newer version is requested and the registry
returns the local path, the local path is actually on an older version, lacking
features that the user may want.

### actual version in external/

For a given module, this is the version declared in
`external/<module_name>/MODULE.bazel`, with a few exceptions.

This is the actual version of the dependency. But at build time, Bazel does not
care about the actual version. Because of
[backwards compatibility guarantees](https://bazel.build/external/module#compatibility_level)
when compatibility level is the same, it is okay to use a new version as an
old version.

Usually, the following also holds true:

```text
local BCR version == actual version in external/
```

However, if the external Git repository is updated indenpendently, there may
be a period of time where `local BCR version < actual version in external/`,
until `external/bazelbuild-bazel-central-registry` has `source.json` updated
for that module.

## See also

[https://bazel.build/external/module](Bazel modules)
