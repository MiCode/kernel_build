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
load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
load("@kernel_toolchain_info//:dict.bzl", "CLANG_VERSION")
load(":constants.bzl", "TOOLCHAIN_VERSION_FILENAME")
load(":hermetic_tools.bzl", "HermeticToolsInfo")
load(":update_source_file.bzl", "update_source_file")
load(
    ":utils.bzl",
    "find_file",
    "find_files",
    "getoptattr",
    "reverse_dict",
)
load(
    "//build/kernel/kleaf/tests:kernel_test.bzl",
    "kernel_build_test",
    "kernel_module_test",
)

# Outputs of a kernel_build rule needed to build kernel_module's
_kernel_build_internal_outs = [
    "Module.symvers",
    "include/config/kernel.release",
]

def _debug_trap():
    return """set -x
              trap '>&2 /bin/date' DEBUG"""

def _debug_print_scripts(ctx, command, what = None):
    if ctx.attr._debug_print_scripts[BuildSettingInfo].value:
        print("""
        # Script that runs %s%s:%s""" % (ctx.label, (" " + what if what else ""), command))

def _filter_module_srcs(files):
    """Create the list of `module_srcs` for a [`kernel_build`] or similar."""
    return [
        s
        for s in files
        if s.path.endswith(".h") or any([token in s.path for token in [
            "Makefile",
            "scripts/",
        ]])
    ]

def _kernel_build_config_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.attr.name + ".generated")
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        cat {srcs} > {out_file}
    """.format(
        srcs = " ".join([src.path for src in ctx.files.srcs]),
        out_file = out_file.path,
    )
    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelBuildConfig",
        inputs = ctx.files.srcs + ctx.attr._hermetic_tools[HermeticToolsInfo].deps,
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
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
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

def _kernel_build_outs_add_vmlinux(name, outs):
    notrim_outs = outs
    added_vmlinux = False
    if notrim_outs == None:
        notrim_outs = ["vmlinux"]
        added_vmlinux = True
    if type(notrim_outs) == type([]):
        if "vmlinux" not in notrim_outs:
            # don't use append to avoid changing outs
            notrim_outs = notrim_outs + ["vmlinux"]
            added_vmlinux = True
    elif type(outs) == type({}):
        notrim_outs_new = {}
        for k, v in notrim_outs.items():
            if "vmlinux" not in v:
                # don't use append to avoid changing outs
                v = v + ["vmlinux"]
                added_vmlinux = True
            notrim_outs_new[k] = v
        notrim_outs = notrim_outs_new
    else:
        fail("{}: Invalid type for outs: {}".format(name, type(outs)))
    return notrim_outs, added_vmlinux

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
        kmi_symbol_list = None,
        additional_kmi_symbol_lists = None,
        trim_nonlisted_kmi = None,
        kmi_symbol_list_strict_mode = None,
        collect_unstripped_modules = None,
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

          If set, the list of files specified in the `DefaultInfo` of the rule specified in
          `base_kernel` is copied to a directory, and `KBUILD_MIXED_TREE` is set to the directory.
          Setting `KBUILD_MIXED_TREE` effectively enables mixed build.

          To set additional flags for mixed build, change `build_config` to a `kernel_build_config`
          rule, with a build config fragment that contains the additional flags.

          The label specified by `base_kernel` must produce a list of files similar
          to what a `kernel_build` rule does. Usually, this points to one of the following:
          - `//common:kernel_{arch}`
          - A `kernel_filegroup` rule, e.g.
            ```
            load("//build/kernel/kleaf:constants.bzl, "aarch64_outs")
            kernel_filegroup(
              name = "my_kernel_filegroup",
              srcs = aarch64_outs,
            )
            ```

        generate_vmlinux_btf: If `True`, generates `vmlinux.btf` that is stripped of any debug
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

            See `search_and_cp_output.py` for details.

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
        kmi_symbol_list: A label referring to the main KMI symbol list file. See `additional_kmi_symbol_list`.

          This is the Bazel equivalent of `ADDTIONAL_KMI_SYMBOL_LISTS`.
        additional_kmi_symbol_list: A list of labels referring to additional KMI symbol list files.

          This is the Bazel equivalent of `ADDTIONAL_KMI_SYMBOL_LISTS`.

          Let
          ```
          all_kmi_symbol_lists = [kmi_symbol_list] + additional_kmi_symbol_list
          ```

          If `all_kmi_symbol_lists` is a non-empty list, `abi_symbollist` and
          `abi_symbollist.report` are created and added to the
          [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html),
          and copied to `DIST_DIR` during distribution.

          If `all_kmi_symbol_lists` is `None` or an empty list, `abi_symbollist` and
          `abi_symbollist.report` are not created.

          It is possible to use a `glob()` to determine whether `abi_symbollist`
          and `abi_symbollist.report` should be generated at build time.
          For example:
          ```
          kmi_symbol_list = "android/abi_gki_aarch64",
          additional_kmi_symbol_lists = glob(["android/abi_gki_aarch64*"], exclude = ["android/abi_gki_aarch64"]),
          ```
        trim_nonlisted_kmi: If `True`, trim symbols not listed in
          `kmi_symbol_list` and `additional_kmi_symbol_lists`.
          This is the Bazel equivalent of `TRIM_NONLISTED_KMI`.

          Requires `all_kmi_symbol_lists` to be non-empty. If `kmi_symbol_list`
          or `additional_kmi_symbol_lists`
          is a `glob()`, it is possible to set `trim_nonlisted_kmi` to be a
          value based on that `glob()`. For example:
          ```
          trim_nonlisted_kmi = len(glob(["android/abi_gki_aarch64*"])) > 0
          ```
        kmi_symbol_list_strict_mode: If `True`, add a build-time check between
          `[kmi_symbol_list] + additional_kmi_symbol_lists`
          and the KMI resulting from the build, to ensure
          they match 1-1.
        collect_unstripped_modules: If `True`, provide all unstripped in-tree.

          Approximately equivalent to `UNSTRIPPED_MODULES=*` in `build.sh`.
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
    kmi_symbol_list_target_name = name + "_kmi_symbol_list"
    abi_symbollist_target_name = name + "_kmi_symbol_list_abi_symbollist"
    raw_kmi_symbol_list_target_name = name + "_raw_kmi_symbol_list"

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

    all_kmi_symbol_lists = []
    if kmi_symbol_list:
        all_kmi_symbol_lists.append(kmi_symbol_list)
    if additional_kmi_symbol_lists:
        all_kmi_symbol_lists += additional_kmi_symbol_lists

    _kmi_symbol_list(
        name = kmi_symbol_list_target_name,
        env = env_target_name,
        srcs = all_kmi_symbol_lists,
    )

    native.filegroup(
        name = abi_symbollist_target_name,
        srcs = [kmi_symbol_list_target_name],
        output_group = "abi_symbollist",
    )

    _raw_kmi_symbol_list(
        name = raw_kmi_symbol_list_target_name,
        env = env_target_name,
        src = abi_symbollist_target_name if all_kmi_symbol_lists else None,
    )

    _kernel_config(
        name = config_target_name,
        env = env_target_name,
        srcs = srcs,
        config = config_target_name + "/.config",
        trim_nonlisted_kmi = trim_nonlisted_kmi,
        raw_kmi_symbol_list = raw_kmi_symbol_list_target_name if all_kmi_symbol_lists else None,
    )

    _modules_prepare(
        name = modules_prepare_target_name,
        config = config_target_name,
        srcs = srcs,
        outdir_tar_gz = modules_prepare_target_name + "/modules_prepare_outdir.tar.gz",
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
        kmi_symbol_list_strict_mode = kmi_symbol_list_strict_mode,
        raw_kmi_symbol_list = raw_kmi_symbol_list_target_name if all_kmi_symbol_lists else None,
        kernel_uapi_headers = uapi_headers_target_name,
        collect_unstripped_modules = collect_unstripped_modules,
        combined_abi_symbollist = abi_symbollist_target_name if all_kmi_symbol_lists else None,
        **kwargs
    )

    # key = attribute name, value = a list of labels for that attribute
    real_outs = {}

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
            real_outs[out_name] = [name + "/" + out for out in out_attr_val]
        elif type(out_attr_val) == type({}):
            # out_attr_val = {config_setting: [out, ...], ...}
            # => reverse_dict = {out: [config_setting, ...], ...}
            for out, config_settings in reverse_dict(out_attr_val).items():
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
            real_outs[out_name] = [name + "/" + out for out, _ in reverse_dict(out_attr_val).items()]
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

    kernel_build_test(
        name = name + "_test",
        target = name,
    )
    kernel_module_test(
        name = name + "_modules_test",
        modules = real_outs.get("module_outs"),
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

def _get_stable_status_cmd(ctx, var):
    return """cat {stable_status} | ( grep -e "^{var} " || true ) | cut -f2- -d' '""".format(
        stable_status = ctx.info_file.path,
        var = var,
    )

def _get_scmversion_cmd(srctree, scmversion):
    """Return a shell script that sets up .scmversion file in the source tree conditionally.

    Args:
      srctree: Path to the source tree where `setlocalversion` were supposed to run with.
      scmversion: The result of executing `setlocalversion` if it were executed on `srctree`.
    """
    return """
         # Set up scm version
           (
              # Save scmversion to .scmversion if .scmversion does not already exist.
              # If it does exist, then it is part of "srcs", so respect its value.
              # If .git exists, we are not in sandbox. Let make calls setlocalversion.
              if [[ ! -d {srctree}/.git ]] && [[ ! -f {srctree}/.scmversion ]]; then
                scmversion={scmversion}
                if [[ -n "${{scmversion}}" ]]; then
                    mkdir -p {srctree}
                    echo $scmversion > {srctree}/.scmversion
                fi
              fi
           )
