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

def _sum(iterable, start):
    ret = start
    for e in iterable:
        ret += e
    return ret

def _invert_dict(d):
    """Invert a dict. Values become keys and keys become values.

    In the source dict, if two keys have the same value, error.
    """
    ret = {value: key for key, value in d.items()}
    if len(d) != len(ret):
        fail("dict cannot be inverted: {}".format(d))
    return ret

def _invert_dict_file(d):
    """As _invert_dict, except values are transformed to value.files."""
    return {key: value.files for key, value in _invert_dict(d).items()}

def _kernel_build_tools_starlark(toolchain_version = _KERNEL_BUILD_DEFAULT_TOOLCHAIN_VERSION):
    return [
        "//build:kernel-build-scripts",
        "//build:host-tools",
        "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
        "//prebuilts/build-tools:linux-x86",
        "//prebuilts/kernel-build-tools:linux-x86",
    ]

def _kernel_build_tools(env, toolchain_version):
    """Deprecated. Use _kernel_build_tools_starlark instead."""
    return _kernel_build_tools_starlark(toolchain_version) + [env]

def _kernel_build_common_setup_starlark(env, build_host_tools, D = "$"):
    return """
         # do not fail upon unset variables being read
           set +u
         # source the build environment
           source {env}
         # setup the PATH to also include the host tools
           export PATH={D}PATH:{D}PWD/{D}(dirname {D}( echo {build_host_tools} | tr ' ' '\n' | head -n 1 ) )
           """.format(D = D, env = env, build_host_tools = build_host_tools)

def _kernel_build_common_setup(env):
    """Deprecated. Use _kernel_build_common_setup_starlark instead."""
    return _kernel_build_common_setup_starlark(
        env = "$(location {env})".format(env = env),
        build_host_tools = "$(locations //build:host-tools)",
        D = "$$",
    )

def _kernel_setup_config_starlark(config, include_tar_gz, D = "$"):
    return """
         # Restore inputs
           mkdir -p {D}{{OUT_DIR}}/include/
           cp {config} {D}{{OUT_DIR}}/.config
           tar xf {include_tar_gz} -C {D}{{OUT_DIR}}
           """.format(D = D, config = config, include_tar_gz = include_tar_gz)

def _kernel_setup_config(config_target_name):
    """Deprecated. Use _kernel_setup_config_starlark instead."""
    return _kernel_setup_config_starlark(
        config = "$(location {config_target_name}/.config)".format(config_target_name = config_target_name),
        include_tar_gz = "$(location {config_target_name}/include.tar.gz)".format(config_target_name = config_target_name),
        D = "$$",
    )

def _kernel_modules_common_setup_starlark(outdir, D = "$"):
    return """
         # Set variables
           if [ "{D}{{DO_NOT_STRIP_MODULES}}" != "1" ]; then
             module_strip_flag="INSTALL_MOD_STRIP=1"
           fi
           mkdir -p {outdir}
           module_staging_dir={D}(realpath {outdir})/intermediates/staging
           mkdir -p {D}{{module_staging_dir}}
           """.format(outdir = outdir, D = D)

