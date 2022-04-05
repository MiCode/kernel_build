# Copyright (C) 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load(
    ":kernel.bzl",
    "kernel_build",
    "kernel_build_abi",
    "kernel_compile_commands",
    "kernel_filegroup",
    "kernel_images",
    "kernel_kythe",
    "kernel_modules_install",
)
load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load(
    ":constants.bzl",
    "CI_TARGET_MAPPING",
    "GKI_DOWNLOAD_CONFIGS",
    "GKI_MODULES",
    "aarch64_outs",
    "x86_64_outs",
)

_ARCH_CONFIGS = {
    "kernel_aarch64": {
        "build_config": "build.config.gki.aarch64",
        "outs": aarch64_outs,
    },
    "kernel_aarch64_debug": {
        "build_config": "build.config.gki-debug.aarch64",
        "outs": aarch64_outs,
    },
    "kernel_x86_64": {
        "build_config": "build.config.gki.x86_64",
        "outs": x86_64_outs,
    },
    "kernel_x86_64_debug": {
        "build_config": "build.config.gki-debug.x86_64",
        "outs": x86_64_outs,
    },
}

# Valid configs of the value of the kmi_config argument in
# `define_common_kernels`
_KMI_CONFIG_VALID_KEYS = [
    "kmi_symbol_list",
    "additional_kmi_symbol_lists",
    "trim_nonlisted_kmi",
    "kmi_symbol_list_strict_mode",
]

# Always collect_unstripped_modules for common kernels.
_COLLECT_UNSTRIPPED_MODULES = True

# glob() must be executed in a BUILD thread, so this cannot be a global
# variable.
def _default_kmi_configs():
    """Return the default value of `kmi_configs` of [`define_common_kernels()`](#define_common_kernels).
    """
    aarch64_kmi_symbol_list = native.glob(["android/abi_gki_aarch64"])
    aarch64_kmi_symbol_list = aarch64_kmi_symbol_list[0] if aarch64_kmi_symbol_list else None
    aarch64_additional_kmi_symbol_lists = native.glob(
        ["android/abi_gki_aarch64*"],
        exclude = ["**/*.xml", "android/abi_gki_aarch64"],
    )
    aarch64_trim_and_check = bool(aarch64_kmi_symbol_list) or len(aarch64_additional_kmi_symbol_lists) > 0
    return {
        "kernel_aarch64": {
            # Assume the value for KMI_SYMBOL_LIST and ADDITIONAL_KMI_SYMBOL_LISTS
            # for build.config.gki.aarch64
            "kmi_symbol_list": aarch64_kmi_symbol_list,
            "additional_kmi_symbol_lists": aarch64_additional_kmi_symbol_lists,
            # In build.config.gki.aarch64:
            # - If there are symbol lists: assume TRIM_NONLISTED_KMI=${TRIM_NONLISTED_KMI:-1}
            # - If there aren't:           assume TRIM_NONLISTED_KMI unspecified
            "trim_nonlisted_kmi": aarch64_trim_and_check,
            "kmi_symbol_list_strict_mode": aarch64_trim_and_check,
        },
        "kernel_aarch64_debug": {
            # Assume the value for KMI_SYMBOL_LIST and ADDITIONAL_KMI_SYMBOL_LISTS
            # for build.config.gki-debug.aarch64
            "kmi_symbol_list": aarch64_kmi_symbol_list,
            "additional_kmi_symbol_lists": aarch64_additional_kmi_symbol_lists,
            # Assume TRIM_NONLISTED_KMI="" in build.config.gki-debug.aarch64
            "trim_nonlisted_kmi": False,
        },
        "kernel_x86_64_debug": {
            # Assume TRIM_NONLISTED_KMI="" in build.config.gki-debug.x86_64
            "trim_nonlisted_kmi": False,
        },
    }

def _filter_keys(d, valid_keys, what):
    """Remove keys from `d` if the key is not in `valid_keys`.

    Fail if there are unknown keys in `d`.
    """
    ret = {key: value for key, value in d.items() if key in valid_keys}
    if sorted(ret.keys()) != sorted(d.keys()):
        fail("{what} contains invalid keys {invalid_keys}. Valid keys are: {valid_keys}".format(
            what = what,
            invalid_keys = [key for key in d.keys() if key not in valid_keys],
            valid_keys = valid_keys,
        ))
    return ret

