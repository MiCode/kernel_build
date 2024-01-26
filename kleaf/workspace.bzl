# Copyright (C) 2022 The Android Open Source Project
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

"""
Defines repositories in a Kleaf workspace.
"""

load("//build/bazel_common_rules/workspace:external.bzl", "import_external_repositories")
load(
    "//build/kernel/kleaf:constants.bzl",
    "CI_TARGET_MAPPING",
    "GKI_DOWNLOAD_CONFIGS",
)
load("//build/kernel/kleaf:download_repo.bzl", "download_artifacts_repo")
load("//build/kernel/kleaf:key_value_repo.bzl", "key_value_repo")
load("//prebuilts/clang/host/linux-x86/kleaf:register.bzl", "register_clang_toolchains")

# buildifier: disable=unnamed-macro
def define_kleaf_workspace(common_kernel_package = None, include_remote_java_tools_repo = False):
    """Common macro for defining repositories in a Kleaf workspace.

    **This macro must only be called from `WORKSPACE` or `WORKSPACE.bazel`
    files, not `BUILD` or `BUILD.bazel` files!**

    If [`define_kleaf_workspace_epilog`](#define_kleaf_workspace_epilog) is
    called, it must be called after `define_kleaf_workspace` is called.

    Args:
      common_kernel_package: Default is `"@//common"`. The package to the common
        kernel source tree.

        As a legacy behavior, if the provided string does not start with
        `@` or `//`, it is prepended with `@//`.

        Do not provide the trailing `/`.
      include_remote_java_tools_repo: Default is `False`. Whether to vendor two extra
        repositories: remote_java_tools and remote_java_tools_linux.

        These respositories should exist under `//prebuilts/bazel/`
    """
    if common_kernel_package == None:
        common_kernel_package = "@//common"
    if not common_kernel_package.startswith("@") and not common_kernel_package.startswith("//"):
        common_kernel_package = "@//" + common_kernel_package

        # buildifier: disable=print
        print("""
WARNING: define_kleaf_workspace() should be called with common_kernel_package={}.
    This will become an error in the future.""".format(
            repr(common_kernel_package),
        ))

    import_external_repositories(
        # keep sorted
        bazel_skylib = True,
        io_abseil_py = True,
        io_bazel_stardoc = True,
    )

    # The prebuilt NDK does not support Bazel.
    # https://docs.bazel.build/versions/main/external.html#non-bazel-projects
    native.new_local_repository(
        name = "prebuilt_ndk",
        path = "prebuilts/ndk-r23",
        build_file = "build/kernel/kleaf/ndk.BUILD",
    )

    key_value_repo(
        name = "kernel_toolchain_info",
        srcs = ["{}:build.config.constants".format(common_kernel_package)],
        additional_values = {
            "common_kernel_package": common_kernel_package,
        },
    )

    # TODO: Make this architecture agnostic.
    gki_prebuilts_files = {out: None for out in CI_TARGET_MAPPING["kernel_aarch64"]["outs"]}
    gki_prebuilts_optional_files = {CI_TARGET_MAPPING["kernel_aarch64"]["protected_modules"]: None}
    for config in GKI_DOWNLOAD_CONFIGS:
        if config.get("mandatory", True):
            files_dict = gki_prebuilts_files
        else:
            files_dict = gki_prebuilts_optional_files

        files_dict.update({out: None for out in config.get("outs", [])})

        for out, remote_filename_fmt in config.get("outs_mapping", {}).items():
            file_metadata = {"remote_filename_fmt": remote_filename_fmt}
            files_dict.update({out: file_metadata})

    download_artifacts_repo(
        name = "gki_prebuilts",
        files = gki_prebuilts_files,
        optional_files = gki_prebuilts_optional_files,
        target = "kernel_aarch64",
    )

    # TODO(b/200202912): Re-route this when rules_python is pulled into AOSP.
    native.local_repository(
        name = "rules_python",
        path = "build/bazel_common_rules/rules/python/stubs",
    )

    # The following 2 repositories contain prebuilts that are necessary to the Java Rules.
    # They are vendored locally to avoid the need for CI bots to download them.
    if include_remote_java_tools_repo:
        native.local_repository(
            name = "remote_java_tools",
            path = "prebuilts/bazel/common/remote_java_tools",
        )

        native.local_repository(
            name = "remote_java_tools_linux",
            path = "prebuilts/bazel/linux-x86_64/remote_java_tools_linux",
        )

    # Use checked-in JDK from prebuilts as local_jdk
    #   Needed for stardoc
    # Note: This was not added directly to avoid conflicts with roboleaf,
    #   see https://android-review.googlesource.com/c/platform/build/bazel/+/2457390
    #   for more details.
    native.new_local_repository(
        name = "local_jdk",
        path = "prebuilts/jdk/jdk11/linux-x86",
        build_file = "build/kernel/kleaf/jdk11.BUILD",
    )

    # Fake rules_cc to avoid fetching it for any py_binary targets.
    native.local_repository(
        name = "rules_cc",
        path = "build/kernel/kleaf/impl/fake_rules_cc",
    )

    # Stub out @remote_coverage_tools required for testing.
    native.local_repository(
        name = "remote_coverage_tools",
        path = "build/bazel_common_rules/rules/coverage/remote_coverage_tools",
    )

    # Stub out @rules_java required for stardoc.
    native.local_repository(
        name = "rules_java",
        path = "build/bazel_common_rules/rules/java/rules_java",
    )

    # Use checked-in JDK from prebuilts as local_jdk
    #   Needed for stardoc
    native.register_toolchains(
        "@local_jdk//:all",
    )

    native.register_toolchains(
        "//prebuilts/build-tools:py_toolchain",
        "//build/kernel:hermetic_tools_toolchain",
    )

    register_clang_toolchains()
