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

_KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION = "r416183b"

def kernel_build(
        name,
        build_config,
        srcs,
        outs,
        deps = (),
        toolchain_version = _KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION):
    """Defines a kernel build target with all dependent targets.

        It uses a build_config to construct a deterministic build environment
        (e.g. 'common/build.config.gki.aarch64'). The kernel sources need to be
        declared via srcs (using a glob). outs declares the output files
        that are surviving the build. The effective output file names will be
        $(name)/$(output_file). Any other artifact is not guaranteed to be
        accessible after the rule has run. The default toolchain_version is
        defined with a sensible default, but can be overriden.

        Two additional labels, "{name}_env" and "{name}_config", are generated.
        For example, if name is "kernel_aarch64":
        - kernel_aarch64_env provides a source-able build environment defined
          by the build config.
        - kernel_aarch64_config provides the kernel config.

    Args:
        name: the final kernel target name, e.g. "kernel_aarch64"
        build_config: the path to the build config from the directory containing
           the WORKSPACE file, e.g. "common/build.config.gki.aarch64"
        srcs: the kernel sources (a glob())
        outs: the expected output files. For each item {out}:

          - If {out} does not contain a slash, the build rule
            automatically finds a file with name {out} in the kernel
            build output directory ${OUT_DIR}.
              find ${OUT_DIR} -name {out}
            There must be exactly one match.
            The file is copied to the following in the output directory
              {name}/{out}

            Example:
              kernel_build(name = "kernel_aarch64", outs = ["vmlinux"])
            The bulid system copies
              ${OUT_DIR}/[<optional subdirectory>/]vmlinux
            to
              kernel_aarch64/vmlinux.
            `kernel_aarch64/vmlinux` is the label to the file.

          - If {out} contains a slash, the build rule locates the file in the
            kernel build output directory ${OUT_DIR} with path {out}
            The file is copied to the following in the output directory
              1. {name}/{out}
              2. {name}/$(basename {out})

            Example:
              kernel_build(
                name = "kernel_aarch64",
                outs = ["arch/arm64/boot/vmlinux"])
            The bulid system copies
              ${OUT_DIR}/arch/arm64/boot/vmlinux
            to:
              1. kernel_aarch64/arch/arm64/boot/vmlinux
              2. kernel_aarch64/vmlinux
            They are also the labels to the output files, respectively.

            See search_and_mv_output.py for details.
        toolchain_version: the toolchain version to depend on
    """
    sources_target_name = name + "_sources"
    env_target_name = name + "_env"
    config_target_name = name + "_config"
    build_config_srcs = [
        s
        for s in srcs
        if "/build.config" in s or s.startswith("build.config")
    ]
    kernel_srcs = [s for s in srcs if s not in build_config_srcs]

    native.filegroup(name = sources_target_name, srcs = kernel_srcs)

    kernel_env(
        name = env_target_name,
        build_config = build_config,
        srcs = build_config_srcs,
    )

    kernel_config(
        name = config_target_name,
        env = env_target_name,
        srcs = [sources_target_name],
    )

    _kernel_build(
        name = name,
        config = config_target_name,
        srcs = [sources_target_name],
        outs = [name + "/" + out for out in outs],
        deps = deps,
    )

KernelEnvInfo = provider(fields = {
    "dependencies": "dependencies that need to provided to use this environment setup",
    "setup": "the setup script to initialize the environment",
})

