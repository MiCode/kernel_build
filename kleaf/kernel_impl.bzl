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
load("@kernel_toolchain_info//:dict.bzl", "CLANG_VERSION")

# Outputs of a kernel_build rule needed to build kernel_module's
_kernel_build_internal_outs = [
    "Module.symvers",
    "include/config/kernel.release",
]

def _debug_trap():
    return """set -x
              trap '>&2 /bin/date' DEBUG"""

def _debug_print_scripts(ctx, command):
    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s:%s""" % (ctx.label, command))

def _reverse_dict(d):
    """Reverse a dictionary of {key: [value, ...]}

    Return {value: [key, ...]}.
    """
    ret = {}
    for k, values in d.items():
        for v in values:
            if v not in ret:
                ret[v] = []
            ret[v].append(k)
    return ret

def _getoptattr(thing, attr, default_value = None):
    if hasattr(thing, attr):
        return getattr(thing, attr)
    return default_value

def _kernel_build_config_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.attr.name + ".generated")
    command = "cat {srcs} > {out_file}".format(
        srcs = " ".join([src.path for src in ctx.files.srcs]),
        out_file = out_file.path,
    )
    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [out_file],
        command = command,
        progress_message = "Generating build config {}".format(ctx.label),
    )
    return DefaultInfo(files = depset([out_file]))

kernel_build_config = rule(
    implementation = _kernel_build_config_impl,
    doc = "Create a build.config file by concatenating build config fragments.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = """List of build config fragments.

Order matters. To prevent buildifier from sorting the list, use the
`# do not sort` magic line. For example:

```
kernel_build_config(
    name = "build.config.foo.mixed",
    srcs = [
        # do not sort
        "build.config.mixed",
        "build.config.foo",
    ],
)
```

""",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _transform_kernel_build_outs(name, what, outs):
    """Transform `*outs` attributes for `kernel_build`.

    - If `outs` is a list, return it directly.
    - If `outs` is a dict, return `select(outs)`.
    - Otherwise fail
    """
    if outs == None:
        return None
    if type(outs) == type([]):
        return outs
    elif type(outs) == type({}):
        return select(outs)
    else:
        fail("{}: Invalid type for {}: {}".format(name, what, type(outs)))

KernelFilesInfo = provider(doc = """Contains information of files that a kernel build produces.

