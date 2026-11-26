"""
Rules for building dtb image.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _dtb_image_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    out_name = ctx.attr.out or ctx.label.name
    out = ctx.actions.declare_file(out_name)
    inputs = depset(transitive = [target.files for target in ctx.attr.srcs])

    cmd = hermetic_tools.setup + """
        cat {files} > {output}
    """.format(
        files = " ".join([shell.quote(input.path) for input in inputs.to_list()]),
        output = shell.quote(out.path),
    )

    ctx.actions.run_shell(
        mnemonic = "DtbImage",
        inputs = inputs,
        outputs = [out],
        progress_message = "Building DTB image %{label}",
        command = cmd,
        tools = hermetic_tools.deps,
    )

    return [
        DefaultInfo(files = depset([out])),
    ]

dtb_image = rule(
    doc = "Build `dtb` image.",
    implementation = _dtb_image_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".dtb"],
            doc = "DTB sources to add to the dtb image",
        ),
        "out": attr.string(
            doc = """Name of `dtb` image.

                Default to `name` if not set
                """,
        ),
    },
    toolchains = [hermetic_toolchain.type],
)
