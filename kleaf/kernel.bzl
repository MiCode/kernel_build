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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

_KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION = "r428724"

def _debug_trap():
    return """set -x
              trap '>&2 /bin/date' DEBUG"""

def kernel_build(
        name,
        build_config,
        srcs,
        outs,
        deps = (),
        toolchain_version = _KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION):
    """Defines a kernel build target with all dependent targets.

    It uses a `build_config` to construct a deterministic build environment (e.g.
    `common/build.config.gki.aarch64`). The kernel sources need to be declared
    via srcs (using a `glob()`). outs declares the output files that are surviving
    the build. The effective output file names will be
    `$(name)/$(output_file)`. Any other artifact is not guaranteed to be
    accessible after the rule has run. The default `toolchain_version` is defined
    with a sensible default, but can be overriden.

    Two additional labels, `{name}_env` and `{name}_config`, are generated.
    For example, if name is `"kernel_aarch64"`:
    - `kernel_aarch64_env` provides a source-able build environment defined by
      the build config.
    - `kernel_aarch64_config` provides the kernel config.

    Args:
        name: The final kernel target name, e.g. `"kernel_aarch64"`.
        build_config: Label of the build.config file, e.g. `"build.config.gki.aarch64"`.
        srcs: The kernel sources (a `glob()`).
        deps: Additional dependencies to build this kernel.
        outs: The expected output files. For each item `out`:

          - If `out` does not contain a slash, the build rule
            automatically finds a file with name `out` in the kernel
            build output directory `${OUT_DIR}`.
            ```
            find ${OUT_DIR} -name {out}
            ```
            There must be exactly one match.
            The file is copied to the following in the output directory
            `{name}/{out}`

            Example:
            ```
            kernel_build(name = "kernel_aarch64", outs = ["vmlinux"])
            ```
            The bulid system copies `${OUT_DIR}/[<optional subdirectory>/]vmlinux`
            to `kernel_aarch64/vmlinux`.
            `kernel_aarch64/vmlinux` is the label to the file.

          - If `out` contains a slash, the build rule locates the file in the
            kernel build output directory `${OUT_DIR}` with path `out`
            The file is copied to the following in the output directory
              1. `{name}/{out}`
              2. `{name}/$(basename {out})`

            Example:
            ```
            kernel_build(
              name = "kernel_aarch64",
              outs = ["arch/arm64/boot/vmlinux"])
            ```
            The bulid system copies
              `${OUT_DIR}/arch/arm64/boot/vmlinux`
            to:
              - `kernel_aarch64/arch/arm64/boot/vmlinux`
              - `kernel_aarch64/vmlinux`
            They are also the labels to the output files, respectively.

            See `search_and_mv_output.py` for details.
        toolchain_version: The toolchain version to depend on.
    """
    sources_target_name = name + "_sources"
    env_target_name = name + "_env"
    config_target_name = name + "_config"
    modules_prepare_target_name = name + "_modules_prepare"
    build_config_srcs = [
        s
        for s in srcs
        if "/build.config" in s or s.startswith("build.config")
    ]
    kernel_srcs = [s for s in srcs if s not in build_config_srcs]

    native.filegroup(name = sources_target_name, srcs = kernel_srcs)

    _kernel_env(
        name = env_target_name,
        build_config = build_config,
        srcs = build_config_srcs,
        toolchain_version = toolchain_version,
    )

    _kernel_config(
        name = config_target_name,
        env = env_target_name,
        srcs = [sources_target_name],
        config = config_target_name + "/.config",
        include_tar_gz = config_target_name + "/include.tar.gz",
    )

    _modules_prepare(
        name = modules_prepare_target_name,
        config = config_target_name,
        srcs = [sources_target_name],
        outdir_tar_gz = modules_prepare_target_name + "/outdir.tar.gz",
    )

    _kernel_build(
        name = name,
        config = config_target_name,
        srcs = [sources_target_name],
        outs = [name + "/" + out for out in outs],
        deps = deps,
    )

_KernelEnvInfo = provider(fields = {
    "dependencies": "dependencies required to use this environment setup",
    "setup": "setup script to initialize the environment",
})

