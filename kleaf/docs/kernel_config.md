# Run `make *config` or `config.sh` in Kleaf

To run `make *config` or `config.sh` in Kleaf, follow the following steps.

## Step 0: Try the old `config.sh` command to guess the Kleaf equivalent

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
