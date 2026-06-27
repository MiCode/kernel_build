# Kleaf - Building Android Kernels with Bazel

## Table of contents

[Introduction to Kleaf](docs/kleaf.md)

[Building your kernels and drivers with Bazel](docs/impl.md)

[`build.sh` build configs](docs/build_configs.md)

[Support ABI monitoring (GKI)](docs/abi.md)

[Support ABI monitoring (Device)](docs/abi_device.md)

[Handling SCM version](docs/scmversion.md)

[Resolving common errors](docs/errors.md)

[References to Bazel rules and macros for the Android Kernel](https://ci.android.com/builds/latest/branches/aosp_kernel-common-android-mainline/targets/kleaf_docs/view/index.html)

[Kleaf testing](docs/testing.md)

[Building against downloaded prebuilts](docs/download_prebuilt.md)

[Cheatsheet](docs/cheatsheet.md)

### Configurations

`--config=release`: [Release builds](docs/release.md)

`--config=fast`: [Make local builds faster](docs/fast.md)

`--config=local`: [Sandboxing](docs/sandbox.md)

`--config=stamp`: [Handling SCM version](docs/scmversion.md)

`--lto`: [Disable LTO during development](docs/lto.md)

`--kbuild_symtypes`: [KBUILD\_SYMTYPES](docs/symtypes.md)

`--kasan`: [kasan](docs/kasan.md)
