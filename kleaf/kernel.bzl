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

def _kernel_build_tools(env, toolchain_version):
    return [
        env,
        "//build:kernel-build-scripts",
        "//build:host-tools",
        "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
        "//prebuilts/build-tools:linux-x86",
        "//prebuilts/kernel-build-tools:linux-x86",
    ]

def _kernel_build_common_setup(env):
    return """
         # do not fail upon unset variables being read
           set +u
         # source the build environment
           source $(location {env})
         # setup the PATH to also include the host tools
           export PATH=$$PATH:$$PWD/$$(dirname $$( echo $(locations //build:host-tools) | tr ' ' '\n' | head -n 1 ) )
           """.format(env = env)

def _kernel_setup_config(config_target_name):
    return """
         # Restore inputs
           mkdir -p $${{OUT_DIR}}/include/
           cp $(location {config_target_name}/.config) $${{OUT_DIR}}/.config
           tar xf $(location {config_target_name}/include.tar.gz) -C $${{OUT_DIR}}
           """.format(config_target_name = config_target_name)

def _kernel_modules_common_setup(name):
    return """
         # Set variables
           if [ "$${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
             module_strip_flag="INSTALL_MOD_STRIP=1"
           fi
           module_staging_dir=$$(realpath $(@D))/{name}/intermediates/staging
           mkdir -p $${{module_staging_dir}}
           """.format(name = name)

def kernel_build(
        name,
        build_config,
        srcs,
        outs,
        toolchain_version = _KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION,
        **kwargs):
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

    _config(
        config_target_name,
        env_target_name,
        [sources_target_name],
        toolchain_version,
        **kwargs
    )
    _kernel_build(
        name,
        env_target_name,
        config_target_name,
        [sources_target_name],
        outs,
        toolchain_version,
        **kwargs
    )

def _kernel_env_impl(ctx):
    build_config = ctx.file.build_config
    setup_env = ctx.file.setup_env
    preserve_env = ctx.file.preserve_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)

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
    return [DefaultInfo(files = depset([out_file]))]

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

Args:
    name: the name of the resulting environment
    build_config: a label referring to the main build config
    srcs: A list of labels. The source files that this build
      config may refer to, including itself.
      E.g. ["build.config.gki.aarch64", "build.config.gki"]