In particular, this is required by the `base_kernel` attribute of a `kernel_build` rule.
""", fields = {
    "files": "A list of files that this kernel build provides.",
})

def kernel_build(
        name,
        build_config,
        outs,
        srcs = None,
        module_outs = None,
        implicit_outs = None,
        generate_vmlinux_btf = None,
        deps = None,
        base_kernel = None,
        kconfig_ext = None,
        dtstree = None,
        toolchain_version = None,
        **kwargs):
    """Defines a kernel build target with all dependent targets.

    It uses a `build_config` to construct a deterministic build environment (e.g.
    `common/build.config.gki.aarch64`). The kernel sources need to be declared
    via srcs (using a `glob()`). outs declares the output files that are surviving
    the build. The effective output file names will be
    `$(name)/$(output_file)`. Any other artifact is not guaranteed to be
    accessible after the rule has run. The default `toolchain_version` is defined
    with the value in `common/build.config.constants`, but can be overriden.

    A few additional labels are generated.
    For example, if name is `"kernel_aarch64"`:
    - `kernel_aarch64_uapi_headers` provides the UAPI kernel headers.
    - `kernel_aarch64_headers` provides the kernel headers.

    Args:
        name: The final kernel target name, e.g. `"kernel_aarch64"`.
        build_config: Label of the build.config file, e.g. `"build.config.gki.aarch64"`.
        kconfig_ext: Label of an external Kconfig.ext file sourced by the GKI kernel.
        srcs: The kernel sources (a `glob()`). If unspecified or `None`, it is the following:
          ```
          glob(
              ["**"],
              exclude = [
                  "**/.*",          # Hidden files
                  "**/.*/**",       # Files in hidden directories
                  "**/BUILD.bazel", # build files
                  "**/*.bzl",       # build files
              ],
          )
          ```
        base_kernel: A label referring the base kernel build.

          If set, the list of files specified in the `KernelFilesInfo` of the rule specified in
          `base_kernel` is copied to a directory, and `KBUILD_MIXED_TREE` is set to the directory.
          Setting `KBUILD_MIXED_TREE` effectively enables mixed build.

          To set additional flags for mixed build, change `build_config` to a `kernel_build_config`
          rule, with a build config fragment that contains the additional flags.

          The label specified by `base_kernel` must conform to
          [`KernelFilesInfo`](#kernelfilesinfo). Usually, this points to one of the following:
          - `//common:kernel_{arch}`
          - A `kernel_filegroup` rule, e.g.
            ```
            load("//build/kernel/kleaf:common_kernels.bzl, "aarch64_outs")
            kernel_filegroup(
              name = "my_kernel_filegroup",
              srcs = aarch64_outs,
            )
            ```

        generate_vmlinux_btf: If `True`, generates `vmlinux.btf` that is stripped off any debug
          symbols, but contains type and symbol information within a .BTF section.
          This is suitable for ABI analysis through BTF.

          Requires that `"vmlinux"` is in `outs`.
        deps: Additional dependencies to build this kernel.
        module_outs: A list of in-tree drivers. Similar to `outs`, but for `*.ko` files.

          If a `*.ko` kernel module should not be copied to `${DIST_DIR}`, it must be
          included `implicit_outs` instead of `module_outs`. The list `implicit_outs + module_outs`
          must include **all** `*.ko` files in `${OUT_DIR}`. If not, a build error is raised.

          Like `outs`, `module_outs` are part of the
          [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html)
          that this `kernel_build` returns. For example:
          ```
          kernel_build(name = "kernel", module_outs = ["foo.ko"], ...)
          copy_to_dist_dir(name = "kernel_dist", data = [":kernel"])
          ```
          `foo.ko` will be included in the distribution.

          Like `outs`, this may be a `dict`. If so, it is wrapped in
          [`select()`](https://docs.bazel.build/versions/main/configurable-attributes.html). See
          documentation for `outs` for more details.
        outs: The expected output files.

          Note: in-tree modules should be specified in `module_outs` instead.

          This attribute must be either a `dict` or a `list`. If it is a `list`, for each item
          in `out`:

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

          Files in `outs` are part of the
          [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html)
          that this `kernel_build` returns. For example:
          ```
          kernel_build(name = "kernel", outs = ["vmlinux"], ...)
          copy_to_dist_dir(name = "kernel_dist", data = [":kernel"])
          ```
          `vmlinux` will be included in the distribution.

          If it is a `dict`, it is wrapped in
          [`select()`](https://docs.bazel.build/versions/main/configurable-attributes.html).

          Example:
          ```
          kernel_build(
            name = "kernel_aarch64",
            outs = {"config_foo": ["vmlinux"]})
          ```
          If conditions in `config_foo` is met, the rule is equivalent to
          ```
          kernel_build(
            name = "kernel_aarch64",
            outs = ["vmlinux"])
          ```
          As explained above, the bulid system copies `${OUT_DIR}/[<optional subdirectory>/]vmlinux`
          to `kernel_aarch64/vmlinux`.
          `kernel_aarch64/vmlinux` is the label to the file.

          Note that a `select()` may not be passed into `kernel_build()` because
          [`select()` cannot be evaluated in macros](https://docs.bazel.build/versions/main/configurable-attributes.html#why-doesnt-select-work-in-macros).
          Hence:
          - [combining `select()`s](https://docs.bazel.build/versions/main/configurable-attributes.html#combining-selects)
            is not allowed. Instead, expand the cartesian product.
          - To use
            [`AND` chaining](https://docs.bazel.build/versions/main/configurable-attributes.html#or-chaining)
            or
            [`OR` chaining](https://docs.bazel.build/versions/main/configurable-attributes.html#selectsconfig_setting_group),
            use `selects.config_setting_group()`.

        implicit_outs: Like `outs`, but not copied to the distribution directory.

          Labels are created for each item in `implicit_outs` as in `outs`.
        toolchain_version: The toolchain version to depend on.
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).

          These arguments applies on the target with `{name}`, `{name}_headers`, `{name}_uapi_headers`, and `{name}_vmlinux_btf`.
    """
    env_target_name = name + "_env"
    config_target_name = name + "_config"
    modules_prepare_target_name = name + "_modules_prepare"
    uapi_headers_target_name = name + "_uapi_headers"
    headers_target_name = name + "_headers"

    if srcs == None:
        srcs = native.glob(
            ["**"],
            exclude = [
                "**/.*",
                "**/.*/**",
                "**/BUILD.bazel",
                "**/*.bzl",
            ],
        )

    _kernel_env(
        name = env_target_name,
        build_config = build_config,
        kconfig_ext = kconfig_ext,
        dtstree = dtstree,
        srcs = srcs,
        toolchain_version = toolchain_version,
    )

    _kernel_config(
        name = config_target_name,
        env = env_target_name,
        srcs = srcs,
        config = config_target_name + "/.config",
        include_tar_gz = config_target_name + "/include.tar.gz",
    )

    _modules_prepare(
        name = modules_prepare_target_name,
        config = config_target_name,
        srcs = srcs,
        outdir_tar_gz = modules_prepare_target_name + "/outdir.tar.gz",
    )

    _kernel_build(
        name = name,
        config = config_target_name,
        srcs = srcs,
        outs = _transform_kernel_build_outs(name, "outs", outs),
        module_outs = _transform_kernel_build_outs(name, "module_outs", module_outs),
        implicit_outs = _transform_kernel_build_outs(name, "implicit_outs", implicit_outs),
        internal_outs = _transform_kernel_build_outs(name, "internal_outs", _kernel_build_internal_outs),
        deps = deps,
        base_kernel = base_kernel,
        modules_prepare = modules_prepare_target_name,
        **kwargs
    )

    for out_name, out_attr_val in (
        ("outs", outs),
        ("module_outs", module_outs),
        ("implicit_outs", implicit_outs),
        # internal_outs are opaque to the user, hence we don't create a alias (filegroup) for them.
    ):
        if out_attr_val == None:
            continue
        if type(out_attr_val) == type([]):
            for out in out_attr_val:
                native.filegroup(name = name + "/" + out, srcs = [":" + name], output_group = out)
        elif type(out_attr_val) == type({}):
            # out_attr_val = {config_setting: [out, ...], ...}
            # => reverse_dict = {out: [config_setting, ...], ...}
            for out, config_settings in _reverse_dict(out_attr_val).items():
                native.filegroup(
                    name = name + "/" + out,
                    # Use a select() to prevent this rule to build when config_setting is not fulfilled.
                    srcs = select({
                        config_setting: [":" + name]
                        for config_setting in config_settings
                    }),
                    output_group = out,
                    # Use "manual" tags to prevent it to be built with ...
                    tags = ["manual"],
                )
        else:
            fail("Unexpected type {} for {}: {}".format(type(out_attr_val), out_name, out_attr_val))

    _kernel_uapi_headers(
        name = uapi_headers_target_name,
        config = config_target_name,
        srcs = srcs,
        **kwargs
    )

    _kernel_headers(
        name = headers_target_name,
        kernel_build = name,
        env = env_target_name,
        # TODO: We need arch/ and include/ only.
        srcs = srcs,
        **kwargs
    )

    if generate_vmlinux_btf:
        vmlinux_btf_name = name + "_vmlinux_btf"
        _vmlinux_btf(
            name = vmlinux_btf_name,
            vmlinux = name + "/vmlinux",
            env = env_target_name,
            **kwargs
        )

_DtsTreeInfo = provider(fields = {
    "srcs": "DTS tree sources",
    "makefile": "DTS tree makefile",
})

def _kernel_dtstree_impl(ctx):
    return _DtsTreeInfo(
        srcs = ctx.files.srcs,
        makefile = ctx.file.makefile,
    )

_kernel_dtstree = rule(
    implementation = _kernel_dtstree_impl,
    attrs = {
        "srcs": attr.label_list(doc = "kernel device tree sources", allow_files = True),
        "makefile": attr.label(mandatory = True, allow_single_file = True),
    },
)

def kernel_dtstree(
        name,
        srcs = None,
        makefile = None,
        **kwargs):
    """Specify a kernel DTS tree.

    Args:
      srcs: sources of the DTS tree. Default is

        ```
        glob(["**"], exclude = [
            "**/.*",
            "**/.*/**",
            "**/BUILD.bazel",
            "**/*.bzl",
        ])
        ```
      makefile: Makefile of the DTS tree. Default is `:Makefile`, i.e. the `Makefile`
        at the root of the package.
      kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    if srcs == None:
        srcs = native.glob(
            ["**"],
            exclude = [
                "**/.*",
                "**/.*/**",
                "**/BUILD.bazel",
                "**/*.bzl",
            ],
        )
    if makefile == None:
        makefile = ":Makefile"

    kwargs.update(
        # This should be the exact list of arguments of kernel_dtstree.
        name = name,
        srcs = srcs,
        makefile = makefile,
    )
    _kernel_dtstree(**kwargs)

_KernelEnvInfo = provider(fields = {
    "dependencies": "dependencies required to use this environment setup",
    "setup": "setup script to initialize the environment",
})

def _kernel_env_impl(ctx):
    srcs = [
        s
        for s in ctx.files.srcs
        if "/build.config" in s.path or s.path.startswith("build.config")
    ]

    build_config = ctx.file.build_config
    kconfig_ext = ctx.file.kconfig_ext
    dtstree_makefile = None
    dtstree_srcs = []
    if ctx.attr.dtstree != None:
        dtstree_makefile = ctx.attr.dtstree[_DtsTreeInfo].makefile
        dtstree_srcs = ctx.attr.dtstree[_DtsTreeInfo].srcs

    setup_env = ctx.file.setup_env
    preserve_env = ctx.file.preserve_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)
    dependencies = ctx.files._tools + ctx.files._host_tools

    command = ""
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += _debug_trap()

    if kconfig_ext:
        command += """
              export KCONFIG_EXT={kconfig_ext}
            """.format(
            kconfig_ext = kconfig_ext.short_path,
        )
    if dtstree_makefile:
        command += """
              export DTSTREE_MAKEFILE={dtstree}
            """.format(
            dtstree = dtstree_makefile.short_path,
        )

    command += """
        # error on failures
          set -e
          set -o pipefail
    """

    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += """
          export MAKEFLAGS="${MAKEFLAGS} V=1"
        """
    else:
        command += """
        # Run Make in silence mode to suppress most of the info output
          export MAKEFLAGS="${MAKEFLAGS} -s"
        """

    command += """
        # Increase parallelism # TODO(b/192655643): do not use -j anymore
          export MAKEFLAGS="${{MAKEFLAGS}} -j$(nproc)"
        # create a build environment
          source {build_utils_sh}
          export BUILD_CONFIG={build_config}
          source {setup_env}
        # capture it as a file to be sourced in downstream rules
          {preserve_env} > {out}
        """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
        build_config = build_config.path,
        setup_env = setup_env.path,
        preserve_env = preserve_env.path,
        out = out_file.path,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = srcs + [
            ctx.file._build_utils_sh,
            build_config,
            setup_env,
            preserve_env,
        ],
        outputs = [out_file],
        progress_message = "Creating build environment for %s" % ctx.attr.name,
        command = command,
        use_default_shell_env = True,
    )

    host_tool_path = ctx.files._host_tools[0].dirname

    setup = ""
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        setup += _debug_trap()

    setup += """
         # error on failures
           set -e
           set -o pipefail
         # utility functions
           source {build_utils_sh}
         # source the build environment
           source {env}
         # setup the PATH to also include the host tools
           export PATH=$PATH:$PWD/{host_tool_path}
         # setup LD_LIBRARY_PATH for prebuilts
           export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PWD/{linux_x86_libs_path}
           if [ -n "${{KCONFIG_EXT}}" ]; then
             export KCONFIG_EXT_PREFIX=$(rel_path $(realpath $(dirname ${{KCONFIG_EXT}})) ${{ROOT_DIR}}/${{KERNEL_DIR}})/
           fi
           if [ -n "${{DTSTREE_MAKEFILE}}" ]; then
             export dtstree=$(rel_path $(realpath $(dirname ${{DTSTREE_MAKEFILE}})) ${{ROOT_DIR}}/${{KERNEL_DIR}})
           fi
           """.format(
        env = out_file.path,
        host_tool_path = host_tool_path,
        build_utils_sh = ctx.file._build_utils_sh.path,
        linux_x86_libs_path = ctx.files._linux_x86_libs[0].dirname,
    )

    dependencies += [
        out_file,
        ctx.file._build_utils_sh,
    ]
    if kconfig_ext:
        dependencies.append(kconfig_ext)
    dependencies += dtstree_srcs
    return [
        _KernelEnvInfo(
            dependencies = dependencies,
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

_KernelToolchainInfo = provider(fields = {
    "toolchain_version": "The toolchain version",
})

def _kernel_toolchain_aspect_impl(target, ctx):
    if ctx.rule.kind == "_kernel_build":
        return ctx.rule.attr.config[_KernelToolchainInfo]
    if ctx.rule.kind == "_kernel_config":
        return ctx.rule.attr.env[_KernelToolchainInfo]
    if ctx.rule.kind == "_kernel_env":
        return _KernelToolchainInfo(toolchain_version = ctx.rule.attr.toolchain_version)
    if ctx.rule.kind == "kernel_filegroup":
        # TODO(b/213939521): Support _KernelToolchainInfo on prebuilts
        return _KernelToolchainInfo()
    fail("{label}: Unable to get toolchain info because {kind} is not supported.".format(
        kind = ctx.rule.kind,
        label = ctx.label,
    ))

_kernel_toolchain_aspect = aspect(
    implementation = _kernel_toolchain_aspect_impl,
    doc = "An aspect describing the toolchain of a `_kernel_build`, `_kernel_config`, or `_kernel_env` rule.",
    attr_aspects = [
        "config",
        "env",
    ],
)

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
            default = Label("//build/kernel/kleaf:preserve_env.sh"),
            doc = "label referring to the script capturing the environment",
        ),
        "toolchain_version": attr.string(
            doc = "the toolchain to use for this environment",
            default = CLANG_VERSION,
        ),
        "kconfig_ext": attr.label(
            allow_single_file = True,
            doc = "an external Kconfig.ext file sourced by the base kernel",
        ),
        "dtstree": attr.label(
            providers = [_DtsTreeInfo],
            doc = "Device tree",
        ),
        "_tools": attr.label_list(default = _get_tools),
        "_host_tools": attr.label(default = "//build:host-tools"),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build:build_utils.sh"),
        ),
        "_debug_annotate_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_annotate_scripts",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_linux_x86_libs": attr.label(default = "//prebuilts/kernel-build-tools:linux-x86-libs"),
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
            ".fragment",
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
          cp -p ${{OUT_DIR}}/.config {config}
          tar czf {include_tar_gz} -C ${{OUT_DIR}} include/
        """.format(
        config = config.path,
        include_tar_gz = include_tar_gz.path,
        lto_command = lto_command,
    )

    _debug_print_scripts(ctx, command)
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
           rsync -p -L {config} ${{OUT_DIR}}/.config
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
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "config": attr.output(mandatory = True, doc = "the .config file"),
        "include_tar_gz": attr.output(
            mandatory = True,
            doc = "the packaged include/ files",
        ),
        "lto": attr.label(default = "//build/kernel/kleaf:lto"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

_KernelBuildInfo = provider(fields = {
    "modules_staging_archive": "Archive containing staging kernel modules. " +
                               "Does not contain the lib/modules/* suffix.",
    "module_srcs": "sources for this kernel_build for building external modules",
    "out_dir_kernel_headers_tar": "Archive containing headers in `OUT_DIR`",
    "outs": "A list of File object corresponding to the `outs` attribute (excluding `module_outs`, `implicit_outs` and `internal_outs`)",
    "base_kernel_files": "[Default outputs](https://docs.bazel.build/versions/main/skylark/rules.html#default-outputs) of the rule specified by `base_kernel`",
    "interceptor_output": "`interceptor` log. See [`interceptor`](https://android.googlesource.com/kernel/tools/interceptor/) project.",
})

_SrcsInfo = provider(fields = {
    "srcs": "The srcs attribute of a rule.",
})

def _srcs_aspect_impl(target, ctx):
    return [_SrcsInfo(srcs = _getoptattr(ctx.rule.attr, "srcs"))]

_srcs_aspect = aspect(
    implementation = _srcs_aspect_impl,
    doc = "An aspect that retrieves srcs attribute from a rule.",
    attr_aspects = ["srcs"],
)

_KernelBuildAspectInfo = provider(fields = {
    "modules_prepare": "The *_modules_prepare target",
})

def _kernel_build_aspect_impl(target, ctx):
    return [_KernelBuildAspectInfo(
        modules_prepare = _getoptattr(ctx.rule.attr, "modules_prepare"),
    )]

_kernel_build_aspect = aspect(
    implementation = _kernel_build_aspect_impl,
    doc = "An aspect describing attributes of a _kernel_build rule.",
    attr_aspects = [
        "modules_prepare",
    ],
)

def _kernel_build_check_toolchain(ctx):
    """
    Check toolchain_version is the same as base_kernel.
    """

    this_toolchain = ctx.attr.config[_KernelToolchainInfo].toolchain_version
    base_toolchain = _getoptattr(ctx.attr.base_kernel[_KernelToolchainInfo], "toolchain_version")

    # TODO(b/213939521): Support _KernelToolchainInfo on kernel_filegroup and drop the None check
    if base_toolchain == None:
        return

    if this_toolchain != base_toolchain:
        fail("""{this_label}:

ERROR: `toolchain_version` is "{this_toolchain}" for "{this_label}", but
       `toolchain_version` is "{base_toolchain}" for "{base_kernel}" (`base_kernel`).
       They must use the same `toolchain_version`.

       Fix by setting `toolchain_version` of "{this_label}"
       to be the one used by "{base_kernel}".
       If "{base_kernel}" does not set `toolchain_version` explicitly, do not set
       `toolchain_version` for "{this_label}" either.
""".format(
            this_label = ctx.label,
            this_toolchain = this_toolchain,
            base_kernel = ctx.attr.base_kernel.label,
            base_toolchain = base_toolchain,
        ))

def _kernel_build_impl(ctx):
    kbuild_mixed_tree = None
    base_kernel_files = []
    if ctx.attr.base_kernel:
        _kernel_build_check_toolchain(ctx)

        # Create a directory for KBUILD_MIXED_TREE. Flatten the directory structure of the files
        # that ctx.attr.base_kernel provides. declare_directory is sufficient because the directory should
        # only change when the dependent ctx.attr.base_kernel changes.
        kbuild_mixed_tree = ctx.actions.declare_directory("{}_kbuild_mixed_tree".format(ctx.label.name))
        base_kernel_files = ctx.attr.base_kernel[KernelFilesInfo].files
        kbuild_mixed_tree_command = """
          # Restore GKI artifacts for mixed build
            export KBUILD_MIXED_TREE=$(realpath {kbuild_mixed_tree})
            rm -rf ${{KBUILD_MIXED_TREE}}
            mkdir -p ${{KBUILD_MIXED_TREE}}
            for base_kernel_file in {base_kernel_files}; do
              ln -s $(readlink -m ${{base_kernel_file}}) ${{KBUILD_MIXED_TREE}}
            done
        """.format(
            base_kernel_files = " ".join([file.path for file in base_kernel_files]),
            kbuild_mixed_tree = kbuild_mixed_tree.path,
        )
        ctx.actions.run_shell(
            inputs = base_kernel_files,
            outputs = [kbuild_mixed_tree],
            progress_message = "Creating KBUILD_MIXED_TREE",
            command = kbuild_mixed_tree_command,
        )

    ruledir = ctx.actions.declare_directory(ctx.label.name)

    inputs = [
        ctx.file._search_and_mv_output,
    ]
    inputs += ctx.files.srcs
    inputs += ctx.files.deps
    if kbuild_mixed_tree:
        inputs.append(kbuild_mixed_tree)

    # kernel_build(name="kenrel", outs=["out"])
    # => _kernel_build(name="kernel", outs=["kernel/out"], internal_outs=["kernel/Module.symvers", ...])
    # => all_output_names = ["foo", "Module.symvers", ...]
    #    all_output_files = {"out": {"foo": File(...)}, "internal_outs": {"Module.symvers": File(...)}, ...}
    all_output_files = {}
    for attr in ("outs", "module_outs", "implicit_outs", "internal_outs"):
        all_output_files[attr] = {name: ctx.actions.declare_file("{}/{}".format(ctx.label.name, name)) for name in getattr(ctx.attr, attr)}
    all_output_names = []
    for d in all_output_files.values():
        all_output_names += d.keys()

    modules_staging_archive = ctx.actions.declare_file(
        "{name}/modules_staging_dir.tar.gz".format(name = ctx.label.name),
    )
    out_dir_kernel_headers_tar = ctx.actions.declare_file(
        "{name}/out-dir-kernel-headers.tar.gz".format(name = ctx.label.name),
    )
    interceptor_output = ctx.actions.declare_file("{name}/interceptor_output.bin".format(name = ctx.label.name))
    modules_staging_dir = modules_staging_archive.dirname + "/staging"

    # all outputs that |command| generates
    command_outputs = [
        ruledir,
        modules_staging_archive,
        out_dir_kernel_headers_tar,
        interceptor_output,
    ]
    for d in all_output_files.values():
        command_outputs += d.values()

    command = ""
    command += ctx.attr.config[_KernelEnvInfo].setup

    if kbuild_mixed_tree:
        command += """
                   export KBUILD_MIXED_TREE=$(realpath {kbuild_mixed_tree})
        """.format(
            kbuild_mixed_tree = kbuild_mixed_tree.path,
        )

    command += """
         # Actual kernel build
           interceptor -r -l {interceptor_output} -- make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{MAKE_GOALS}}
         # Set variables and create dirs for modules
           if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
             module_strip_flag="INSTALL_MOD_STRIP=1"
           fi
           mkdir -p {modules_staging_dir}
         # Install modules
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} DEPMOD=true O=${{OUT_DIR}} ${{module_strip_flag}} INSTALL_MOD_PATH=$(realpath {modules_staging_dir}) modules_install
         # Archive headers in OUT_DIR
           find ${{OUT_DIR}} -name *.h -print0                          \
               | tar czf {out_dir_kernel_headers_tar}                   \
                       --absolute-names                                 \
                       --dereference                                    \
                       --transform "s,.*$OUT_DIR,,"                     \
                       --transform "s,^/,,"                             \
                       --null -T -
         # Grab outputs. If unable to find from OUT_DIR, look at KBUILD_MIXED_TREE as well.
           {search_and_mv_output} --srcdir ${{OUT_DIR}} {kbuild_mixed_tree_arg} {dtstree_arg} --dstdir {ruledir} {all_output_names}
         # Check if there are remaining *.ko files
           remaining_ko_files=$(find ${{OUT_DIR}} -type f -name '*.ko')
           if [[ ${{remaining_ko_files}} ]]; then
             echo "ERROR: The following kernel modules are built but not copied. Add these lines to the module_outs attribute of {label}:" >&2
             for ko in ${{remaining_ko_files}}; do
               echo '    "'"$(basename ${{ko}})"'",' >&2
             done
             exit 1
           fi
         # Archive modules_staging_dir
           tar czf {modules_staging_archive} -C {modules_staging_dir} .
         # Clean up staging directories
           rm -rf {modules_staging_dir}
         """.format(
        search_and_mv_output = ctx.file._search_and_mv_output.path,
        kbuild_mixed_tree_arg = "--srcdir ${KBUILD_MIXED_TREE}" if kbuild_mixed_tree else "",
        dtstree_arg = "--srcdir ${OUT_DIR}/${dtstree}",
        ruledir = ruledir.path,
        all_output_names = " ".join(all_output_names),
        modules_staging_dir = modules_staging_dir,
        modules_staging_archive = modules_staging_archive.path,
        out_dir_kernel_headers_tar = out_dir_kernel_headers_tar.path,
        interceptor_output = interceptor_output.path,
        label = ctx.label,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        tools = ctx.attr.config[_KernelEnvInfo].dependencies,
        progress_message = "Building kernel %s" % ctx.attr.name,
        command = command,
    )

    # Only outs and internal_outs are needed. But for simplicity, copy the full {ruledir}
    # which includes module_outs and implicit_outs too.
    env_info_dependencies = []
    env_info_dependencies += ctx.attr.config[_KernelEnvInfo].dependencies
    for d in all_output_files.values():
        env_info_dependencies += d.values()
    env_info_setup = ctx.attr.config[_KernelEnvInfo].setup + """
         # Restore kernel build outputs
           cp -R {ruledir}/* ${{OUT_DIR}}
           """.format(ruledir = ruledir.path)
    if kbuild_mixed_tree:
        env_info_dependencies.append(kbuild_mixed_tree)
        env_info_setup += """
            export KBUILD_MIXED_TREE=$(realpath {kbuild_mixed_tree})
        """.format(kbuild_mixed_tree = kbuild_mixed_tree.path)
    env_info = _KernelEnvInfo(
        dependencies = env_info_dependencies,
        setup = env_info_setup,
    )

    module_srcs = [
        s
        for s in ctx.files.srcs
        if s.path.endswith(".h") or any([token in s.path for token in [
            "Makefile",
            "scripts/",
        ]])
    ]
    kernel_build_info = _KernelBuildInfo(
        modules_staging_archive = modules_staging_archive,
        module_srcs = module_srcs,
        out_dir_kernel_headers_tar = out_dir_kernel_headers_tar,
        outs = all_output_files["outs"].values(),
        base_kernel_files = base_kernel_files,
        interceptor_output = interceptor_output,
    )

    output_group_kwargs = {}
    for d in all_output_files.values():
        output_group_kwargs.update({name: depset([file]) for name, file in d.items()})
    output_group_info = OutputGroupInfo(**output_group_kwargs)

    default_info_files = all_output_files["outs"].values() + all_output_files["module_outs"].values()
    default_info = DefaultInfo(files = depset(default_info_files))
    kernel_files_info = KernelFilesInfo(files = default_info_files)

    return [
        env_info,
        kernel_build_info,
        output_group_info,
        default_info,
        kernel_files_info,
    ]

_kernel_build = rule(
    implementation = _kernel_build_impl,
    doc = "Defines a kernel build target.",
    attrs = {
        "config": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            aspects = [_kernel_toolchain_aspect],
            doc = "the kernel_config target",
        ),
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "outs": attr.string_list(),
        "module_outs": attr.string_list(doc = "output *.ko files"),
        "internal_outs": attr.string_list(doc = "Like `outs`, but not in dist"),
        "implicit_outs": attr.string_list(doc = "Like `outs`, but not in dist"),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_mv_output.py"),
            doc = "label referring to the script to process outputs",
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
        "base_kernel": attr.label(
            providers = [KernelFilesInfo],
            aspects = [_kernel_toolchain_aspect],
        ),
        "modules_prepare": attr.label(),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _modules_prepare_impl(ctx):
    command = ctx.attr.config[_KernelEnvInfo].setup + """
         # Prepare for the module build
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}} modules_prepare
         # Package files
           tar czf {outdir_tar_gz} -C ${{OUT_DIR}} .
    """.format(outdir_tar_gz = ctx.outputs.outdir_tar_gz.path)

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [ctx.outputs.outdir_tar_gz],
        tools = ctx.attr.config[_KernelEnvInfo].dependencies,
        progress_message = "Preparing for module build %s" % ctx.label,
        command = command,
    )

    setup = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
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
        "srcs": attr.label_list(mandatory = True, doc = "kernel sources", allow_files = True),
        "outdir_tar_gz": attr.output(
            mandatory = True,
            doc = "the packaged ${OUT_DIR} files",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

_KernelModuleInfo = provider(fields = {
    "kernel_build": "kernel_build attribute of this module",
    "modules_staging_archive": "Archive containing staging kernel modules. " +
                               "Contains the lib/modules/* suffix.",
    "kernel_uapi_headers_archive": "Archive containing UAPI headers to use the module.",
})

def _check_kernel_build(kernel_modules, kernel_build, this_label):
    """Check that kernel_modules have the same kernel_build as the given one.

    Args:
        kernel_modules: the attribute of kernel_module dependencies. Should be
          an attribute of a list of labels.
        kernel_build: the attribute of kernel_build. Should be an attribute of
          a label.
        this_label: label of the module being checked.
    """

    for kernel_module in kernel_modules:
        if kernel_module[_KernelModuleInfo].kernel_build.label != \
           kernel_build.label:
            fail((
                "{this_label} refers to kernel_build {kernel_build}, but " +
                "depended kernel_module {dep} refers to kernel_build " +
                "{dep_kernel_build}. They must refer to the same kernel_build."
            ).format(
                this_label = this_label,
                kernel_build = kernel_build.label,
                dep = kernel_module.label,
                dep_kernel_build = kernel_module[_KernelModuleInfo].kernel_build.label,
            ))

def _kernel_module_impl(ctx):
    _check_kernel_build(ctx.attr.kernel_module_deps, ctx.attr.kernel_build, ctx.label)

    modules_prepare = ctx.attr.kernel_build[_KernelBuildAspectInfo].modules_prepare
    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += modules_prepare[_KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[_KernelBuildInfo].module_srcs
    inputs += ctx.files.makefile
    inputs += [
        ctx.file._search_and_mv_output,
    ]
    for kernel_module_dep in ctx.attr.kernel_module_deps:
        inputs += kernel_module_dep[_KernelEnvInfo].dependencies

    modules_staging_archive = ctx.actions.declare_file("{}/modules_staging_archive.tar.gz".format(ctx.attr.name))
    modules_staging_dir = modules_staging_archive.dirname + "/staging"
    kernel_uapi_headers_archive = ctx.actions.declare_file("{}/kernel-uapi-headers.tar.gz".format(ctx.attr.name))
    kernel_uapi_headers_dir = kernel_uapi_headers_archive.dirname + "/kernel-uapi-headers.tar.gz_staging"
    outdir = modules_staging_archive.dirname  # equivalent to declare_directory(ctx.attr.name)

    # additional_outputs: archives + [basename(out) for out in outs]
    additional_outputs = [
        modules_staging_archive,
        kernel_uapi_headers_archive,
    ]

    # Original `outs` attribute of `kernel_module` macro.
    original_outs = []
    for out in ctx.outputs.outs:
        # outdir includes target name at the end already. So short_name is the original
        # token in `outs` of `kernel_module` macro.
        # e.g. kernel_module(name = "foo", outs = ["bar"])
        #   => _kernel_module(name = "foo", outs = ["foo/bar"])
        #   => outdir = ".../foo"
        #      ctx.outputs.outs = [File(".../foo/bar")]
        #   => short_name = "bar"
        short_name = out.path[len(outdir) + 1:]
        original_outs.append(short_name)
        if "/" in short_name:
            additional_outputs.append(ctx.actions.declare_file("{name}/{basename}".format(
                name = ctx.attr.name,
                basename = out.basename,
            )))

    module_symvers = ctx.actions.declare_file("{}/Module.symvers".format(ctx.attr.name))
    additional_declared_outputs = [
        module_symvers,
    ]

    command = ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += modules_prepare[_KernelEnvInfo].setup
    command += """
             # create dirs for modules
               mkdir -p {modules_staging_dir} {kernel_uapi_headers_dir}/usr
    """.format(
        modules_staging_dir = modules_staging_dir,
        kernel_uapi_headers_dir = kernel_uapi_headers_dir,
    )
    for kernel_module_dep in ctx.attr.kernel_module_deps:
        command += kernel_module_dep[_KernelEnvInfo].setup

    modules_staging_outs = []
    for short_name in original_outs:
        modules_staging_outs.append("lib/modules/*/extra/" + ctx.attr.ext_mod + "/" + short_name)

    command += """
             # Set variables
               if [ "${{DO_NOT_STRIP_MODULES}}" != "1" ]; then
                 module_strip_flag="INSTALL_MOD_STRIP=1"
               fi
               ext_mod_rel=$(rel_path ${{ROOT_DIR}}/{ext_mod} ${{KERNEL_DIR}})

             # Actual kernel module build
               make -C {ext_mod} ${{TOOL_ARGS}} M=${{ext_mod_rel}} O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}
             # Install into staging directory
               make -C {ext_mod} ${{TOOL_ARGS}} DEPMOD=true M=${{ext_mod_rel}} \
                   O=${{OUT_DIR}} KERNEL_SRC=${{ROOT_DIR}}/${{KERNEL_DIR}}     \
                   INSTALL_MOD_PATH=$(realpath {modules_staging_dir})          \
                   INSTALL_MOD_DIR=extra/{ext_mod}                             \
                   KERNEL_UAPI_HEADERS_DIR=$(realpath {kernel_uapi_headers_dir}) \
                   INSTALL_HDR_PATH=$(realpath {kernel_uapi_headers_dir}/usr)  \
                   ${{module_strip_flag}} modules_install
             # Archive modules_staging_dir
               (
                 modules_staging_archive=$(realpath {modules_staging_archive})
                 cd {modules_staging_dir}
                 if ! mod_order=$(ls lib/modules/*/extra/{ext_mod}/modules.order.*); then
                   # The modules.order.* file may not exist. Just keep it empty.
                   mod_order=
                 fi
                 tar czf ${{modules_staging_archive}} {modules_staging_outs} ${{mod_order}}
               )
             # Move files into place
               {search_and_mv_output} --srcdir {modules_staging_dir}/lib/modules/*/extra/{ext_mod}/ --dstdir {outdir} {outs}
             # Create headers archive
               tar czf {kernel_uapi_headers_archive} --directory={kernel_uapi_headers_dir} usr/
             # Remove staging dirs because they are not declared
               rm -rf {modules_staging_dir} {kernel_uapi_headers_dir}
             # Move Module.symvers
               mv ${{OUT_DIR}}/${{ext_mod_rel}}/Module.symvers {module_symvers}
               """.format(
        ext_mod = ctx.attr.ext_mod,
        search_and_mv_output = ctx.file._search_and_mv_output.path,
        module_symvers = module_symvers.path,
        modules_staging_dir = modules_staging_dir,
        modules_staging_archive = modules_staging_archive.path,
        outdir = outdir,
        outs = " ".join(original_outs),
        modules_staging_outs = " ".join(modules_staging_outs),
        kernel_uapi_headers_archive = kernel_uapi_headers_archive.path,
        kernel_uapi_headers_dir = kernel_uapi_headers_dir,
    )

    _debug_print_scripts(ctx, command)
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
               # rel_path requires the existence of ${{ROOT_DIR}}/{ext_mod}, which may not be the case for
               # _kernel_modules_install. Make that.
               mkdir -p ${{ROOT_DIR}}/{ext_mod}
               ext_mod_rel=$(rel_path ${{ROOT_DIR}}/{ext_mod} ${{KERNEL_DIR}})
             # Restore Modules.symvers
               mkdir -p ${{OUT_DIR}}/${{ext_mod_rel}}
               cp {module_symvers} ${{OUT_DIR}}/${{ext_mod_rel}}/Module.symvers
             # New shell ends
               )
    """.format(
        ext_mod = ctx.attr.ext_mod,
        module_symvers = module_symvers.path,
    )

    # Only declare outputs in the "outs" list. For additional outputs that this rule created,
    # the label is available, but this rule doesn't explicitly return it in the info.
    return [
        DefaultInfo(files = depset(ctx.outputs.outs)),
        _KernelEnvInfo(
            dependencies = additional_declared_outputs,
            setup = setup,
        ),
        _KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            modules_staging_archive = modules_staging_archive,
            kernel_uapi_headers_archive = kernel_uapi_headers_archive,
        ),
    ]

_kernel_module = rule(
    implementation = _kernel_module_impl,
    doc = """
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "makefile": attr.label_list(
            allow_files = True,
        ),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo, _KernelBuildInfo],
            aspects = [_kernel_build_aspect],
        ),
        "kernel_module_deps": attr.label_list(
            providers = [_KernelEnvInfo, _KernelModuleInfo],
        ),
        "ext_mod": attr.string(mandatory = True),
        # Not output_list because it is not a list of labels. The list of
        # output labels are inferred from name and outs.
        "outs": attr.output_list(),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_mv_output.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def kernel_module(
        name,
        kernel_build,
        outs = None,
        srcs = None,
        kernel_module_deps = None,
        **kwargs):
    """Generates a rule that builds an external kernel module.

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
    )
    ```

    Args:
        name: Name of this kernel module.
        srcs: Source files to build this kernel module. If unspecified or value
          is `None`, it is by default the list in the above example:
          ```
          glob([
            "**/*.c",
            "**/*.h",
            "**/Kbuild",
            "**/Makefile",
          ])
          ```
        kernel_build: Label referring to the kernel_build module.
        kernel_module_deps: A list of other kernel_module dependencies.

          Before building this target, `Modules.symvers` from the targets in
          `kernel_module_deps` are restored, so this target can be built against
          them.
        outs: The expected output files. If unspecified or value is `None`, it
          is `["{name}.ko"]` by default.

          For each token `out`, the build rule automatically finds a
          file named `out` in the legacy kernel modules staging
          directory. The file is copied to the output directory of
          this package, with the label `name/out`.

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

            `nfc/nfc.ko` is the label to the file.

          - If `out` contains slashes, its value is used. The file is
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

            `nfc/foo/nfc.ko` is the label to the file.

            The file is also copied to `<package output dir>/nfc.ko`.

            `nfc/nfc.ko` is the label to the file.

            See `search_and_mv_output.py` for details.
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    kwargs.update(
        # This should be the exact list of arguments of kernel_module.
        # Default arguments of _kernel_module go into _kernel_module_set_defaults.
        name = name,
        srcs = srcs,
        kernel_build = kernel_build,
        kernel_module_deps = kernel_module_deps,
        outs = ["{name}/{out}".format(name = name, out = out) for out in outs] if outs else [],
    )
    kwargs = _kernel_module_set_defaults(kwargs)
    _kernel_module(**kwargs)

def _kernel_module_set_defaults(kwargs):
    """
    Set default values for `_kernel_module` that can't be specified in
    `attr.*(default=...)` in rule().
    """
    if kwargs.get("makefile") == None:
        kwargs["makefile"] = native.glob(["Makefile"])

    if kwargs.get("ext_mod") == None:
        kwargs["ext_mod"] = native.package_name()

    if kwargs.get("outs") == None:
        kwargs["outs"] = ["{}.ko".format(kwargs["name"])]

    if kwargs.get("srcs") == None:
        kwargs["srcs"] = native.glob([
            "**/*.c",
            "**/*.h",
            "**/Kbuild",
            "**/Makefile",
        ])

    return kwargs

def _kernel_modules_install_impl(ctx):
    _check_kernel_build(ctx.attr.kernel_modules, ctx.attr.kernel_build, ctx.label)

    modules_prepare = ctx.attr.kernel_build[_KernelBuildAspectInfo].modules_prepare

    # A list of declared files for outputs of kernel_module rules
    external_modules = []

    inputs = []
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += modules_prepare[_KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[_KernelBuildInfo].module_srcs
    inputs += [
        ctx.file._search_and_mv_output,
        ctx.file._check_duplicated_files_in_archives,
        ctx.attr.kernel_build[_KernelBuildInfo].modules_staging_archive,
    ]
    for kernel_module in ctx.attr.kernel_modules:
        inputs += kernel_module[_KernelEnvInfo].dependencies
        inputs += [
            kernel_module[_KernelModuleInfo].modules_staging_archive,
        ]

        # Intentionally expand depset.to_list() to figure out what module files
        # will be installed to module install directory.
        for module_file in kernel_module[DefaultInfo].files.to_list():
            declared_file = ctx.actions.declare_file("{}/{}".format(ctx.label.name, module_file.basename))
            external_modules.append(declared_file)

    modules_staging_archive = ctx.actions.declare_file("{}.tar.gz".format(ctx.label.name))
    modules_staging_dir = modules_staging_archive.dirname + "/staging"

    command = ""
    command += ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += modules_prepare[_KernelEnvInfo].setup
    command += """
             # create dirs for modules
               mkdir -p {modules_staging_dir}
             # Restore modules_staging_dir from kernel_build
               tar xf {kernel_build_modules_staging_archive} -C {modules_staging_dir}
               modules_staging_archives="{kernel_build_modules_staging_archive}"
    """.format(
        modules_staging_dir = modules_staging_dir,
        kernel_build_modules_staging_archive =
            ctx.attr.kernel_build[_KernelBuildInfo].modules_staging_archive.path,
    )
    for kernel_module in ctx.attr.kernel_modules:
        command += kernel_module[_KernelEnvInfo].setup

        command += """
                 # Restore modules_staging_dir from depended kernel_module
                   tar xf {modules_staging_archive} -C {modules_staging_dir}
                   modules_staging_archives="${{modules_staging_archives}} {modules_staging_archive}"
        """.format(
            modules_staging_archive = kernel_module[_KernelModuleInfo].modules_staging_archive.path,
            modules_staging_dir = modules_staging_dir,
        )

    # TODO(b/194347374): maybe run depmod.sh with CONFIG_SHELL?
    command += """
             # Check if there are duplicated files in modules_staging_archive of
             # depended kernel_build and kernel_module's
               {check_duplicated_files_in_archives} ${{modules_staging_archives}}
             # Set variables
               if [[ ! -f ${{OUT_DIR}}/include/config/kernel.release ]]; then
                   echo "ERROR: No ${{OUT_DIR}}/include/config/kernel.release" >&2
                   exit 1
               fi
               kernelrelease=$(cat ${{OUT_DIR}}/include/config/kernel.release 2> /dev/null)
               mixed_build_prefix=
               if [[ ${{KBUILD_MIXED_TREE}} ]]; then
                   mixed_build_prefix=${{KBUILD_MIXED_TREE}}/
               fi
               real_modules_staging_dir=$(realpath {modules_staging_dir})
             # Run depmod
               (
                 cd ${{OUT_DIR}} # for System.map when mixed_build_prefix is not set
                 INSTALL_MOD_PATH=${{real_modules_staging_dir}} ${{ROOT_DIR}}/${{KERNEL_DIR}}/scripts/depmod.sh depmod ${{kernelrelease}} ${{mixed_build_prefix}}
               )
             # Archive modules_staging_dir
               tar czf {modules_staging_archive} -C {modules_staging_dir} .
    """.format(
        modules_staging_dir = modules_staging_dir,
        modules_staging_archive = modules_staging_archive.path,
        check_duplicated_files_in_archives = ctx.file._check_duplicated_files_in_archives.path,
    )

    if external_modules:
        external_module_dir = external_modules[0].dirname
        command += """
                 # Move external modules to declared output location
                   {search_and_mv_output} --srcdir {modules_staging_dir}/lib/modules/*/extra --dstdir {outdir} {filenames}
        """.format(
            modules_staging_dir = modules_staging_dir,
            outdir = external_module_dir,
            filenames = " ".join([declared_file.basename for declared_file in external_modules]),
            search_and_mv_output = ctx.file._search_and_mv_output.path,
        )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = external_modules + [
            modules_staging_archive,
        ],
        command = command,
        progress_message = "Running depmod {}".format(ctx.label),
    )

    return [
        DefaultInfo(files = depset(external_modules)),
        _KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            modules_staging_archive = modules_staging_archive,
        ),
    ]

kernel_modules_install = rule(
    implementation = _kernel_modules_install_impl,
    doc = """Generates a rule that runs depmod in the module installation directory.

When including this rule to the `data` attribute of a `copy_to_dist_dir` rule,
all external kernel modules specified in `kernel_modules` are included in
distribution. This excludes `module_outs` in `kernel_build` to avoid conflicts.

Example:
```
kernel_modules_install(
    name = "foo_modules_install",
    kernel_build = ":foo",           # A kernel_build rule
    kernel_modules = [               # kernel_module rules
        "//path/to/nfc:nfc_module",
    ],
)
kernel_build(
    name = "foo",
    outs = ["vmlinux"],
    module_outs = ["core_module.ko"],
)
copy_to_dist_dir(
    name = "foo_dist",
    data = [
        ":foo",                      # Includes core_module.ko and vmlinux
        ":foo_modules_install",      # Includes nfc_module
    ],
)
```
In `foo_dist`, specifying `foo_modules_install` in `data` won't include
`core_module.ko`, because it is already included in `foo` in `data`.
""",
    attrs = {
        "kernel_modules": attr.label_list(
            providers = [_KernelEnvInfo, _KernelModuleInfo],
            doc = "A list of labels referring to `kernel_module`s to install. Must have the same `kernel_build` as this rule.",
        ),
        "kernel_build": attr.label(
            providers = [_KernelEnvInfo, _KernelBuildInfo],
            doc = "Label referring to the `kernel_build` module.",
            aspects = [_kernel_build_aspect],
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_check_duplicated_files_in_archives": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:check_duplicated_files_in_archives.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_mv_output.py"),
            doc = "Label referring to the script to process outputs",
        ),
    },
)

def _kernel_uapi_headers_impl(ctx):
    out_file = ctx.actions.declare_file("{}/kernel-uapi-headers.tar.gz".format(ctx.label.name))
    command = ctx.attr.config[_KernelEnvInfo].setup + """
         # Create staging directory
           mkdir -p {kernel_uapi_headers_dir}/usr
         # Actual headers_install
           make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} INSTALL_HDR_PATH=$(realpath {kernel_uapi_headers_dir}/usr) headers_install
         # Create archive
           tar czf {out_file} --directory={kernel_uapi_headers_dir} usr/
         # Delete kernel_uapi_headers_dir because it is not declared
           rm -rf {kernel_uapi_headers_dir}
    """.format(
        out_file = out_file.path,
        kernel_uapi_headers_dir = out_file.path + "_staging",
    )
    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = ctx.files.srcs + ctx.attr.config[_KernelEnvInfo].dependencies,
        outputs = [out_file],
        progress_message = "Building UAPI kernel headers %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(files = depset([out_file])),
    ]

_kernel_uapi_headers = rule(
    implementation = _kernel_uapi_headers_impl,
    doc = """Build kernel-uapi-headers.tar.gz""",
    attrs = {
        "srcs": attr.label_list(),
        "config": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            doc = "the kernel_config target",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_headers_impl(ctx):
    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.env[_KernelEnvInfo].dependencies
    inputs += [
        ctx.attr.kernel_build[_KernelBuildInfo].out_dir_kernel_headers_tar,
    ]
    out_file = ctx.actions.declare_file("{}/kernel-headers.tar.gz".format(ctx.label.name))
    command = ctx.attr.env[_KernelEnvInfo].setup + """
            # Restore headers in ${{OUT_DIR}}
              mkdir -p ${{OUT_DIR}}
              tar xf {out_dir_kernel_headers_tar} -C ${{OUT_DIR}}
            # Create archive
              (
                real_out_file=$(realpath {out_file})
                cd ${{ROOT_DIR}}/${{KERNEL_DIR}}
                find arch include ${{OUT_DIR}} -name *.h -print0         \
                    | tar czf ${{real_out_file}}                         \
                        --absolute-names                                 \
                        --dereference                                    \
                        --transform "s,.*$OUT_DIR,,"                     \
                        --transform "s,^,kernel-headers/,"               \
                        --null -T -
              )
    """.format(
        out_file = out_file.path,
        out_dir_kernel_headers_tar = ctx.attr.kernel_build[_KernelBuildInfo].out_dir_kernel_headers_tar.path,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Building kernel headers %s" % ctx.attr.name,
        command = command,
    )

    return [
        DefaultInfo(files = depset([out_file])),
    ]

_kernel_headers = rule(
    implementation = _kernel_headers_impl,
    doc = "Build kernel-headers.tar.gz",
    attrs = {
        "srcs": attr.label_list(),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [_KernelBuildInfo],  # for out_dir_kernel_headers_tar only
        ),
        "env": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _vmlinux_btf_impl(ctx):
    inputs = [
        ctx.file.vmlinux,
    ]
    inputs += ctx.attr.env[_KernelEnvInfo].dependencies
    out_file = ctx.actions.declare_file("{}/vmlinux.btf".format(ctx.label.name))
    out_dir = out_file.dirname
    command = ctx.attr.env[_KernelEnvInfo].setup + """
              mkdir -p {out_dir}
              cp -Lp {vmlinux} {vmlinux_btf}
              pahole -J {vmlinux_btf}
              llvm-strip --strip-debug {vmlinux_btf}
    """.format(
        vmlinux = ctx.file.vmlinux.path,
        vmlinux_btf = out_file.path,
        out_dir = out_dir,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Building vmlinux.btf {}".format(ctx.label),
        command = command,
    )
    return DefaultInfo(files = depset([out_file]))

_vmlinux_btf = rule(
    implementation = _vmlinux_btf_impl,
    doc = "Build vmlinux.btf",
    attrs = {
        "vmlinux": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "env": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _build_modules_image_impl_common(
        ctx,
        what,
        outputs,
        build_command,
        modules_staging_dir,
        implicit_outputs = None,
        additional_inputs = None):
    """Command implementation for building images that directly contain modules.

    Args:
        ctx: ctx
        what: what is being built, for logging
        outputs: list of `ctx.actions.declare_file`
        build_command: the command to build `outputs` and `implicit_outputs`
        modules_staging_dir: a staging directory for module installation
        implicit_outputs: like `outputs`, but not installed to `DIST_DIR` (not returned in
          `DefaultInfo`)
    """
    kernel_build = ctx.attr.kernel_modules_install[_KernelModuleInfo].kernel_build
    kernel_build_outs = kernel_build[_KernelBuildInfo].outs + kernel_build[_KernelBuildInfo].base_kernel_files
    system_map = None
    for kernel_build_out in kernel_build_outs:
        if kernel_build_out.basename == "System.map":
            if system_map != None:
                fail("{}: dependent kernel_build {} has multiple System.map in outs:\n  {}\n  {}".format(
                    ctx.label,
                    kernel_build,
                    system_map.path,
                    kernel_build_out.path,
                ))
            system_map = kernel_build_out
    if system_map == None:
        fail("{}: dependent kernel_build {} has no System.map in outs".format(
            ctx.label,
            kernel_build,
        ))
    modules_staging_archive = ctx.attr.kernel_modules_install[_KernelModuleInfo].modules_staging_archive

    inputs = []
    if additional_inputs != None:
        inputs += additional_inputs
    inputs += [
        system_map,
        modules_staging_archive,
    ]
    inputs += ctx.files.deps
    inputs += kernel_build[_KernelEnvInfo].dependencies

    command_outputs = []
    command_outputs += outputs
    if implicit_outputs != None:
        command_outputs += implicit_outputs

    command = ""
    command += kernel_build[_KernelEnvInfo].setup
    command += """
             # create staging dirs
               mkdir -p {modules_staging_dir}
             # Restore modules_staging_dir from kernel_modules_install
               tar xf {modules_staging_archive} -C {modules_staging_dir}

             # Restore System.map to DIST_DIR for run_depmod in create_modules_staging
               mkdir -p ${{DIST_DIR}}
               cp {system_map} ${{DIST_DIR}}/System.map

               {build_command}

             # remove staging dirs
               rm -rf {modules_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dir,
        modules_staging_archive = modules_staging_archive.path,
        system_map = system_map.path,
        build_command = build_command,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        progress_message = "Building {} {}".format(what, ctx.label),
        command = command,
    )
    return DefaultInfo(files = depset(outputs))

def _build_modules_image_attrs_common(additional = None):
    """Common attrs for rules that builds images that directly contain modules."""
    ret = {
        "kernel_modules_install": attr.label(
            mandatory = True,
            providers = [_KernelModuleInfo],
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    }
    if additional != None:
        ret.update(additional)
    return ret

_InitramfsInfo = provider(fields = {
    "initramfs_img": "Output image",
    "initramfs_staging_archive": "Archive of initramfs staging directory",
})

def _initramfs_impl(ctx):
    initramfs_img = ctx.actions.declare_file("{}/initramfs.img".format(ctx.label.name))
    modules_load = ctx.actions.declare_file("{}/modules.load".format(ctx.label.name))
    vendor_boot_modules_load = ctx.outputs.vendor_boot_modules_load
    initramfs_staging_archive = ctx.actions.declare_file("{}/initramfs_staging_archive.tar.gz".format(ctx.label.name))

    outputs = [
        initramfs_img,
        modules_load,
        vendor_boot_modules_load,
    ]

    modules_staging_dir = initramfs_img.dirname + "/staging"
    initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"

    command = """
               mkdir -p {initramfs_staging_dir}
             # Build initramfs
               create_modules_staging "${{MODULES_LIST}}" {modules_staging_dir} \
                 {initramfs_staging_dir} "${{MODULES_BLOCKLIST}}" "-e"
               modules_root_dir=$(echo {initramfs_staging_dir}/lib/modules/*)
               cp ${{modules_root_dir}}/modules.load {modules_load}
               cp ${{modules_root_dir}}/modules.load {vendor_boot_modules_load}
               echo "${{MODULES_OPTIONS}}" > ${{modules_root_dir}}/modules.options
               mkbootfs "{initramfs_staging_dir}" >"{modules_staging_dir}/initramfs.cpio"
               ${{RAMDISK_COMPRESS}} "{modules_staging_dir}/initramfs.cpio" >"{initramfs_img}"
             # Archive initramfs_staging_dir
               tar czf {initramfs_staging_archive} -C {initramfs_staging_dir} .
             # Remove staging directories
               rm -rf {initramfs_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dir,
        initramfs_staging_dir = initramfs_staging_dir,
        modules_load = modules_load.path,
        vendor_boot_modules_load = vendor_boot_modules_load.path,
        initramfs_img = initramfs_img.path,
        initramfs_staging_archive = initramfs_staging_archive.path,
    )

    default_info = _build_modules_image_impl_common(
        ctx = ctx,
        what = "initramfs",
        outputs = outputs,
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        implicit_outputs = [
            initramfs_staging_archive,
        ],
    )
    return [
        default_info,
        _InitramfsInfo(
            initramfs_img = initramfs_img,
            initramfs_staging_archive = initramfs_staging_archive,
        ),
    ]

_initramfs = rule(
    implementation = _initramfs_impl,
    doc = """Build initramfs.

When included in a `copy_to_dist_dir` rule, this rule copies the following to `DIST_DIR`:
- `initramfs.img`
- `modules.load`
- `vendor_boot.modules.load`

An additional label, `{name}/vendor_boot.modules.load`, is declared to point to the
corresponding files.
""",
    attrs = _build_modules_image_attrs_common({
        "vendor_boot_modules_load": attr.output(),
    }),
)

def _system_dlkm_image_impl(ctx):
    system_dlkm_img = ctx.actions.declare_file("{}/system_dlkm.img".format(ctx.label.name))
    system_dlkm_staging_archive = ctx.actions.declare_file("{}/system_dlkm_staging_archive.tar.gz".format(ctx.label.name))

    modules_staging_dir = system_dlkm_img.dirname + "/staging"
    system_dlkm_staging_dir = modules_staging_dir + "/system_dlkm_staging"

    command = """
               mkdir -p {system_dlkm_staging_dir}
             # Build system_dlkm.img
               create_modules_staging "${{MODULES_LIST}}" {modules_staging_dir} \
                 {system_dlkm_staging_dir} "${{MODULES_BLOCKLIST}}" "-e"
               modules_root_dir=$(ls {system_dlkm_staging_dir}/lib/modules/*)
             # Re-sign the stripped modules using kernel build time key
               for module in $(find {system_dlkm_staging_dir} -type f -name '*.ko'); do
                   "${{OUT_DIR}}"/scripts/sign-file sha1 \
                   "${{OUT_DIR}}"/certs/signing_key.pem \
                   "${{OUT_DIR}}"/certs/signing_key.x509 "${{module}}"
               done
             # Build system_dlkm.img with signed GKI modules
               mkfs.erofs -zlz4hc "{system_dlkm_img}" "{system_dlkm_staging_dir}"
             # No need to sign the image as modules are signed; add hash footer
               avbtool add_hash_footer \
                   --partition_name system_dlkm \
                   --partition_size $((64 << 20)) \
                   --image "{system_dlkm_img}"
             # Archive system_dlkm_staging_dir
               tar czf {system_dlkm_staging_archive} -C {system_dlkm_staging_dir} .
             # Remove staging directories
               rm -rf {system_dlkm_staging_dir}
    """.format(
        modules_staging_dir = modules_staging_dir,
        system_dlkm_staging_dir = system_dlkm_staging_dir,
        system_dlkm_img = system_dlkm_img.path,
        system_dlkm_staging_archive = system_dlkm_staging_archive.path,
    )

    default_info = _build_modules_image_impl_common(
        ctx = ctx,
        what = "system_dlkm",
        outputs = [system_dlkm_img, system_dlkm_staging_archive],
        build_command = command,
        modules_staging_dir = modules_staging_dir,
    )
    return [default_info]

_system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm.img an erofs image with GKI modules.

When included in a `copy_to_dist_dir` rule, this rule copies the `system_dlkm.img` to `DIST_DIR`.

""",
    attrs = _build_modules_image_attrs_common(),
)

def _vendor_dlkm_image_impl(ctx):
    vendor_dlkm_img = ctx.actions.declare_file("{}/vendor_dlkm.img".format(ctx.label.name))
    vendor_dlkm_modules_load = ctx.actions.declare_file("{}/vendor_dlkm.modules.load".format(ctx.label.name))
    vendor_dlkm_modules_blocklist = ctx.actions.declare_file("{}/vendor_dlkm.modules.blocklist".format(ctx.label.name))
    modules_staging_dir = vendor_dlkm_img.dirname + "/staging"
    vendor_dlkm_staging_dir = modules_staging_dir + "/vendor_dlkm_staging"
    command = """
            # Restore vendor_boot.modules.load
              cp {vendor_boot_modules_load} ${{DIST_DIR}}/vendor_boot.modules.load
            # Build vendor_dlkm
              mkdir -p {vendor_dlkm_staging_dir}
              (
                MODULES_STAGING_DIR={modules_staging_dir}
                VENDOR_DLKM_STAGING_DIR={vendor_dlkm_staging_dir}
                build_vendor_dlkm
              )
            # Move output files into place
              mv "${{DIST_DIR}}/vendor_dlkm.img" {vendor_dlkm_img}
              mv "${{DIST_DIR}}/vendor_dlkm.modules.load" {vendor_dlkm_modules_load}
              if [[ -f "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" ]]; then
                mv "${{DIST_DIR}}/vendor_dlkm.modules.blocklist" {vendor_dlkm_modules_blocklist}
              else
                : > {vendor_dlkm_modules_blocklist}
              fi
            # Remove staging directories
              rm -rf {vendor_dlkm_staging_dir}
    """.format(
        vendor_boot_modules_load = ctx.file.vendor_boot_modules_load.path,
        modules_staging_dir = modules_staging_dir,
        vendor_dlkm_staging_dir = vendor_dlkm_staging_dir,
        vendor_dlkm_img = vendor_dlkm_img.path,
        vendor_dlkm_modules_load = vendor_dlkm_modules_load.path,
        vendor_dlkm_modules_blocklist = vendor_dlkm_modules_blocklist.path,
    )

    return _build_modules_image_impl_common(
        ctx = ctx,
        what = "vendor_dlkm",
        outputs = [vendor_dlkm_img, vendor_dlkm_modules_load, vendor_dlkm_modules_blocklist],
        build_command = command,
        modules_staging_dir = modules_staging_dir,
        additional_inputs = [ctx.file.vendor_boot_modules_load],
    )

_vendor_dlkm_image = rule(
    implementation = _vendor_dlkm_image_impl,
    doc = """Build vendor_dlkm image.

Execute `build_vendor_dlkm` in `build_utils.sh`.

When included in a `copy_to_dist_dir` rule, this rule copies a `vendor_dlkm.img` to `DIST_DIR`.
""",
    attrs = _build_modules_image_attrs_common({
        "vendor_boot_modules_load": attr.label(
            allow_single_file = True,
            doc = """File to `vendor_boot.modules.load`.

Modules listed in this file is stripped away from the `vendor_dlkm` image.""",
        ),
    }),
)

def _boot_images_impl(ctx):
    initramfs_staging_archive = ctx.attr.initramfs[_InitramfsInfo].initramfs_staging_archive
    outdir = ctx.actions.declare_directory(ctx.label.name)
    modules_staging_dir = outdir.path + "/staging"
    initramfs_staging_dir = modules_staging_dir + "/initramfs_staging"
    mkbootimg_staging_dir = modules_staging_dir + "/mkbootimg_staging"

    outs = []
    for out in ctx.outputs.outs:
        outs.append(out.short_path[len(outdir.short_path) + 1:])

    kernel_build_outs = ctx.attr.kernel_build[_KernelBuildInfo].outs + ctx.attr.kernel_build[_KernelBuildInfo].base_kernel_files

    inputs = [
        ctx.attr.initramfs[_InitramfsInfo].initramfs_img,
        initramfs_staging_archive,
        ctx.file.mkbootimg,
        ctx.file._search_and_mv_output,
    ]
    inputs += ctx.files.deps
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += kernel_build_outs

    command = ""
    command += ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += """
             # Create and restore initramfs_staging_dir
               mkdir -p {initramfs_staging_dir}
               tar xf {initramfs_staging_archive} -C {initramfs_staging_dir}
             # Create and restore DIST_DIR.
             # We don't need all of *_for_dist. Copying all declared outputs of kernel_build is
             # sufficient.
               mkdir -p ${{DIST_DIR}}
               cp {kernel_build_outs} ${{DIST_DIR}}
               cp {initramfs_img} ${{DIST_DIR}}/initramfs.img
             # Build boot images
               (
                 INITRAMFS_STAGING_DIR={initramfs_staging_dir}
                 MKBOOTIMG_STAGING_DIR=$(realpath {mkbootimg_staging_dir})
                 build_boot_images
               )
               {search_and_mv_output} --srcdir ${{DIST_DIR}} --dstdir {outdir} {outs}
             # Remove staging directories
               rm -rf {modules_staging_dir}
    """.format(
        initramfs_staging_dir = initramfs_staging_dir,
        mkbootimg_staging_dir = mkbootimg_staging_dir,
        search_and_mv_output = ctx.file._search_and_mv_output.path,
        outdir = outdir.path,
        outs = " ".join(outs),
        modules_staging_dir = modules_staging_dir,
        initramfs_staging_archive = initramfs_staging_archive.path,
        initramfs_img = ctx.attr.initramfs[_InitramfsInfo].initramfs_img.path,
        kernel_build_outs = " ".join([out.path for out in kernel_build_outs]),
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = ctx.outputs.outs + [outdir],
        progress_message = "Building boot images {}".format(ctx.label),
        command = command,
    )

_boot_images = rule(
    implementation = _boot_images_impl,
    doc = """Build boot images, including `boot.img`, `vendor_boot.img`, etc.

Execute `build_boot_images` in `build_utils.sh`.""",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo, _KernelBuildInfo],
        ),
        "initramfs": attr.label(
            providers = [_InitramfsInfo],
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
        "outs": attr.output_list(),
        "mkbootimg": attr.label(
            allow_single_file = True,
            default = "//tools/mkbootimg:mkbootimg.py",
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
        "_search_and_mv_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_mv_output.py"),
        ),
    },
)

def _dtbo_impl(ctx):
    output = ctx.actions.declare_file("{}/dtbo.img".format(ctx.label.name))
    inputs = []
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += ctx.files.srcs
    command = ""
    command += ctx.attr.kernel_build[_KernelEnvInfo].setup

    command += """
             # make dtbo
               mkdtimg create {output} ${{MKDTIMG_FLAGS}} {srcs}
    """.format(
        output = output.path,
        srcs = " ".join([f.path for f in ctx.files.srcs]),
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [output],
        progress_message = "Building dtbo {}".format(ctx.label),
        command = command,
    )
    return DefaultInfo(files = depset([output]))

_dtbo = rule(
    implementation = _dtbo_impl,
    doc = "Build dtbo.",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo, _KernelBuildInfo],
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    },
)

def kernel_images(
        name,
        kernel_modules_install,
        kernel_build = None,
        build_initramfs = None,
        build_vendor_dlkm = None,
        build_boot_images = None,
        build_system_dlkm = None,
        build_dtbo = None,
        dtbo_srcs = None,
        mkbootimg = None,
        deps = None,
        boot_image_outs = None):
    """Build multiple kernel images.

    Args:
        name: name of this rule, e.g. `kernel_images`,
        kernel_modules_install: A `kernel_modules_install` rule.

          The main kernel build is inferred from the `kernel_build` attribute of the
          specified `kernel_modules_install` rule. The main kernel build must contain
          `System.map` in `outs` (which is included if you use `aarch64_outs` or
          `x86_64_outs` from `common_kernels.bzl`).
        kernel_build: A `kernel_build` rule. Must specify if `build_boot_images`.
        mkbootimg: Path to the mkbootimg.py script which builds boot.img.
          Keep in sync with `MKBOOTIMG_PATH`. Only used if `build_boot_images`. If `None`,
          default to `//tools/mkbootimg:mkbootimg.py`.
        deps: Additional dependencies to build images.

          This must include the following:
          - For `initramfs`:
            - The file specified by `MODULES_LIST`
            - The file specified by `MODULES_BLOCKLIST`, if `MODULES_BLOCKLIST` is set
          - For `vendor_dlkm` image:
            - The file specified by `VENDOR_DLKM_MODULES_LIST`
            - The file specified by `VENDOR_DLKM_MODULES_BLOCKLIST`, if set
            - The file specified by `VENDOR_DLKM_PROPS`, if set
            - The file specified by `selinux_fc` in `VENDOR_DLKM_PROPS`, if set

        boot_image_outs: A list of output files that will be installed to `DIST_DIR` when
          `build_boot_images` is executed.

          If `build_boot_images` is equal to `False`, the default is empty.

          If `build_boot_images` is equal to `True`, the default list assumes the following:
          - `BOOT_IMAGE_FILENAME` is not set (which takes default value `boot.img`), or is set to
            `"boot.img"`
          - `SKIP_VENDOR_BOOT` is not set, which builds `vendor_boot.img"
          - `RAMDISK_EXT=lz4`. If the build configuration has a different value, replace
            `ramdisk.lz4` with `ramdisk.{RAMDISK_EXT}` accordingly.
          - `BOOT_IMAGE_HEADER_VERSION >= 4`, which creates `vendor-bootconfig.img` to contain
            `VENDOR_BOOTCONFIG`
          - The list contains `dtb.img`
        build_initramfs: Whether to build initramfs. Keep in sync with `BUILD_INITRAMFS`.
        build_system_dlkm: Whether to build system_dlkm.img an erofs image with GKI modules.
        build_vendor_dlkm: Whether to build `vendor_dlkm` image. It must be set if
          `VENDOR_DLKM_MODULES_LIST` is non-empty.

          Note: at the time of writing (Jan 2022), unlike `build.sh`,
          `vendor_dlkm.modules.blocklist` is **always** created
          regardless of the value of `VENDOR_DLKM_MODULES_BLOCKLIST`.
          If `build_vendor_dlkm()` in `build_utils.sh` does not generate
          `vendor_dlkm.modules.blocklist`, an empty file is created.
        build_boot_images: Whether to build boot images. It must be set if either `BUILD_BOOT_IMG`
          or `BUILD_VENDOR_BOOT_IMG` is set.

          This depends on `initramfs` and `kernel_build`. Hence, if this is set to `True`,
          `build_initramfs` is implicitly true, and `kernel_build` must be set.
        build_dtbo: Whether to build dtbo image. Keep this in sync with `BUILD_DTBO_IMG`.

          If `dtbo_srcs` is non-empty, `build_dtbo` is `True` by default. Otherwise it is `False`
          by default.
        dtbo_srcs: list of `*.dtbo` files used to package the `dtbo.img`. Keep this in sync
          with `MKDTIMG_DTBOS`; see example below.

          If `dtbo_srcs` is non-empty, `build_dtbo` must not be explicitly set to `False`.

          Example:
          ```
          kernel_build(
              name = "tuna_kernel",
              outs = [
                  "path/to/foo.dtbo",
                  "path/to/bar.dtbo",
              ],
          )
          kernel_images(
              name = "tuna_images",
              kernel_build = ":tuna_kernel",
              dtbo_srcs = [
                  ":tuna_kernel/path/to/foo.dtbo",
                  ":tuna_kernel/path/to/bar.dtbo",
              ]
          )
          ```
    """
    all_rules = []

    if build_boot_images:
        if build_initramfs == None:
            build_initramfs = True
        if not build_initramfs:
            fail("{}: Must set build_initramfs to True if build_boot_images".format(name))
        if kernel_build == None:
            fail("{}: Must set kernel_build if build_boot_images".format(name))

    # Set default value for boot_image_outs according to build_boot_images
    if boot_image_outs == None:
        if not build_boot_images:
            boot_image_outs = []
        else:
            boot_image_outs = [
                "boot.img",
                "dtb.img",
                "ramdisk.lz4",
                "vendor_boot.img",
                "vendor-bootconfig.img",
            ]

    if build_initramfs:
        _initramfs(
            name = "{}_initramfs".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name),
        )
        all_rules.append(":{}_initramfs".format(name))

    if build_system_dlkm:
        _system_dlkm_image(
            name = "{}_system_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
        )
        all_rules.append(":{}_system_dlkm_image".format(name))

    if build_vendor_dlkm:
        _vendor_dlkm_image(
            name = "{}_vendor_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name),
            deps = deps,
        )
        all_rules.append(":{}_vendor_dlkm_image".format(name))

    # Assume BUILD_BOOT_IMG or BUILD_VENDOR_BOOT_IMG
    if build_boot_images:
        _boot_images(
            name = "{}_boot_images".format(name),
            kernel_build = kernel_build,
            outs = ["{}_boot_images/{}".format(name, out) for out in boot_image_outs],
            deps = deps,
            initramfs = ":{}_initramfs".format(name),
            mkbootimg = mkbootimg,
        )
        all_rules.append(":{}_boot_images".format(name))

    if build_dtbo == None:
        build_dtbo = bool(dtbo_srcs)

    if dtbo_srcs:
        if not build_dtbo:
            fail("{}: build_dtbo must be True if dtbo_srcs is non-empty.")

    if build_dtbo:
        _dtbo(
            name = "{}_dtbo".format(name),
            srcs = dtbo_srcs,
            kernel_build = kernel_build,
        )
        all_rules.append(":{}_dtbo".format(name))

    native.filegroup(
        name = name,
        srcs = all_rules,
    )

def _kernel_filegroup_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        KernelFilesInfo(files = ctx.files.srcs),
    ]

kernel_filegroup = rule(
    implementation = _kernel_filegroup_impl,
    doc = """Specify a list of kernel prebuilts.

This is similar to [`filegroup`](https://docs.bazel.build/versions/main/be/general.html#filegroup)
that gives a convenient name to a collection of targets, which can be referenced from other rules.

In addition, this rule is conformed with [`KernelFilesInfo`](#kernelfilesinfo), so it can be used
in the `base_kernel` attribute of a [`kernel_build`](#kernel_build).
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "The list of labels that are members of this file group.",
        ),
    },
)

def _kernel_compile_commands_impl(ctx):
    interceptor_output = ctx.attr.kernel_build[_KernelBuildInfo].interceptor_output
    compile_commands = ctx.actions.declare_file(ctx.attr.name + "/compile_commands.json")
    inputs = [interceptor_output]
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    command = ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += """
             # Generate compile_commands.json
               interceptor_analysis -l {interceptor_output} -o {compile_commands} -t compdb_commands --relative
    """.format(
        interceptor_output = interceptor_output.path,
        compile_commands = compile_commands.path,
    )
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [compile_commands],
        command = command,
        progress_message = "Building compile_commands.json {}".format(ctx.label),
    )
    return DefaultInfo(files = depset([compile_commands]))

kernel_compile_commands = rule(
    implementation = _kernel_compile_commands_impl,
    doc = """
Generate `compile_commands.json` from a `kernel_build`.
    """,
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            doc = "The `kernel_build` rule to extract from.",
            providers = [_KernelEnvInfo, _KernelBuildInfo],
        ),
    },
)

def _kernel_kythe_impl(ctx):
    compile_commands = ctx.file.compile_commands
    all_kzip = ctx.actions.declare_file(ctx.attr.name + "/all.kzip")
    runextractor_error = ctx.actions.declare_file(ctx.attr.name + "/runextractor_error.log")
    kzip_dir = all_kzip.dirname + "/intermediates"
    extracted_kzip_dir = all_kzip.dirname + "/extracted"
    transitive_inputs = [src.files for src in ctx.attr.kernel_build[_SrcsInfo].srcs]
    inputs = [compile_commands]
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    command = ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += """
             # Copy compile_commands.json to root
               cp {compile_commands} ${{ROOT_DIR}}
             # Prepare directories
               mkdir -p {kzip_dir} {extracted_kzip_dir} ${{OUT_DIR}}
             # Define env variables
               export KYTHE_ROOT_DIRECTORY=${{ROOT_DIR}}
               export KYTHE_OUTPUT_DIRECTORY={kzip_dir}
               export KYTHE_CORPUS="{corpus}"
             # Generate kzips
               runextractor compdb -extractor $(which cxx_extractor) 2> {runextractor_error} || true

             # Package it all into a single .kzip, ignoring duplicates.
               for zip in $(find {kzip_dir} -name '*.kzip'); do
                   unzip -qn "${{zip}}" -d {extracted_kzip_dir}
               done
               soong_zip -C {extracted_kzip_dir} -D {extracted_kzip_dir} -o {all_kzip}
             # Clean up directories
               rm -rf {kzip_dir}
               rm -rf {extracted_kzip_dir}
    """.format(
        compile_commands = compile_commands.path,
        kzip_dir = kzip_dir,
        extracted_kzip_dir = extracted_kzip_dir,
        corpus = ctx.attr.corpus,
        all_kzip = all_kzip.path,
        runextractor_error = runextractor_error.path,
    )
    ctx.actions.run_shell(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [all_kzip, runextractor_error],
        command = command,
        progress_message = "Building Kythe source code index (kzip) {}".format(ctx.label),
    )

    return DefaultInfo(files = depset([
        all_kzip,
        runextractor_error,
    ]))

kernel_kythe = rule(
    implementation = _kernel_kythe_impl,
    doc = """
Extract Kythe source code index (kzip file) from a `kernel_build`.
    """,
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            doc = "The `kernel_build` target to extract from.",
            providers = [_KernelEnvInfo, _KernelBuildInfo],
            aspects = [_srcs_aspect],
        ),
        "compile_commands": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The `compile_commands.json`, or a `kernel_compile_commands` target.",
        ),
        "corpus": attr.string(
            default = "android.googlesource.com/kernel/superproject",
            doc = "The value of `KYTHE_CORPUS`. See [kythe.io/examples](https://kythe.io/examples).",
        ),
    },
)
