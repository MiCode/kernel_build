load(
    "@kleaf//build/kernel/kleaf:kernel.bzl",
    "kernel_build",
)

filegroup(
    name = "common_kernel_sources",
    srcs = glob(
        ["**"],
        exclude = [
            "BUILD.bazel",
            "**/*.bzl",
            ".git/**",
        ],
    ),
    visibility = ["//visibility:public"],
)

# Pretend that we have a kernel_build to build some in-tree modules.
kernel_build(
    name = "fake_device",
    srcs = [":common_kernel_sources"],
    # Force the target to be built by Bazel.
    outs = [".config"],
    build_config = "build.config.gki.aarch64",
    make_goals = ["olddefconfig"],
)