""",
    attrs = {
        "build_config": attr.label(mandatory = True, allow_single_file = True),
        "srcs": attr.label_list(mandatory = True, allow_files = True),
        "setup_env": attr.label(
            allow_single_file = True,
            default = "//build:_setup_env.sh",
        ),
        "preserve_env": attr.label(
            allow_single_file = True,
            default = "//build/kleaf:preserve_env.sh",
        ),
    },
)

def _config(
        name,
        env_target_name,
        srcs,
        toolchain_version,
        **kwargs):
    """Defines a kernel config target.

    Args:
        name: the name of the kernel config
        env_target_name: A label that names the environment target of a
          kernel_build module, e.g. "kernel_aarch64_env"
        srcs: the kernel sources
        toolchain_version: the toolchain version to depend on
    """
    kwargs["tools"] = kwargs.get("tools", []) + _kernel_build_tools(
        env_target_name,
        toolchain_version,
    )

    native.genrule(
        name = name,
        srcs = [s for s in srcs if s.startswith("scripts") or
                                   not s.endswith((".c", ".h"))],
        # e.g. kernel_aarch64/.config
        outs = [
            name + "/.config",
            name + "/include.tar.gz",
        ],
        cmd = _kernel_build_common_setup(env_target_name) + """
            # Pre-defconfig commands
              eval $${{PRE_DEFCONFIG_CMDS}}
            # Actual defconfig
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{DEFCONFIG}}
            # Post-defconfig commands
              eval $${{POST_DEFCONFIG_CMDS}}
            # Grab outputs
              mv $${{OUT_DIR}}/.config $(location {name}/.config)
              tar czf $(location {name}/include.tar.gz) -C $${{OUT_DIR}} include/
            """.format(name = name),
        message = "Configuring kernel",
        **kwargs
    )

def _kernel_build(
        name,
        env_target_name,
        config_target_name,
        srcs,
        outs,
        toolchain_version,
        **kwargs):
    """Generates a kernel build rule."""

    kwargs["tools"] = kwargs.get("tools", [])
    kwargs["tools"] += _kernel_build_tools(env_target_name, toolchain_version)
    kwargs["tools"] += [
        "//build/kleaf:search_and_mv_output.py",
    ]

    genrule_outs = []
    for out in outs:
        genrule_outs.append("{name}/{out}".format(name = name, out = out))
        if "/" in out:
            base = out[out.rfind("/") + 1:]
            genrule_outs.append("{name}/{base}".format(name = name, base = base))
    genrule_outs.append(name + "/module_staging_dir.tar.gz")

    native.genrule(
        name = name,
        srcs = srcs + [
            config_target_name + "/.config",
            config_target_name + "/include.tar.gz",
        ],
        # e.g. kernel_aarch64/vmlinux
        outs = genrule_outs,
        cmd = _kernel_build_common_setup(env_target_name) +
              _kernel_setup_config(config_target_name) +
              _kernel_modules_common_setup(name) +
              """
            # Actual kernel build
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{MAKE_GOALS}}
            # Install modules
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} $${{module_strip_flag}} INSTALL_MOD_PATH=$${{module_staging_dir}} modules_install
            # Grab outputs
              $(execpath //build/kleaf:search_and_mv_output.py) --srcdir $${{OUT_DIR}} --dstdir $(@D)/{name} {outs}
            # Grab modules
              tar czf $(execpath {name}/module_staging_dir.tar.gz) -C $${{module_staging_dir}} .
              """.format(name = name, outs = " ".join(outs)),
        message = "Building kernel",
        **kwargs
    )

def kernel_module(
        name,
        kernel_build,
        srcs,
        outs,
        makefile = "Makefile",
        toolchain_version = _KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION,
        **kwargs):
    """Defines a kernel module target.

    Args:
        name: the kernel module name
        kernel_build: a label referring to a kernel_build target
        srcs: the sources for building the kernel module
        outs: the expected output files. For each token {out}, the build rule
          automatically finds a file named {out} in the legacy kernel modules
          staging directory. Subdirectories are searched.
          The file is copied to the output directory of {name},
          with the label {name}/{out}.

          {out} may contain slashes. In this case, the parent directory name
          must also match.

          For example:
            kernel_module(name = "nfc", outs = ["foo/nfc.ko"])

          The build system copies
            <legacy modules staging dir>/<some subdir>/foo/nfc.ko
          to
            nfc/foo/nfc.ko
          `nfc/foo/nfc.ko` is the label to the file.
          See search_and_mv_output.py for details.
        makefile: location of the Makefile. This is where "make" is
          executed on ("make -C $(dirname ${makefile})").
        toolchain_version: the toolchain version to depend on
    """
    env_target_name = kernel_build + "_env"
    config_target_name = kernel_build + "_config"
    sources_target_name = kernel_build + "_sources"

    kwargs["tools"] = list(kwargs.get("tools", []))
    kwargs["tools"] += _kernel_build_tools(env_target_name, toolchain_version)
    kwargs["tools"] += [
        "//build/kleaf:search_and_mv_output.py",
    ]

    additional_srcs = [
        kernel_build,
        kernel_build + "/vmlinux",
        sources_target_name,
        config_target_name + "/.config",
        config_target_name + "/include.tar.gz",
        kernel_build + "/module_staging_dir.tar.gz",
    ]
    if makefile not in srcs:
        additional_srcs.append(makefile)

    genrule_outs = []
    for out in outs:
        genrule_outs.append("{name}/{out}".format(name = name, out = out))
        if "/" in out:
            base = out[out.rfind("/") + 1:]
            genrule_outs.append("{name}/{base}".format(name = name, base = base))

    out_cmd = """
        $(execpath //build/kleaf:search_and_mv_output.py) --srcdir $${{module_staging_dir}}/lib/modules/*/extra --dstdir $(@D)/{name} {outs}
        """.format(name = name, outs = " ".join(outs))

    native.genrule(
        name = name,
        srcs = srcs + additional_srcs,
        outs = genrule_outs,
        cmd = _kernel_build_common_setup(env_target_name) +
              _kernel_setup_config(config_target_name) +
              _kernel_modules_common_setup(name) +
              """
            # Restore inputs from kernel_build.
            # Use vmlinux as an anchor to find the directory, then copy all
            # contents of the directory to OUT_DIR
              mkdir -p $${{OUT_DIR}}
              cp -R $$(dirname $(location {kernel_build}/vmlinux))/* $${{OUT_DIR}}
            # Restore module_staging_dir
              tar xf $(execpath {kernel_build}/module_staging_dir.tar.gz) -C $${{module_staging_dir}}

            # Set variables
              ext_mod=$$(dirname $(location {makefile}))
              ext_mod_rel=$$(python3 -c "import os.path; print(os.path.relpath('$${{ROOT_DIR}}/$${{ext_mod}}', '$${{KERNEL_DIR}}'))")

            # Prepare for kernel module build
              make -C $${{KERNEL_DIR}} $${{TOOL_ARGS}} O=$${{OUT_DIR}} KERNEL_SRC=$${{ROOT_DIR}}/$${{KERNEL_DIR}} modules_prepare
            # Actual kernel module build
              make -C $${{ext_mod}} $${{TOOL_ARGS}} M=$${{ext_mod_rel}} O=$${{OUT_DIR}} KERNEL_SRC=$${{ROOT_DIR}}/$${{KERNEL_DIR}}
            # Install into staging directory
              make -C $${{ext_mod}} $${{TOOL_ARGS}} M=$${{ext_mod_rel}} O=$${{OUT_DIR}} KERNEL_SRC=$${{ROOT_DIR}}/$${{KERNEL_DIR}} INSTALL_MOD_PATH=$${{module_staging_dir}} $${{module_strip_flag}} modules_install
            # Move files into place
              {out_cmd}
              """.format(name = name, makefile = makefile, kernel_build = kernel_build, out_cmd = out_cmd),
        message = "Building external kernel module",
        **kwargs
    )
