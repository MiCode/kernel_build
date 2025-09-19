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
    |    `- kernel/
    |- common/
    |    `- build.config.constants              # Note 2
    `- external/
         |- bazelbuild-bazel-central-registry
         `- <other external repositories>       # Note 3
```

**Note 1**: The root `WORKSPACE` file is present to support pre-bzlmod builds.
After bzlmod migration, this file may be removed.

**Note 2**: If `build.config.constants` exists elsewhere other than `common/`,
create the symlink `common/build.config.constants` to the file. This may be
done with `<linkfile>` in your repo manifest.

**Note 3**: A list of external repositories are required for bzlmod to work.
For the up-to-date list, refer to the repo manifest of the ACK branch.

### Use @kleaf as dependency

This will be supported in the near future. Stay tuned!

## Versions of dependent modules

### Cheatsheet

```text
bazel_dep version <= actual version in external/
```

### bazel\_dep version

This refers to the version of a given module declared in `bazel_dep` in
[MODULE.bazel](../bzlmod/bazel.MODULE.bazel).

This is the version that `@kleaf` expects from the dependent module. For
example, if `@kleaf` uses feature A from `rules_cc@1.5`, then the `bazel_dep`
declaration should have at least `rules_cc@1.5`.

In practice, the above version may get outdated. Because `MODULE.bazel`
declares `local_path_override`, the versions in `bazel_dep` are ignored, and
Kleaf will continue to work with the actual version in `external/` as
guaranteed by continuous testing. This may become a problem in the future
when Kleaf is used as a dependency module and the root module does not use the
same `local_path_override`.

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
bazel_dep version == actual version in external/
```

However, if the external Git repository is updated indenpendently, there may
be a period of time where `bazel_dep version < actual version in external/`,
until `MODULE.bazel` is updated.

## See also

[Bazel modules](https://bazel.build/external/module)