def _kernel_env_impl(ctx):
    build_config = ctx.file.build_config
    setup_env = ctx.file.setup_env
    preserve_env = ctx.file.preserve_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)
    dependencies = ctx.files._tools + ctx.files._host_tools

    command = ""
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += _debug_trap()

    command += """
        export SOURCE_DATE_EPOCH=0  # TODO(b/194772369)
        # error on failures
          set -e
          set -o pipefail
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
    )

    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))

    ctx.actions.run_shell(
        inputs = ctx.files.srcs + [
            setup_env,
            preserve_env,
        ],
        outputs = [out_file],
        progress_message = "Creating build environment for %s" % ctx.attr.name,
        command = command,
    )

    host_tool_path = ctx.files._host_tools[0].dirname

    setup = ""
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        setup += _debug_trap()

    setup += """
         # error on failures
           set -e
           set -o pipefail
         # source the build environment
           source {env}
         # setup the PATH to also include the host tools
           export PATH=$PATH:$PWD/{host_tool_path}
           """.format(env = out_file.path, host_tool_path = host_tool_path)

    return [
        _KernelEnvInfo(
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

_kernel_env = rule(
    implementation = _kernel_env_impl,
    doc = """Generates a rule that generates a source-able build environment.

          A build environment is defined by a single entry build config file
          that can refer to further build config files.

          Example:
          ```
              kernel_env(
                  name = "kernel_aarch64_env,
                  build_config = "build.config.gki.aarch64",
                  srcs = glob(["build.config.*"]),
              )
          ```
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
            doc = """labels that this build config refers to, including itself.
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
            doc = "the toolchain to use for this environment",
        ),
        "_tools": attr.label_list(default = _get_tools),
        "_host_tools": attr.label(default = "//build:host-tools"),
        "_debug_annotate_scripts": attr.label(
            default = "//build/kleaf:debug_annotate_scripts",
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kleaf:debug_print_scripts",
        ),
    },
)

def _kernel_config_impl(ctx):
    srcs = [
        s
        for s in ctx.files.srcs
        if any([token in s.path for token in [
            "Kbuild",
            "Kconfig",
            "Makefile",
            "configs/",
            "scripts/",
        ]])
    ]

    config = ctx.outputs.config
    include_tar_gz = ctx.outputs.include_tar_gz

    lto_config_flag = ctx.attr.lto[BuildSettingInfo].value

    lto_command = ""
    if lto_config_flag != "default":
        # none config
        lto_config = {
            "LTO_CLANG": "d",
            "LTO_NONE": "e",
            "LTO_CLANG_THIN": "d",
            "LTO_CLANG_FULL": "d",
            "THINLTO": "d",
        }
        if lto_config_flag == "thin":
            lto_config.update(
                LTO_CLANG = "e",
                LTO_NONE = "d",
                LTO_CLANG_THIN = "e",
                THINLTO = "e",
            )
        elif lto_config_flag == "full":
            lto_config.update(
                LTO_CLANG = "e",
                LTO_NONE = "d",
                LTO_CLANG_FULL = "e",
            )

        lto_command = """
            ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config {configs}
            make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
        """.format(configs = " ".join([
            "-%s %s" % (value, key)
            for key, value in lto_config.items()
        ]))

    command = ctx.attr.env[_KernelEnvInfo].setup + """
        # Pre-defconfig commands
          eval ${{PRE_DEFCONFIG_CMDS}}
        # Actual defconfig
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{DEFCONFIG}}
        # Post-defconfig commands
          eval ${{POST_DEFCONFIG_CMDS}}
        # LTO configuration
        {lto_command}
        # Grab outputs
          mv ${{OUT_DIR}}/.config {config}
          tar czf {include_tar_gz} -C ${{OUT_DIR}} include/
        """.format(
        config = config.path,
        include_tar_gz = include_tar_gz.path,
        lto_command = lto_command,
    )

    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))

    ctx.actions.run_shell(
        inputs = srcs,
        outputs = [config, include_tar_gz],
        tools = ctx.attr.env[_KernelEnvInfo].dependencies,
        progress_message = "Creating kernel config %s" % ctx.attr.name,
        command = command,
    )

    setup = ctx.attr.env[_KernelEnvInfo].setup + """
         # Restore kernel config inputs
           mkdir -p ${{OUT_DIR}}/include/
           cp {config} ${{OUT_DIR}}/.config
           tar xf {include_tar_gz} -C ${{OUT_DIR}}
    """.format(config = config.path, include_tar_gz = include_tar_gz.path)

    return [
        _KernelEnvInfo(
            dependencies = ctx.attr.env[_KernelEnvInfo].dependencies +
                           [config, include_tar_gz],
            setup = setup,
        ),
        DefaultInfo(files = depset([config, include_tar_gz])),
    ]

_kernel_config = rule(
    implementation = _kernel_config_impl,
    doc = "Defines a kernel config target.",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources"),
        "config": attr.output(mandatory = True, doc = "the .config file"),
        "include_tar_gz": attr.output(
            mandatory = True,
            doc = "the packaged include/ files",
        ),
        "lto": attr.label(default = "//build/kleaf:lto"),
        "_debug_print_scripts": attr.label(
            default = "//build/kleaf:debug_print_scripts",
        ),
    },
)

_KernelBuildInfo = provider(fields = {
    "module_staging_archive": "Archive containing staging kernel modules. " +
                              "Does not contain the lib/modules/* suffix.",
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

    command = ctx.attr.config[_KernelEnvInfo].setup + """
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

    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))

    ctx.actions.run_shell(
        inputs = ctx.files.srcs + ctx.files.deps +
                 [ctx.file._search_and_mv_output],
        outputs = ctx.outputs.outs + [
            outdir,
            module_staging_archive,
        ],
        tools = ctx.attr.config[_KernelEnvInfo].dependencies,
        progress_message = "Building kernel %s" % ctx.attr.name,
        command = command,
    )

    setup = ctx.attr.config[_KernelEnvInfo].setup + """
         # Restore kernel build outputs
           cp -R {outdir}/* ${{OUT_DIR}}
           """.format(outdir = outdir.path)

    return [
        _KernelEnvInfo(
            dependencies = ctx.attr.config[_KernelEnvInfo].dependencies +
                           ctx.outputs.outs,
            setup = setup,
        ),
        _KernelBuildInfo(
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
            providers = [_KernelEnvInfo],
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
        "_debug_print_scripts": attr.label(
            default = "//build/kleaf:debug_print_scripts",
        ),
    },
)