def define_common_kernels(
        kmi_configs = None,
        toolchain_version = None,
        visibility = None):
    """Defines common build targets for Android Common Kernels.

    This macro expands to the commonly defined common kernels (such as the GKI
    kernels and their variants. They are defined based on the conventionally
    used `BUILD_CONFIG` file and produce usual output files.

    Targets declared for kernel build (parent list item depends on child list item):
    - `kernel_aarch64_sources`
    - `kernel_aarch64_dist`
      - `kernel_aarch64`
      - `kernel_aarch64_uapi_headers`
      - `kernel_aarch64_additional_artifacts`
    - `kernel_aarch64_debug_dist`
      - `kernel_aarch64_debug`
    - `kernel_x86_64_sources`
    - `kernel_x86_64_dist`
      - `kernel_x86_64`
      - `kernel_x86_64_uapi_headers`
      - `kernel_x86_64_additional_artifacts`
    - `kernel_x86_64_debug_dist`
      - `kernel_x86_64_debug`

    `<name>` (aka `kernel_{aarch64,x86}{_debug,}`) targets build the
    main kernel build artifacts, e.g. `vmlinux`, etc.

    `<name>_sources` are convenience filegroups that refers to all sources required to
    build `<name>` and related targets.

    `<name>_uapi_headers` targets build `kernel-uapi-headers.tar.gz`.

    `<name>_additional_artifacts` contains additional artifacts that may be added to
    a distribution. This includes:
      - Images, including `system_dlkm`, etc.
      - `kernel-headers.tar.gz`

    `<name>_dist` targets can be run to obtain a distribution outside the workspace.

    Aliases are created to refer to the GKI kernel (`kernel_aarch64`) as
    "`kernel`" and the corresponding dist target (`kernel_aarch64_dist`) as
    "`kernel_dist`".

    Targets declared for cross referencing:
    - `kernel_aarch64_kythe_dist`
      - `kernel_aarch64_kythe`

    **ABI monitoring**
    On branches with ABI monitoring turned on (aka KMI symbol lists are checked
    in; see argument `kmi_configs`), the following targets are declared:

    - `kernel_aarch64_abi`

    See [`kernel_build_abi()`](#kernel_build_abi) for details.

    **Prebuilts**

    You may set the argument `--use_prebuilt_gki` to a GKI prebuilt build number
    on [ci.android.com](http://ci.android.com). The format is:

    ```
    bazel <command> --use_prebuilt_gki=<build_number> <targets>
    ```

    For example, the following downloads GKI artifacts of build number 8077484 (assuming
    the current package is `//common`):

    ```
    bazel build --use_prebuilt_gki=8077484 //common:kernel_aarch64_download_or_build
    ```

    If you leave out the `--use_prebuilt_gki` argument, the command is equivalent to
    `bazel build //common:kernel_aarch64`, which builds kernel from source.

    `<name>_download_or_build` targets builds `<name>` from source if the `use_prebuilt_gki`
    is not set, and downloads artifacts of the build number from
    [ci.android.com](http://ci.android.com) if it is set. The build number is spe

    - `kernel_aarch64_download_or_build`
      - `kernel_aarch64_additional_artifacts_download_or_build`
      - `kernel_aarch64_uapi_headers_download_or_build`

    Note: If a device should build against downloaded prebuilts unconditionally, set
    `--//<package>:use_prebuilt_gki` and a fixed build number in `device.bazelrc`. For example:
    ```
    # device.bazelrc
    build --//common:use_prebuilt_gki
    build --action_env=KLEAF_DOWNLOAD_BUILD_NUMBER_MAP="gki_prebuilts=8077484"
    ```

    This is equivalent to specifying `--use_prebuilt_gki=8077484` for all Bazel commands.

    Args:
      kmi_configs: A dictionary, where keys are target names, and
        values are a dictionary of configurations on the KMI.

        The content of `kmi_configs` should match the following variables in
        `build.config.gki{,-debug}.{aarch64,x86_64}`:
        - `KMI_SYMBOL_LIST`
        - `ADDITIONAL_KMI_SYMBOL_LISTS`
        - `TRIM_NONLISTED_KMI`
        - `KMI_SYMBOL_LIST_STRICT_MODE`

        The keys of the `kmi_configs` may be one of the following:
        - `kernel_aarch64`
        - `kernel_aarch64_debug`
        - `kernel_x86_64`
        - `kernel_x86_64_debug`

        The values of the `kmi_configs` should be a dictionary, where keys
        are one of the following, and values are passed to the corresponding
        argument in [`kernel_build`](#kernel_build):
        - `kmi_symbol_list`
        - `additional_kmi_symbol_lists`
        - `trim_nonlisted_kmi`
        - `kmi_symbol_list_strict_mode`

        If an architecture or configuration is not specified in `kmi_configs`,
        its value is passed to `kernel_build` as `None`, so `kernel_build`
        decides its default value. See [`kernel_build`](#kernel_build) for
        the default value of each configuration.

        If `kmi_configs` is unspecified or `None`, use sensible defaults:
        - `kernel_aarch64`:
          - `kmi_symbol_list = "android/abi_gki_aarch64"` if the file exist, else `None`
          - `additional_kmi_symbol_list = glob(["android/abi_gki_aarch64*"])` excluding `kmi_symbol_list` and XMLs
          - `TRIM_NONLISTED_KMI=${TRIM_NONLISTED_KMI:-1}` in `build.config` if there are symbol lists, else empty
          - `KMI_SYMBOL_LIST_STRICT_MODE=${KMI_SYMBOL_LIST_STRICT_MODE:-1}` in `build.config` if there are symbol lists, else empty
        - `kernel_aarch64_debug`:
          - `kmi_symbol_list = "android/abi_gki_aarch64"` if the file exist, else `None`
          - `additional_kmi_symbol_list = glob(["android/abi_gki_aarch64*"])` excluding `kmi_symbol_list` and XMLs
          - `TRIM_NONLISTED_KMI=""` in `build.config`
          - `KMI_SYMBOL_LIST_STRICT_MODE=""` in `build.config`
        - `kernel_x86_64`:
          - No `kmi_symbol_list` nor `additional_kmi_symbol_lists`
          - `TRIM_NONLISTED_KMI` is not specified in `build.config`
          - `KMI_SYMBOL_LIST_STRICT_MODE` is not specified in `build.config`
        - `kernel_x86_64_debug`:
          - No `kmi_symbol_list` nor `additional_kmi_symbol_lists`
          - `TRIM_NONLISTED_KMI=""` in `build.config`
          - `KMI_SYMBOL_LIST_STRICT_MODE` is not specified in `build.config`

        That is, the default value is:
        ```
        aarch64_kmi_symbol_list = glob(["android/abi_gki_aarch64"])
        aarch64_kmi_symbol_list = aarch64_kmi_symbol_list[0] if aarch64_kmi_symbol_list else None
        aarch64_additional_kmi_symbol_lists = glob(
            ["android/abi_gki_aarch64*"],
            exclude = ["**/*.xml", "android/abi_gki_aarch64"],
        )
        aarch64_trim_and_check = bool(aarch64_kmi_symbol_list) or len(aarch64_additional_kmi_symbol_lists) > 0
        kmi_configs = {
            "kernel_aarch64": {
                "kmi_symbol_list": aarch64_kmi_symbol_list,
                "additional_kmi_symbol_lists": aarch64_additional_kmi_symbol_lists,
                "trim_nonlisted_kmi": aarch64_trim_and_check,
                "kmi_symbol_list_strict_mode": aarch64_trim_and_check,
            },
            "kernel_aarch64_debug": {
                "kmi_symbol_list": aarch64_kmi_symbol_list,
                "additional_kmi_symbol_lists": aarch64_additional_kmi_symbol_lists,
                "trim_nonlisted_kmi": False,
            },
            "kernel_x86_64_debug": {
                "trim_nonlisted_kmi": False,
            },
        }
        ```

        If `kmi_configs` is not set explicitly in `define_common_kernels()`:

        |                                   |trim?         |
        |-----------------------------------|--------------|
        |`kernel_aarch64`                   |TRIM          |
        |(with symbol lists)                |              |
        |(`trim_nonlisted_kmi=True`)        |              |
        |-----------------------------------|--------------|
        |`kernel_aarch64`                   |NO TRIM       |
        |(no symbol lists)                  |              |
        |(`trim_nonlisted_kmi=None`)        |              |
        |-----------------------------------|--------------|
        |`kernel_aarch64_debug`             |NO TRIM       |
        |(`trim_nonlisted_kmi=False`)       |              |
        |-----------------------------------|--------------|
        |`kernel_x86_64`                    |NO TRIM       |
        |(`trim_nonlisted_kmi=None`)        |              |
        |-----------------------------------|--------------|
        |`kernel_x86_64_debug`              |NO TRIM       |
        |(`trim_nonlisted_kmi=False`)       |              |

      toolchain_version: If not set, use default value in `kernel_build`.
      visibility: visibility of the `kernel_build` and targets defined for downloaded prebuilts.
        If unspecified, its value is `["//visibility:public"]`.

        See [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
    """

    if visibility == None:
        visibility = ["//visibility:public"]

    if kmi_configs == None:
        kmi_configs = _default_kmi_configs()
    if kmi_configs:
        kmi_configs = _filter_keys(
            kmi_configs,
            valid_keys = _ARCH_CONFIGS.keys(),
            what = "//{package}: kmi_configs".format(package = native.package_name()),
        )

    for name, arch_config in _ARCH_CONFIGS.items():
        native.filegroup(
            name = name + "_sources",
            srcs = native.glob(
                ["**"],
                exclude = [
                    "BUILD.bazel",
                    "**/*.bzl",
                    ".git/**",
                ],
            ),
        )

        kmi_config = _filter_keys(
            kmi_configs.get(name, {}),
            valid_keys = _KMI_CONFIG_VALID_KEYS,
            what = '//{package}:{name}: kmi_configs["{name}"]'.format(
                package = native.package_name(),
                name = name,
            ),
        )
        kernel_build_abi(
            name = name,
            srcs = [name + "_sources"],
            outs = arch_config["outs"],
            implicit_outs = [
                # Kernel build time module signining utility and keys
                # Only available during GKI builds
                # Device fragments need to add: '# CONFIG_MODULE_SIG_ALL is not set'
                "scripts/sign-file",
                "certs/signing_key.pem",
                "certs/signing_key.x509",
            ],
            module_outs = GKI_MODULES,
            build_config = arch_config["build_config"],
            visibility = visibility,
            define_abi_targets = bool(kmi_config.get("kmi_symbol_list")),
            # Sync with KMI_SYMBOL_LIST_MODULE_GROUPING
            module_grouping = None,
            collect_unstripped_modules = _COLLECT_UNSTRIPPED_MODULES,
            toolchain_version = toolchain_version,
            **kmi_config
        )

        kernel_modules_install(
            name = name + "_modules_install",
            kernel_modules = [],
            kernel_build = name,
        )

        kernel_images(
            name = name + "_images",
            kernel_build = name,
            kernel_modules_install = name + "_modules_install",
            # Sync with GKI_DOWNLOAD_CONFIGS, "additional_artifacts".
            build_system_dlkm = True,
            deps = [
                # Keep the following in sync with build.config.gki* MODULES_LIST
                "android/gki_system_dlkm_modules",
            ],
        )

        # module_staging_archive from <name>
        native.filegroup(
            name = name + "_modules_staging_archive",
            srcs = [name],
            output_group = "modules_staging_archive",
        )

        # Everything in name + "_dist", minus UAPI headers & DDK, because
        # device-specific external kernel modules may install different headers.
        native.filegroup(
            name = name + "_additional_artifacts",
            srcs = [
                # Sync with GKI_DOWNLOAD_CONFIGS, "additional_artifacts".
                name + "_headers",
                name + "_modules_install",
                name + "_images",
                name + "_kmi_symbol_list",
            ],
        )

        # Everything in name + "_dist" for the DDK.
        # These aren't in DIST_DIR for build.sh-style builds, but necessary for driver
        # development. Hence they are also added to kernel_*_dist so they can be downloaded.
        # Note: This poke into details of kernel_build!
        native.filegroup(
            name = name + "_ddk_artifacts",
            srcs = [
                name + "_modules_prepare",
                name + "_modules_staging_archive",
            ],
        )

        copy_to_dist_dir(
            name = name + "_dist",
            data = [
                name,
                name + "_uapi_headers",
                name + "_additional_artifacts",
                name + "_ddk_artifacts",
            ],
            flat = True,
        )

    native.alias(
        name = "kernel",
        actual = ":kernel_aarch64",
    )

    native.alias(
        name = "kernel_dist",
        actual = ":kernel_aarch64_dist",
    )

    kernel_compile_commands(
        name = "kernel_aarch64_compile_commands",
        kernel_build = ":kernel_aarch64",
    )

    kernel_kythe(
        name = "kernel_aarch64_kythe",
        kernel_build = ":kernel_aarch64",
        compile_commands = ":kernel_aarch64_compile_commands",
    )

    copy_to_dist_dir(
        name = "kernel_aarch64_kythe_dist",
        data = [
            ":kernel_aarch64_compile_commands",
            ":kernel_aarch64_kythe",
        ],
        flat = True,
    )

    _define_prebuilts(visibility = visibility)