def _kernel_env_impl(ctx):
    build_config = ctx.file.build_config
    setup_env = ctx.file.setup_env
    preserve_env = ctx.file.preserve_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)
    dependencies = ctx.files._tools + ctx.files._host_tools

    ctx.actions.run_shell(
        inputs = ctx.files.srcs + [
            setup_env,
            preserve_env,
        ],
        outputs = [out_file],
        progress_message = "Creating build environment for %s" % ctx.attr.name,
        command = """
            # do not fail upon unset variables being read
              set +u
            # Run Make in silence mode to suppress most of the info output
              export MAKEFLAGS="${{MAKEFLAGS}} -s"
            # Increase parallelism # TODO(b/192655643): do not use -j anymore
              export MAKEFLAGS="${{MAKEFLAGS}} -j$(nproc)"
            # create a build environment
              export BUILD_CONFIG={build_config}
              source {setup_env}
            # capture it as a file to be sourced in downstream rules
              {preserve_env} > {out}
            """.format(
            build_config = build_config.path,
            setup_env = setup_env.path,
            preserve_env = preserve_env.path,
            out = out_file.path,
        ),
    )

    host_tool_path = ctx.files._host_tools[0].dirname
    setup = """
         # do not fail upon unset variables being read
           set +u
         # source the build environment
           source {env}
         # setup the PATH to also include the host tools
           export PATH=$PATH:$PWD/{host_tool_path}
           """.format(env = out_file.path, host_tool_path = host_tool_path)

    return [
        KernelEnvInfo(
            dependencies = dependencies + [out_file],
            setup = setup,
        ),
        DefaultInfo(files = depset([out_file])),
    ]

def _get_tools(toolchain_version):
    return [
        Label(e)
        for e in (
            "//build:kernel-build-scripts",
            "//prebuilts/build-tools:linux-x86",
            "//prebuilts/kernel-build-tools:linux-x86",
            "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
        )
    ]

kernel_env = rule(
    implementation = _kernel_env_impl,
    doc = """
Generates a rule that generates a source-able build environment.

A build environment is defined by a single entry build config file that can
refer to further build config files.

Example:
    kernel_env(
        name = "kernel_aarch64_env,
        build_config = "build.config.gki.aarch64",
        srcs = glob(["build.config.*"]),
    )
""",
    attrs = {
        "build_config": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "label referring to the main build config",
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = """labels that this build config may refer to, including itself.
            E.g. ["build.config.gki.aarch64", "build.config.gki"]""",
        ),
        "setup_env": attr.label(
            allow_single_file = True,
            default = Label("//build:_setup_env.sh"),
            doc = "label referring to _setup_env.sh",
        ),
        "preserve_env": attr.label(
            allow_single_file = True,
            default = Label("//build/kleaf:preserve_env.sh"),
            doc = "label referring to the script capturing the environment",
        ),
        "toolchain_version": attr.string(
            default = _KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION,
            doc = "the toolchain to use for this environment",
        ),
        "_tools": attr.label_list(default = _get_tools),
        "_host_tools": attr.label(default = "//build:host-tools"),
    },
)

def _kernel_config_impl(ctx):
    srcs = [
        s
        for s in ctx.files.srcs
        if "scripts" in s.path or not s.path.endswith((".h", ".c"))
    ]

    config = ctx.outputs.config
    include_tar_gz = ctx.outputs.include_tar_gz

    ctx.actions.run_shell(
        inputs = srcs,
        outputs = [config, include_tar_gz],
        tools = ctx.attr.env[KernelEnvInfo].dependencies,
        progress_message = "Creating kernel config %s" % ctx.attr.name,
        command = ctx.attr.env[KernelEnvInfo].setup + """
            # Pre-defconfig commands
              eval ${{PRE_DEFCONFIG_CMDS}}
            # Actual defconfig
              make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{DEFCONFIG}}
            # Post-defconfig commands
              eval ${{POST_DEFCONFIG_CMDS}}
            # Grab outputs
              mv ${{OUT_DIR}}/.config {config}
              tar czf {include_tar_gz} -C ${{OUT_DIR}} include/
            """.format(
            config = config.path,
            include_tar_gz = include_tar_gz.path,
        ),
    )

    setup = ctx.attr.env[KernelEnvInfo].setup + """
         # Restore kernel config inputs
           mkdir -p ${{OUT_DIR}}/include/
           cp {config} ${{OUT_DIR}}/.config
           tar xf {include_tar_gz} -C ${{OUT_DIR}}
    """.format(config = config.path, include_tar_gz = include_tar_gz.path)

    return [
        KernelEnvInfo(
            dependencies = ctx.attr.env[KernelEnvInfo].dependencies +
                           [config, include_tar_gz],
            setup = setup,
        ),
        DefaultInfo(files = depset([config, include_tar_gz])),
    ]