def _modules_prepare_impl(ctx):
    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))

    command = ctx.attr.config[_KernelEnvInfo].setup + """
         # Prepare for the module build
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
         # Package files
           tar czf {outdir_tar_gz} -C ${{OUT_DIR}} .
    """.format(outdir_tar_gz = ctx.outputs.outdir_tar_gz.path)

    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [ctx.outputs.outdir_tar_gz],
        tools = ctx.attr.config[_KernelEnvInfo].dependencies,
        progress_message = "Preparing for module build %s" % ctx.label,
        command = command,
    )

    setup = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "modules_prepare setup run without OUT_DIR set!" && exit 1
           tar xf {outdir_tar_gz} -C ${{OUT_DIR}}
           """.format(outdir_tar_gz = ctx.outputs.outdir_tar_gz.path)

    return [_KernelEnvInfo(
        dependencies = [ctx.outputs.outdir_tar_gz],
        setup = setup,
    )]

_modules_prepare = rule(
    implementation = _modules_prepare_impl,
    attrs = {
        "config": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            doc = "the kernel_config target",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources"),
        "outdir_tar_gz": attr.output(
            mandatory = True,
            doc = "the packaged ${OUT_DIR} files",
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kleaf:debug_print_scripts",
        ),
    },
)

_KernelModuleInfo = provider(fields = {
    "kernel_build": "kernel_build attribute of this module",
    "module_staging_archive": "Archive containing staging kernel modules. " +
                              "Does not contain the lib/modules/* suffix.",
})

def _kernel_module_impl(ctx):
    name = ctx.label.name

    for kernel_module_dep in ctx.attr.kernel_module_deps:
        if kernel_module_dep[_KernelModuleInfo].kernel_build != \
           ctx.attr.kernel_build:
            fail((
                "{name} refers to kernel_build {kernel_build}, but " +
                "depended kernel_module {dep} refers to kernel_build " +
                "{kernel_build}. They must refer to the same kernel_build."
            ).format(
                name = ctx.label,
                kernel_build = ctx.attr.kernel_build.label,
                dep = kernel_module_dep.label,
                dep_kernel_build = kernel_module_dep[_KernelModuleInfo].kernel_build.label,
            ))

    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += ctx.attr._modules_prepare[_KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[_KernelBuildInfo].srcs
    inputs += [
        ctx.attr.kernel_build[_KernelBuildInfo].module_staging_archive,
        ctx.file.makefile,
        ctx.file._search_and_mv_output,
    ]
    for kernel_module_dep in ctx.attr.kernel_module_deps:
        inputs += kernel_module_dep[_KernelEnvInfo].dependencies
        inputs.append(kernel_module_dep[_KernelModuleInfo].module_staging_archive)

    module_staging_archive = ctx.actions.declare_file("module_staging_archive.tar.gz")
    module_staging_dir = module_staging_archive.dirname + "/staging"
    outdir = module_staging_archive.dirname

    # additional_outputs: [module_staging_archive] + [basename(out) for out in outs]
    additional_outputs = [
        module_staging_archive,
    ]
    for out in ctx.outputs.outs:
        short_name = out.path[len(outdir) + 1:]
        if "/" in short_name:
            additional_outputs.append(ctx.actions.declare_file(out.basename))

    ext_mod_archive = ctx.actions.declare_file("ext_mod_archive.tar.gz")
    additional_declared_outputs = [
        ext_mod_archive,
    ]

    command = ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += ctx.attr._modules_prepare[_KernelEnvInfo].setup
    command += """
             # create dirs for modules
               mkdir -p {module_staging_dir}
    """.format(module_staging_dir = module_staging_dir)
    for kernel_module_dep in ctx.attr.kernel_module_deps:
        command += kernel_module_dep[_KernelEnvInfo].setup

        # TODO(b/194347374): ensure that output files for different modules don't conflict.
        command += """
            tar xf {module_staging_archive} -C {module_staging_dir}
        """.format(
            module_staging_archive = kernel_module_dep[_KernelModuleInfo].module_staging_archive.path,
            module_staging_dir = module_staging_dir,
        )
    command += """
             # Set variables
               if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
                 module_strip_flag="INSTALL_MOD_STRIP=1"
               fi
               ext_mod_rel=$(python3 -c "import os.path; print(os.path.relpath('${{ROOT_DIR}}/{ext_mod}', '${{KERNEL_DIR}}'))")
             # Restore module_staging_dir from kernel_build
               tar xf {kernel_build_module_staging_archive} -C {module_staging_dir}

             # Actual kernel module build
               make -C {ext_mod} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}

             # Archive ext_mod
               tar czf {ext_mod_archive} -C ${{OUT_DIR}}/${{ext_mod_rel}} .

             # Install into staging directory
               make -C {ext_mod} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} INSTALL_MOD_PATH=$(realpath {module_staging_dir}) ${{module_strip_flag}} modules_install
             # Archive module_staging_dir
               (
                 module_staging_archive=$(realpath {module_staging_archive})
                 cd {module_staging_dir}
                 tar czf ${{module_staging_archive}} lib/modules/*/extra/{{{comma_separated_outs}}}
               )
             # Move files into place
               {search_and_mv_output} --srcdir {module_staging_dir}/lib/modules/*/extra --dstdir {outdir} {outs}
             # Remove {module_staging_dir} because they are not declared
               rm -rf {module_staging_dir}
               """.format(
        ext_mod = ctx.file.makefile.dirname,
        ext_mod_archive = ext_mod_archive.path,
        search_and_mv_output = ctx.file._search_and_mv_output.path,
        kernel_build_module_staging_archive =
            ctx.attr.kernel_build[_KernelBuildInfo].module_staging_archive.path,
        module_staging_dir = module_staging_dir,
        module_staging_archive = module_staging_archive.path,
        outdir = outdir,
        outs = " ".join([out.name for out in ctx.attr.outs]),
        comma_separated_outs = "".join([out.name + "," for out in ctx.attr.outs]),
    )

    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = ctx.outputs.outs + additional_outputs +
                  additional_declared_outputs,
        command = command,
        progress_message = "Building external kernel module {}".format(ctx.label),
    )

    setup = """
             # Use a new shell to avoid polluting variables
               (
             # Set variables
               ext_mod_rel=$(python3 -c "import os.path; print(os.path.relpath('${{ROOT_DIR}}/{ext_mod}', '${{KERNEL_DIR}}'))")
             # Restore ext_mod_archive
               mkdir -p ${{OUT_DIR}}/${{ext_mod_rel}}
               tar xf {ext_mod_archive} -C ${{OUT_DIR}}/${{ext_mod_rel}}
             # New shell ends
               )
    """.format(
        ext_mod = ctx.file.makefile.dirname,
        ext_mod_archive = ext_mod_archive.path,
    )

    # Only declare outputs in the "outs" list. For additional outputs that this rule created,
    # the label is available, but this rule doesn't explicitly return it in the info.
    return [
        DefaultInfo(files = depset(ctx.outputs.outs + additional_declared_outputs)),
        _KernelEnvInfo(
            dependencies = additional_declared_outputs,
            setup = setup,
        ),
        _KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            module_staging_archive = module_staging_archive,
        ),
    ]

def _get_modules_prepare(kernel_build):
    return Label(str(kernel_build) + "_modules_prepare")

kernel_module = rule(
    implementation = _kernel_module_impl,
    doc = """Generates a rule that builds an external kernel module.

Example:
```
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
```
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = "Source files to build this kernel module.",
        ),
        # TODO figure out how to specify default :Makefile
        "makefile": attr.label(
            allow_single_file = True,
            doc = """Label referring to the makefile. This is where `make` is executed on (`make -C $(dirname ${makefile})`).""",
        ),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo, _KernelBuildInfo],
            doc = "Label referring to the kernel_build module.",
        ),
        "kernel_module_deps": attr.label_list(
            doc = "A list of other kernel_module dependencies.",
            providers = [_KernelEnvInfo, _KernelModuleInfo],
        ),
        # Not output_list because it is not a list of labels. The list of
        # output labels are inferred from name and outs.
        "outs": attr.output_list(
            doc = """The expected output files.

For each token `out`, the build rule automatically finds a
file named `out` in the legacy kernel modules staging
directory. The file is copied to the output directory of
this package, with the label `out`.

- If `out` doesn't contain a slash, subdirectories are searched.

    Example:
    ```
    kernel_module(name = "nfc", outs = ["nfc.ko"])
    ```

    The build system copies
    ```
    <legacy modules staging dir>/lib/modules/*/extra/<some subdir>/nfc.ko
    ```
    to
    ```
    <package output dir>/nfc.ko
    ```

    `nfc.ko` is the label to the file.

- If {out} contains slashes, its value is used. The file is
  also copied to the top of package output directory.

    For example:
    ```
    kernel_module(name = "nfc", outs = ["foo/nfc.ko"])
    ```

    The build system copies
    ```
    <legacy modules staging dir>/lib/modules/*/extra/foo/nfc.ko
    ```
    to
    ```
    foo/nfc.ko
    ```

    `foo/nfc.ko` is the label to the file.

    The file is also copied to `<package output dir>/nfc.ko`.

    `nfc.ko` is the label to the file.

    See `search_and_mv_output.py` for details.
""",
        ),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kleaf:search_and_mv_output.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_modules_prepare": attr.label(
            default = _get_modules_prepare,
            providers = [_KernelEnvInfo],
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kleaf:debug_print_scripts",
        ),
    },
)
