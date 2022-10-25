# Run `make *config` or `config.sh` in Kleaf

To run `make *config` or `config.sh` in Kleaf, follow the following steps.

## Step 1: Run the following Kleaf command

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