def _define_prebuilts(**kwargs):
    # Build number for GKI prebuilts
    bool_flag(
        name = "use_prebuilt_gki",
        build_setting_default = False,
    )

    # Matches when --use_prebuilt_gki is set.
    native.config_setting(
        name = "use_prebuilt_gki_set",
        flag_values = {
            ":use_prebuilt_gki": "true",
        },
    )

    for name, value in CI_TARGET_MAPPING.items():
        repo_name = value["repo_name"]
        main_target_outs = value["outs"]  # outs of target named {name}

        source_package_name = ":" + name

        native.filegroup(
            name = name + "_downloaded",
            srcs = ["@{}//{}".format(repo_name, filename) for filename in main_target_outs],
        )

        # A kernel_filegroup that:
        # - If --use_prebuilt_gki_num is set, use downloaded prebuilt of kernel_aarch64
        # - Otherwise build kernel_aarch64 from sources.
        kernel_filegroup(
            name = name + "_download_or_build",
            srcs = select({
                ":use_prebuilt_gki_set": [":" + name + "_downloaded"],
                "//conditions:default": [source_package_name],
            }),
            deps = select({
                ":use_prebuilt_gki_set": [source_package_name + "_ddk_artifacts_downloaded"],
                "//conditions:default": [source_package_name + "_ddk_artifacts"],
            }),
            kernel_srcs = [source_package_name + "_sources"],
            kernel_uapi_headers = source_package_name + "_uapi_headers_download_or_build",
            collect_unstripped_modules = _COLLECT_UNSTRIPPED_MODULES,
            **kwargs
        )

        for config in GKI_DOWNLOAD_CONFIGS:
            target_suffix = config["target_suffix"]
            suffixed_target_outs = config["outs"]  # outs of target named {name}_{target_suffix}

            native.filegroup(
                name = name + "_" + target_suffix + "_downloaded",
                srcs = ["@{}//{}".format(repo_name, filename) for filename in suffixed_target_outs],
            )

            # A filegroup that:
            # - If --use_prebuilt_gki_num is set, use downloaded prebuilt of kernel_{arch}_{target_suffix}
            # - Otherwise build kernel_{arch}_{target_suffix}
            native.filegroup(
                name = name + "_" + target_suffix + "_download_or_build",
                srcs = select({
                    ":use_prebuilt_gki_set": [":" + name + "_" + target_suffix + "_downloaded"],
                    "//conditions:default": [source_package_name + "_" + target_suffix],
                }),
                **kwargs
            )