def _kernel_modules_common_setup(name):
    """Deprecated. Use _kernel_modules_common_setup_starlark instead."""
    return _kernel_modules_common_setup_starlark(
        outdir = "$(@D)/{name}".format(name = name),
        D = "$$",
    )

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
    kwargs["tools"] = list(kwargs.get("tools", []))
    kwargs["tools"] += _kernel_build_tools(
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

    kwargs["tools"] = list(kwargs.get("tools", []))
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

# TODO: instead of relying on names, kernel_build module should export labels of these modules in the provider it returns
def _kernel_module_kernel_build_deps(kernel_build):
    return {
        kernel_build.relative(kernel_build.name + suffix): suffix
        for suffix in [
            "_config/.config",
            "_config/include.tar.gz",
            "_env",
            "_sources",
            "/vmlinux",
            "/module_staging_dir.tar.gz",
        ]
    }

def _kernel_module_impl(ctx):
    name = ctx.label.name
    kernel_build_deps = _invert_dict_file(ctx.attr._kernel_module_kernel_build_deps)
    tools = _invert_dict_file(ctx.attr._tools)

    inputs = []
    inputs += ctx.files.srcs
    inputs += _sum([e.to_list() for e in kernel_build_deps.values()], [])
    inputs += _sum([e.to_list() for e in tools.values()], [])
    inputs += ctx.files.kernel_build
    inputs += [
        ctx.file.makefile,
    ]

    outputs = []

    # outdir is not added to outputs because we don't need to return it.
    outdir = ctx.actions.declare_directory(ctx.label.name)

    for out in ctx.attr.outs:
        outputs.append(ctx.actions.declare_file("{name}/{out}".format(name = ctx.label.name, out = out)))
        if "/" in out:
            base = out[out.rfind("/") + 1:]
            outputs.append(ctx.actions.declare_file("{name}/{base}".format(name = name, base = base)))

    command = _kernel_build_common_setup_starlark(
        env = kernel_build_deps["_env"].to_list()[0].path,
        build_host_tools = " ".join([x.path for x in tools["//build:host-tools"].to_list()]),
    )
    command += _kernel_setup_config_starlark(
        config = kernel_build_deps["_config/.config"].to_list()[0].path,
        include_tar_gz = kernel_build_deps["_config/include.tar.gz"].to_list()[0].path,
    )
    command += _kernel_modules_common_setup_starlark(outdir = outdir.path)
    command += """
             # Restore inputs from kernel_build.
             # Use vmlinux as an anchor to find the directory, then copy all
             # contents of the directory to OUT_DIR
             # TODO: Ask kernel_build's provider to provide a list of files it creates.
               mkdir -p ${{OUT_DIR}}
               cp -R $(dirname {vmlinux})/* ${{OUT_DIR}}
             # Restore module_staging_dir
               tar xf {module_staging_dir} -C ${{module_staging_dir}}

             # Set variables
               ext_mod=$(dirname {makefile})
               ext_mod_rel=$(python3 -c "import os.path; print(os.path.relpath('${{ROOT_DIR}}/${{ext_mod}}', '${{KERNEL_DIR}}'))")

             # Prepare for kernel module build
               make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
             # Actual kernel module build
               make -C ${{ext_mod}} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}
             # Install into staging directory
               make -C ${{ext_mod}} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} INSTALL_MOD_PATH=${{module_staging_dir}} ${{module_strip_flag}} modules_install
             # Move files into place
               {search_and_mv_output} --srcdir ${{module_staging_dir}}/lib/modules/*/extra --dstdir {outdir} {outs}
             # Delete intermediates to avoid confusion
               rm -rf ${{module_staging_dir}}
               """.format(
        vmlinux = kernel_build_deps["/vmlinux"].to_list()[0].path,
        module_staging_dir = kernel_build_deps["/module_staging_dir.tar.gz"].to_list()[0].path,
        makefile = ctx.file.makefile.path,
        search_and_mv_output = tools["//build/kleaf:search_and_mv_output.py"].to_list()[0].path,
        outdir = outdir.path,
        outs = " ".join(ctx.attr.outs),
    )

    ctx.actions.run_shell(
        inputs = inputs,
        # Declare that this command also creates outdir.
        outputs = [outdir] + outputs,
        command = command,
    )

    return [DefaultInfo(files = depset(outputs))]

kernel_module = rule(
    implementation = _kernel_module_impl,
    doc = """Generates a rule that builds an external kernel module.

Example:
    kernel_module(
        name = "nfc",
        srcs = glob(["**"])
        outs = ["nfc.ko"],
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
            doc = "Label referring to the kernel_build module",
        ),
        "_kernel_module_kernel_build_deps": attr.label_keyed_string_dict(
            default = _kernel_module_kernel_build_deps,
            allow_files = True,
        ),
        # Not output_list because it is not a list of labels. The list of
        # output labels are inferred from name and outs.
        "outs": attr.string_list(
            doc = """the expected output files. For each token {out}, the build rule
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
            """,
        ),
        "_tools": attr.label_keyed_string_dict(
            allow_files = True,
            default = {Label(e): e for e in _kernel_build_tools_starlark() + [
                "//build/kleaf:search_and_mv_output.py",
            ]},
        ),
    },
)