""".format(
        srctree = srctree,
        scmversion = scmversion,
    )

_KernelEnvInfo = provider(fields = {
    "dependencies": "dependencies required to use this environment setup",
    "setup": "setup script to initialize the environment",
})

def _sanitize_label_as_filename(label):
    """Sanitize a Bazel label so it is safe to be used as a filename."""
    label_text = str(label)
    return "".join([c if c.isalnum() else "_" for c in label_text.elems()])

def _remove_suffix(s, suffix):
    if s.endswith(suffix):
        return s[:-len(suffix)]
    return s

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

    command = ""
    command += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
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

    # If multiple targets have the same KERNEL_DIR are built simultaneously
    # with --spawn_strategy=local, try to isolate their OUT_DIRs.
    command += """
          export OUT_DIR_SUFFIX={name}
    """.format(name = _remove_suffix(_sanitize_label_as_filename(ctx.label), "_env"))

    command += """
        # Increase parallelism # TODO(b/192655643): do not use -j anymore
          export MAKEFLAGS="${{MAKEFLAGS}} -j$(nproc)"
        # Set the value of SOURCE_DATE_EPOCH
          export SOURCE_DATE_EPOCH=$({source_date_epoch_cmd})
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
        source_date_epoch_cmd = _get_stable_status_cmd(ctx, "STABLE_SOURCE_DATE_EPOCH"),
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelEnv",
        inputs = srcs + [
            ctx.file._build_utils_sh,
            build_config,
            setup_env,
            preserve_env,
            ctx.info_file,
        ] + ctx.attr._hermetic_tools[HermeticToolsInfo].deps,
        outputs = [out_file],
        progress_message = "Creating build environment for %s" % ctx.attr.name,
        command = command,
    )

    setup = ""
    setup += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        setup += _debug_trap()

    # workspace_status.py does not prepend BRANCH and KMI_GENERATION before
    # STABLE_SCMVERSION because their values aren't known at that point.
    # Hence, mimic the logic in setlocalversion to prepend them.
    stable_scmversion_cmd = _get_stable_status_cmd(ctx, "STABLE_SCMVERSION")

    # TODO(b/227520025): Deduplicate logic with setlocalversion.
    # Right now, we need this logic for sandboxed builds, and the logic in
    # setlocalversion for non-sandboxed builds.
    set_up_scmversion_cmd = """
        (
            # Extract the Android release version. If there is no match, then return 255
            # and clear the variable $android_release
            set +e
            android_release=$(echo "$BRANCH" | sed -e '/android[0-9]\\{{2,\\}}/!{{q255}}; s/^\\(android[0-9]\\{{2,\\}}\\)-.*/\\1/')
            if [[ $? -ne 0 ]]; then
                android_release=
            fi
            set -e
            if [[ -n "$KMI_GENERATION" ]] && [[ $(expr $KMI_GENERATION : '^[0-9]\\+$') -eq 0 ]]; then
                echo "Invalid KMI_GENERATION $KMI_GENERATION" >&2
                exit 1
            fi
            scmversion=""
            stable_scmversion=$({stable_scmversion_cmd})
            if [[ -n "$stable_scmversion" ]]; then
                scmversion_prefix=
                if [[ -n "$android_release" ]] && [[ -n "$KMI_GENERATION" ]]; then
                    scmversion_prefix="-$android_release-$KMI_GENERATION"
                elif [[ -n "$android_release" ]]; then
                    scmversion_prefix="-$android_release"
                fi
                scmversion="${{scmversion_prefix}}${{stable_scmversion}}"
            fi
            {setup_cmd}
        )
    """.format(
        stable_scmversion_cmd = stable_scmversion_cmd,
        setup_cmd = _get_scmversion_cmd(
            srctree = "${ROOT_DIR}/${KERNEL_DIR}",
            scmversion = "${scmversion}",
        ),
    )

    setup += """
         # error on failures
           set -e
           set -o pipefail
         # utility functions
           source {build_utils_sh}
         # source the build environment
           source {env}
         # re-setup the PATH to also include the hermetic tools, because env completely overwrites
         # PATH with HERMETIC_TOOLCHAIN=1
           {hermetic_tools_additional_setup}
         # setup LD_LIBRARY_PATH for prebuilts
           export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${{ROOT_DIR}}/{linux_x86_libs_path}
           {set_up_scmversion_cmd}
         # Set up KCONFIG_EXT
           if [ -n "${{KCONFIG_EXT}}" ]; then
             export KCONFIG_EXT_PREFIX=$(rel_path $(realpath $(dirname ${{KCONFIG_EXT}})) ${{ROOT_DIR}}/${{KERNEL_DIR}})/
           fi
           if [ -n "${{DTSTREE_MAKEFILE}}" ]; then
             export dtstree=$(rel_path $(realpath $(dirname ${{DTSTREE_MAKEFILE}})) ${{ROOT_DIR}}/${{KERNEL_DIR}})
           fi
           """.format(
        hermetic_tools_additional_setup = ctx.attr._hermetic_tools[HermeticToolsInfo].additional_setup,
        env = out_file.path,
        build_utils_sh = ctx.file._build_utils_sh.path,
        linux_x86_libs_path = ctx.files._linux_x86_libs[0].dirname,
        set_up_scmversion_cmd = set_up_scmversion_cmd,
    )

    dependencies = ctx.files._tools + ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    dependencies += [
        out_file,
        ctx.file._build_utils_sh,
        ctx.info_file,
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
            "//build/kernel:kernel-build-scripts",
            "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
        )
    ]

_KernelToolchainInfo = provider(fields = {
    "toolchain_version": "The toolchain version",
    "toolchain_version_file": "A file containing the toolchain version",
})

def _kernel_toolchain_aspect_impl(target, ctx):
    if ctx.rule.kind == "_kernel_build":
        return ctx.rule.attr.config[_KernelToolchainInfo]
    if ctx.rule.kind == "_kernel_config":
        return ctx.rule.attr.env[_KernelToolchainInfo]
    if ctx.rule.kind == "_kernel_env":
        return _KernelToolchainInfo(toolchain_version = ctx.rule.attr.toolchain_version)

    if ctx.rule.kind == "kernel_filegroup":
        # Create a depset that contains all files referenced by "srcs"
        all_srcs = depset([], transitive = [src.files for src in ctx.rule.attr.srcs])

        # Traverse this depset and look for a file named "toolchain_version".
        # If no file matches, leave it as None so that _kernel_build_check_toolchain prints a
        # warning.
        toolchain_version_file = find_file(name = TOOLCHAIN_VERSION_FILENAME, files = all_srcs.to_list(), what = ctx.label)
        return _KernelToolchainInfo(toolchain_version_file = toolchain_version_file)

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
            default = Label("//build/kernel:_setup_env.sh"),
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
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils.sh"),
        ),
        "_debug_annotate_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_annotate_scripts",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_linux_x86_libs": attr.label(default = "//prebuilts/kernel-build-tools:linux-x86-libs"),
    },
)

