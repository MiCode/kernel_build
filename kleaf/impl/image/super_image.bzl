"""Builds super.img"""

load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")
load(":debug.bzl", "debug")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _super_image_impl(ctx):
    inputs = []
    inputs += ctx.files.system_dlkm_image
    inputs += ctx.files.vendor_dlkm_image

    hermetic_tools = hermetic_toolchain.get(ctx)

    tools = [
        ctx.file._build_utils_sh,
    ]
    transitive_tools = [hermetic_tools.deps]

    super_img = ctx.actions.declare_file("{}/{}".format(ctx.label.name, ctx.attr.out))
    super_img_size = ctx.attr.super_img_size

    outputs = [super_img]

    # Create a bash array of input images
    super_img_contents = "("
    for dep in [ctx.attr.system_dlkm_image, ctx.attr.vendor_dlkm_image]:
        # TODO (b/299326717): Clean up depset to_list() call
        for f in dep.files.to_list():
            if f.extension == "img":
                super_img_contents += f.path + " "
    super_img_contents += ")"

    command = hermetic_tools.setup
    command += """
              source "{build_utils_sh}"
              export DIST_DIR={intermediates_dir}
            # Build super
              mkdir -p "$DIST_DIR"
              (
                SUPER_IMAGE_CONTENTS={super_img_contents}
                SUPER_IMAGE_SIZE={super_img_size}
                build_super
              )
            # Move output files into place
              mv "${{DIST_DIR}}/super.img" {super_img}
    """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
        intermediates_dir = utils.intermediates_dir(ctx),
        super_img = super_img.path,
        super_img_size = super_img_size,
        super_img_contents = super_img_contents,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "SuperImage",
        inputs = depset(inputs),
        outputs = outputs,
        tools = depset(tools, transitive = transitive_tools),
        progress_message = "Building super image %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
        ),
    ]

def _unsparsed_image_impl(ctx):
    inputs = [ctx.file.src]

    unsparsed_img = ctx.actions.declare_file("{}/{}".format(ctx.label.name, ctx.attr.out))

    outputs = [unsparsed_img]

    hermetic_tools = hermetic_toolchain.get(ctx)

    command = hermetic_tools.setup
    command += 'simg2img "{img}" "{unsparsed_img}"'.format(
        img = ctx.file.src.path,
        unsparsed_img = unsparsed_img.path,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "UnsparsedSuperImage",
        inputs = depset(inputs),
        outputs = outputs,
        tools = hermetic_tools.deps,
        progress_message = "Building unsparsed image %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
        ),
    ]

super_image = rule(
    implementation = _super_image_impl,
    doc = """Build super image.

Optionally takes in a "system_dlkm" and "vendor_dlkm".

When included in a `copy_to_dist_dir` rule, this rule copies a `super.img` to `DIST_DIR`.
""",
    attrs = {
        "system_dlkm_image": attr.label(
            allow_files = True,
            doc = "`system_dlkm_image` to include in super.img",
        ),
        "vendor_dlkm_image": attr.label(
            allow_files = True,
            doc = "`vendor_dlkm_image` to include in super.img",
        ),
        "super_img_size": attr.int(
            default = 0x10000000,
            doc = "Size of super.img",
        ),
        "out": attr.string(
            default = "super.img",
            doc = "Image file name",
        ),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils"),
            cfg = "exec",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    toolchains = [
        hermetic_toolchain.type,
    ],
)

unsparsed_image = rule(
    implementation = _unsparsed_image_impl,
    doc = """Build an unsparsed image.

Takes in a .img file and unsparses it.

When included in a `copy_to_dist_dir` rule, this rule copies a `super_unsparsed.img` to `DIST_DIR`.
""",
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            doc = "image to unsparse",
        ),
        "out": attr.string(mandatory = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    toolchains = [
        hermetic_toolchain.type,
    ],
)