kernel_config = rule(
    implementation = _kernel_config_impl,
    doc = "Defines a kernel config target.",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources"),
    },
    outputs = {
        "config": "%{name}/.config",
        "include_tar_gz": "%{name}/include.tar.gz",
    },
)

KernelBuildInfo = provider(fields = {
    "module_staging_archive": "Archive containing directory for staging kernel modules. Does not contain the lib/modules/* suffix.",
    "srcs": "sources for this kernel_build",
})

def _kernel_build_impl(ctx):
    outdir = ctx.actions.declare_directory(ctx.label.name)

    outs = []
    for out in ctx.outputs.outs:
        short_name = out.short_path[len(outdir.short_path) + 1:]
        outs.append(short_name)

    module_staging_archive = ctx.actions.declare_file(
        "{name}/module_staging_dir.tar.gz".format(name = ctx.label.name),
    )

    command = ctx.attr.config[KernelEnvInfo].setup + """
         # Actual kernel build
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{MAKE_GOALS}}
         # Set variables and create dirs for modules
           if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
             module_strip_flag="INSTALL_MOD_STRIP=1"
           fi
           mkdir -p {module_staging_dir}
         # Install modules
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{module_strip_flag}} INSTALL_MOD_PATH=$(realpath {module_staging_dir}) modules_install
         # Grab outputs
           {search_and_mv_output} --srcdir ${{OUT_DIR}} --dstdir {outdir} {outs}
         # Archive module_staging_dir
           tar czf {module_staging_archive} -C {module_staging_dir} .
           rm -rf {module_staging_dir}
         """.format(
        search_and_mv_output = ctx.file._search_and_mv_output.path,
        outdir = outdir.path,
        outs = " ".join(outs),
        module_staging_dir = module_staging_archive.dirname + "/staging",
        module_staging_archive = module_staging_archive.path,
    )

    ctx.actions.run_shell(
        inputs = ctx.files.srcs + ctx.files.deps + [ctx.file._search_and_mv_output],
        outputs = ctx.outputs.outs + [
            outdir,
            module_staging_archive,
        ],
        tools = ctx.attr.config[KernelEnvInfo].dependencies,
        progress_message = "Building kernel %s" % ctx.attr.name,
        command = command,
    )

    setup = ctx.attr.config[KernelEnvInfo].setup + """
         # Restore kernel build outputs
           cp -R {outdir}/* ${{OUT_DIR}}
           """.format(outdir = outdir.path)

    return [
        KernelEnvInfo(
            dependencies = ctx.attr.config[KernelEnvInfo].dependencies +
                           ctx.outputs.outs,
            setup = setup,
        ),
        KernelBuildInfo(
            module_staging_archive = module_staging_archive,
            srcs = ctx.files.srcs,
        ),
    ]

_kernel_build = rule(
    implementation = _kernel_build_impl,
    doc = "Defines a kernel build target.",
    attrs = {
        "config": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
            doc = "the kernel_config target",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources"),
        "outs": attr.output_list(),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kleaf:search_and_mv_output.py"),
            doc = "label referring to the script to process outputs",
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
    },
)