def _kernel_config_impl(ctx):
    inputs = [
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
    include_dir = ctx.actions.declare_directory(ctx.attr.name + "_include")

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

    if ctx.attr.trim_nonlisted_kmi and not ctx.file.raw_kmi_symbol_list:
        fail("{}: trim_nonlisted_kmi is set but raw_kmi_symbol_list is empty.".format(ctx.label))

    trim_kmi_command = ""
    if ctx.attr.trim_nonlisted_kmi:
        # We can't use an absolute path in CONFIG_UNUSED_KSYMS_WHITELIST.
        # - ctx.file.raw_kmi_symbol_list is a relative path (e.g.
        #   bazel-out/k8-fastbuild/bin/common/kernel_aarch64_raw_kmi_symbol_list/abi_symbollist.raw)
        # - Canonicalizing the path gives an absolute path into the sandbox of
        #   the _kernel_config rule. The sandbox is destroyed during the
        #   execution of _kernel_build.
        # Hence we use a relative path. In this case, it is
        # interpreted as a path relative to $abs_srctree, which is
        # ${ROOT_DIR}/${KERNEL_DIR}. See common/scripts/gen_autoksyms.sh.
        # Hence we set CONFIG_UNUSED_KSYMS_WHITELIST to the path of abi_symobllist.raw
        # relative to ${KERNEL_DIR}.
        trim_kmi_command = """
            # Modify .config to trim symbols not listed in KMI
              ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config \
                  -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
                  --set-str UNUSED_KSYMS_WHITELIST $(rel_path {raw_kmi_symbol_list} ${{KERNEL_DIR}})
              make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
        """.format(raw_kmi_symbol_list = ctx.file.raw_kmi_symbol_list.path)

        # rel_path requires the file to exist.
        inputs.append(ctx.file.raw_kmi_symbol_list)

    command = ctx.attr.env[_KernelEnvInfo].setup + """
        # Pre-defconfig commands
          eval ${{PRE_DEFCONFIG_CMDS}}
        # Actual defconfig
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} ${{DEFCONFIG}}
        # Post-defconfig commands
          eval ${{POST_DEFCONFIG_CMDS}}
        # LTO configuration
        {lto_command}
        # Trim nonlisted symbols
          {trim_kmi_command}
        # HACK: run syncconfig to avoid re-triggerring kernel_build
          make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} syncconfig
        # Grab outputs
          rsync -aL ${{OUT_DIR}}/.config {config}
          rsync -aL ${{OUT_DIR}}/include/ {include_dir}/
        """.format(
        config = config.path,
        include_dir = include_dir.path,
        lto_command = lto_command,
        trim_kmi_command = trim_kmi_command,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelConfig",
        inputs = inputs,
        outputs = [config, include_dir],
        tools = ctx.attr.env[_KernelEnvInfo].dependencies,
        progress_message = "Creating kernel config %s" % ctx.attr.name,
        command = command,
    )

    setup_deps = ctx.attr.env[_KernelEnvInfo].dependencies + \
                 [config, include_dir]
    setup = ctx.attr.env[_KernelEnvInfo].setup + """
         # Restore kernel config inputs
           mkdir -p ${{OUT_DIR}}/include/
           rsync -aL {config} ${{OUT_DIR}}/.config
           rsync -aL {include_dir}/ ${{OUT_DIR}}/include/
           find ${{OUT_DIR}}/include -type d -exec chmod +w {{}} \\;
    """.format(config = config.path, include_dir = include_dir.path)
    if ctx.file.raw_kmi_symbol_list:
        setup_deps.append(ctx.file.raw_kmi_symbol_list)

    return [
        _KernelEnvInfo(
            dependencies = setup_deps,
            setup = setup,
        ),
        DefaultInfo(files = depset([config, include_dir])),
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
        "lto": attr.label(default = "//build/kernel/kleaf:lto"),
        "trim_nonlisted_kmi": attr.bool(doc = "If true, modify the config to trim non-listed symbols."),
        "raw_kmi_symbol_list": attr.label(
            doc = "Label to abi_symbollist.raw.",
            allow_single_file = True,
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kmi_symbol_list_impl(ctx):
    if not ctx.files.srcs:
        return

    inputs = [] + ctx.files.srcs
    inputs += ctx.attr.env[_KernelEnvInfo].dependencies
    inputs += ctx.files._kernel_abi_scripts

    outputs = []
    out_file = ctx.actions.declare_file("{}/abi_symbollist".format(ctx.attr.name))
    report_file = ctx.actions.declare_file("{}/abi_symbollist.report".format(ctx.attr.name))
    outputs = [out_file, report_file]

    command = ctx.attr.env[_KernelEnvInfo].setup + """
        mkdir -p {out_dir}
        {process_symbols} --out-dir={out_dir} --out-file={out_file_base} \
            --report-file={report_file_base} --in-dir="${{ROOT_DIR}}/${{KERNEL_DIR}}" \
            {srcs}
    """.format(
        process_symbols = ctx.file._process_symbols.path,
        out_dir = out_file.dirname,
        out_file_base = out_file.basename,
        report_file_base = report_file.basename,
        srcs = " ".join(["$(rel_path {} ${{ROOT_DIR}}/${{KERNEL_DIR}})".format(f.path) for f in ctx.files.srcs]),
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KmiSymbolList",
        inputs = inputs,
        outputs = outputs,
        progress_message = "Creating abi_symbollist and report {}".format(ctx.label),
        command = command,
    )

    return [
        DefaultInfo(files = depset(outputs)),
        OutputGroupInfo(abi_symbollist = depset([out_file])),
    ]

_kmi_symbol_list = rule(
    implementation = _kmi_symbol_list_impl,
    doc = "Build abi_symbollist if there are sources, otherwise don't build anything",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "srcs": attr.label_list(
            doc = "`KMI_SYMBOL_LIST` + `ADDTIONAL_KMI_SYMBOL_LISTS`",
            allow_files = True,
        ),
        "_kernel_abi_scripts": attr.label(default = "//build/kernel:kernel-abi-scripts"),
        "_process_symbols": attr.label(default = "//build/kernel:abi/process_symbols", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _raw_kmi_symbol_list_impl(ctx):
    if not ctx.file.src:
        return

    inputs = [ctx.file.src]
    inputs += ctx.files._kernel_abi_scripts
    inputs += ctx.attr.env[_KernelEnvInfo].dependencies

    out_file = ctx.actions.declare_file("{}/abi_symbollist.raw".format(ctx.attr.name))

    command = ctx.attr.env[_KernelEnvInfo].setup + """
        mkdir -p {out_dir}
        cat {src} | {flatten_symbol_list} > {out_file}
    """.format(
        out_dir = out_file.dirname,
        flatten_symbol_list = ctx.file._flatten_symbol_list.path,
        out_file = out_file.path,
        src = ctx.file.src.path,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "RawKmiSymbolList",
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Creating abi_symbollist.raw {}".format(ctx.label),
        command = command,
    )

    return DefaultInfo(files = depset([out_file]))

_raw_kmi_symbol_list = rule(
    implementation = _raw_kmi_symbol_list_impl,
    doc = "Build `abi_symbollist.raw` if `src` refers to a file, otherwise don't build anything",
    attrs = {
        "env": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            doc = "environment target that defines the kernel build environment",
        ),
        "src": attr.label(
            doc = "Label to `abi_symbollist`",
            allow_single_file = True,
        ),
        "_kernel_abi_scripts": attr.label(default = "//build/kernel:kernel-abi-scripts"),
        "_flatten_symbol_list": attr.label(default = "//build/kernel:abi/flatten_symbol_list", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

_KernelBuildInfo = provider(fields = {
    "out_dir_kernel_headers_tar": "Archive containing headers in `OUT_DIR`",
    "outs": "A list of File object corresponding to the `outs` attribute (excluding `module_outs`, `implicit_outs` and `internal_outs`)",
    "base_kernel_files": "[Default outputs](https://docs.bazel.build/versions/main/skylark/rules.html#default-outputs) of the rule specified by `base_kernel`",
    "interceptor_output": "`interceptor` log. See [`interceptor`](https://android.googlesource.com/kernel/tools/interceptor/) project.",
})

_KernelBuildExtModuleInfo = provider(
    doc = "A provider that specifies the expectations of a `_kernel_module` (an external module) or a `kernel_modules_install` from its `kernel_build` attribute.",
    fields = {
        "modules_staging_archive": "Archive containing staging kernel modules. " +
                                   "Does not contain the lib/modules/* suffix.",
        "module_srcs": "sources for this kernel_build for building external modules",
        "modules_prepare_setup": "A command that is equivalent to running `make modules_prepare`. Requires env setup.",
        "modules_prepare_deps": "A list of deps to run `modules_prepare_cmd`.",
        "collect_unstripped_modules": "Whether an external [`kernel_module`](#kernel_module) building against this [`kernel_build`](#kernel_build) should provide unstripped ones for debugging.",
    },
)

_KernelBuildUapiInfo = provider(
    doc = "A provider that specifies the expecation of a `merged_uapi_headers` rule from its `kernel_build` attribute.",
    fields = {
        "base_kernel": "the `base_kernel` target, if exists",
        "kernel_uapi_headers": "the `*_kernel_uapi_headers` target",
    },
)

_KernelBuildAbiInfo = provider(
    doc = "A provider that specifies the expectations of a [`kernel_abi`](#kernel_abi) on a `kernel_build`.",
    fields = {
        "trim_nonlisted_kmi": "Value of `trim_nonlisted_kmi` in [`kernel_build()`](#kernel_build).",
        "combined_abi_symbollist": "The **combined** `abi_symbollist` file from the `_kmi_symbol_list` rule, consist of the source `kmi_symbol_list` and `additional_kmi_symbol_lists`.",
    },
)

_KernelUnstrippedModulesInfo = provider(
    doc = "A provider that provides unstripped modules",
    fields = {
        "base_kernel": "the `base_kernel` target, if exists",
        "directory": """A [`File`](https://bazel.build/rules/lib/File) that
points to a directory containing unstripped modules.

For [`kernel_build()`](#kernel_build), this is a directory containing unstripped in-tree modules.
- This is `None` if and only if `collect_unstripped_modules = False`
- Never `None` if and only if `collect_unstripped_modules = True`
- An empty directory if and only if `collect_unstripped_modules = True` and `module_outs` is empty

For an external [`kernel_module()`](#kernel_module), this is a directory containing unstripped external modules.
- This is `None` if and only if the `kernel_build` argument has `collect_unstripped_modules = False`
- Never `None` if and only if the `kernel_build` argument has `collect_unstripped_modules = True`
""",
    },
)

_SrcsInfo = provider(fields = {
    "srcs": "The srcs attribute of a rule.",
})

def _srcs_aspect_impl(target, ctx):
    return [_SrcsInfo(srcs = getoptattr(ctx.rule.attr, "srcs"))]

_srcs_aspect = aspect(
    implementation = _srcs_aspect_impl,
    doc = "An aspect that retrieves srcs attribute from a rule.",
    attr_aspects = ["srcs"],
)

def _kernel_build_check_toolchain(ctx):
    """
    Check toolchain_version is the same as base_kernel.
    """

    base_kernel = ctx.attr.base_kernel
    this_toolchain = ctx.attr.config[_KernelToolchainInfo].toolchain_version
    base_toolchain = getoptattr(base_kernel[_KernelToolchainInfo], "toolchain_version")
    base_toolchain_file = getoptattr(base_kernel[_KernelToolchainInfo], "toolchain_version_file")

    if base_toolchain == None and base_toolchain_file == None:
        print(("\nWARNING: {this_label}: No check is performed between the toolchain " +
               "version of the base build ({base_kernel}) and the toolchain version of " +
               "{this_name} ({this_toolchain}), because the toolchain version of {base_kernel} " +
               "is unknown.").format(
            this_label = ctx.label,
            base_kernel = base_kernel.label,
            this_name = ctx.label.name,
            this_toolchain = this_toolchain,
        ))
        return

    if base_toolchain != None and this_toolchain != base_toolchain:
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
            base_kernel = base_kernel.label,
            base_toolchain = base_toolchain,
        ))

    if base_toolchain_file != None:
        out = ctx.actions.declare_file("{}_toolchain_version/toolchain_version_checked")
        base_toolchain = "$(cat {})".format(base_toolchain_file.path)
        msg = """ERROR: toolchain_version is {this_toolchain} for {this_label}, but
       toolchain_version is {base_toolchain} for {base_kernel} (base_kernel).
       They must use the same toolchain_version.

       Fix by setting toolchain_version of {this_label} to be {base_toolchain}.
""".format(
            this_label = ctx.label,
            this_toolchain = this_toolchain,
            base_kernel = base_kernel.label,
            base_toolchain = base_toolchain,
        )
        command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
                # Check toolchain_version against base kernel
                  if ! diff <(cat {base_toolchain_file}) <(echo "{this_toolchain}") > /dev/null; then
                    echo "{msg}" >&2
                    exit 1
                  fi
                  touch {out}
        """.format(
            base_toolchain_file = base_toolchain_file.path,
            this_toolchain = this_toolchain,
            msg = msg,
            out = out.path,
        )

        _debug_print_scripts(ctx, command, what = "check_toolchain")
        ctx.actions.run_shell(
            mnemonic = "KernelBuildCheckToolchain",
            inputs = [base_toolchain_file] + ctx.attr._hermetic_tools[HermeticToolsInfo].deps,
            outputs = [out],
            command = command,
            progress_message = "Checking toolchain version against base kernel {}".format(ctx.label),
        )
        return out

def _kernel_build_dump_toolchain_version(ctx):
    this_toolchain = ctx.attr.config[_KernelToolchainInfo].toolchain_version
    out = ctx.actions.declare_file("{}_toolchain_version/{}".format(ctx.attr.name, TOOLCHAIN_VERSION_FILENAME))
    ctx.actions.write(
        output = out,
        content = this_toolchain + "\n",
    )
    return out

def _kmi_symbol_list_strict_mode(ctx, all_output_files, all_module_names_file):
    """Run for `KMI_SYMBOL_LIST_STRICT_MODE`.
    """
    if not ctx.attr.kmi_symbol_list_strict_mode:
        return None
    if not ctx.file.raw_kmi_symbol_list:
        fail("{}: kmi_symbol_list_strict_mode requires kmi_symbol_list or additional_kmi_symbol_lists.")

    vmlinux = all_output_files["outs"].get("vmlinux")
    if not vmlinux:
        fail("{}: with kmi_symbol_list_strict_mode, outs does not contain vmlinux")
    module_symvers = all_output_files["internal_outs"].get("Module.symvers")
    if not module_symvers:
        fail("{}: with kmi_symbol_list_strict_mode, outs does not contain module_symvers")

    inputs = [
        module_symvers,
        ctx.file.raw_kmi_symbol_list,
        all_module_names_file,
    ]
    inputs += ctx.files._kernel_abi_scripts
    inputs += ctx.attr.config[_KernelEnvInfo].dependencies

    out = ctx.actions.declare_file("{}_kmi_strict_out/kmi_symbol_list_strict_mode_checked".format(ctx.attr.name))
    command = ctx.attr.config[_KernelEnvInfo].setup + """
        KMI_STRICT_MODE_OBJECTS="{vmlinux_base} $(cat {all_module_names_file} | sed 's/\\.ko$//')" {compare_to_symbol_list} {module_symvers} {raw_kmi_symbol_list}
        touch {out}
    """.format(
        vmlinux_base = vmlinux.basename,  # A fancy way of saying "vmlinux"
        all_module_names_file = all_module_names_file.path,
        compare_to_symbol_list = ctx.file._compare_to_symbol_list.path,
        module_symvers = module_symvers.path,
        raw_kmi_symbol_list = ctx.file.raw_kmi_symbol_list.path,
        out = out.path,
    )
    _debug_print_scripts(ctx, command, what = "kmi_symbol_list_strict_mode")
    ctx.actions.run_shell(
        mnemonic = "KernelBuildKmiSymbolListStrictMode",
        inputs = inputs,
        outputs = [out],
        command = command,
        progress_message = "Checking for kmi_symbol_list_strict_mode {}".format(ctx.label),
    )
    return out

def _kernel_build_impl(ctx):
    kbuild_mixed_tree = None
    base_kernel_files = []
    check_toolchain_out = None
    if ctx.attr.base_kernel:
        check_toolchain_out = _kernel_build_check_toolchain(ctx)

        # Create a directory for KBUILD_MIXED_TREE. Flatten the directory structure of the files
        # that ctx.attr.base_kernel provides. declare_directory is sufficient because the directory should
        # only change when the dependent ctx.attr.base_kernel changes.
        kbuild_mixed_tree = ctx.actions.declare_directory("{}_kbuild_mixed_tree".format(ctx.label.name))
        base_kernel_files = ctx.files.base_kernel
        kbuild_mixed_tree_command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
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
        _debug_print_scripts(ctx, kbuild_mixed_tree_command, what = "kbuild_mixed_tree")
        ctx.actions.run_shell(
            mnemonic = "KernelBuildKbuildMixedTree",
            inputs = base_kernel_files + ctx.attr._hermetic_tools[HermeticToolsInfo].deps,
            outputs = [kbuild_mixed_tree],
            progress_message = "Creating KBUILD_MIXED_TREE",
            command = kbuild_mixed_tree_command,
        )

    ruledir = ctx.actions.declare_directory(ctx.label.name)

    inputs = [
        ctx.file._search_and_cp_output,
        ctx.file._check_declared_output_list,
    ]
    inputs += ctx.files.srcs
    inputs += ctx.files.deps
    if check_toolchain_out:
        inputs.append(check_toolchain_out)
    if kbuild_mixed_tree:
        inputs.append(kbuild_mixed_tree)

    # kernel_build(name="kernel", outs=["out"])
    # => _kernel_build(name="kernel", outs=["kernel/out"], internal_outs=["kernel/Module.symvers", ...])
    # => all_output_names = ["foo", "Module.symvers", ...]
    #    all_output_files = {"out": {"foo": File(...)}, "internal_outs": {"Module.symvers": File(...)}, ...}
    all_output_files = {}
    for attr in ("outs", "module_outs", "implicit_outs", "internal_outs"):
        all_output_files[attr] = {name: ctx.actions.declare_file("{}/{}".format(ctx.label.name, name)) for name in getattr(ctx.attr, attr)}
    all_output_names_minus_modules = []
    for attr, d in all_output_files.items():
        if attr != "module_outs":
            all_output_names_minus_modules += d.keys()

    # A file containing all module_outs
    all_module_names = all_output_files["module_outs"].keys()
    all_module_names_file = ctx.actions.declare_file("{}_all_module_names/all_module_names.txt".format(ctx.label.name))
    ctx.actions.write(
        output = all_module_names_file,
        content = "\n".join(all_module_names) + "\n",
    )
    inputs.append(all_module_names_file)

    modules_staging_archive = ctx.actions.declare_file(
        "{name}/modules_staging_dir.tar.gz".format(name = ctx.label.name),
    )
    out_dir_kernel_headers_tar = ctx.actions.declare_file(
        "{name}/out-dir-kernel-headers.tar.gz".format(name = ctx.label.name),
    )
    interceptor_output = ctx.actions.declare_file("{name}/interceptor_output.bin".format(name = ctx.label.name))
    modules_staging_dir = modules_staging_archive.dirname + "/staging"

    unstripped_dir = None
    if ctx.attr.collect_unstripped_modules:
        unstripped_dir = ctx.actions.declare_directory("{name}/unstripped".format(name = ctx.label.name))

    # all outputs that |command| generates
    command_outputs = [
        ruledir,
        modules_staging_archive,
        out_dir_kernel_headers_tar,
        interceptor_output,
    ]
    for d in all_output_files.values():
        command_outputs += d.values()
    if unstripped_dir:
        command_outputs.append(unstripped_dir)

    command = ""
    command += ctx.attr.config[_KernelEnvInfo].setup

    if kbuild_mixed_tree:
        command += """
                   export KBUILD_MIXED_TREE=$(realpath {kbuild_mixed_tree})
        """.format(
            kbuild_mixed_tree = kbuild_mixed_tree.path,
        )

    grab_intree_modules_cmd = ""
    if all_module_names:
        grab_intree_modules_cmd = """
            {search_and_cp_output} --srcdir {modules_staging_dir}/lib/modules/*/kernel --dstdir {ruledir} $(cat {all_module_names_file})
        """.format(
            search_and_cp_output = ctx.file._search_and_cp_output.path,
            modules_staging_dir = modules_staging_dir,
            ruledir = ruledir.path,
            all_module_names_file = all_module_names_file.path,
        )

    grab_unstripped_intree_modules_cmd = ""
    if all_module_names and unstripped_dir:
        grab_unstripped_intree_modules_cmd = """
            mkdir -p {unstripped_dir}
            {search_and_cp_output} --srcdir ${{OUT_DIR}} --dstdir {unstripped_dir} $(cat {all_module_names_file})
        """.format(
            search_and_cp_output = ctx.file._search_and_cp_output.path,
            unstripped_dir = unstripped_dir.path,
            all_module_names_file = all_module_names_file.path,
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
           {search_and_cp_output} --srcdir ${{OUT_DIR}} {kbuild_mixed_tree_arg} {dtstree_arg} --dstdir {ruledir} {all_output_names_minus_modules}
         # Archive modules_staging_dir
           tar czf {modules_staging_archive} -C {modules_staging_dir} .
         # Grab in-tree modules
           {grab_intree_modules_cmd}
         # Grab unstripped in-tree modules
           {grab_unstripped_intree_modules_cmd}
         # Check if there are remaining *.ko files
           remaining_ko_files=$({check_declared_output_list} \\
                --declared $(cat {all_module_names_file}) \\
                --actual $(cd {modules_staging_dir}/lib/modules/*/kernel && find . -type f -name '*.ko' | sed 's:^./::'))
           if [[ ${{remaining_ko_files}} ]]; then
             echo "ERROR: The following kernel modules are built but not copied. Add these lines to the module_outs attribute of {label}:" >&2
             for ko in ${{remaining_ko_files}}; do
               echo '    "'"${{ko}}"'",' >&2
             done
             exit 1
           fi
         # Clean up staging directories
           rm -rf {modules_staging_dir}
         """.format(
        check_declared_output_list = ctx.file._check_declared_output_list.path,
        search_and_cp_output = ctx.file._search_and_cp_output.path,
        kbuild_mixed_tree_arg = "--srcdir ${KBUILD_MIXED_TREE}" if kbuild_mixed_tree else "",
        dtstree_arg = "--srcdir ${OUT_DIR}/${dtstree}",
        ruledir = ruledir.path,
        all_output_names_minus_modules = " ".join(all_output_names_minus_modules),
        grab_intree_modules_cmd = grab_intree_modules_cmd,
        grab_unstripped_intree_modules_cmd = grab_unstripped_intree_modules_cmd,
        all_module_names_file = all_module_names_file.path,
        modules_staging_dir = modules_staging_dir,
        modules_staging_archive = modules_staging_archive.path,
        out_dir_kernel_headers_tar = out_dir_kernel_headers_tar.path,
        interceptor_output = interceptor_output.path,
        label = ctx.label,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelBuild",
        inputs = inputs,
        outputs = command_outputs,
        tools = ctx.attr.config[_KernelEnvInfo].dependencies,
        progress_message = "Building kernel %s" % ctx.attr.name,
        command = command,
    )

    toolchain_version_out = _kernel_build_dump_toolchain_version(ctx)
    kmi_strict_mode_out = _kmi_symbol_list_strict_mode(ctx, all_output_files, all_module_names_file)

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

    module_srcs = _filter_module_srcs(ctx.files.srcs)

    kernel_build_info = _KernelBuildInfo(
        out_dir_kernel_headers_tar = out_dir_kernel_headers_tar,
        outs = all_output_files["outs"].values(),
        base_kernel_files = base_kernel_files,
        interceptor_output = interceptor_output,
    )

    kernel_build_module_info = _KernelBuildExtModuleInfo(
        modules_staging_archive = modules_staging_archive,
        module_srcs = module_srcs,
        modules_prepare_setup = ctx.attr.modules_prepare[_KernelEnvInfo].setup,
        modules_prepare_deps = ctx.attr.modules_prepare[_KernelEnvInfo].dependencies,
        collect_unstripped_modules = ctx.attr.collect_unstripped_modules,
    )

    kernel_build_uapi_info = _KernelBuildUapiInfo(
        base_kernel = ctx.attr.base_kernel,
        kernel_uapi_headers = ctx.attr.kernel_uapi_headers,
    )

    kernel_build_abi_info = _KernelBuildAbiInfo(
        trim_nonlisted_kmi = ctx.attr.trim_nonlisted_kmi,
        combined_abi_symbollist = ctx.file.combined_abi_symbollist,
    )

    kernel_unstripped_modules_info = _KernelUnstrippedModulesInfo(
        base_kernel = ctx.attr.base_kernel,
        directory = unstripped_dir,
    )

    output_group_kwargs = {}
    for d in all_output_files.values():
        output_group_kwargs.update({name: depset([file]) for name, file in d.items()})
    output_group_kwargs["modules_staging_archive"] = depset([modules_staging_archive])
    output_group_info = OutputGroupInfo(**output_group_kwargs)

    default_info_files = all_output_files["outs"].values() + all_output_files["module_outs"].values()
    default_info_files.append(toolchain_version_out)
    if kmi_strict_mode_out:
        default_info_files.append(kmi_strict_mode_out)
    default_info = DefaultInfo(
        files = depset(default_info_files),
        # For kernel_build_test
        runfiles = ctx.runfiles(files = default_info_files),
    )

    return [
        env_info,
        kernel_build_info,
        kernel_build_module_info,
        kernel_build_uapi_info,
        kernel_build_abi_info,
        kernel_unstripped_modules_info,
        output_group_info,
        default_info,
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
        "_check_declared_output_list": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:check_declared_output_list.py"),
        ),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
            doc = "label referring to the script to process outputs",
        ),
        "deps": attr.label_list(
            allow_files = True,
        ),
        "base_kernel": attr.label(
            aspects = [_kernel_toolchain_aspect],
        ),
        "kmi_symbol_list_strict_mode": attr.bool(),
        "raw_kmi_symbol_list": attr.label(
            doc = "Label to abi_symbollist.raw.",
            allow_single_file = True,
        ),
        "collect_unstripped_modules": attr.bool(),
        "_kernel_abi_scripts": attr.label(default = "//build/kernel:kernel-abi-scripts"),
        "_compare_to_symbol_list": attr.label(default = "//build/kernel:abi/compare_to_symbol_list", allow_single_file = True),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        # Though these rules are unrelated to the `_kernel_build` rule, they are added as fake
        # dependencies so _KernelBuildExtModuleInfo and _KernelBuildUapiInfo works.
        # There are no real dependencies. Bazel does not build these targets before building the
        # `_kernel_build` target.
        "modules_prepare": attr.label(),
        "kernel_uapi_headers": attr.label(),
        "trim_nonlisted_kmi": attr.bool(),
        "combined_abi_symbollist": attr.label(allow_single_file = True, doc = "The **combined** `abi_symbollist` file, consist of `kmi_symbol_list` and `additional_kmi_symbol_lists`."),
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
        mnemonic = "ModulesPrepare",
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

    inputs = []
    inputs += ctx.files.srcs
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[_KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.attr.kernel_build[_KernelBuildExtModuleInfo].module_srcs
    inputs += ctx.files.makefile
    inputs += [
        ctx.file._search_and_cp_output,
    ]
    for kernel_module_dep in ctx.attr.kernel_module_deps:
        inputs += kernel_module_dep[_KernelEnvInfo].dependencies

    modules_staging_archive = ctx.actions.declare_file("{}/modules_staging_archive.tar.gz".format(ctx.attr.name))
    modules_staging_dir = modules_staging_archive.dirname + "/staging"
    kernel_uapi_headers_archive = ctx.actions.declare_file("{}/kernel-uapi-headers.tar.gz".format(ctx.attr.name))
    kernel_uapi_headers_dir = kernel_uapi_headers_archive.dirname + "/kernel-uapi-headers.tar.gz_staging"
    outdir = modules_staging_archive.dirname  # equivalent to declare_directory(ctx.attr.name)

    unstripped_dir = None
    if ctx.attr.kernel_build[_KernelBuildExtModuleInfo].collect_unstripped_modules:
        unstripped_dir = ctx.actions.declare_directory("{name}/unstripped".format(name = ctx.label.name))

    # additional_outputs: archives + unstripped + [basename(out) for out in outs]
    additional_outputs = [
        modules_staging_archive,
        kernel_uapi_headers_archive,
    ]
    if unstripped_dir:
        additional_outputs.append(unstripped_dir)

    # Original `outs` attribute of `kernel_module` macro.
    original_outs = []

    # apply basename to all of original_outs
    original_outs_base = []
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
        original_outs_base.append(out.basename)

    module_symvers = ctx.actions.declare_file("{}/Module.symvers".format(ctx.attr.name))
    additional_declared_outputs = [
        module_symvers,
    ]

    command = ""
    command += ctx.attr.kernel_build[_KernelEnvInfo].setup
    command += ctx.attr.kernel_build[_KernelBuildExtModuleInfo].modules_prepare_setup
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

    grab_unstripped_cmd = ""
    if unstripped_dir:
        grab_unstripped_cmd = """
            mkdir -p {unstripped_dir}
            {search_and_cp_output} --srcdir ${{OUT_DIR}}/${{ext_mod_rel}} --dstdir {unstripped_dir} {outs}
        """.format(
            search_and_cp_output = ctx.file._search_and_cp_output.path,
            unstripped_dir = unstripped_dir.path,
            # Use basenames to flatten the unstripped directory, even though outs may contain items with slash.
            outs = " ".join(original_outs_base),
        )

    # {ext_mod}:{scmversion} {ext_mod}:{scmversion} ...
    scmversion_cmd = _get_stable_status_cmd(ctx, "STABLE_SCMVERSION_EXT_MOD")
    scmversion_cmd += """ | sed -n 's|.*\\<{ext_mod}:\\(\\S\\+\\).*|\\1|p'""".format(ext_mod = ctx.attr.ext_mod)

    # workspace_status.py does not set STABLE_SCMVERSION if setlocalversion
    # should not run on KERNEL_DIR. However, for STABLE_SCMVERSION_EXT_MOD,
    # we may have a missing item if setlocalversion should not run in
    # a certain directory. Hence, be lenient about failures.
    scmversion_cmd += " || true"

    command += _get_scmversion_cmd(
        srctree = "${{ROOT_DIR}}/{ext_mod}".format(ext_mod = ctx.attr.ext_mod),
        scmversion = "$({})".format(scmversion_cmd),
    )

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
               {search_and_cp_output} --srcdir {modules_staging_dir}/lib/modules/*/extra/{ext_mod}/ --dstdir {outdir} {outs}
             # Grab unstripped modules
               {grab_unstripped_cmd}
             # Create headers archive
               tar czf {kernel_uapi_headers_archive} --directory={kernel_uapi_headers_dir} usr/
             # Remove staging dirs because they are not declared
               rm -rf {modules_staging_dir} {kernel_uapi_headers_dir}
             # Move Module.symvers
               mv ${{OUT_DIR}}/${{ext_mod_rel}}/Module.symvers {module_symvers}
               """.format(
        ext_mod = ctx.attr.ext_mod,
        search_and_cp_output = ctx.file._search_and_cp_output.path,
        module_symvers = module_symvers.path,
        modules_staging_dir = modules_staging_dir,
        modules_staging_archive = modules_staging_archive.path,
        outdir = outdir,
        outs = " ".join(original_outs),
        modules_staging_outs = " ".join(modules_staging_outs),
        kernel_uapi_headers_archive = kernel_uapi_headers_archive.path,
        kernel_uapi_headers_dir = kernel_uapi_headers_dir,
        grab_unstripped_cmd = grab_unstripped_cmd,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelModule",
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
        DefaultInfo(
            files = depset(ctx.outputs.outs),
            # For kernel_module_test
            runfiles = ctx.runfiles(files = ctx.outputs.outs),
        ),
        _KernelEnvInfo(
            dependencies = additional_declared_outputs,
            setup = setup,
        ),
        _KernelModuleInfo(
            kernel_build = ctx.attr.kernel_build,
            modules_staging_archive = modules_staging_archive,
            kernel_uapi_headers_archive = kernel_uapi_headers_archive,
        ),
        _KernelUnstrippedModulesInfo(
            directory = unstripped_dir,
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
            providers = [_KernelEnvInfo, _KernelBuildExtModuleInfo],
        ),
        "kernel_module_deps": attr.label_list(
            providers = [_KernelEnvInfo, _KernelModuleInfo],
        ),
        "ext_mod": attr.string(mandatory = True),
        # Not output_list because it is not a list of labels. The list of
        # output labels are inferred from name and outs.
        "outs": attr.output_list(),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
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

            See `search_and_cp_output.py` for details.
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

    kernel_module_test(
        name = name + "_test",
        modules = [name],
    )

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

    # A list of declared files for outputs of kernel_module rules
    external_modules = []

    inputs = []
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += ctx.attr.kernel_build[_KernelBuildExtModuleInfo].modules_prepare_deps
    inputs += ctx.attr.kernel_build[_KernelBuildExtModuleInfo].module_srcs
    inputs += [
        ctx.file._search_and_cp_output,
        ctx.file._check_duplicated_files_in_archives,
        ctx.attr.kernel_build[_KernelBuildExtModuleInfo].modules_staging_archive,
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
    command += ctx.attr.kernel_build[_KernelBuildExtModuleInfo].modules_prepare_setup
    command += """
             # create dirs for modules
               mkdir -p {modules_staging_dir}
             # Restore modules_staging_dir from kernel_build
               tar xf {kernel_build_modules_staging_archive} -C {modules_staging_dir}
               modules_staging_archives="{kernel_build_modules_staging_archive}"
    """.format(
        modules_staging_dir = modules_staging_dir,
        kernel_build_modules_staging_archive =
            ctx.attr.kernel_build[_KernelBuildExtModuleInfo].modules_staging_archive.path,
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
                   {search_and_cp_output} --srcdir {modules_staging_dir}/lib/modules/*/extra --dstdir {outdir} {filenames}
        """.format(
            modules_staging_dir = modules_staging_dir,
            outdir = external_module_dir,
            filenames = " ".join([declared_file.basename for declared_file in external_modules]),
            search_and_cp_output = ctx.file._search_and_cp_output.path,
        )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelModulesInstall",
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
            providers = [_KernelEnvInfo, _KernelBuildExtModuleInfo],
            doc = "Label referring to the `kernel_build` module.",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_check_duplicated_files_in_archives": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:check_duplicated_files_in_archives.py"),
            doc = "Label referring to the script to process outputs",
        ),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
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
        mnemonic = "KernelUapiHeaders",
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
        "srcs": attr.label_list(allow_files = True),
        "config": attr.label(
            mandatory = True,
            providers = [_KernelEnvInfo],
            doc = "the kernel_config target",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _merged_kernel_uapi_headers_impl(ctx):
    kernel_build = ctx.attr.kernel_build
    base_kernel = kernel_build[_KernelBuildUapiInfo].base_kernel

    # Early elements = higher priority
    srcs = []
    if base_kernel:
        srcs += base_kernel[_KernelBuildUapiInfo].kernel_uapi_headers.files.to_list()
    srcs += kernel_build[_KernelBuildUapiInfo].kernel_uapi_headers.files.to_list()
    for kernel_module in ctx.attr.kernel_modules:
        srcs.append(kernel_module[_KernelModuleInfo].kernel_uapi_headers_archive)

    inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + srcs

    out_file = ctx.actions.declare_file("{}/kernel-uapi-headers.tar.gz".format(ctx.attr.name))
    intermediates_dir = out_file.dirname + "/intermediates"

    command = ""
    command += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    command += """
        mkdir -p {intermediates_dir}
    """.format(
        intermediates_dir = intermediates_dir,
    )

    # Extract the source tarballs in low to high priority order.
    for src in reversed(srcs):
        command += """
            tar xf {src} -C {intermediates_dir}
        """.format(
            src = src.path,
            intermediates_dir = intermediates_dir,
        )

    command += """
        tar czf {out_file} -C {intermediates_dir} usr/
        rm -rf {intermediates_dir}
    """.format(
        out_file = out_file.path,
        intermediates_dir = intermediates_dir,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Merging kernel-uapi-headers.tar.gz {}".format(ctx.label),
        command = command,
        mnemonic = "MergedKernelUapiHeaders",
    )
    return DefaultInfo(files = depset([out_file]))

merged_kernel_uapi_headers = rule(
    implementation = _merged_kernel_uapi_headers_impl,
    doc = """Merge `kernel-uapi-headers.tar.gz`.

On certain devices, kernel modules install additional UAPI headers. Use this
rule to add these module UAPI headers to the final `kernel-uapi-headers.tar.gz`.

If there are conflicts of file names in the source tarballs, files higher in
the list have higher priority:
1. UAPI headers from the `base_kernel` of the `kernel_build` (ususally the GKI build)
2. UAPI headers from the `kernel_build` (usually the device build)
3. UAPI headers from ``kernel_modules`. Order among the modules are undetermined.
""",
    attrs = {
        "kernel_build": attr.label(
            doc = "The `kernel_build`",
            mandatory = True,
            providers = [_KernelBuildUapiInfo],
        ),
        "kernel_modules": attr.label_list(
            doc = """A list of external `kernel_module`s to merge `kernel-uapi-headers.tar.gz`""",
            providers = [_KernelModuleInfo],
        ),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
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
        mnemonic = "KernelHeaders",
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
        "srcs": attr.label_list(allow_files = True),
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
        mnemonic = "VmlinuxBtf",
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
        additional_inputs = None,
        mnemonic = None):
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
    system_map = find_file(
        name = "System.map",
        files = kernel_build_outs,
        required = True,
        what = "{}: outs of dependent kernel_build {}".format(ctx.label, kernel_build),
    )
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

    for attr_name in (
        "modules_list",
        "modules_blocklist",
        "modules_options",
        "vendor_dlkm_modules_list",
        "vendor_dlkm_modules_blocklist",
        "vendor_dlkm_props",
    ):
        # Checks if attr_name is a valid attribute name in the current rule.
        # If not, do not touch its value.
        if not hasattr(ctx.file, attr_name):
            continue

        # If it is a valid attribute name, set environment variable to the path if the argument is
        # supplied, otherwise set environment variable to empty.
        file = getattr(ctx.file, attr_name)
        path = ""
        if file != None:
            path = file.path
            inputs.append(file)
        command += """
            {name}={path}
        """.format(
            name = attr_name.upper(),
            path = path,
        )

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
        mnemonic = mnemonic,
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
        mnemonic = "Initramfs",
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
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
        "modules_options": attr.label(allow_single_file = True),
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
               avbtool add_hashtree_footer \
                   --partition_name system_dlkm \
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
        mnemonic = "SystemDlkmImage",
    )
    return [default_info]

_system_dlkm_image = rule(
    implementation = _system_dlkm_image_impl,
    doc = """Build system_dlkm.img an erofs image with GKI modules.

When included in a `copy_to_dist_dir` rule, this rule copies the `system_dlkm.img` to `DIST_DIR`.

""",
    attrs = _build_modules_image_attrs_common({
        "modules_list": attr.label(allow_single_file = True),
        "modules_blocklist": attr.label(allow_single_file = True),
    }),
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
        mnemonic = "VendorDlkmImage",
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
        "vendor_dlkm_modules_list": attr.label(allow_single_file = True),
        "vendor_dlkm_modules_blocklist": attr.label(allow_single_file = True),
        "vendor_dlkm_props": attr.label(allow_single_file = True),
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
        ctx.file._search_and_cp_output,
    ]
    inputs += ctx.files.deps
    inputs += ctx.attr.kernel_build[_KernelEnvInfo].dependencies
    inputs += kernel_build_outs
    inputs += ctx.files.vendor_ramdisk_binaries

    command = ""
    command += ctx.attr.kernel_build[_KernelEnvInfo].setup

    vendor_boot_flag_cmd = ""
    if not ctx.attr.build_vendor_boot:
        vendor_boot_flag_cmd = "SKIP_VENDOR_BOOT=1"

    if ctx.files.vendor_ramdisk_binaries:
        # build_utils.sh uses singular VENDOR_RAMDISK_BINARY
        command += """
            VENDOR_RAMDISK_BINARY="{vendor_ramdisk_binaries}"
        """.format(
            vendor_ramdisk_binaries = " ".join([file.path for file in ctx.files.vendor_ramdisk_binaries]),
        )

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
                 {vendor_boot_flag_cmd}
                 INITRAMFS_STAGING_DIR={initramfs_staging_dir}
                 MKBOOTIMG_STAGING_DIR=$(realpath {mkbootimg_staging_dir})
                 build_boot_images
               )
               {search_and_cp_output} --srcdir ${{DIST_DIR}} --dstdir {outdir} {outs}
             # Remove staging directories
               rm -rf {modules_staging_dir}
    """.format(
        initramfs_staging_dir = initramfs_staging_dir,
        mkbootimg_staging_dir = mkbootimg_staging_dir,
        search_and_cp_output = ctx.file._search_and_cp_output.path,
        outdir = outdir.path,
        outs = " ".join(outs),
        modules_staging_dir = modules_staging_dir,
        initramfs_staging_archive = initramfs_staging_archive.path,
        initramfs_img = ctx.attr.initramfs[_InitramfsInfo].initramfs_img.path,
        kernel_build_outs = " ".join([out.path for out in kernel_build_outs]),
        vendor_boot_flag_cmd = vendor_boot_flag_cmd,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "BootImages",
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
        "build_vendor_boot": attr.bool(),
        "vendor_ramdisk_binaries": attr.label_list(allow_files = True),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
        "_search_and_cp_output": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:search_and_cp_output.py"),
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
        mnemonic = "Dtbo",
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
        build_boot = None,
        build_vendor_boot = None,
        build_system_dlkm = None,
        build_dtbo = None,
        dtbo_srcs = None,
        mkbootimg = None,
        deps = None,
        boot_image_outs = None,
        modules_list = None,
        modules_blocklist = None,
        modules_options = None,
        vendor_ramdisk_binaries = None,
        vendor_dlkm_modules_list = None,
        vendor_dlkm_modules_blocklist = None,
        vendor_dlkm_props = None):
    """Build multiple kernel images.

    Args:
        name: name of this rule, e.g. `kernel_images`,
        kernel_modules_install: A `kernel_modules_install` rule.

          The main kernel build is inferred from the `kernel_build` attribute of the
          specified `kernel_modules_install` rule. The main kernel build must contain
          `System.map` in `outs` (which is included if you use `aarch64_outs` or
          `x86_64_outs` from `common_kernels.bzl`).
        kernel_build: A `kernel_build` rule. Must specify if `build_boot`.
        mkbootimg: Path to the mkbootimg.py script which builds boot.img.
          Keep in sync with `MKBOOTIMG_PATH`. Only used if `build_boot`. If `None`,
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
          `build_boot_images` in `build/kernel/build_utils.sh` is executed.

          You may leave out `vendor_boot.img` from the list. It is automatically added when
          `build_vendor_boot = True`.

          If `build_boot` is equal to `False`, the default is empty.

          If `build_boot` is equal to `True`, the default list assumes the following:
          - `BOOT_IMAGE_FILENAME` is not set (which takes default value `boot.img`), or is set to
            `"boot.img"`
          - `vendor_boot.img` if `build_vendor_boot`
          - `RAMDISK_EXT=lz4`. If the build configuration has a different value, replace
            `ramdisk.lz4` with `ramdisk.{RAMDISK_EXT}` accordingly.
          - `BOOT_IMAGE_HEADER_VERSION >= 4`, which creates `vendor-bootconfig.img` to contain
            `VENDOR_BOOTCONFIG`
          - The list contains `dtb.img`
        build_initramfs: Whether to build initramfs. Keep in sync with `BUILD_INITRAMFS`.
        build_system_dlkm: Whether to build system_dlkm.img an erofs image with GKI modules.
        build_vendor_dlkm: Whether to build `vendor_dlkm` image. It must be set if
          `vendor_dlkm_modules_list` is set.

          Note: at the time of writing (Jan 2022), unlike `build.sh`,
          `vendor_dlkm.modules.blocklist` is **always** created
          regardless of the value of `VENDOR_DLKM_MODULES_BLOCKLIST`.
          If `build_vendor_dlkm()` in `build_utils.sh` does not generate
          `vendor_dlkm.modules.blocklist`, an empty file is created.
        build_boot: Whether to build boot image. It must be set if either `BUILD_BOOT_IMG`
          or `BUILD_VENDOR_BOOT_IMG` is set.

          This depends on `initramfs` and `kernel_build`. Hence, if this is set to `True`,
          `build_initramfs` is implicitly true, and `kernel_build` must be set.
        build_vendor_boot: Whether to build `vendor_boot` image. It must be set if either
          `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set.

          If `True`, requires `build_boot = True`.

          If `True`, adds `vendor-boot.img` to `boot_image_outs` if not already in the list.
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
        modules_list: A file containing list of modules to use for `vendor_boot.modules.load`.

          This corresponds to `MODULES_LIST` in `build.config` for `build.sh`.
        modules_blocklist: A file containing a list of modules which are
          blocked from being loaded.

          This file is copied directly to staging directory, and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        modules_options: A `/lib/modules/modules.options` file is created on the ramdisk containing
          the contents of this variable.

          Lines should be of the form:
          ```
          options <modulename> <param1>=<val> <param2>=<val> ...
          ```

          This corresponds to `MODULES_OPTIONS` in `build.config` for `build.sh`.
        vendor_dlkm_modules_list: location of an optional file
          containing the list of kernel modules which shall be copied into a
          `vendor_dlkm` partition image. Any modules passed into `MODULES_LIST` which
          become part of the `vendor_boot.modules.load` will be trimmed from the
          `vendor_dlkm.modules.load`.

          This corresponds to `VENDOR_DLKM_MODULES_LIST` in `build.config` for `build.sh`.
        vendor_dlkm_modules_blocklist: location of an optional file containing a list of modules
          which are blocked from being loaded.

          This file is copied directly to the staging directory and should be in the format:
          ```
          blocklist module_name
          ```

          This corresponds to `VENDOR_DLKM_MODULES_BLOCKLIST` in `build.config` for `build.sh`.
        vendor_dlkm_props: location of a text file containing
          the properties to be used for creation of a `vendor_dlkm` image
          (filesystem, partition size, etc). If this is not set (and
          `build_vendor_dlkm` is), a default set of properties will be used
          which assumes an ext4 filesystem and a dynamic partition.

          This corresponds to `VENDOR_DLKM_PROPS` in `build.config` for `build.sh`.
        vendor_ramdisk_binaries: List of vendor ramdisk binaries
          which includes the device-specific components of ramdisk like the fstab
          file and the device-specific rc files. If specifying multiple vendor ramdisks
          and identical file paths exist in the ramdisks, the file from last ramdisk is used.

          Note: **order matters**. To prevent buildifier from sorting the list, add the following:
          ```
          # do not sort
          ```

          This corresponds to `VENDOR_RAMDISK_BINARY` in `build.config` for `build.sh`.
    """
    all_rules = []

    if build_vendor_boot and not build_boot:
        fail("{}: build_vendor_boot = True requires build_boot = True.".format(name))

    if build_boot:
        if build_initramfs == None:
            build_initramfs = True
        if not build_initramfs:
            fail("{}: Must set build_initramfs to True if build_boot".format(name))
        if kernel_build == None:
            fail("{}: Must set kernel_build if build_boot".format(name))

    # Set default value for boot_image_outs according to build_boot
    if boot_image_outs == None:
        if not build_boot:
            boot_image_outs = []
        else:
            boot_image_outs = [
                "boot.img",
                "dtb.img",
                "ramdisk.lz4",
                "vendor-bootconfig.img",
            ]

    if build_vendor_boot and "vendor_boot.img" not in boot_image_outs:
        boot_image_outs.append("vendor_boot.img")

    if build_initramfs:
        _initramfs(
            name = "{}_initramfs".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name),
            modules_list = modules_list,
            modules_blocklist = modules_blocklist,
            modules_options = modules_options,
        )
        all_rules.append(":{}_initramfs".format(name))

    if build_system_dlkm:
        _system_dlkm_image(
            name = "{}_system_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            deps = deps,
            modules_list = modules_list,
            modules_blocklist = modules_blocklist,
        )
        all_rules.append(":{}_system_dlkm_image".format(name))

    if build_vendor_dlkm:
        _vendor_dlkm_image(
            name = "{}_vendor_dlkm_image".format(name),
            kernel_modules_install = kernel_modules_install,
            vendor_boot_modules_load = "{}_initramfs/vendor_boot.modules.load".format(name),
            deps = deps,
            vendor_dlkm_modules_list = vendor_dlkm_modules_list,
            vendor_dlkm_modules_blocklist = vendor_dlkm_modules_blocklist,
            vendor_dlkm_props = vendor_dlkm_props,
        )
        all_rules.append(":{}_vendor_dlkm_image".format(name))

    if build_boot:
        _boot_images(
            name = "{}_boot_images".format(name),
            kernel_build = kernel_build,
            outs = ["{}_boot_images/{}".format(name, out) for out in boot_image_outs],
            deps = deps,
            initramfs = ":{}_initramfs".format(name),
            mkbootimg = mkbootimg,
            build_vendor_boot = build_vendor_boot,
            vendor_ramdisk_binaries = vendor_ramdisk_binaries,
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
    all_deps = ctx.files.srcs + ctx.files.deps

    # TODO(b/219112010): implement _KernelEnvInfo for the modules_prepare target
    modules_prepare_out_dir_tar_gz = find_file("modules_prepare_outdir.tar.gz", all_deps, what = ctx.label)
    modules_prepare_setup = """
         # Restore modules_prepare outputs. Assumes env setup.
           [ -z ${{OUT_DIR}} ] && echo "ERROR: modules_prepare setup run without OUT_DIR set!" >&2 && exit 1
           tar xf {outdir_tar_gz} -C ${{OUT_DIR}}
    """.format(outdir_tar_gz = modules_prepare_out_dir_tar_gz)
    modules_prepare_deps = [modules_prepare_out_dir_tar_gz]

    kernel_module_dev_info = _KernelBuildExtModuleInfo(
        modules_staging_archive = find_file("modules_staging_dir.tar.gz", all_deps, what = ctx.label),
        modules_prepare_setup = modules_prepare_setup,
        modules_prepare_deps = modules_prepare_deps,
        # TODO(b/211515836): module_srcs might also be downloaded
        module_srcs = _filter_module_srcs(ctx.files.kernel_srcs),
        collect_unstripped_modules = ctx.attr.collect_unstripped_modules,
    )
    uapi_info = _KernelBuildUapiInfo(
        kernel_uapi_headers = ctx.attr.kernel_uapi_headers,
    )
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        kernel_module_dev_info,
        # TODO(b/219112010): implement _KernelEnvInfo for _kernel_build
        uapi_info,
    ]

kernel_filegroup = rule(
    implementation = _kernel_filegroup_impl,
    doc = """Specify a list of kernel prebuilts.

This is similar to [`filegroup`](https://docs.bazel.build/versions/main/be/general.html#filegroup)
that gives a convenient name to a collection of targets, which can be referenced from other rules.

It can be used in the `base_kernel` attribute of a [`kernel_build`](#kernel_build).
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = """The list of labels that are members of this file group.

This usually contains a list of prebuilts, e.g. `vmlinux`, `Image.lz4`, `kernel-headers.tar.gz`,
etc.

Not to be confused with [`kernel_srcs`](#kernel_filegroup-kernel_srcs).""",
        ),
        "deps": attr.label_list(
            allow_files = True,
            doc = """A list of additional labels that participates in implementing the providers.

This usually contains a list of prebuilts.

Unlike srcs, these labels are NOT added to the [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html)""",
        ),
        "kernel_srcs": attr.label_list(
            allow_files = True,
            doc = """A list of files that would have been listed as `srcs` if this rule were a [`kernel_build`](#kernel_build).

This is usually a `glob()` of source files.

Not to be confused with [`srcs`](#kernel_filegroup-srcs).
""",
        ),
        "kernel_uapi_headers": attr.label(
            allow_files = True,
            doc = """The label pointing to `kernel-uapi-headers.tar.gz`.

This attribute should be set to the `kernel-uapi-headers.tar.gz` artifact built by the
[`kernel_build`](#kernel_build) macro if the `kernel_filegroup` rule were a `kernel_build`.

Setting this attribute allows [`merged_kernel_uapi_headers`](#merged_kernel_uapi_headers) to
work properly when this `kernel_filegroup` is set to the `base_kernel`.

For example:
```
kernel_filegroup(
    name = "kernel_aarch64_prebuilts",
    srcs = [
        "vmlinux",
        # ...
    ],
    kernel_uapi_headers = "kernel-uapi-headers.tar.gz",
)

kernel_build(
    name = "tuna",
    base_kernel = ":kernel_aarch64_prebuilts",
    # ...
)

merged_kernel_uapi_headers(
    name = "tuna_merged_kernel_uapi_headers",
    kernel_build = "tuna",
    # ...
)
```
""",
        ),
        "collect_unstripped_modules": attr.bool(
            default = True,
            doc = """See [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).

Unlike `kernel_build`, this has default value `True` because
[`kernel_build_abi`](#kernel_build_abi) sets
[`define_abi_targets`](#kernel_build_abi-define_abi_targets) to `True` by
default, which in turn sets `collect_unstripped_modules` to `True` by default.
""",
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
        mnemonic = "KernelCompileCommands",
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
        mnemonic = "KernelKythe",
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

def _kernel_extracted_symbols_impl(ctx):
    if ctx.attr.kernel_build_notrim[_KernelBuildAbiInfo].trim_nonlisted_kmi:
        fail("{}: Requires `kernel_build` {} to have `trim_nonlisted_kmi = False`.".format(
            ctx.label,
            ctx.attr.kernel_build_notrim.label,
        ))

    out = ctx.actions.declare_file("{}/extracted_symbols".format(ctx.attr.name))
    genfiles_dir = ctx.genfiles_dir.path

    vmlinux = find_file(name = "vmlinux", files = ctx.files.kernel_build_notrim, what = "{}: kernel_build_notrim".format(ctx.attr.name), required = True)
    in_tree_modules = find_files(suffix = ".ko", files = ctx.files.kernel_build_notrim, what = "{}: kernel_build_notrim".format(ctx.attr.name))
    srcs = [vmlinux] + in_tree_modules
    srcs += ctx.files.kernel_modules  # external modules

    inputs = [ctx.file._extract_symbols]
    inputs += srcs
    inputs += ctx.attr.kernel_build_notrim[_KernelEnvInfo].dependencies

    command = ctx.attr.kernel_build_notrim[_KernelEnvInfo].setup
    command += """
        cp -pl {srcs} {genfiles_dir}
        {extract_symbols} --symbol-list {out} {skip_module_grouping_flag} {genfiles_dir}
    """.format(
        srcs = " ".join([file.path for file in srcs]),
        genfiles_dir = genfiles_dir,
        extract_symbols = ctx.file._extract_symbols.path,
        out = out.path,
        skip_module_grouping_flag = "" if ctx.attr.module_grouping else "--skip-module-grouping",
    )
    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out],
        command = command,
        progress_message = "Extracting symbols {}".format(ctx.label),
        mnemonic = "KernelExtractedSymbols",
    )

    return DefaultInfo(files = depset([out]))

_kernel_extracted_symbols = rule(
    implementation = _kernel_extracted_symbols_impl,
    attrs = {
        # We can't use kernel_filegroup + hermetic_tools here because
        # - extract_symbols depends on the clang toolchain, which requires us to
        #   know the toolchain_version ahead of time.
        # - We also don't have the necessity to extract symbols from prebuilts.
        "kernel_build_notrim": attr.label(providers = [_KernelEnvInfo, _KernelBuildAbiInfo]),
        "kernel_modules": attr.label_list(),
        "module_grouping": attr.bool(default = True),
        "_extract_symbols": attr.label(default = "//build/kernel:abi/extract_symbols", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_abi_dump_impl(ctx):
    full_abi_out_file = _kernel_abi_dump_full(ctx)
    abi_out_file = _kernel_abi_dump_filtered(ctx, full_abi_out_file)
    return [
        DefaultInfo(files = depset([full_abi_out_file, abi_out_file])),
        OutputGroupInfo(abi_out_file = depset([abi_out_file])),
    ]

def _kernel_abi_dump_epilog_cmd(path, append_version):
    ret = ""
    if append_version:
        ret += """
             # Append debug information to abi file
               echo "
<!--
     libabigail: $(abidw --version)
-->" >> {path}
""".format(path = path)
    return ret

def _kernel_abi_dump_full(ctx):
    abi_linux_tree = ctx.genfiles_dir.path + "/abi_linux_tree"
    full_abi_out_file = ctx.actions.declare_file("{}/abi-full.xml".format(ctx.attr.name))
    vmlinux = find_file(name = "vmlinux", files = ctx.files.kernel_build, what = "{}: kernel_build".format(ctx.attr.name), required = True)

    unstripped_dir_provider_targets = [ctx.attr.kernel_build] + ctx.attr.kernel_modules
    unstripped_dir_providers = [target[_KernelUnstrippedModulesInfo] for target in unstripped_dir_provider_targets]
    for prov in unstripped_dir_providers:
        if not prov.directory:
            fail("{}: Requires dep {} to set collect_unstripped_modules = True".format(ctx.label, prov.label))
    unstripped_dirs = [prov.directory for prov in unstripped_dir_providers]

    inputs = [vmlinux, ctx.file._dump_abi]
    inputs += ctx.files._dump_abi_scripts
    inputs += unstripped_dirs

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    # Directories could be empty, so use a find + cp
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        mkdir -p {abi_linux_tree}
        find {unstripped_dirs} -type f -name '*.ko' -exec cp -pl -t {abi_linux_tree} {{}} +
        cp -pl {vmlinux} {abi_linux_tree}
        {dump_abi} --linux-tree {abi_linux_tree} --out-file {full_abi_out_file}
        {epilog}
    """.format(
        abi_linux_tree = abi_linux_tree,
        unstripped_dirs = " ".join([unstripped_dir.path for unstripped_dir in unstripped_dirs]),
        dump_abi = ctx.file._dump_abi.path,
        vmlinux = vmlinux.path,
        full_abi_out_file = full_abi_out_file.path,
        epilog = _kernel_abi_dump_epilog_cmd(full_abi_out_file.path, True),
    )
    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [full_abi_out_file],
        command = command,
        mnemonic = "AbiDumpFull",
        progress_message = "Extracting ABI {}".format(ctx.label),
    )
    return full_abi_out_file

def _kernel_abi_dump_filtered(ctx, full_abi_out_file):
    abi_out_file = ctx.actions.declare_file("{}/abi.xml".format(ctx.attr.name))
    inputs = [full_abi_out_file]

    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    combined_abi_symbollist = ctx.attr.kernel_build[_KernelBuildAbiInfo].combined_abi_symbollist
    if combined_abi_symbollist:
        inputs += [
            ctx.file._filter_abi,
            combined_abi_symbollist,
        ]

        command += """
            {filter_abi} --in-file {full_abi_out_file} --out-file {abi_out_file} --kmi-symbol-list {abi_symbollist}
            {epilog}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
            filter_abi = ctx.file._filter_abi.path,
            abi_symbollist = combined_abi_symbollist.path,
            epilog = _kernel_abi_dump_epilog_cmd(abi_out_file.path, False),
        )
    else:
        command += """
            cp -p {full_abi_out_file} {abi_out_file}
        """.format(
            abi_out_file = abi_out_file.path,
            full_abi_out_file = full_abi_out_file.path,
        )
    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [abi_out_file],
        command = command,
        mnemonic = "AbiDumpFiltered",
        progress_message = "Filtering ABI dump {}".format(ctx.label),
    )
    return abi_out_file

_kernel_abi_dump = rule(
    implementation = _kernel_abi_dump_impl,
    doc = "Extracts the ABI.",
    attrs = {
        "kernel_build": attr.label(providers = [_KernelEnvInfo, _KernelBuildAbiInfo, _KernelUnstrippedModulesInfo]),
        "kernel_modules": attr.label_list(providers = [_KernelUnstrippedModulesInfo]),
        "_dump_abi_scripts": attr.label(default = "//build/kernel:dump-abi-scripts"),
        "_dump_abi": attr.label(default = "//build/kernel:abi/dump_abi", allow_single_file = True),
        "_filter_abi": attr.label(default = "//build/kernel:abi/filter_abi", allow_single_file = True),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_abi_prop_impl(ctx):
    content = []
    if ctx.file.kmi_definition:
        content.append("KMI_DEFINITION={}".format(ctx.file.kmi_definition.basename))
        content.append("KMI_MONITORED=1")

        if ctx.attr.kmi_enforced:
            content.append("KMI_ENFORCED=1")

    combined_abi_symbollist = ctx.attr.kernel_build[_KernelBuildAbiInfo].combined_abi_symbollist
    if combined_abi_symbollist:
        content.append("KMI_SYMBOL_LIST={}".format(combined_abi_symbollist.basename))

    # This just appends `KERNEL_BINARY=vmlinux`, but find_file additionally ensures that
    # we are building vmlinux.
    vmlinux = find_file(name = "vmlinux", files = ctx.files.kernel_build, what = "{}: kernel_build".format(ctx.attr.name), required = True)
    content.append("KERNEL_BINARY={}".format(vmlinux.basename))

    if ctx.file.modules_archive:
        content.append("MODULES_ARCHIVE={}".format(ctx.file.modules_archive.basename))

    out = ctx.actions.declare_file("{}/abi.prop".format(ctx.attr.name))
    ctx.actions.write(
        output = out,
        content = "\n".join(content) + "\n",
    )
    return DefaultInfo(files = depset([out]))

_kernel_abi_prop = rule(
    implementation = _kernel_abi_prop_impl,
    doc = "Create `abi.prop`",
    attrs = {
        "kernel_build": attr.label(providers = [_KernelBuildAbiInfo]),
        "modules_archive": attr.label(allow_single_file = True),
        "kmi_definition": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
    },
)

def kernel_build_abi(
        name,
        define_abi_targets = None,
        # for kernel_abi
        kernel_modules = None,
        module_grouping = None,
        abi_definition = None,
        kmi_enforced = None,
        unstripped_modules_archive = None,
        # for kernel_build
        **kwargs):
    """Declare multiple targets to support ABI monitoring.

    This macro is meant to be used in place of the [`kernel_build`](#kernel_build)
    marco. All arguments in `kwargs` are passed to `kernel_build` directly.

    For example, you may have the following declaration. (For actual definition
    of `kernel_aarch64`, see
    [`define_common_kernels()`](#define_common_kernels).

    ```
    kernel_build_abi(name = "kernel_aarch64", **kwargs)
    _dist_targets = ["kernel_aarch64", ...]
    copy_to_dist_dir(name = "kernel_aarch64_dist", data = _dist_targets)
    copy_to_dist_dir(name = "kernel_aarch64_abi_dist", data = _dist_targets + ["kernel_aarch64_abi"])
    ```

    The `kernel_build_abi` invocation is equivalent to the following:

    ```
    kernel_build(name = "kernel_aarch64", **kwargs)
    # if define_abi_targets, also define some other targets
    ```

    See [`kernel_build`](#kernel_build) for the targets defined.

    In addition, the following targets are defined if `define_abi_targets = True`:
    - kernel_aarch64_abi_update_symbol_list
      - Running this target updates `kmi_symbol_list`.
    - kernel_aarch64_abi_dump
      - Building this target extracts the ABI.
      - Include this target in a `copy_to_dist_dir` target to copy
        ABI dump to `--dist-dir`.
    - kernel_aarch64_abi_update
      - Running this target updates `abi_definition`.
    - kernel_aarch64_abi_dump
      - Building this target extracts the ABI.
      - Include this target in a `copy_to_dist_dir` target to copy
        ABI dump to `--dist-dir`.
    - kernel_aarch64_abi (if `abi_definition` is not `None`)
      - Building this target compares the ABI with `abi_definition`.
      - Include this target in a `copy_to_dist_dir` target to copy
        ABI dump and diff report to `--dist-dir`.

    Assuming the above, here's a table for converting `build_abi.sh`
    into Bazel commands. Note: it is recommended to disable the sandbox for
    certain targets to boost incremental builds.

    |build_abi.sh equivalent            |Bazel command                                          |What does the Bazel command do                                         |
    |-----------------------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
    |`build_abi.sh --update_symbol_list`|`bazel run kernel_aarch64_abi_update_symbol_list`[1]   |Update symbol list                                                     |
    |-----------------------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
    |`build_abi.sh --nodiff`            |`bazel build kernel_aarch64_abi_dump` [2]              |Extract the ABI (but do not compare it)                                |
    |-----------------------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
    |`build_abi.sh --nodiff --update`   |`bazel run kernel_aarch64_abi_update_symbol_list && \\`|Update symbol list,                                                    |
    |                                   |`    bazel run kernel_aarch64_abi_update` [1][2][3]    |Extract the ABI (but do not compare it), then update `abi_definition`  |
    |-----------------------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
    |`build_abi.sh --update`            |`bazel run kernel_aarch64_abi_update_symbol_list && \\`|Update symbol list,                                                    |
    |                                   |`    bazel build kernel_aarch64_abi && \\`             |Extract the ABI and compare it,                                        |
    |                                   |`    bazel run kernel_aarch64_abi_update` [1][2][3]    |then update `abi_definition`                                           |
    |-----------------------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
    |`build_abi.sh`                     |`bazel build kernel_aarch64_abi` [2]                   |Extract the ABI and compare it                                         |
    |-----------------------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
    |`build_abi.sh`                     |`bazel run kernel_aarch64_abi_dist -- --dist_dir=...`  |Extract the ABI and compare it, then copy artifacts to `--dist_dir`    |

    Notes:

    1. The command updates `kmi_symbol_list` but it does not update
      `$DIST_DIR/abi_symbollist`, unlike the `build_abi.sh --update-symbol-list`
      command.
    2. The Bazel command extracts the ABI and/or compares the ABI like the
       `build_abi.sh` command, but it does not copy the ABI dump and/or the diff
       report to `$DIST_DIR` like the `build_abi.sh` command. You may find the
       ABI dump in Bazel's output directory under `bazel-bin/`.
    3. Order matters, and the two commands cannot run in parallel. This is
       because updating the ABI definition requires the **source**
       `kmi_symbol_list` to be updated first.

    Args:
      name: Name of the main `kernel_build`.
      define_abi_targets: Whether to create the `<name>_abi` target and
        targets to support it. If `None`, defaults to `True`.

        If `False`, this macro is equivalent to just calling
        `kernel_build(name, **kwargs)`.

        If `True`, implies `collect_unstripped_modules = True`. See
        [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).
      kernel_modules: A list of external [`kernel_module()`](#kernel_module)s
        to extract symbols from.
      module_grouping: If unspecified or `None`, it is `True` by default.
        If `True`, then the symbol list will group symbols based
        on the kernel modules that reference the symbol. Otherwise the symbol
        list will simply be a sorted list of symbols used by all the kernel
        modules.
      abi_definition: Location of the ABI definition.
      kmi_enforced: This is an indicative option to signal that KMI is enforced.
        If set to `True`, KMI checking tools respects it and
        reacts to it by failing if KMI differences are detected.
      unstripped_modules_archive: A [`kernel_unstripped_modules_archive`](#kernel_unstripped_modules_archive)
        which name is specified in `abi.prop`.
      kwargs: See [`kernel_build.kwargs`](#kernel_build-kwargs)
    """

    if define_abi_targets == None:
        define_abi_targets = True

    kwargs = dict(kwargs)
    if define_abi_targets and kwargs.get("collect_unstripped_modules") == None:
        kwargs["collect_unstripped_modules"] = True

    kernel_build(name = name, **kwargs)

    if not define_abi_targets:
        return

    # notrim: outs += [vmlinux], trim_nonlisted_kmi = False
    outs_and_vmlinux, added_vmlinux = _kernel_build_outs_add_vmlinux(name, kwargs.get("outs"))
    if kwargs.get("trim_nonlisted_kmi") or added_vmlinux:
        notrim_kwargs = dict(kwargs)
        notrim_kwargs["outs"] = _transform_kernel_build_outs(name + "_notrim", "outs", outs_and_vmlinux)
        notrim_kwargs["trim_nonlisted_kmi"] = False
        notrim_kwargs["kmi_symbol_list_strict_mode"] = False
        kernel_build(name = name + "_notrim", **notrim_kwargs)
    else:
        native.alias(name = name + "_notrim", actual = name)

    # with_vmlinux: outs += [vmlinux]
    if added_vmlinux:
        with_vmlinux_kwargs = dict(kwargs)
        with_vmlinux_kwargs["outs"] = _transform_kernel_build_outs(name + "_with_vmlinux", "outs", outs_and_vmlinux)
        kernel_build(name = name + "_with_vmlinux", **with_vmlinux_kwargs)
    else:
        native.alias(name = name + "_with_vmlinux", actual = name)

    default_outputs = []

    # extract_symbols ...
    _kernel_extracted_symbols(
        name = name + "_abi_extracted_symbols",
        kernel_build_notrim = name + "_notrim",
        kernel_modules = kernel_modules,
        module_grouping = module_grouping,
    )
    update_source_file(
        name = name + "_abi_update_symbol_list",
        src = name + "_abi_extracted_symbols",
        dst = kwargs.get("kmi_symbol_list"),
    )

    _kernel_abi_dump(
        name = name + "_abi_dump",
        kernel_build = name + "_with_vmlinux",
        kernel_modules = kernel_modules,
    )
    default_outputs.append(name + "_abi_dump")

    if abi_definition:
        native.filegroup(
            name = name + "_abi_out_file",
            srcs = [name + "_abi_dump"],
            output_group = "abi_out_file",
        )

        _kernel_abi_diff(
            name = name + "_abi_diff",
            baseline = abi_definition,
            new = name + "_abi_out_file",
            kmi_enforced = kmi_enforced,
        )
        default_outputs.append(name + "_abi_diff")

        update_source_file(
            name = name + "_abi_update",
            src = name + "_abi_out_file",
            dst = abi_definition,
        )

    _kernel_abi_prop(
        name = name + "_abi_prop",
        kmi_definition = name + "_abi_out_file" if abi_definition else None,
        kmi_enforced = kmi_enforced,
        kernel_build = name + "_with_vmlinux",
        modules_archive = unstripped_modules_archive,
    )
    default_outputs.append(name + "_abi_prop")

    native.filegroup(
        name = name + "_abi",
        srcs = default_outputs,
    )

def _kernel_abi_diff_impl(ctx):
    inputs = [
        ctx.file._diff_abi,
        ctx.file.baseline,
        ctx.file.new,
    ]
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    inputs += ctx.files._diff_abi_scripts

    output_dir = ctx.actions.declare_directory("{}/abi_diff".format(ctx.attr.name))
    error_msg_file = "{}/error.txt".format(ctx.genfiles_dir.path)
    default_outputs = [output_dir]

    command_outputs = default_outputs

    command = ctx.attr._hermetic_tools[HermeticToolsInfo].setup + """
        set +e
        {diff_abi} --baseline {baseline}                \\
                   --new      {new}                     \\
                   --report   {output_dir}/abi.report   \\
                   --abi-tool delegated 2> {error_msg_file}
        rc=$?
        set -e
        if [ $rc -ne 0 ]; then
            echo "ERROR: $(cat {error_msg_file})" >&2
        fi
    """.format(
        diff_abi = ctx.file._diff_abi.path,
        baseline = ctx.file.baseline.path,
        new = ctx.file.new.path,
        output_dir = output_dir.path,
        error_msg_file = error_msg_file,
    )
    if ctx.attr.kmi_enforced:
        command += """
            exit $rc
        """

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = command_outputs,
        command = command,
        mnemonic = "KernelDiffAbi",
        progress_message = "Comparing ABI {}".format(ctx.label),
    )

    return DefaultInfo(files = depset(default_outputs))

_kernel_abi_diff = rule(
    implementation = _kernel_abi_diff_impl,
    doc = "Run `diff_abi`",
    attrs = {
        "baseline": attr.label(allow_single_file = True),
        "new": attr.label(allow_single_file = True),
        "kmi_enforced": attr.bool(),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_diff_abi_scripts": attr.label(default = "//build/kernel:diff-abi-scripts"),
        "_diff_abi": attr.label(default = "//build/kernel:abi/diff_abi", allow_single_file = True),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)

def _kernel_unstripped_modules_archive_impl(ctx):
    kernel_build = ctx.attr.kernel_build
    base_kernel = kernel_build[_KernelUnstrippedModulesInfo].base_kernel if kernel_build else None

    # Early elements = higher priority. In-tree modules from base_kernel has highest priority,
    # then in-tree modules of the device kernel_build, then external modules (in an undetermined
    # order).
    # TODO(b/228557644): kernel module names should not collide. Detect collsions.
    srcs = []
    for kernel_build_object in (base_kernel, kernel_build):
        if not kernel_build_object:
            continue
        directory = kernel_build_object[_KernelUnstrippedModulesInfo].directory
        if not directory:
            fail("{} does not have collect_unstripped_modules = True.".format(kernel_build_object.label))
        srcs.append(directory)
    for kernel_module in ctx.attr.kernel_modules:
        srcs.append(kernel_module[_KernelUnstrippedModulesInfo].directory)

    inputs = ctx.attr._hermetic_tools[HermeticToolsInfo].deps + srcs

    out_file = ctx.actions.declare_file("{}/unstripped_modules.tar.gz".format(ctx.attr.name))
    unstripped_dir = ctx.genfiles_dir.path + "/unstripped"

    command = ""
    command += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    command += """
        mkdir -p {unstripped_dir}
    """.format(unstripped_dir = unstripped_dir)

    # Copy the source ko files in low to high priority order.
    for src in reversed(srcs):
        # src could be empty, so use find + cp
        command += """
            find {src} -name '*.ko' -exec cp -l -t {unstripped_dir} {{}} +
        """.format(
            src = src.path,
            unstripped_dir = unstripped_dir,
        )

    command += """
        tar -czhf {out_file} -C $(dirname {unstripped_dir}) $(basename {unstripped_dir})
    """.format(
        out_file = out_file.path,
        unstripped_dir = unstripped_dir,
    )

    _debug_print_scripts(ctx, command)
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Compressing unstripped modules {}".format(ctx.label),
        command = command,
        mnemonic = "KernelUnstrippedModulesArchive",
    )
    return DefaultInfo(files = depset([out_file]))

kernel_unstripped_modules_archive = rule(
    implementation = _kernel_unstripped_modules_archive_impl,
    doc = """Compress the unstripped modules into a tarball.

This is the equivalent of `COMPRESS_UNSTRIPPED_MODULES=1` in `build.sh`.

Add this target to a `copy_to_dist_dir` rule to copy it to the distribution
directory, or `DIST_DIR`.
""",
    attrs = {
        "kernel_build": attr.label(
            doc = """A [`kernel_build`](#kernel_build) to retrieve unstripped in-tree modules from.

It requires `collect_unstripped_modules = True`. If the `kernel_build` has a `base_kernel`, the rule
also retrieves unstripped in-tree modules from the `base_kernel`, and requires the
`base_kernel` has `collect_unstripped_modules = True`.
""",
            providers = [_KernelUnstrippedModulesInfo],
        ),
        "kernel_modules": attr.label_list(
            doc = """A list of external [`kernel_module`](#kernel_module)s to retrieve unstripped external modules from.

It requires that the base `kernel_build` has `collect_unstripped_modules = True`.
""",
            providers = [_KernelUnstrippedModulesInfo],
        ),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
