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

"""Rules for defining a DDK (Driver Development Kit) module."""

load(":ddk/ddk_conditional_filegroup.bzl", "flatten_conditional_srcs")
load(":ddk/ddk_module_config.bzl", "ddk_module_config")
load(":ddk/makefiles.bzl", "makefiles")
load(":kernel_module.bzl", "kernel_module")

visibility("//build/kernel/kleaf/...")

def ddk_module(
        name,
        kernel_build,
        srcs = None,
        deps = None,
        hdrs = None,
        textual_hdrs = None,
        includes = None,
        conditional_srcs = None,
        crate_root = None,
        linux_includes = None,
        out = None,
        local_defines = None,
        copts = None,
        removed_copts = None,
        asopts = None,
        linkopts = None,
        config = None,
        kconfig = None,
        defconfig = None,
        generate_btf = None,
        autofdo_profile = None,
        debug_info_for_profiling = None,
        **kwargs):
    """
    Defines a DDK (Driver Development Kit) module.

    Example:

    ```
    ddk_module(
        name = "my_module",
        srcs = ["my_module.c", "private_header.h"],
        out = "my_module.ko",
        # Exported headers
        hdrs = ["include/my_module_exported.h"],
        textual_hdrs = ["my_template.c"],
        includes = ["include"],
    )
    ```

    Note: Local headers should be specified in one of the following ways:

    - In a `ddk_headers` target in the same package, if you need to auto-generate `-I` ccflags.
      In that case, specify the `ddk_headers` target in `deps`.
    - Otherwise, in `srcs` if you don't need the `-I` ccflags.

    Exported headers should be specified in one of the following ways:

    - In a separate `ddk_headers` target in the same package. Then specify the
      target in `hdrs`. This is recommended if there
      are multiple `ddk_module`s depending on a
      [`glob`](https://bazel.build/reference/be/functions#glob) of headers or a large list
      of headers.
    - Using `hdrs`, `textual_hdrs` and `includes` of this target.

    For details, see `build/kernel/kleaf/tests/ddk_examples/README.md`.

    `hdrs`, `textual_hdrs` and `includes` have the same semantics as [`ddk_headers`](#ddk_headers).
    That is, this target effectively acts as a `ddk_headers` target when specified in the `deps`
    attribute of another `ddk_module`. In other words, the following code snippet:

    ```
    ddk_module(name = "module_A", hdrs = [...], includes = [...], ...)
    ddk_module(name = "module_B", deps = ["module_A"], ...)
    ```

    ... is effectively equivalent to the following:

    ```
    ddk_headers(name = "module_A_hdrs, hdrs = [...], includes = [...], ...)
    ddk_module(name = "module_A", ...)
    ddk_module(name = "module_B", deps = ["module_A", "module_A_hdrs"], ...)
    ```

    **Submodules**

    See [ddk_submodule](#ddk_submodule).

    If `deps` contains a `ddk_submodule` target, the `ddk_module` target must not specify
    anything except:

    - `kernel_build`
    - `linux_includes`

    It is not recommended that a `ddk_submodule` depends on a `ddk_headers` target that specifies
    `linux_includes`. If a `ddk_submodule` does depend on a `ddk_headers` target
    that specifies `linux_includes`, all submodules below the same directory (i.e. sharing the same
    `Kbuild` file) gets these `linux_includes`. This is because `LINUXINCLUDE` is set for the whole
    `Kbuild` file, not per compilation unit.

    In particular, a `ddk_submodule` should not depend on `//common:all_headers`.
    Instead, the dependency should come from the `kernel_build`; that is, the `kernel_build` of
    the `ddk_module`, or the `base_kernel`, should specify
    `ddk_module_headers = "//common:all_headers"`.

    To avoid confusion, the dependency on this `ddk_headers` target with `linux_includes` should
    be moved to the top-level `ddk_module`. In this case, all submodules of this `ddk_module`
    receives the said `LINUXINCLUDE` from the `ddk_headers` target.

    Example:
    ```
    # //common
    kernel_build(name = "kernel_aarch64", ddk_module_headers = ":all_headers_aarch64")
    ddk_headers(
        name = "all_headers_aarch64",
        linux_includes = [
            "arch/arm64/include",
            "arch/arm64/include/uapi",
            "include",
            "include/uapi",
        ],
    )
    ```
    ```
    # //device
    kernel_build(name = "tuna", base_kernel = "//common:kernel_aarch64")

    ddk_headers(name = "uapi", linux_includes = ["uapi/include"])

    ddk_module(
        name = "mymodule",
        kernel_build = ":tuna",
        deps = [
            ":mysubmodule"
            # Specify dependency on :uapi in the top level ddk_module
            ":uapi",
        ],
    )

    ddk_submodule(
        name = "mysubmodule",
        deps = [
            # Not recommended to specify dependency on :uapi since it contains
            # linux_includes

            # No need tp specify dependency on //common:all_headers_aarch64
            # since it comes from :tuna -> //common:kernel_aarch64
        ]
    )
    ```

    **Ordering of `includes`**

    **The best practice is to not have conflicting header names and search paths.**
    But if you do, see below for ordering of include directories to be
    searched for header files.

    A [`ddk_module`](#ddk_module) is compiled with the following order of include directories
    (`-I` options):

    1. Traverse depedencies for `linux_includes`:
        1. All `linux_includes` of this target, in the specified order
        2. All `linux_includes` of `deps`, in the specified order (recursively apply #1.3 on each target)
        3. All `linux_includes` of `hdrs`, in the specified order (recursively apply #1.3 on each target)
        4. All `linux_includes` from kernel_build:
           1. All `linux_includes` from `ddk_module_headers` of the `base_kernel` of the
              `kernel_build` of this `ddk_module`;
           2. All `linux_includes` from `ddk_module_headers` of the `kernel_build` of this
              `ddk_module`;
    2. `LINUXINCLUDE` (See `${KERNEL_DIR}/Makefile`)
    3. Traverse depedencies for `includes`:
        1. All `includes` of this target, in the specified order
        2. All `includes` of `deps`, in the specified order (recursively apply #3.1 and #3.3 on each target)
        3. All `includes` of `hdrs`, in the specified order (recursively apply #3.1 and #3.3 on each target)
        4. All `includes` from kernel_build:
           1. All `includes` from `ddk_module_headers` of the `base_kernel` of the
              `kernel_build` of this `ddk_module`;
           2. All `includes` from `ddk_module_headers` of the `kernel_build` of this
              `ddk_module`;

    In other words, #1 and #3 uses the `preorder` of
    [depset](https://bazel.build/rules/lib/depset).

    "In the specified order" means that order matters within these lists.
    To prevent buildifier from sorting these lists, use the `# do not sort` magic line.

    To export a target `:x` in `hdrs` before other targets in `deps`
    (that is, if you need #3.3 before #3.2, or #1.2 before #1.1),
    specify `:x` in the `deps` list in the position you want. See example below.

    To export an include directory in `includes` that needs to be included
    after other targets in `hdrs` or `deps` (that is, if you need #3.1 after #3.2
    or #3.3), specify the include directory in a separate `ddk_headers` target,
    then specify this `ddk_headers` target in `hdrs` and/or `deps` based on
    your needs.

    For example:

    ```
    ddk_headers(name = "base_ddk_headers", includes = ["base"], linux_includes = ["uapi/base"])
    ddk_headers(name = "device_ddk_headers", includes = ["device"], linux_includes = ["uapi/device"])

    kernel_build(
        name = "kernel_aarch64",
        ddk_module_headers = [":base_ddk_headers"],
    )
    kernel_build(
        name = "device",
        base_kernel = ":kernel_aarch64",
        ddk_module_headers = [":device_ddk_headers"],
    )

    ddk_headers(name = "dep_a", includes = ["dep_a"], linux_includes = ["uapi/dep_a"])
    ddk_headers(name = "dep_b", includes = ["dep_b"])
    ddk_headers(name = "dep_c", includes = ["dep_c"], hdrs = ["dep_a"])
    ddk_headers(name = "hdrs_a", includes = ["hdrs_a"], linux_includes = ["uapi/hdrs_a"])
    ddk_headers(name = "hdrs_b", includes = ["hdrs_b"])
    ddk_headers(name = "x", includes = ["x"])

    ddk_module(
        name = "module",
        kernel_build = ":device",
        deps = [":dep_b", ":x", ":dep_c"],
        hdrs = [":hdrs_a", ":x", ":hdrs_b"],
        linux_includes = ["uapi/module"],
        includes = ["self_1", "self_2"],
    )
    ```

    Then `":module"` is compiled with these flags, in this order:

    ```
    # 1.1 linux_includes
    -Iuapi/module

    # 1.2 deps, linux_includes, recursively
    -Iuapi/dep_a

    # 1.3 hdrs, linux_includes, recursively
    -Iuapi/hdrs_a

    # 1.4 linux_includes from kernel_build and base_kernel
    -Iuapi/device
    -Iuapi/base

    # 2.
    $(LINUXINCLUDE)

    # 3.1 includes
    -Iself_1
    -Iself_2

    # 3.2. deps, recursively
    -Idep_b
    -Ix
    -Idep_a   # :dep_c depends on :dep_a, so include dep_a/ first
    -Idep_c

    # 3.3. hdrs, recursively
    -Ihdrs_a
    # x is already included, skip
    -Ihdrs_b

    # 3.4. includes from kernel_build and base_kernel
    -Idevice
    -Ibase
    ```

    A dependent module automatically gets #1.1, #1.3, #3.1, #3.3, in this order. For example:

    ```
    ddk_module(
        name = "child",
        kernel_build = ":device",
        deps = [":module"],
        # ...
    )
    ```

    Then `":child"` is compiled with these flags, in this order:

    ```
    # 1.2. linux_includes of deps, recursively
    -Iuapi/module
    -Iuapi/hdrs_a

    # 1.4 linux_includes from kernel_build and base_kernel
    -Iuapi/device
    -Iuapi/base

    # 2.
    $(LINUXINCLUDE)

    # 3.2. includes of deps, recursively
    -Iself_1
    -Iself_2
    -Ihdrs_a
    -Ix
    -Ihdrs_b

    # 3.4. includes from kernel_build and base_kernel
    -Idevice
    -Ibase
    ```

    Args:
        name: Name of target. This should usually be name of the output `.ko` file without the
          suffix.
        srcs: sources or local headers.

            Source files (`.c`, `.S`, `.rs`) must be in the package of
            this `ddk_module` target, or in subpackages.

            Generated source files (`.c`, `.S`, `.rs`) are accepted as long as
            they are in the package of this `ddk_module` target, or in
            subpackages.

            Header files specified here are only visible to this `ddk_module`
            target, but not dependencies. To export a header so dependencies
            can use it, put it in `hdrs` and set `includes` accordingly.

            Generated header files are accepted.
        deps: A list of dependent targets. Each of them must be one of the following:

            - [`kernel_module`](#kernel_module)
            - [`ddk_module`](#ddk_module)
            - [`ddk_headers`](#ddk_headers).
            - [`ddk_prebuilt_object`](#ddk_prebuilt_object)
            - [`ddk_library`](#ddk_library)

            If [`config`](#ddk_module-config) is set, if some `deps` of this target have `kconfig`
            / `defconfig` set (including transitive dependencies), you may need to duplicate these
            targets in `ddk_config.deps`. Inconsistent configs are disallowed; if the resulting
            `.config` is not the same as the one from [`config`](#ddk_module-config), you get a
            build error.
        hdrs: See [`ddk_headers.hdrs`](#ddk_headers-hdrs)

            If [`config`](#ddk_module-config) is set, if some `hdrs` of this target have `kconfig`
            / `defconfig` set (including transitive dependencies), you may need to duplicate these
            targets in `ddk_config.deps`. Inconsistent configs are disallowed; if the resulting
            `.config` is not the same as the one from [`config`](#ddk_module-config), you get a
            build error.
        textual_hdrs: See [`ddk_headers.textual_hdrs`](#ddk_headers-textual_hdrs). DEPRECATED. Use `hdrs`.
        includes: See [`ddk_headers.includes`](#ddk_headers-includes)
        linux_includes: See [`ddk_headers.linux_includes`](#ddk_headers-linux_includes)

          Unlike `ddk_headers.linux_includes`, `ddk_module.linux_includes` is **NOT**
          applied to dependent `ddk_module`s.
        kernel_build: [`kernel_build`](#kernel_build)
        conditional_srcs: A dictionary that specifies sources conditionally compiled based on configs.

          Example:

          ```
          conditional_srcs = {
              "CONFIG_FOO": {
                  True: ["foo.c"],
                  False: ["notfoo.c"]
              }
          }
          ```

          In the above example, if `CONFIG_FOO` is `y` or `m`, `foo.c` is compiled.
          Otherwise, `notfoo.c` is compiled instead.

        crate_root: For Rust modules, the file that will be passed to rustc to
            be used for building this module.

            Currently, each `.ko` may only contain a single Rust crate. Modules with multiple crates
            are not yet supported. Hence, only a single file may be passed into crate_root.

            Unlike `rust_binary`, this must always be set for Rust modules. No defaults are assumed.

        out: The output module file. This should usually be `"{name}.ko"`.

          This is required if this target does not contain submodules.
        local_defines: List of defines to add to the compile and assemble command line.

          **Order matters**. To prevent buildifier from sorting the list, use the
          `# do not sort` magic line.

          Each string is prepended with `-D` and added to the compile/assemble command
          line for this target, but not to its dependents.

          Unlike
          [`cc_library.local_defines`](https://bazel.build/reference/be/c-cpp#cc_library.local_defines),
          this is not subject to
          ["Make" variable substitution](https://bazel.build/reference/be/make-variables) or
          [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).

          Each string is treated as a single Bourne shell token. Unlike
          [`cc_library.local_defines`](https://bazel.build/reference/be/c-cpp#cc_library.local_defines),
          this is not subject to
          [Bourne shell tokenization](https://bazel.build/reference/be/common-definitions#sh-tokenization).
          The behavior is similar to `cc_library` with the `no_copts_tokenization`
          [feature](https://bazel.build/reference/be/functions#package.features).
          For details about `no_copts_tokenization`, see
          [`cc_library.copts`](https://bazel.build/reference/be/c-cpp#cc_library.copts).

        copts: Add these options to the compilation command.

          **Order matters**. To prevent buildifier from sorting the list, use the
          `# do not sort` magic line.

          Subject to
          [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).

          The flags take effect only for compiling this target, not its
          dependencies, so be careful about header files included elsewhere.

          All host paths should be provided via
          [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).
          See "Implementation detail" section below.

          Each `$(location)` expression should occupy its own token; optional argument key is
          allowed as a prefix. For example:

          ```
          # Good
          copts = ["-include", "$(location //other:header.h)"]
          copts = ["-include=$(location //other:header.h)"]

          # BAD - Don't do this! Split into two tokens.
          copts = ["-include $(location //other:header.h)"]

          # BAD - Don't do this! Split into two tokens.
          copts = ["$(location //other:header.h) -Werror"]

          # BAD - Don't do this! Split into two tokens.
          copts = ["$(location //other:header.h) $(location //other:header2.h)"]
          ```

          Unlike
          [`cc_library.local_defines`](https://bazel.build/reference/be/c-cpp#cc_library.local_defines),
          this is not subject to
          ["Make" variable substitution](https://bazel.build/reference/be/make-variables).

          Each string is treated as a single Bourne shell token. Unlike
          [`cc_library.copts`](https://bazel.build/reference/be/c-cpp#cc_library.copts)
          this is not subject to
          [Bourne shell tokenization](https://bazel.build/reference/be/common-definitions#sh-tokenization).
          The behavior is similar to `cc_library` with the `no_copts_tokenization`
          [feature](https://bazel.build/reference/be/functions#package.features).
          For details about `no_copts_tokenization`, see
          [`cc_library.copts`](https://bazel.build/reference/be/c-cpp#cc_library.copts).

          Because each string is treated as a single Bourne shell token, if
          a plural `$(locations)` expression expands to multiple paths, they
          are treated as a single Bourne shell token, which is likely an
          undesirable behavior. To avoid surprising behaviors, use singular
          `$(location)` expressions to ensure that the label only expands to one
          path. For differences between the `$(locations)` and `$(location)`, see
          [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).

          **Implementation detail**: Unlike usual `$(location)` expansion,
          `$(location)` in `copts` is expanded to a path relative to the current
          package before sending to the compiler.

          For example:

          ```
          # package: //package
          ddk_module(
            name = "my_module",
            copts = ["-include", "$(location //other:header.h)"],
            srcs = ["//other:header.h", "my_module.c"],
          )
          ```
          Then the content of generated Makefile is semantically equivalent to:

          ```
          CFLAGS_my_module.o += -include ../other/header.h
          ```

          The behavior is such because the generated `Makefile` is located in
          `package/Makefile`, and `make` is executed under `package/`. In order
          to find `other/header.h`, its path relative to `package/` is given.

        removed_copts: Similar to `copts` but for flags **removed** from the
            compilation command.

            For example:
            ```
            ddk_module(
                name = "my_module",
                removed_copts = ["-Werror"],
                srcs = ["my_module.c"],
            )
            ```
            Then the content of generated Makefile is semantically equivalent to:

            ```
            CFLAGS_REMOVE_my_module.o += -Werror
            ```

            Note: Due to implementation details of Kleaf flags in `copts` are written to a file and
            provided to the compiler with the `@<arg_file>` syntax, so they are not affected
            by `removed_copts` implemented by `CFLAGS_REMOVE_`. To remove flags from the Bazel
            `copts` list, do so directly.

        asopts: Similar to `copts` but for assembly.

            For example:
            ```
            ddk_module(
                name = "my_module",
                asopts = ["-ansi"],
                srcs = ["my_module.S"],
            )
            ```
            Then the content of generated Makefile is semantically equivalent to:

            ```
            AFLAGS_my_module.o += -ansi
            ```
        linkopts: Similar to `copts` but for linking the module.

            For example:
            ```
            ddk_module(
                name = "my_module",
                linkopts = ["-lc"],
                out = "my_module.ko",
                # ...
            )
            ```
            Then the content of generated Makefile is semantically equivalent to:

            ```
            LDFLAGS_my_module.ko += -lc
            ```
        config: **EXPERIMENTAL**. The parent [ddk_config](#ddk_config) that encapsulates
            Kconfig/defconfig.

        kconfig: The Kconfig files for this external module.

          See
          [`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
          for its format.

          Kconfig is optional for a `ddk_module`. The final Kconfig known by
          this module consists of the following:

          - Kconfig from `kernel_build`
          - Kconfig from dependent modules, if any
          - Kconfig of this module, if any

          For legacy reasons, this is singular and accepts a single target. If multiple `Kconfig`
          files should be added, use a
          [`filegroup`](https://bazel.build/reference/be/general#filegroup) to wrap the files.
        defconfig: The `defconfig` file.

          Items must already be declared in `kconfig`. An item not declared
          in Kconfig and inherited Kconfig files is silently dropped.

          An item declared in `kconfig` without a specific value in `defconfig`
          uses default value specified in `kconfig`.
        generate_btf: Allows generation of BTF type information for the module.
          See [kernel_module.generate_btf](#kernel_module-generate_btf)
        autofdo_profile: Label to an AutoFDO profile.
        debug_info_for_profiling: If true, enables extra debug information to be emitted to make
            profile matching during AutoFDO more accurate.
        **kwargs: Additional attributes to the internal rule.
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if textual_hdrs:
        # buildifier: disable=print
        print("\nWARNING: textual_hdrs deprecated, use `hdrs` instead.")

    module_hdrs = (hdrs or []) + (textual_hdrs or [])

    ddk_module_config(
        name = name + "_config",
        parent = config,
        defconfig = defconfig,
        kconfig = kconfig,
        kernel_build = kernel_build,
        module_deps = deps,
        module_hdrs = module_hdrs,
        generate_btf = generate_btf,
        **kwargs
    )

    kernel_module(
        name = name,
        kernel_build = kernel_build,
        srcs = [],
        # Set it to empty list, not None, so kernel_module() doesn't fallback to {name}.ko.
        # _kernel_module_impl infers the list of outs from internal_ddk_makefiles_dir.
        outs = [],
        generate_btf = generate_btf,
        internal_ddk_makefiles_dir = ":{name}_makefiles".format(name = name),
        # This is used in build_cleaner.
        internal_module_symvers_name = "{name}_Module.symvers".format(name = name),
        internal_drop_modules_order = True,
        internal_exclude_kernel_build_module_srcs = True,
        internal_ddk_config = name + "_config",
        internal_mnemonic = "DDK module",
        **kwargs
    )

    private_kwargs = dict(kwargs)
    private_kwargs["visibility"] = ["//visibility:private"]

    flattened_conditional_srcs = flatten_conditional_srcs(
        module_name = name,
        conditional_srcs = conditional_srcs,
        **private_kwargs
    )

    makefiles(
        name = name + "_makefiles",
        kernel_build = kernel_build,
        module_srcs = (srcs or []) + flattened_conditional_srcs,
        module_crate_root = crate_root,
        module_hdrs = module_hdrs,
        module_includes = includes,
        module_linux_includes = linux_includes,
        module_out = out,
        module_deps = deps,
        module_local_defines = local_defines,
        module_copts = copts,
        module_removed_copts = removed_copts,
        module_asopts = asopts,
        module_linkopts = linkopts,
        module_autofdo_profile = autofdo_profile,
        module_debug_info_for_profiling = debug_info_for_profiling,
        target_type = "module",
        top_level_makefile = True,
        kbuild_has_linux_include = True,
        **private_kwargs
    )