def _kernel_module_impl(ctx):
    name = ctx.label.name

    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.kernel_build[KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[KernelBuildInfo].srcs
    inputs += [
        ctx.attr.kernel_build[KernelBuildInfo].module_staging_archive,
        ctx.file.makefile,
        ctx.file._search_and_mv_output,
    ]

    module_staging_dir = ctx.actions.declare_directory("staging")
    outdir = module_staging_dir.dirname

    # additional_outputs: [module_staging_dir] + [basename(out) for out in outs]
    additional_outputs = [
        module_staging_dir,
    ]
    for out in ctx.outputs.outs:
        short_name = out.path[len(outdir) + 1:]
        if "/" in short_name:
            additional_outputs.append(ctx.actions.declare_file(out.basename))

    command = ctx.attr.kernel_build[KernelEnvInfo].setup
    command += """
             # Set variables and create dirs for modules
               if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
                 module_strip_flag="INSTALL_MOD_STRIP=1"
               fi
               mkdir -p {module_staging_dir}
               ext_mod=$(dirname {makefile})
               ext_mod_rel=$(python3 -c "import os.path; print(os.path.relpath('${{ROOT_DIR}}/${{ext_mod}}', '${{KERNEL_DIR}}'))")
             # Restore module_staging_dir from kernel_build
               tar xf {kernel_build_module_staging_archive} -C {module_staging_dir}

             # Prepare for kernel module build
               make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
             # Actual kernel module build
               make -C ${{ext_mod}} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}
             # Install into staging directory
               make -C ${{ext_mod}} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} INSTALL_MOD_PATH=$(realpath {module_staging_dir}) ${{module_strip_flag}} modules_install
             # Move files into place
               {search_and_mv_output} --srcdir {module_staging_dir}/lib/modules/*/extra --dstdir {outdir} {outs}
               """.format(
        makefile = ctx.file.makefile.path,
        search_and_mv_output = ctx.file._search_and_mv_output.path,
        kernel_build_module_staging_archive = ctx.attr.kernel_build[KernelBuildInfo].module_staging_archive.path,
        module_staging_dir = module_staging_dir.path,
        outdir = outdir,
        outs = " ".join([out.name for out in ctx.attr.outs]),
    )

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = ctx.outputs.outs + additional_outputs,
        command = command,
        progress_message = "Building external kernel module {}".format(ctx.label),
    )

    # Only declare outputs in the "outs" list. For additional outputs that this rule created,
    # the label is available, but this rule doesn't explicitly return it in the info.
    return [DefaultInfo(files = depset(ctx.outputs.outs))]

kernel_module = rule(
    implementation = _kernel_module_impl,
    doc = """Generates a rule that builds an external kernel module.

Example:
    kernel_module(
        name = "nfc",
        srcs = glob([
            "**/*.c",
            "**/*.h",

            # If there are Kbuild files, add them
            "**/Kbuild",
            # If there are additional makefiles in subdirectories, add them
            "**/Makefile",
        ]),
        outs = ["nfc.ko"],
        kernel_build = "//common:kernel_aarch64",
        makefile = ":Makefile",
    )
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = "source files to build this kernel module",
        ),
        # TODO figure out how to specify default :Makefile
        "makefile": attr.label(
            allow_single_file = True,
            doc = """Label referring to the makefile. This is where "make" is executed on ("make -C $(dirname ${makefile})").""",
        ),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo, KernelBuildInfo],
            doc = "Label referring to the kernel_build module",
        ),
        # Not output_list because it is not a list of labels. The list of
        # output labels are inferred from name and outs.
        "outs": attr.output_list(
            doc = """the expected output files. For each token {out}, the build rule
automatically finds a file named {out} in the legacy kernel modules
staging directory.
The file is copied to the output directory of this package,
with the label {out}.

- If {out} doesn't contain a slash, subdirectories are searched.

Example:
kernel_module(name = "nfc", outs = ["nfc.ko"])

The build system copies
  <legacy modules staging dir>/lib/modules/*/extra/<some subdir>/nfc.ko
to
  <package output dir>/nfc.ko
`nfc.ko` is the label to the file.

- If {out} contains slashes, its value is used. The file is also copied
  to the top of package output directory.

For example:
kernel_module(name = "nfc", outs = ["foo/nfc.ko"])

The build system copies
  <legacy modules staging dir>/lib/modules/*/extra/foo/nfc.ko
to
  foo/nfc.ko
`foo/nfc.ko` is the label to the file.
The file is also copied to
  <package output dir>/nfc.ko
`nfc.ko` is the label to the file.
See search_and_mv_output.py for details.
            """,
        ),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kleaf:search_and_mv_output.py"),
            doc = "label referring to the script to process outputs",
        ),
    },
)
