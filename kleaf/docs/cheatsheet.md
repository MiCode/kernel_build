# Kleaf Cheatsheet

## Building

### Just vmlinux and in-tree modules etc. ( = `make`)

```shell
$ tools/bazel build //common:kernel_aarch64
```

### All GKI artifacts for distribution ( = `build/build.sh`)

```shell
$ tools/bazel run //common:kernel_aarch64_dist
```

### Keep intermediate build artifacts (for example `*.o` files) in `out/cache/`

```shell
$ tools/bazel build --config=local //common:kernel_aarch64
```

## ABI monitoring

### Building all artifacts

```shell
$ tools/bazel run //common:kernel_aarch64_abi_dist
```

### Update symbol list

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update_symbol_list
```

### Update ABI definition

```shell
$ tools/bazel run //common:kernel_aarch64_abi_update
```

## LTO

```text
--lto={none,thin,default,full}
```

```shell
$ bazel run --lto=none //common:kernel_aarch64_dist
```

## Mnemonic

```text
$           BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
#   =>
$ tools/bazel run      //common:[........]kernel_aarch64[..............]_dist -- ...

$           BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh
#   =>
$ tools/bazel run      //common:[........]kernel_aarch64[..........]_abi[...]_dist -- ...

$           BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh --update_symbol_list
#   =>
$ tools/bazel run      //common:[........]kernel_aarch64[..........]_abi[...]_update_symbol_list

# The following two Bazel commands require updating the symbol list and
# protected exports list before executing the command.

$           BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh --nodiff --update
#   =>
$ tools/bazel run      //common:[........]kernel_aarch64[..........]_abi[...]_nodiff_update

$           BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh --update
#   =>
$ tools/bazel run      //common:[........]kernel_aarch64[..........]_abi[...]_update
```
