<!-- Generated with Stardoc: http://skydoc.bazel.build -->

All public rules and macros to build the kernel.

[TOC]

<a id="android_filegroup"></a>

## android_filegroup

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "android_filegroup")

android_filegroup(<a href="#android_filegroup-name">name</a>, <a href="#android_filegroup-srcs">srcs</a>, <a href="#android_filegroup-cpu">cpu</a>)
</pre>

Like filegroup, but applies transitions to Android.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="android_filegroup-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="android_filegroup-srcs"></a>srcs |  Sources of the filegroup.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="android_filegroup-cpu"></a>cpu |  Architecture.   | String | optional |  `"arm64"`  |


<a id="checkpatch"></a>

## checkpatch

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "checkpatch")

checkpatch(<a href="#checkpatch-name">name</a>, <a href="#checkpatch-checkpatch_pl">checkpatch_pl</a>, <a href="#checkpatch-ignorelist">ignorelist</a>)
</pre>

Run `checkpatch.sh` at the root of this package.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="checkpatch-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="checkpatch-checkpatch_pl"></a>checkpatch_pl |  Label to `checkpatch.pl`.<br><br>This is usually `//<common_package>:scripts/checkpatch.pl`.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="checkpatch-ignorelist"></a>ignorelist |  checkpatch ignorelist   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@kleaf//build/kernel/static_analysis:checkpatch_ignorelist"`  |


<a id="ddk_config"></a>

## ddk_config

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_config")

ddk_config(<a href="#ddk_config-name">name</a>, <a href="#ddk_config-deps">deps</a>, <a href="#ddk_config-defconfig">defconfig</a>, <a href="#ddk_config-kconfigs">kconfigs</a>, <a href="#ddk_config-kernel_build">kernel_build</a>)
</pre>

**EXPERIMENTAL.** A target that can later be used to configure a [`ddk_module`](#ddk_module).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ddk_config-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ddk_config-deps"></a>deps |  See [ddk_module.deps](#ddk_module-deps).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="ddk_config-defconfig"></a>defconfig |  The `defconfig` file.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="ddk_config-kconfigs"></a>kconfigs |  The extra `Kconfig` files for external modules that use this config.<br><br>See [`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html) for its format.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="ddk_config-kernel_build"></a>kernel_build |  [`kernel_build`](#kernel_build).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="ddk_headers"></a>

## ddk_headers

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_headers")

ddk_headers(<a href="#ddk_headers-name">name</a>, <a href="#ddk_headers-hdrs">hdrs</a>, <a href="#ddk_headers-defconfigs">defconfigs</a>, <a href="#ddk_headers-includes">includes</a>, <a href="#ddk_headers-kconfigs">kconfigs</a>, <a href="#ddk_headers-linux_includes">linux_includes</a>, <a href="#ddk_headers-textual_hdrs">textual_hdrs</a>)
</pre>

A rule that exports a list of header files to be used in DDK.

Example:

```
ddk_headers(
   name = "headers",
   hdrs = ["include/module.h", "template.c"],
   includes = ["include"],
)
```

`ddk_headers` can be chained; that is, a `ddk_headers` target can re-export
another `ddk_headers` target. For example:

```
ddk_headers(
   name = "foo",
   hdrs = ["include_foo/foo.h"],
   includes = ["include_foo"],
)
ddk_headers(
   name = "headers",
   hdrs = [":foo", "include/module.h"],
   includes = ["include"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ddk_headers-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ddk_headers-hdrs"></a>hdrs |  One of the following:<br><br>- Local header files to be exported. You may also need to set the `includes` attribute. - Other `ddk_headers` targets to be re-exported.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="ddk_headers-defconfigs"></a>defconfigs |  `defconfig` files.<br><br>Items must already be declared in `kconfigs`. An item not declared in Kconfig and inherited Kconfig files is silently dropped.<br><br>An item declared in `kconfigs` without a specific value in `defconfigs` uses default value specified in `kconfigs`.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="ddk_headers-includes"></a>includes |  A list of directories, relative to the current package, that are re-exported as include directories.<br><br>[`ddk_module`](#ddk_module) with `deps` including this target automatically adds the given include directory in the generated `Kbuild` files.<br><br>You still need to add the actual header files to `hdrs`.   | List of strings | optional |  `[]`  |
| <a id="ddk_headers-kconfigs"></a>kconfigs |  Kconfig files.<br><br>See [`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html) for its format.<br><br>Kconfig is optional for a `ddk_module`. The final Kconfig known by this module consists of the following:<br><br>- Kconfig from `kernel_build` - Kconfig from dependent modules, if any - Kconfig of this module, if any   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="ddk_headers-linux_includes"></a>linux_includes |  Like `includes` but specified in `LINUXINCLUDES` instead.<br><br>Setting this attribute allows you to override headers from `${KERNEL_DIR}`. See "Order of includes" in [`ddk_module`](#ddk_module) for details.<br><br>Like `includes`, `linux_includes` is applied to dependent `ddk_module`s.   | List of strings | optional |  `[]`  |
| <a id="ddk_headers-textual_hdrs"></a>textual_hdrs |  DEPRECATED. Use `hdrs` instead.<br><br>The list of header files to be textually included by sources.<br><br>This is the location for declaring header files that cannot be compiled on their own; that is, they always need to be textually included by other source files to build valid code.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="ddk_headers_archive"></a>

## ddk_headers_archive

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_headers_archive")

ddk_headers_archive(<a href="#ddk_headers_archive-name">name</a>, <a href="#ddk_headers_archive-srcs">srcs</a>)
</pre>

An archive of [`ddk_headers`](#ddk_headers).

The archive includes all headers, as well as a `BUILD` file that is
semantically identical to the original `ddk_headers` definition.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ddk_headers_archive-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ddk_headers_archive-srcs"></a>srcs |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="ddk_prebuilt_object"></a>

## ddk_prebuilt_object

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_prebuilt_object")

ddk_prebuilt_object(<a href="#ddk_prebuilt_object-name">name</a>, <a href="#ddk_prebuilt_object-src">src</a>, <a href="#ddk_prebuilt_object-cmd">cmd</a>, <a href="#ddk_prebuilt_object-config">config</a>, <a href="#ddk_prebuilt_object-config_bool_value">config_bool_value</a>)
</pre>

Wraps a `<stem>.o` file so it can be used in [ddk_module.srcs](#ddk_module-srcs).

An optional `.<stem>.o.cmd` file may be provided. If not provided, a fake
`.<stem>.o.cmd` is generated.

Example:

```
ddk_prebuilt_object(
    name = "foo",
    src = "foo.o",
)

ddk_module(
    name = "mymod",
    deps = [":foo"],
    # ...
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ddk_prebuilt_object-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ddk_prebuilt_object-src"></a>src |  The .o file, e.g. `foo.o`   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="ddk_prebuilt_object-cmd"></a>cmd |  The .cmd file, e.g. `.foo.o.cmd`. If missing, an empty file is provided.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="ddk_prebuilt_object-config"></a>config |  If set, name of the config with the `CONFIG_` prefix. The prebuilt object is only linked when the given config matches `config_bool_value`.   | String | optional |  `""`  |
| <a id="ddk_prebuilt_object-config_bool_value"></a>config_bool_value |  If `config` is set, and `config_bool_value == True`, the object is only included if the config is `y` or `m`. If `config` is set and `config_bool_value == False`, the object is only included if the config is not set.   | Boolean | optional |  `False`  |


<a id="ddk_uapi_headers"></a>

## ddk_uapi_headers

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_uapi_headers")

ddk_uapi_headers(<a href="#ddk_uapi_headers-name">name</a>, <a href="#ddk_uapi_headers-srcs">srcs</a>, <a href="#ddk_uapi_headers-out">out</a>, <a href="#ddk_uapi_headers-kernel_build">kernel_build</a>)
</pre>

A rule that generates a sanitized UAPI header tarball.

Example:

```
ddk_uapi_headers(
   name = "my_headers",
   srcs = glob(["include/uapi/**/*.h"]),
   out = "my_headers.tar.gz",
   kernel_build = "//common:kernel_aarch64",
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ddk_uapi_headers-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ddk_uapi_headers-srcs"></a>srcs |  UAPI headers files which can be sanitized by "make headers_install"   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="ddk_uapi_headers-out"></a>out |  Name of the output tarball   | String | required |  |
| <a id="ddk_uapi_headers-kernel_build"></a>kernel_build |  [`kernel_build`](#kernel_build).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="dependency_graph_drawer"></a>

## dependency_graph_drawer

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "dependency_graph_drawer")

dependency_graph_drawer(<a href="#dependency_graph_drawer-name">name</a>, <a href="#dependency_graph_drawer-adjacency_list">adjacency_list</a>, <a href="#dependency_graph_drawer-colorful">colorful</a>)
</pre>

A rule that creates a [Graphviz](https://graphviz.org/) diagram file.

* Inputs:
  A json file describing a graph as an adjacency list.

* Outputs:
  A `dependency_graph.dot` file containing the diagram representation.

* NOTE: For further simplification of the resulting diagram
  [tred utility](https://graphviz.org/docs/cli/tred/) from the CLI can
  be used as in the following example:
  ```
  tred dependency_graph.dot > simplified.dot
  ```

* Example:
  ```
  dependency_graph_drawer(
      name = "db845c_dependency_graph",
      adjacency_list = ":db845c_dependencies",
  )
  ```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="dependency_graph_drawer-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="dependency_graph_drawer-adjacency_list"></a>adjacency_list |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="dependency_graph_drawer-colorful"></a>colorful |  Whether outgoing edges from every node are colored.   | Boolean | optional |  `False`  |


<a id="dependency_graph_extractor"></a>

## dependency_graph_extractor

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "dependency_graph_extractor")

dependency_graph_extractor(<a href="#dependency_graph_extractor-name">name</a>, <a href="#dependency_graph_extractor-enable_add_vmlinux">enable_add_vmlinux</a>, <a href="#dependency_graph_extractor-exclude_base_kernel_modules">exclude_base_kernel_modules</a>, <a href="#dependency_graph_extractor-kernel_build">kernel_build</a>,
                           <a href="#dependency_graph_extractor-kernel_modules">kernel_modules</a>)
</pre>

A rule that extracts a symbol dependency graph from a kernel build and modules.

It works by matching undefined symbols from one module with exported symbols from other.

* Inputs:
  It receives a Kernel build target, where the analysis will run (vmlinux + in-tree modules),
   aditionally a list of external modules can be accepted.

* Outputs:
  A `dependency_graph.json` file describing the graph as an adjacency list.

* Example:
  ```
  dependency_graph_extractor(
      name = "db845c_dependencies",
      kernel_build = ":db845c",
      # kernel_modules = [],
  )
  ```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="dependency_graph_extractor-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="dependency_graph_extractor-enable_add_vmlinux"></a>enable_add_vmlinux |  If `True` enables `kernel_build_add_vmlinux` transition.   | Boolean | optional |  `True`  |
| <a id="dependency_graph_extractor-exclude_base_kernel_modules"></a>exclude_base_kernel_modules |  Whether the analysis should made for only external modules.   | Boolean | optional |  `False`  |
| <a id="dependency_graph_extractor-kernel_build"></a>kernel_build |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="dependency_graph_extractor-kernel_modules"></a>kernel_modules |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="dtb_image"></a>

## dtb_image

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "dtb_image")

dtb_image(<a href="#dtb_image-name">name</a>, <a href="#dtb_image-srcs">srcs</a>, <a href="#dtb_image-out">out</a>)
</pre>

Build `dtb` image.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="dtb_image-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="dtb_image-srcs"></a>srcs |  DTB sources to add to the dtb image   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="dtb_image-out"></a>out |  Name of `dtb` image.<br><br>Default to `name` if not set   | String | optional |  `""`  |


<a id="dtbo"></a>

## dtbo

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "dtbo")

dtbo(<a href="#dtbo-name">name</a>, <a href="#dtbo-srcs">srcs</a>, <a href="#dtbo-config_file">config_file</a>, <a href="#dtbo-kernel_build">kernel_build</a>)
</pre>

Build dtbo.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="dtbo-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="dtbo-srcs"></a>srcs |  List of `*.dtbo` files used to package the `dtbo.img`. This corresponds to `MKDTIMG_DTBOS` in build configs; see example below.<br><br>Example: <pre><code>kernel_build(&#10;    name = "tuna_kernel",&#10;    outs = [&#10;        "path/to/foo.dtbo",&#10;        "path/to/bar.dtbo",&#10;    ],&#10;)&#10;dtbo(&#10;    name = "tuna_images",&#10;    kernel_build = ":tuna_kernel",&#10;    srcs = [&#10;        ":tuna_kernel/path/to/foo.dtbo",&#10;        ":tuna_kernel/path/to/bar.dtbo",&#10;    ],&#10;)</code></pre>   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="dtbo-config_file"></a>config_file |  A config file to create dtbo image by cfg_create command.<br><br>If set, use mkdtimg cfg_create with the given config file, instead of mkdtimg create   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="dtbo-kernel_build"></a>kernel_build |  The [`kernel_build`](#kernel_build).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="extract_symbols"></a>

## extract_symbols

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "extract_symbols")

extract_symbols(<a href="#extract_symbols-name">name</a>, <a href="#extract_symbols-src">src</a>, <a href="#extract_symbols-enable_add_vmlinux">enable_add_vmlinux</a>, <a href="#extract_symbols-kernel_build">kernel_build</a>, <a href="#extract_symbols-kernel_modules">kernel_modules</a>,
                <a href="#extract_symbols-kernel_modules_exclude_list">kernel_modules_exclude_list</a>, <a href="#extract_symbols-kmi_symbol_list_add_only">kmi_symbol_list_add_only</a>, <a href="#extract_symbols-module_grouping">module_grouping</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="extract_symbols-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="extract_symbols-src"></a>src |  Source `abi_gki_*` file. Used when `kmi_symbol_list_add_only`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="extract_symbols-enable_add_vmlinux"></a>enable_add_vmlinux |  If `True` enables `kernel_build_add_vmlinux` transition.   | Boolean | optional |  `True`  |
| <a id="extract_symbols-kernel_build"></a>kernel_build |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="extract_symbols-kernel_modules"></a>kernel_modules |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="extract_symbols-kernel_modules_exclude_list"></a>kernel_modules_exclude_list |  Base name list of kernel modules to exclude from.   | List of strings | optional |  `[]`  |
| <a id="extract_symbols-kmi_symbol_list_add_only"></a>kmi_symbol_list_add_only |  -   | Boolean | optional |  `False`  |
| <a id="extract_symbols-module_grouping"></a>module_grouping |  -   | Boolean | optional |  `True`  |


<a id="gki_artifacts"></a>

## gki_artifacts

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "gki_artifacts")

gki_artifacts(<a href="#gki_artifacts-name">name</a>, <a href="#gki_artifacts-arch">arch</a>, <a href="#gki_artifacts-boot_img_sizes">boot_img_sizes</a>, <a href="#gki_artifacts-gki_kernel_cmdline">gki_kernel_cmdline</a>, <a href="#gki_artifacts-kernel_build">kernel_build</a>, <a href="#gki_artifacts-mkbootimg">mkbootimg</a>)
</pre>

`BUILD_GKI_ARTIFACTS`. Build boot images and optionally `boot-img.tar.gz` as default outputs.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="gki_artifacts-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="gki_artifacts-arch"></a>arch |  `ARCH`.   | String | required |  |
| <a id="gki_artifacts-boot_img_sizes"></a>boot_img_sizes |  A dictionary, with key is the compression algorithm, and value is the size of the boot image.<br><br>For example: <pre><code>{&#10;    "":    str(64 * 1024 * 1024), # For Image and boot.img&#10;    "lz4": str(64 * 1024 * 1024), # For Image.lz4 and boot-lz4.img&#10;}</code></pre>   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="gki_artifacts-gki_kernel_cmdline"></a>gki_kernel_cmdline |  `GKI_KERNEL_CMDLINE`.   | String | optional |  `""`  |
| <a id="gki_artifacts-kernel_build"></a>kernel_build |  The [`kernel_build`](kernel.md#kernel_build) that provides all `Image` and `Image.*`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="gki_artifacts-mkbootimg"></a>mkbootimg |  path to the `mkbootimg.py` script; `MKBOOTIMG_PATH`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@kleaf//tools/mkbootimg:mkbootimg.py"`  |


<a id="gki_artifacts_prebuilts"></a>

## gki_artifacts_prebuilts

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "gki_artifacts_prebuilts")

gki_artifacts_prebuilts(<a href="#gki_artifacts_prebuilts-name">name</a>, <a href="#gki_artifacts_prebuilts-srcs">srcs</a>, <a href="#gki_artifacts_prebuilts-outs">outs</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="gki_artifacts_prebuilts-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="gki_artifacts_prebuilts-srcs"></a>srcs |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="gki_artifacts_prebuilts-outs"></a>outs |  -   | List of strings | optional |  `[]`  |


<a id="initramfs"></a>

## initramfs

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "initramfs")

initramfs(<a href="#initramfs-name">name</a>, <a href="#initramfs-deps">deps</a>, <a href="#initramfs-create_modules_order">create_modules_order</a>, <a href="#initramfs-kernel_modules_install">kernel_modules_install</a>, <a href="#initramfs-modules_blocklist">modules_blocklist</a>,
          <a href="#initramfs-modules_charger_list">modules_charger_list</a>, <a href="#initramfs-modules_list">modules_list</a>, <a href="#initramfs-modules_options">modules_options</a>, <a href="#initramfs-modules_recovery_list">modules_recovery_list</a>,
          <a href="#initramfs-ramdisk_compression">ramdisk_compression</a>, <a href="#initramfs-ramdisk_compression_args">ramdisk_compression_args</a>, <a href="#initramfs-trim_unused_modules">trim_unused_modules</a>, <a href="#initramfs-vendor_boot_name">vendor_boot_name</a>,
          <a href="#initramfs-vendor_ramdisk_dev_nodes">vendor_ramdisk_dev_nodes</a>)
</pre>

Build initramfs.

When included in a `pkg_files` target included by `pkg_install`, this rule copies the following to
`destdir`:

- `initramfs.img`
- `modules.load`
- `modules.load.recovery`
- `modules.load.charger`
- `vendor_boot.modules.load`
- `vendor_boot.modules.load.recovery`
- `vendor_boot.modules.load.charger`

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="initramfs-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="initramfs-deps"></a>deps |  A list of additional dependencies to build initramfs.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="initramfs-create_modules_order"></a>create_modules_order |  Whether to create and keep a modules.order file generated by a postorder traversal of the `kernel_modules_install` sources. It defaults to `True`.   | Boolean | optional |  `True`  |
| <a id="initramfs-kernel_modules_install"></a>kernel_modules_install |  The [`kernel_modules_install`](#kernel_modules_install).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="initramfs-modules_blocklist"></a>modules_blocklist |  A file containing a list of modules which are blocked from being loaded.<br><br>This file is copied directly to staging directory, and should be in the format: <pre><code>blocklist module_name</code></pre>   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="initramfs-modules_charger_list"></a>modules_charger_list |  A file containing a list of modules to load when booting intocharger mode.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="initramfs-modules_list"></a>modules_list |  A file containing list of modules to use for `vendor_boot.modules.load`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="initramfs-modules_options"></a>modules_options |  a file copied to `/lib/modules/<kernel_version>/modules.options` on the ramdisk.<br><br>Lines in the file should be of the form: <pre><code>options &lt;modulename&gt; &lt;param1&gt;=&lt;val&gt; &lt;param2&gt;=&lt;val&gt; ...</code></pre>   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="initramfs-modules_recovery_list"></a>modules_recovery_list |  A file containing a list of modules to load when booting into recovery.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="initramfs-ramdisk_compression"></a>ramdisk_compression |  If provided it specfies the format used for any ramdisks generated.If not provided a fallback value from build.config is used.   | String | optional |  `""`  |
| <a id="initramfs-ramdisk_compression_args"></a>ramdisk_compression_args |  Command line arguments passed only to lz4 command to control compression level.   | String | optional |  `""`  |
| <a id="initramfs-trim_unused_modules"></a>trim_unused_modules |  If `True` then modules not mentioned in modules.load are removed from the initramfs. It defaults to `False`.   | Boolean | optional |  `False`  |
| <a id="initramfs-vendor_boot_name"></a>vendor_boot_name |  Name of `vendor_boot` image.<br><br>* If `"vendor_boot"`, build `vendor_boot.img` * If `"vendor_kernel_boot"`, build `vendor_kernel_boot.img` * If `None`, skip building `vendor_boot`.   | String | optional |  `""`  |
| <a id="initramfs-vendor_ramdisk_dev_nodes"></a>vendor_ramdisk_dev_nodes |  List of dev nodes description files which describes special device files to be added to the vendor ramdisk. File format is as accepted by mkbootfs. See `mkbootfs -h` for more details.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kernel_build_config"></a>

## kernel_build_config

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_build_config")

kernel_build_config(<a href="#kernel_build_config-name">name</a>, <a href="#kernel_build_config-deps">deps</a>, <a href="#kernel_build_config-srcs">srcs</a>)
</pre>

Create a build.config file by concatenating build config fragments.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_build_config-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_build_config-deps"></a>deps |  Additional build config dependencies.<br><br>These include build configs that are indirectly `source`d by items in `srcs`. Unlike `srcs`, they are not be emitted in the output.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_build_config-srcs"></a>srcs |  List of build config fragments.<br><br>Order matters. To prevent buildifier from sorting the list, use the `# do not sort` magic line. For example:<br><br><pre><code>kernel_build_config(&#10;    name = "build.config.foo.mixed",&#10;    srcs = [&#10;        # do not sort&#10;        "build.config.mixed",&#10;        "build.config.foo",&#10;    ],&#10;)</code></pre>   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kernel_compile_commands"></a>

## kernel_compile_commands

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_compile_commands")

kernel_compile_commands(<a href="#kernel_compile_commands-name">name</a>, <a href="#kernel_compile_commands-deps">deps</a>, <a href="#kernel_compile_commands-kernel_build">kernel_build</a>)
</pre>

Define an executable that creates `compile_commands.json` from kernel targets.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_compile_commands-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_compile_commands-deps"></a>deps |  The targets to extract from. The following are allowed:<br><br>- [`kernel_build`](#kernel_build) - [`kernel_module`](#kernel_module) - [`ddk_module`](#ddk_module) - [`kernel_module_group`](#kernel_module_group)   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_compile_commands-kernel_build"></a>kernel_build |  The `kernel_build` rule to extract from.<br><br>Deprecated:     Use `deps` instead.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="kernel_filegroup"></a>

## kernel_filegroup

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_filegroup")

kernel_filegroup(<a href="#kernel_filegroup-name">name</a>, <a href="#kernel_filegroup-deps">deps</a>, <a href="#kernel_filegroup-srcs">srcs</a>, <a href="#kernel_filegroup-outs">outs</a>, <a href="#kernel_filegroup-all_module_names">all_module_names</a>, <a href="#kernel_filegroup-check_post_defconfig_fragments">check_post_defconfig_fragments</a>,
                 <a href="#kernel_filegroup-check_pre_defconfig_fragments">check_pre_defconfig_fragments</a>, <a href="#kernel_filegroup-collect_unstripped_modules">collect_unstripped_modules</a>, <a href="#kernel_filegroup-config_out_dir">config_out_dir</a>,
                 <a href="#kernel_filegroup-config_out_dir_files">config_out_dir_files</a>, <a href="#kernel_filegroup-ddk_module_defconfig_fragments">ddk_module_defconfig_fragments</a>, <a href="#kernel_filegroup-ddk_module_headers">ddk_module_headers</a>, <a href="#kernel_filegroup-defconfig">defconfig</a>,
                 <a href="#kernel_filegroup-env_setup_script">env_setup_script</a>, <a href="#kernel_filegroup-exec_platform">exec_platform</a>, <a href="#kernel_filegroup-expected_toolchain_version">expected_toolchain_version</a>,
                 <a href="#kernel_filegroup-generated_headers_for_module_archive">generated_headers_for_module_archive</a>, <a href="#kernel_filegroup-gki_artifacts">gki_artifacts</a>, <a href="#kernel_filegroup-images">images</a>, <a href="#kernel_filegroup-internal_outs">internal_outs</a>,
                 <a href="#kernel_filegroup-kernel_release">kernel_release</a>, <a href="#kernel_filegroup-kernel_uapi_headers">kernel_uapi_headers</a>, <a href="#kernel_filegroup-module_env_archive">module_env_archive</a>, <a href="#kernel_filegroup-modules_prepare_archive">modules_prepare_archive</a>,
                 <a href="#kernel_filegroup-post_defconfig_fragments">post_defconfig_fragments</a>, <a href="#kernel_filegroup-pre_defconfig_fragments">pre_defconfig_fragments</a>, <a href="#kernel_filegroup-strip_modules">strip_modules</a>, <a href="#kernel_filegroup-target_platform">target_platform</a>)
</pre>

**EXPERIMENTAL.** The API of `kernel_filegroup` rapidly changes and
is not backwards compatible with older builds. The usage of `kernel_filegroup`
is limited to the implementation detail of Kleaf (in particular,
[`define_common_kernels`](#define_common_kernels)). Do not use
`kernel_filegroup` directly. See `download_prebuilt.md` for details.

Specify a list of kernel prebuilts.

This is similar to [`filegroup`](https://docs.bazel.build/versions/main/be/general.html#filegroup)
that gives a convenient name to a collection of targets, which can be referenced from other rules.

It can be used in the `base_kernel` attribute of a [`kernel_build`](#kernel_build).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_filegroup-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_filegroup-deps"></a>deps |  A list of additional labels that participates in implementing the providers.<br><br>This usually contains a list of prebuilts.<br><br>Unlike srcs, these labels are NOT added to the [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html)   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-srcs"></a>srcs |  The list of labels that are members of this file group.<br><br>This usually contains a list of prebuilts, e.g. `vmlinux`, `Image.lz4`, `kernel-headers.tar.gz`, etc.<br><br>Not to be confused with [`kernel_srcs`](#kernel_filegroup-kernel_srcs).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-outs"></a>outs |  Keys: from `_kernel_build.outs`. Values: path under `$OUT_DIR`.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="kernel_filegroup-all_module_names"></a>all_module_names |  `module_outs` and `module_implicit_outs` of the original [`kernel_build`](#kernel_build) target.   | List of strings | optional |  `[]`  |
| <a id="kernel_filegroup-check_post_defconfig_fragments"></a>check_post_defconfig_fragments |  See [kernel_build.check_defconfig](#kernel_build-check_defconfig).   | String | optional |  `"match"`  |
| <a id="kernel_filegroup-check_pre_defconfig_fragments"></a>check_pre_defconfig_fragments |  See [kernel_build.check_defconfig](#kernel_build-check_defconfig).   | String | optional |  `"match"`  |
| <a id="kernel_filegroup-collect_unstripped_modules"></a>collect_unstripped_modules |  See [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).<br><br>Unlike `kernel_build`, this has default value `True` because [`kernel_abi`](#kernel_abi) sets [`define_abi_targets`](#kernel_abi-define_abi_targets) to `True` by default, which in turn sets `collect_unstripped_modules` to `True` by default.   | Boolean | optional |  `True`  |
| <a id="kernel_filegroup-config_out_dir"></a>config_out_dir |  Directory to support `kernel_config`   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-config_out_dir_files"></a>config_out_dir_files |  Files in `config_out_dir`   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-ddk_module_defconfig_fragments"></a>ddk_module_defconfig_fragments |  Additional defconfig fragments for dependant DDK modules.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-ddk_module_headers"></a>ddk_module_headers |  Additional `ddk_headers` for dependant DDK modules.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-defconfig"></a>defconfig |  See [kernel_build.defconfig](#kernel_build-defconfig). Only a file is allowed; allmodconfig is currently not supported.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-env_setup_script"></a>env_setup_script |  Setup script from `kernel_env`   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-exec_platform"></a>exec_platform |  Execution platform, where the build is executed.<br><br>See https://bazel.build/extending/platforms.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="kernel_filegroup-expected_toolchain_version"></a>expected_toolchain_version |  Checks resolved toolchain version against this string.   | String | optional |  `""`  |
| <a id="kernel_filegroup-generated_headers_for_module_archive"></a>generated_headers_for_module_archive |  Archive from `kernel_build.generated_headers_for_module` that contains generated headers to be restored to $OUT_DIR to build external modules.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-gki_artifacts"></a>gki_artifacts |  A list of files that were built from the [`gki_artifacts`](#gki_artifacts) target. The `gki-info.txt` file should be part of that list.<br><br>If `kernel_release` is set, this attribute has no effect.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-images"></a>images |  A label providing files similar to a [`kernel_images`](#kernel_images) target.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-internal_outs"></a>internal_outs |  Keys: from `_kernel_build.internal_outs`. Values: path under `$OUT_DIR`.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="kernel_filegroup-kernel_release"></a>kernel_release |  A file providing the kernel release string. This is preferred over `gki_artifacts`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-kernel_uapi_headers"></a>kernel_uapi_headers |  The label pointing to `kernel-uapi-headers.tar.gz`.<br><br>This attribute should be set to the `kernel-uapi-headers.tar.gz` artifact built by the [`kernel_build`](#kernel_build) macro if the `kernel_filegroup` rule were a `kernel_build`.<br><br>Setting this attribute allows [`merged_kernel_uapi_headers`](#merged_kernel_uapi_headers) to work properly when this `kernel_filegroup` is set to the `base_kernel`.<br><br>For example: <pre><code>kernel_filegroup(&#10;    name = "kernel_aarch64_prebuilts",&#10;    srcs = [&#10;        "vmlinux",&#10;        # ...&#10;    ],&#10;    kernel_uapi_headers = "kernel-uapi-headers.tar.gz",&#10;)&#10;&#10;kernel_build(&#10;    name = "tuna",&#10;    base_kernel = ":kernel_aarch64_prebuilts",&#10;    # ...&#10;)&#10;&#10;merged_kernel_uapi_headers(&#10;    name = "tuna_merged_kernel_uapi_headers",&#10;    kernel_build = "tuna",&#10;    # ...&#10;)</code></pre>   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-module_env_archive"></a>module_env_archive |  Archive from `kernel_build.pack_module_env` that contains necessary source files to build external modules.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-modules_prepare_archive"></a>modules_prepare_archive |  Archive from `modules_prepare`   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_filegroup-post_defconfig_fragments"></a>post_defconfig_fragments |  See [kernel_build.post_defconfig_fragments](#kernel_build-post_defconfig_fragments).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-pre_defconfig_fragments"></a>pre_defconfig_fragments |  See [kernel_build.pre_defconfig_fragments](#kernel_build-pre_defconfig_fragments).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kernel_filegroup-strip_modules"></a>strip_modules |  See [`kernel_build.strip_modules`](#kernel_build-strip_modules).   | Boolean | optional |  `False`  |
| <a id="kernel_filegroup-target_platform"></a>target_platform |  Target platform that describes characteristics of the target device.<br><br>See https://bazel.build/extending/platforms.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="kernel_kythe"></a>

## kernel_kythe

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_kythe")

kernel_kythe(<a href="#kernel_kythe-name">name</a>, <a href="#kernel_kythe-corpus">corpus</a>, <a href="#kernel_kythe-kernel_build">kernel_build</a>)
</pre>

Extract Kythe source code index (kzip file) from a `kernel_build`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_kythe-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_kythe-corpus"></a>corpus |  A flag containing value of `KYTHE_CORPUS`. See [kythe.io/examples](https://kythe.io/examples).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="kernel_kythe-kernel_build"></a>kernel_build |  The `kernel_build` target to extract from.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="kernel_module_group"></a>

## kernel_module_group

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_module_group")

kernel_module_group(<a href="#kernel_module_group-name">name</a>, <a href="#kernel_module_group-srcs">srcs</a>)
</pre>

Like filegroup but for [`kernel_module`](#kernel_module)s or [`ddk_module`](#ddk_module)s.

Example:

```
# //package/my_subsystem

# Hide a.ko and b.ko because they are implementation details of my_subsystem
ddk_module(
    name = "a",
    visibility = ["//visibility:private"],
    ...
)

ddk_module(
    name = "b",
    visibility = ["//visibility:private"],
    ...
)

# my_subsystem is the public target that the device should depend on.
kernel_module_group(
    name = "my_subsystem",
    srcs = [":a", ":b"],
    visibility = ["//package/my_device:__subpackages__"],
)

# //package/my_device
kernel_modules_install(
    name = "my_device_modules_install",
    kernel_modules = [
        "//package/my_subsystem:my_subsystem", # This is equivalent to specifying a and b.
    ],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_module_group-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_module_group-srcs"></a>srcs |  List of [`kernel_module`](#kernel_module)s or [`ddk_module`](#ddk_module)s.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kernel_modules_install"></a>

## kernel_modules_install

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_modules_install")

kernel_modules_install(<a href="#kernel_modules_install-name">name</a>, <a href="#kernel_modules_install-outs">outs</a>, <a href="#kernel_modules_install-kernel_build">kernel_build</a>, <a href="#kernel_modules_install-kernel_modules">kernel_modules</a>)
</pre>

Generates a rule that runs depmod in the module installation directory.

When including this rule to the `srcs` attribute of a `pkg_files` rule that is
included in a `pkg_install` rule,
all external kernel modules specified in `kernel_modules` are included in
distribution.  This excludes `module_outs` in `kernel_build` to avoid conflicts.

Example:
```
kernel_modules_install(
    name = "foo_modules_install",
    kernel_modules = [               # kernel_module rules
        "//path/to/nfc:nfc_module",
    ],
)
kernel_build(
    name = "foo",
    outs = ["vmlinux"],
    module_outs = ["core_module.ko"],
)
pkg_files(
    name = "foo_dist_files",
    srcs = [
        ":foo",                      # Includes core_module.ko and vmlinux
        ":foo_modules_install",      # Includes nfc_module
    ],
)
pkg_install(
    name = "foo_dist",
    srcs = [":foo_dist_files"],
)
```
In `foo_dist`, specifying `foo_modules_install` in `data` won't include
`core_module.ko`, because it is already included in `foo` in `data`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_modules_install-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_modules_install-outs"></a>outs |  A list of additional outputs from `make modules_install`.<br><br>Since external modules are returned by default, it can be used to obtain modules.* related files (results of depmod). Only files with allowed names can be added to outs. (`_OUT_ALLOWLIST`) <pre><code>_OUT_ALLOWLIST = ["modules.dep", "modules.alias", "modules.builtin", "modules.symbols", "modules.softdep"]</code></pre> Example: <pre><code>kernel_modules_install(&#10;    name = "foo_modules_install",&#10;    kernel_modules = [":foo_module_list"],&#10;    outs = [&#10;        "modules.dep",&#10;        "modules.alias",&#10;    ],&#10;)</code></pre>   | List of strings | optional |  `[]`  |
| <a id="kernel_modules_install-kernel_build"></a>kernel_build |  Label referring to the `kernel_build` module. Otherwise, it is inferred from `kernel_modules`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_modules_install-kernel_modules"></a>kernel_modules |  A list of labels referring to `kernel_module`s to install.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kernel_unstripped_modules_archive"></a>

## kernel_unstripped_modules_archive

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_unstripped_modules_archive")

kernel_unstripped_modules_archive(<a href="#kernel_unstripped_modules_archive-name">name</a>, <a href="#kernel_unstripped_modules_archive-kernel_build">kernel_build</a>, <a href="#kernel_unstripped_modules_archive-kernel_modules">kernel_modules</a>)
</pre>

Compress the unstripped modules into a tarball.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_unstripped_modules_archive-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_unstripped_modules_archive-kernel_build"></a>kernel_build |  A [`kernel_build`](#kernel_build) to retrieve unstripped in-tree modules from.<br><br>It requires `collect_unstripped_modules = True`. If the `kernel_build` has a `base_kernel`, the rule also retrieves unstripped in-tree modules from the `base_kernel`, and requires the `base_kernel` has `collect_unstripped_modules = True`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kernel_unstripped_modules_archive-kernel_modules"></a>kernel_modules |  A list of external [`kernel_module`](#kernel_module)s to retrieve unstripped external modules from.<br><br>It requires that the base `kernel_build` has `collect_unstripped_modules = True`.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="merge_kzip"></a>

## merge_kzip

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "merge_kzip")

merge_kzip(<a href="#merge_kzip-name">name</a>, <a href="#merge_kzip-srcs">srcs</a>)
</pre>

Merge .kzip files

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="merge_kzip-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="merge_kzip-srcs"></a>srcs |  kzip files   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="merge_module_symvers"></a>

## merge_module_symvers

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "merge_module_symvers")

merge_module_symvers(<a href="#merge_module_symvers-name">name</a>, <a href="#merge_module_symvers-srcs">srcs</a>)
</pre>

Merge Module.symvers files

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="merge_module_symvers-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="merge_module_symvers-srcs"></a>srcs |  It accepts targets from any of the following rules:   - [ddk_module](#ddk_module)   - [kernel_module_group](#kernel_module_group)   - [kernel_build](#kernel_build) (it requires `keep_module_symvers = True` to be set).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="merged_kernel_uapi_headers"></a>

## merged_kernel_uapi_headers

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "merged_kernel_uapi_headers")

merged_kernel_uapi_headers(<a href="#merged_kernel_uapi_headers-name">name</a>, <a href="#merged_kernel_uapi_headers-kernel_build">kernel_build</a>, <a href="#merged_kernel_uapi_headers-kernel_modules">kernel_modules</a>)
</pre>

Merge `kernel-uapi-headers.tar.gz`.

On certain devices, kernel modules install additional UAPI headers. Use this
rule to add these module UAPI headers to the final `kernel-uapi-headers.tar.gz`.

If there are conflicts of file names in the source tarballs, files higher in
the list have higher priority:
1. UAPI headers from the `base_kernel` of the `kernel_build` (ususally the GKI build)
2. UAPI headers from the `kernel_build` (usually the device build)
3. UAPI headers from ``kernel_modules`. Order among the modules are undetermined.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="merged_kernel_uapi_headers-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="merged_kernel_uapi_headers-kernel_build"></a>kernel_build |  The `kernel_build`   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="merged_kernel_uapi_headers-kernel_modules"></a>kernel_modules |  A list of external `kernel_module`s to merge `kernel-uapi-headers.tar.gz`   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="modinfo_summary_report"></a>

## modinfo_summary_report

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "modinfo_summary_report")

modinfo_summary_report(<a href="#modinfo_summary_report-name">name</a>, <a href="#modinfo_summary_report-deps">deps</a>)
</pre>

Generate a report from kernel modules of the given kernel build.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="modinfo_summary_report-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="modinfo_summary_report-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="super_image"></a>

## super_image

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "super_image")

super_image(<a href="#super_image-name">name</a>, <a href="#super_image-out">out</a>, <a href="#super_image-super_img_size">super_img_size</a>, <a href="#super_image-system_dlkm_image">system_dlkm_image</a>, <a href="#super_image-vendor_dlkm_image">vendor_dlkm_image</a>)
</pre>

Build super image.

Optionally takes in a "system_dlkm" and "vendor_dlkm".

When included in a `pkg_files` target included by `pkg_install`, this rule copies `super.img` to
`destdir`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="super_image-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="super_image-out"></a>out |  Image file name   | String | optional |  `"super.img"`  |
| <a id="super_image-super_img_size"></a>super_img_size |  Size of super.img   | Integer | optional |  `268435456`  |
| <a id="super_image-system_dlkm_image"></a>system_dlkm_image |  `system_dlkm_image` to include in super.img   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="super_image-vendor_dlkm_image"></a>vendor_dlkm_image |  `vendor_dlkm_image` to include in super.img   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="system_dlkm_image"></a>

## system_dlkm_image

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "system_dlkm_image")

system_dlkm_image(<a href="#system_dlkm_image-name">name</a>, <a href="#system_dlkm_image-deps">deps</a>, <a href="#system_dlkm_image-base">base</a>, <a href="#system_dlkm_image-build_flatten">build_flatten</a>, <a href="#system_dlkm_image-fs_types">fs_types</a>, <a href="#system_dlkm_image-internal_extra_archive_files">internal_extra_archive_files</a>,
                  <a href="#system_dlkm_image-kernel_modules_install">kernel_modules_install</a>, <a href="#system_dlkm_image-modules_blocklist">modules_blocklist</a>, <a href="#system_dlkm_image-modules_list">modules_list</a>, <a href="#system_dlkm_image-props">props</a>)
</pre>

Build system_dlkm partition image with signed GKI modules.

When included in a `pkg_files` target included by `pkg_install`, this rule copies the following to
`destdir`:

- `system_dlkm.[erofs|ext4].img` if `fs_types` is specified
- `system_dlkm.flatten.[erofs|ext4].img` if `build_flatten` is True
- `system_dlkm.modules.load`

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="system_dlkm_image-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="system_dlkm_image-deps"></a>deps |  A list of additional dependencies to build system_dlkm image.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="system_dlkm_image-base"></a>base |  The `system_dlkm_image()` corresponding to the `base_kernel` of the `kernel_build`. This is required for building a device-specific `system_dlkm` image. For example, if `base_kernel` of `kernel_build()` is `//common:kernel_aarch64`, then `base` is `//common:kernel_aarch64_system_dlkm_image`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="system_dlkm_image-build_flatten"></a>build_flatten |  When True it builds system_dlkm image with no `uname -r` in the path.   | Boolean | optional |  `False`  |
| <a id="system_dlkm_image-fs_types"></a>fs_types |  List of file systems type for `system_dlkm` images.<br><br>Supported filesystems for `system_dlkm` image are `ext4` and `erofs`. If not specified, build `system_dlkm.ext4.img` with ext4. Otherwise, build `system_dlkm.<fs>.img` for each file system type in the list.<br><br>If the name `system_dlkm.img` is needed, use a [`hermetc_genrule`](hemetic_tools.md#hermetc_genrule) to achieve this. Example:<br><br><pre><code>load("@kleaf//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_genrule")&#10;hermetic_genrule(&#10;    name = "tuna_system_dlkm_with_legacy_name",&#10;    srcs = [":tuna_system_dlkm"],&#10;    outs = ["tuna_system_dlkm_with_legacy_name/system_dlkm.img"],&#10;    cmd = """&#10;        for f in $(execpaths :tuna_system_dlkm); do&#10;            if [[ "$$(basename $$f)" == "system_dlkm.ext4.img" ]]; then&#10;                cp -aL $$f $@&#10;            fi&#10;        done&#10;    """&#10;)</code></pre>   | List of strings | optional |  `["ext4"]`  |
| <a id="system_dlkm_image-internal_extra_archive_files"></a>internal_extra_archive_files |  **Internal only; subject to change without notice.** Extra files to be placed at the root of the archive.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="system_dlkm_image-kernel_modules_install"></a>kernel_modules_install |  The [`kernel_modules_install`](#kernel_modules_install).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="system_dlkm_image-modules_blocklist"></a>modules_blocklist |  An optional file containing a list of modules which are blocked from being loaded.<br><br>This file is copied directly to the staging directory and should be in the format: <pre><code>blocklist module_name</code></pre>   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="system_dlkm_image-modules_list"></a>modules_list |  An optional file containing the list of kernel modules which shall be copied into a system_dlkm partition image.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="system_dlkm_image-props"></a>props |  A text file containing the properties to be used for creation of a `system_dlkm` image (filesystem, partition size, etc). If this is not set (and `build_system_dlkm` is), a default set of properties will be used which assumes an ext4 filesystem and a dynamic partition.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="unsparsed_image"></a>

## unsparsed_image

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "unsparsed_image")

unsparsed_image(<a href="#unsparsed_image-name">name</a>, <a href="#unsparsed_image-src">src</a>, <a href="#unsparsed_image-out">out</a>)
</pre>

Build an unsparsed image.

Takes in a .img file and unsparses it.

When included in a `pkg_files`/`pkg_install` rule, this rule copies a `super_unsparsed.img` to
`destdir`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="unsparsed_image-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="unsparsed_image-src"></a>src |  image to unsparse   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="unsparsed_image-out"></a>out |  -   | String | required |  |


<a id="vendor_boot_image"></a>

## vendor_boot_image

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "vendor_boot_image")

vendor_boot_image(<a href="#vendor_boot_image-name">name</a>, <a href="#vendor_boot_image-deps">deps</a>, <a href="#vendor_boot_image-outs">outs</a>, <a href="#vendor_boot_image-dtb_image">dtb_image</a>, <a href="#vendor_boot_image-header_version">header_version</a>, <a href="#vendor_boot_image-initramfs">initramfs</a>, <a href="#vendor_boot_image-kernel_build">kernel_build</a>,
                  <a href="#vendor_boot_image-kernel_vendor_cmdline">kernel_vendor_cmdline</a>, <a href="#vendor_boot_image-mkbootimg">mkbootimg</a>, <a href="#vendor_boot_image-ramdisk_compression">ramdisk_compression</a>, <a href="#vendor_boot_image-ramdisk_compression_args">ramdisk_compression_args</a>,
                  <a href="#vendor_boot_image-unpack_ramdisk">unpack_ramdisk</a>, <a href="#vendor_boot_image-vendor_boot_name">vendor_boot_name</a>, <a href="#vendor_boot_image-vendor_bootconfig">vendor_bootconfig</a>, <a href="#vendor_boot_image-vendor_ramdisk_binaries">vendor_ramdisk_binaries</a>,
                  <a href="#vendor_boot_image-vendor_ramdisk_dev_nodes">vendor_ramdisk_dev_nodes</a>)
</pre>

Build `vendor_boot` or `vendor_kernel_boot` image.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vendor_boot_image-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vendor_boot_image-deps"></a>deps |  Additional dependencies to build boot images.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vendor_boot_image-outs"></a>outs |  A list of output files that will be installed to `DIST_DIR` when `build_boot_images` in `build/kernel/build_utils.sh` is executed.<br><br>Unlike `kernel_images`, you must specify the list explicitly.   | List of strings | optional |  `[]`  |
| <a id="vendor_boot_image-dtb_image"></a>dtb_image |  A dtb.img to packaged. If this is set, then *.dtb from `kernel_build` are ignored.<br><br>See [`dtb_image`](#dtb_image).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_boot_image-header_version"></a>header_version |  Boot image header version.<br><br>If unspecified, falls back to the value of BOOT_IMAGE_HEADER_VERSION in build configs. If BOOT_IMAGE_HEADER_VERSION is not set, defaults to 3.   | Integer | optional |  `0`  |
| <a id="vendor_boot_image-initramfs"></a>initramfs |  The [`initramfs`](#initramfs).   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_boot_image-kernel_build"></a>kernel_build |  The [`kernel_build`](#kernel_build).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="vendor_boot_image-kernel_vendor_cmdline"></a>kernel_vendor_cmdline |  string of kernel parameters for vendor boot image   | String | optional |  `""`  |
| <a id="vendor_boot_image-mkbootimg"></a>mkbootimg |  mkbootimg.py script which builds boot.img. Only used if `build_boot`. If `None`, default to `//tools/mkbootimg:mkbootimg.py`. NOTE: This overrides `MKBOOTIMG_PATH`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@kleaf//tools/mkbootimg:mkbootimg.py"`  |
| <a id="vendor_boot_image-ramdisk_compression"></a>ramdisk_compression |  If provided it specfies the format used for any ramdisks generated.If not provided a fallback value from build.config is used.   | String | optional |  `""`  |
| <a id="vendor_boot_image-ramdisk_compression_args"></a>ramdisk_compression_args |  Command line arguments passed only to lz4 command to control compression level.   | String | optional |  `""`  |
| <a id="vendor_boot_image-unpack_ramdisk"></a>unpack_ramdisk |  When false it skips unpacking the vendor ramdisk and copy it as is, without modifications, into the boot image. Also skip the mkbootfs step.<br><br>Unlike `kernel_images()`, `unpack_ramdisk` must be specified explicitly to clarify the intent.   | Boolean | required |  |
| <a id="vendor_boot_image-vendor_boot_name"></a>vendor_boot_name |  Name of `vendor_boot` image.<br><br>* If `"vendor_boot"`, build `vendor_boot.img` * If `"vendor_kernel_boot"`, build `vendor_kernel_boot.img`   | String | optional |  `"vendor_boot"`  |
| <a id="vendor_boot_image-vendor_bootconfig"></a>vendor_bootconfig |  bootconfig parameters.<br><br>Each element is present as a line in the bootconfig section.<br><br>Requires header version >= 4.   | List of strings | optional |  `[]`  |
| <a id="vendor_boot_image-vendor_ramdisk_binaries"></a>vendor_ramdisk_binaries |  List of vendor ramdisk binaries which includes the device-specific components of ramdisk like the fstab file and the device-specific rc files. If specifying multiple vendor ramdisks and identical file paths exist in the ramdisks, the file from last ramdisk is used.<br><br>Note: **order matters**. To prevent buildifier from sorting the list, add the following: <pre><code># do not sort</code></pre>   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vendor_boot_image-vendor_ramdisk_dev_nodes"></a>vendor_ramdisk_dev_nodes |  List of dev nodes description files which describes special device files to be added to the vendor ramdisk. File format is as accepted by mkbootfs.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="vendor_dlkm_image"></a>

## vendor_dlkm_image

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "vendor_dlkm_image")

vendor_dlkm_image(<a href="#vendor_dlkm_image-name">name</a>, <a href="#vendor_dlkm_image-deps">deps</a>, <a href="#vendor_dlkm_image-archive">archive</a>, <a href="#vendor_dlkm_image-base_system_dlkm_image">base_system_dlkm_image</a>, <a href="#vendor_dlkm_image-build_flatten">build_flatten</a>, <a href="#vendor_dlkm_image-create_modules_order">create_modules_order</a>,
                  <a href="#vendor_dlkm_image-dedup_dlkm_modules">dedup_dlkm_modules</a>, <a href="#vendor_dlkm_image-etc_files">etc_files</a>, <a href="#vendor_dlkm_image-fs_type">fs_type</a>, <a href="#vendor_dlkm_image-kernel_modules_install">kernel_modules_install</a>, <a href="#vendor_dlkm_image-modules_blocklist">modules_blocklist</a>,
                  <a href="#vendor_dlkm_image-modules_list">modules_list</a>, <a href="#vendor_dlkm_image-props">props</a>, <a href="#vendor_dlkm_image-system_dlkm_image">system_dlkm_image</a>, <a href="#vendor_dlkm_image-vendor_boot_modules_load">vendor_boot_modules_load</a>)
</pre>

Build vendor_dlkm image.

Execute `build_vendor_dlkm` in `build_utils.sh`.

When included in a `pkg_files` target included by `pkg_install`, this rule copies the following to
`destdir`:

- `vendor_dlkm.img`
- `vendor_dlkm_flatten.img` if build_vendor_dlkm_flatten is True

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="vendor_dlkm_image-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="vendor_dlkm_image-deps"></a>deps |  A list of additional dependencies to build system_dlkm image.<br><br>This must include the following:<br><br>- The file specified by `selinux_fc` in `props`, if set   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vendor_dlkm_image-archive"></a>archive |  Whether to archive the `vendor_dlkm` modules   | Boolean | optional |  `False`  |
| <a id="vendor_dlkm_image-base_system_dlkm_image"></a>base_system_dlkm_image |  The `system_dlkm_image()` corresponding to the `base_kernel` of the `kernel_build`. This is required if `dedup_dlkm_modules and not system_dlkm_image`. For example, if `base_kernel` of `kernel_build()` is `//common:kernel_aarch64`, then `base_system_dlkm_image` is `//common:kernel_aarch64_system_dlkm_image`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_dlkm_image-build_flatten"></a>build_flatten |  When True it builds vendor_dlkm image with no `uname -r` in the path   | Boolean | optional |  `False`  |
| <a id="vendor_dlkm_image-create_modules_order"></a>create_modules_order |  Whether to create and keep a modules.order file generated by a postorder traversal of the `kernel_modules_install` sources. It defaults to `True`.   | Boolean | optional |  `True`  |
| <a id="vendor_dlkm_image-dedup_dlkm_modules"></a>dedup_dlkm_modules |  Whether to exclude `system_dlkm` modules   | Boolean | optional |  `False`  |
| <a id="vendor_dlkm_image-etc_files"></a>etc_files |  Files that need to be copied to `vendor_dlkm.img` etc/ directory.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="vendor_dlkm_image-fs_type"></a>fs_type |  Filesystem for `vendor_dlkm.img`.   | String | optional |  `"ext4"`  |
| <a id="vendor_dlkm_image-kernel_modules_install"></a>kernel_modules_install |  The [`kernel_modules_install`](#kernel_modules_install).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="vendor_dlkm_image-modules_blocklist"></a>modules_blocklist |  An optional file containing a list of modules which are blocked from being loaded.<br><br>This file is copied directly to the staging directory and should be in the format: <pre><code>blocklist module_name</code></pre>   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_dlkm_image-modules_list"></a>modules_list |  An optional file containing the list of kernel modules which shall be copied into a `vendor_dlkm` partition image. Any modules passed into `MODULES_LIST` which become part of the `vendor_boot.modules.load` will be trimmed from the `vendor_dlkm.modules.load`.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_dlkm_image-props"></a>props |  A text file containing the properties to be used for creation of a `vendor_dlkm` image (filesystem, partition size, etc). If this is not set (and `build_vendor_dlkm` is), a default set of properties will be used which assumes an ext4 filesystem and a dynamic partition.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_dlkm_image-system_dlkm_image"></a>system_dlkm_image |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="vendor_dlkm_image-vendor_boot_modules_load"></a>vendor_boot_modules_load |  File to `vendor_boot.modules.load`.<br><br>Modules listed in this file is stripped away from the `vendor_dlkm` image.<br><br>As a special case, you may also provide a [`initramfs`](#initramfs) target here, in which case the `vendor_boot.modules.load` of the initramfs is used.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="ddk_library"></a>

## ddk_library

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_library")

ddk_library(<a href="#ddk_library-name">name</a>, <a href="#ddk_library-kernel_build">kernel_build</a>, <a href="#ddk_library-srcs">srcs</a>, <a href="#ddk_library-deps">deps</a>, <a href="#ddk_library-hdrs">hdrs</a>, <a href="#ddk_library-includes">includes</a>, <a href="#ddk_library-linux_includes">linux_includes</a>, <a href="#ddk_library-local_defines">local_defines</a>, <a href="#ddk_library-copts">copts</a>,
            <a href="#ddk_library-removed_copts">removed_copts</a>, <a href="#ddk_library-asopts">asopts</a>, <a href="#ddk_library-config">config</a>, <a href="#ddk_library-kconfig">kconfig</a>, <a href="#ddk_library-defconfig">defconfig</a>, <a href="#ddk_library-autofdo_profile">autofdo_profile</a>,
            <a href="#ddk_library-debug_info_for_profiling">debug_info_for_profiling</a>, <a href="#ddk_library-pkvm_el2">pkvm_el2</a>, <a href="#ddk_library-kwargs">**kwargs</a>)
</pre>

**EXPERIMENTAL**. A library that may be used by a DDK module.

The library has its own list of dependencies, flags that are usually local, and
not exported to the `ddk_module` using it. However, `hdrs`, `includes`,
kconfig and defconfig are exported.

Known issues:
    - (b/392186874) The generated .o.cmd files contain absolute paths and are not reproducible.
    - (b/394411899) kernel_compile_commands() doesn't work on ddk_library yet.
    - (b/395014894) All ddk_module() dependency in ddk_library.deps must be duplicated
        in the ddk_module() that depends on this ddk_library.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="ddk_library-name"></a>name |  name of module   |  none |
| <a id="ddk_library-kernel_build"></a>kernel_build |  [`kernel_build`](#kernel_build)   |  none |
| <a id="ddk_library-srcs"></a>srcs |  see [`ddk_module.srcs`](#ddk_module-srcs)   |  `None` |
| <a id="ddk_library-deps"></a>deps |  see [`ddk_module.deps`](#ddk_module-deps). [`ddk_submodule`](#ddk_submodule)s are not allowed.   |  `None` |
| <a id="ddk_library-hdrs"></a>hdrs |  see [`ddk_module.hdrs`](#ddk_module-hdrs)   |  `None` |
| <a id="ddk_library-includes"></a>includes |  see [`ddk_module.includes`](#ddk_module-includes)   |  `None` |
| <a id="ddk_library-linux_includes"></a>linux_includes |  see [`ddk_module.linux_includes`](#ddk_module-linux_includes)   |  `None` |
| <a id="ddk_library-local_defines"></a>local_defines |  see [`ddk_module.local_defines`](#ddk_module-local_defines)   |  `None` |
| <a id="ddk_library-copts"></a>copts |  see [`ddk_module.copts`](#ddk_module-copts)   |  `None` |
| <a id="ddk_library-removed_copts"></a>removed_copts |  see [`ddk_module.removed_copts`](#ddk_module-removed_copts)   |  `None` |
| <a id="ddk_library-asopts"></a>asopts |  see [`ddk_module.asopts`](#ddk_module-asopts)   |  `None` |
| <a id="ddk_library-config"></a>config |  see [`ddk_module.config`](#ddk_module-config)   |  `None` |
| <a id="ddk_library-kconfig"></a>kconfig |  see [`ddk_module.kconfig`](#ddk_module-kconfig)   |  `None` |
| <a id="ddk_library-defconfig"></a>defconfig |  see [`ddk_module.defconfig`](#ddk_module-defconfig)   |  `None` |
| <a id="ddk_library-autofdo_profile"></a>autofdo_profile |  see [`ddk_module.autofdo_profile`](#ddk_module-autofdo_profile)   |  `None` |
| <a id="ddk_library-debug_info_for_profiling"></a>debug_info_for_profiling |  see [`ddk_module.debug_info_for_profiling`](#ddk_module-debug_info_for_profiling)   |  `None` |
| <a id="ddk_library-pkvm_el2"></a>pkvm_el2 |  **EXPERIMENTAL**. If True, builds EL2 hypervisor code.<br><br>If True: - The output list is the fixed `["kvm_nvhe.o"]`, plus relevant .o.cmd files - The generated Makefile is modified to build EL2 hypervisor code.<br><br>Note: This is only supported in selected branches.   |  `None` |
| <a id="ddk_library-kwargs"></a>kwargs |  Additional attributes to the internal rule. See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="ddk_module"></a>

## ddk_module

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_module")

ddk_module(<a href="#ddk_module-name">name</a>, <a href="#ddk_module-kernel_build">kernel_build</a>, <a href="#ddk_module-srcs">srcs</a>, <a href="#ddk_module-deps">deps</a>, <a href="#ddk_module-hdrs">hdrs</a>, <a href="#ddk_module-textual_hdrs">textual_hdrs</a>, <a href="#ddk_module-includes">includes</a>, <a href="#ddk_module-conditional_srcs">conditional_srcs</a>,
           <a href="#ddk_module-crate_root">crate_root</a>, <a href="#ddk_module-linux_includes">linux_includes</a>, <a href="#ddk_module-out">out</a>, <a href="#ddk_module-local_defines">local_defines</a>, <a href="#ddk_module-copts">copts</a>, <a href="#ddk_module-removed_copts">removed_copts</a>, <a href="#ddk_module-asopts">asopts</a>, <a href="#ddk_module-linkopts">linkopts</a>,
           <a href="#ddk_module-config">config</a>, <a href="#ddk_module-kconfig">kconfig</a>, <a href="#ddk_module-defconfig">defconfig</a>, <a href="#ddk_module-generate_btf">generate_btf</a>, <a href="#ddk_module-autofdo_profile">autofdo_profile</a>, <a href="#ddk_module-debug_info_for_profiling">debug_info_for_profiling</a>,
           <a href="#ddk_module-kwargs">**kwargs</a>)
</pre>

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="ddk_module-name"></a>name |  Name of target. This should usually be name of the output `.ko` file without the suffix.   |  none |
| <a id="ddk_module-kernel_build"></a>kernel_build |  [`kernel_build`](#kernel_build)   |  none |
| <a id="ddk_module-srcs"></a>srcs |  sources or local headers.<br><br>Source files (`.c`, `.S`, `.rs`) must be in the package of this `ddk_module` target, or in subpackages.<br><br>Generated source files (`.c`, `.S`, `.rs`) are accepted as long as they are in the package of this `ddk_module` target, or in subpackages.<br><br>Header files specified here are only visible to this `ddk_module` target, but not dependencies. To export a header so dependencies can use it, put it in `hdrs` and set `includes` accordingly.<br><br>Generated header files are accepted.   |  `None` |
| <a id="ddk_module-deps"></a>deps |  A list of dependent targets. Each of them must be one of the following:<br><br>- [`kernel_module`](#kernel_module) - [`ddk_module`](#ddk_module) - [`ddk_headers`](#ddk_headers). - [`ddk_prebuilt_object`](#ddk_prebuilt_object) - [`ddk_library`](#ddk_library)<br><br>If [`config`](#ddk_module-config) is set, if some `deps` of this target have `kconfig` / `defconfig` set (including transitive dependencies), you may need to duplicate these targets in `ddk_config.deps`. Inconsistent configs are disallowed; if the resulting `.config` is not the same as the one from [`config`](#ddk_module-config), you get a build error.   |  `None` |
| <a id="ddk_module-hdrs"></a>hdrs |  See [`ddk_headers.hdrs`](#ddk_headers-hdrs)<br><br>If [`config`](#ddk_module-config) is set, if some `hdrs` of this target have `kconfig` / `defconfig` set (including transitive dependencies), you may need to duplicate these targets in `ddk_config.deps`. Inconsistent configs are disallowed; if the resulting `.config` is not the same as the one from [`config`](#ddk_module-config), you get a build error.   |  `None` |
| <a id="ddk_module-textual_hdrs"></a>textual_hdrs |  See [`ddk_headers.textual_hdrs`](#ddk_headers-textual_hdrs). DEPRECATED. Use `hdrs`.   |  `None` |
| <a id="ddk_module-includes"></a>includes |  See [`ddk_headers.includes`](#ddk_headers-includes)   |  `None` |
| <a id="ddk_module-conditional_srcs"></a>conditional_srcs |  A dictionary that specifies sources conditionally compiled based on configs.<br><br>Example:<br><br><pre><code>conditional_srcs = {&#10;    "CONFIG_FOO": {&#10;        True: ["foo.c"],&#10;        False: ["notfoo.c"]&#10;    }&#10;}</code></pre><br><br>In the above example, if `CONFIG_FOO` is `y` or `m`, `foo.c` is compiled. Otherwise, `notfoo.c` is compiled instead.   |  `None` |
| <a id="ddk_module-crate_root"></a>crate_root |  For Rust modules, the file that will be passed to rustc to be used for building this module.<br><br>Currently, each `.ko` may only contain a single Rust crate. Modules with multiple crates are not yet supported. Hence, only a single file may be passed into crate_root.<br><br>Unlike `rust_binary`, this must always be set for Rust modules. No defaults are assumed.   |  `None` |
| <a id="ddk_module-linux_includes"></a>linux_includes |  See [`ddk_headers.linux_includes`](#ddk_headers-linux_includes)<br><br>Unlike `ddk_headers.linux_includes`, `ddk_module.linux_includes` is **NOT** applied to dependent `ddk_module`s.   |  `None` |
| <a id="ddk_module-out"></a>out |  The output module file. This should usually be `"{name}.ko"`.<br><br>This is required if this target does not contain submodules.   |  `None` |
| <a id="ddk_module-local_defines"></a>local_defines |  List of defines to add to the compile and assemble command line.<br><br>**Order matters**. To prevent buildifier from sorting the list, use the `# do not sort` magic line.<br><br>Each string is prepended with `-D` and added to the compile/assemble command line for this target, but not to its dependents.<br><br>Unlike [`cc_library.local_defines`](https://bazel.build/reference/be/c-cpp#cc_library.local_defines), this is not subject to ["Make" variable substitution](https://bazel.build/reference/be/make-variables) or [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).<br><br>Each string is treated as a single Bourne shell token. Unlike [`cc_library.local_defines`](https://bazel.build/reference/be/c-cpp#cc_library.local_defines), this is not subject to [Bourne shell tokenization](https://bazel.build/reference/be/common-definitions#sh-tokenization). The behavior is similar to `cc_library` with the `no_copts_tokenization` [feature](https://bazel.build/reference/be/functions#package.features). For details about `no_copts_tokenization`, see [`cc_library.copts`](https://bazel.build/reference/be/c-cpp#cc_library.copts).   |  `None` |
| <a id="ddk_module-copts"></a>copts |  Add these options to the compilation command.<br><br>**Order matters**. To prevent buildifier from sorting the list, use the `# do not sort` magic line.<br><br>Subject to [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).<br><br>The flags take effect only for compiling this target, not its dependencies, so be careful about header files included elsewhere.<br><br>All host paths should be provided via [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables). See "Implementation detail" section below.<br><br>Each `$(location)` expression should occupy its own token; optional argument key is allowed as a prefix. For example:<br><br><pre><code># Good&#10;copts = ["-include", "$(location //other:header.h)"]&#10;copts = ["-include=$(location //other:header.h)"]&#10;&#10;# BAD - Don't do this! Split into two tokens.&#10;copts = ["-include $(location //other:header.h)"]&#10;&#10;# BAD - Don't do this! Split into two tokens.&#10;copts = ["$(location //other:header.h) -Werror"]&#10;&#10;# BAD - Don't do this! Split into two tokens.&#10;copts = ["$(location //other:header.h) $(location //other:header2.h)"]</code></pre><br><br>Unlike [`cc_library.local_defines`](https://bazel.build/reference/be/c-cpp#cc_library.local_defines), this is not subject to ["Make" variable substitution](https://bazel.build/reference/be/make-variables).<br><br>Each string is treated as a single Bourne shell token. Unlike [`cc_library.copts`](https://bazel.build/reference/be/c-cpp#cc_library.copts) this is not subject to [Bourne shell tokenization](https://bazel.build/reference/be/common-definitions#sh-tokenization). The behavior is similar to `cc_library` with the `no_copts_tokenization` [feature](https://bazel.build/reference/be/functions#package.features). For details about `no_copts_tokenization`, see [`cc_library.copts`](https://bazel.build/reference/be/c-cpp#cc_library.copts).<br><br>Because each string is treated as a single Bourne shell token, if a plural `$(locations)` expression expands to multiple paths, they are treated as a single Bourne shell token, which is likely an undesirable behavior. To avoid surprising behaviors, use singular `$(location)` expressions to ensure that the label only expands to one path. For differences between the `$(locations)` and `$(location)`, see [`$(location)` substitution](https://bazel.build/reference/be/make-variables#predefined_label_variables).<br><br>**Implementation detail**: Unlike usual `$(location)` expansion, `$(location)` in `copts` is expanded to a path relative to the current package before sending to the compiler.<br><br>For example:<br><br><pre><code># package: //package&#10;ddk_module(&#10;  name = "my_module",&#10;  copts = ["-include", "$(location //other:header.h)"],&#10;  srcs = ["//other:header.h", "my_module.c"],&#10;)</code></pre> Then the content of generated Makefile is semantically equivalent to:<br><br><pre><code>CFLAGS_my_module.o += -include ../other/header.h</code></pre><br><br>The behavior is such because the generated `Makefile` is located in `package/Makefile`, and `make` is executed under `package/`. In order to find `other/header.h`, its path relative to `package/` is given.   |  `None` |
| <a id="ddk_module-removed_copts"></a>removed_copts |  Similar to `copts` but for flags **removed** from the compilation command.<br><br>For example: <pre><code>ddk_module(&#10;    name = "my_module",&#10;    removed_copts = ["-Werror"],&#10;    srcs = ["my_module.c"],&#10;)</code></pre> Then the content of generated Makefile is semantically equivalent to:<br><br><pre><code>CFLAGS_REMOVE_my_module.o += -Werror</code></pre><br><br>Note: Due to implementation details of Kleaf flags in `copts` are written to a file and provided to the compiler with the `@<arg_file>` syntax, so they are not affected by `removed_copts` implemented by `CFLAGS_REMOVE_`. To remove flags from the Bazel `copts` list, do so directly.   |  `None` |
| <a id="ddk_module-asopts"></a>asopts |  Similar to `copts` but for assembly.<br><br>For example: <pre><code>ddk_module(&#10;    name = "my_module",&#10;    asopts = ["-ansi"],&#10;    srcs = ["my_module.S"],&#10;)</code></pre> Then the content of generated Makefile is semantically equivalent to:<br><br><pre><code>AFLAGS_my_module.o += -ansi</code></pre>   |  `None` |
| <a id="ddk_module-linkopts"></a>linkopts |  Similar to `copts` but for linking the module.<br><br>For example: <pre><code>ddk_module(&#10;    name = "my_module",&#10;    linkopts = ["-lc"],&#10;    out = "my_module.ko",&#10;    # ...&#10;)</code></pre> Then the content of generated Makefile is semantically equivalent to:<br><br><pre><code>LDFLAGS_my_module.ko += -lc</code></pre>   |  `None` |
| <a id="ddk_module-config"></a>config |  **EXPERIMENTAL**. The parent [ddk_config](#ddk_config) that encapsulates Kconfig/defconfig.   |  `None` |
| <a id="ddk_module-kconfig"></a>kconfig |  The Kconfig files for this external module.<br><br>See [`Documentation/kbuild/kconfig-language.rst`](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html) for its format.<br><br>Kconfig is optional for a `ddk_module`. The final Kconfig known by this module consists of the following:<br><br>- Kconfig from `kernel_build` - Kconfig from dependent modules, if any - Kconfig of this module, if any<br><br>For legacy reasons, this is singular and accepts a single target. If multiple `Kconfig` files should be added, use a [`filegroup`](https://bazel.build/reference/be/general#filegroup) to wrap the files.   |  `None` |
| <a id="ddk_module-defconfig"></a>defconfig |  The `defconfig` file.<br><br>Items must already be declared in `kconfig`. An item not declared in Kconfig and inherited Kconfig files is silently dropped.<br><br>An item declared in `kconfig` without a specific value in `defconfig` uses default value specified in `kconfig`.   |  `None` |
| <a id="ddk_module-generate_btf"></a>generate_btf |  Allows generation of BTF type information for the module. See [kernel_module.generate_btf](#kernel_module-generate_btf)   |  `None` |
| <a id="ddk_module-autofdo_profile"></a>autofdo_profile |  Label to an AutoFDO profile.   |  `None` |
| <a id="ddk_module-debug_info_for_profiling"></a>debug_info_for_profiling |  If true, enables extra debug information to be emitted to make profile matching during AutoFDO more accurate.   |  `None` |
| <a id="ddk_module-kwargs"></a>kwargs |  Additional attributes to the internal rule. See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="ddk_submodule"></a>

## ddk_submodule

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "ddk_submodule")

ddk_submodule(<a href="#ddk_submodule-name">name</a>, <a href="#ddk_submodule-out">out</a>, <a href="#ddk_submodule-srcs">srcs</a>, <a href="#ddk_submodule-deps">deps</a>, <a href="#ddk_submodule-hdrs">hdrs</a>, <a href="#ddk_submodule-includes">includes</a>, <a href="#ddk_submodule-local_defines">local_defines</a>, <a href="#ddk_submodule-copts">copts</a>, <a href="#ddk_submodule-removed_copts">removed_copts</a>, <a href="#ddk_submodule-asopts">asopts</a>,
              <a href="#ddk_submodule-linkopts">linkopts</a>, <a href="#ddk_submodule-conditional_srcs">conditional_srcs</a>, <a href="#ddk_submodule-crate_root">crate_root</a>, <a href="#ddk_submodule-autofdo_profile">autofdo_profile</a>, <a href="#ddk_submodule-debug_info_for_profiling">debug_info_for_profiling</a>,
              <a href="#ddk_submodule-kwargs">**kwargs</a>)
</pre>

Declares a DDK (Driver Development Kit) submodule.

Symbol dependencies between submodules in the same [`ddk_module`](#ddk_module)
are not specified explicitly. This is convenient when you have multiple module
files for a subsystem.

See [Building External Modules](https://www.kernel.org/doc/Documentation/kbuild/modules.rst)
or `Documentation/kbuild/modules.rst`, section "6.3 Symbols From Another External Module",
"Use a top-level kbuild file".

Example:

```
ddk_submodule(
    name = "a",
    out = "a.ko",
    srcs = ["a.c"],
)

ddk_submodule(
    name = "b",
    out = "b.ko",
    srcs = ["b_1.c", "b_2.c"],
)

ddk_module(
    name = "mymodule",
    kernel_build = ":tuna",
    deps = [":a", ":b"],
)
```

`linux_includes` must be specified in the top-level `ddk_module`; see
[`ddk_module.linux_includes`](#ddk_module-linux_includes).

`ddk_submodule` should avoid depending on `ddk_headers` that has
`linux_includes`. See the Submodules section in [`ddk_module`](#ddk_module)
for best practices.

**Ordering of `includes`**

See [`ddk_module`](#ddk_module).

**Caveats**

As an implementation detail, `ddk_submodule` alone does not build any modules. The
`ddk_module` target is the one responsible for building all `.ko` files.

A side effect is that for incremental builds, modules may be rebuilt unexpectedly.
In the above example,
if `a.c` is modified, the whole `mymodule` is rebuilt, causing both `a.ko` and `b.ko` to
be rebuilt. Because `ddk_module` is always built in a sandbox, the object files (`*.o`) for
`b.ko` is not cached.

Hence, it is always recommended to use one `ddk_module` per module (`.ko` file). You may
use `build/kernel/kleaf/build_cleaner.py` to resolve dependencies; see
`build/kernel/kleaf/docs/build_cleaner.md`.

The `ddk_submodule` rule should only be used when the dependencies among modules are too
complicated to be presented in `BUILD.bazel`, and are frequently updated. When the
dependencies are stable, it is recommended to:

1. Replace `ddk_submodule` with `ddk_module`;
2. Specify dependencies in the `deps` attribute explicitly.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="ddk_submodule-name"></a>name |  See [`ddk_module.name`](#ddk_module-name).   |  none |
| <a id="ddk_submodule-out"></a>out |  See [`ddk_module.out`](#ddk_module-out).   |  none |
| <a id="ddk_submodule-srcs"></a>srcs |  See [`ddk_module.srcs`](#ddk_module-srcs).   |  `None` |
| <a id="ddk_submodule-deps"></a>deps |  See [`ddk_module.deps`](#ddk_module-deps).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are not exported to downstream targets that depends on the `ddk_module` that includes the current target.   |  `None` |
| <a id="ddk_submodule-hdrs"></a>hdrs |  See [`ddk_module.hdrs`](#ddk_module-hdrs).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are exported to downstream targets that depends on the `ddk_module` that includes the current target. Example:<br><br><pre><code>ddk_submodule(name = "module_parent_a", hdrs = [...])&#10;ddk_module(name = "module_parent", deps = [":module_parent_a"])&#10;ddk_module(name = "module_child", deps = [":module_parent"])</code></pre><br><br>`module_child` automatically gets `hdrs` of `module_parent_a`.   |  `None` |
| <a id="ddk_submodule-includes"></a>includes |  See [`ddk_module.includes`](#ddk_module-includes).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are exported to downstream targets that depends on the `ddk_module` that includes the current target. Example:<br><br><pre><code>ddk_submodule(name = "module_parent_a", includes = [...])&#10;ddk_module(name = "module_parent", deps = [":module_parent_a"])&#10;ddk_module(name = "module_child", deps = [":module_parent"])</code></pre><br><br>`module_child` automatically gets `includes` of `module_parent_a`.   |  `None` |
| <a id="ddk_submodule-local_defines"></a>local_defines |  See [`ddk_module.local_defines`](#ddk_module-local_defines).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are not exported to downstream targets that depends on the `ddk_module` that includes the current target.   |  `None` |
| <a id="ddk_submodule-copts"></a>copts |  See [`ddk_module.copts`](#ddk_module-copts).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are not exported to downstream targets that depends on the `ddk_module` that includes the current target.   |  `None` |
| <a id="ddk_submodule-removed_copts"></a>removed_copts |  See [`ddk_module.removed_copts`](#ddk_module-removed_copts).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are not exported to downstream targets that depends on the `ddk_module` that includes the current target.   |  `None` |
| <a id="ddk_submodule-asopts"></a>asopts |  See [`ddk_module.asopts`](#ddk_module-asopts).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are not exported to downstream targets that depends on the `ddk_module` that includes the current target.   |  `None` |
| <a id="ddk_submodule-linkopts"></a>linkopts |  See [`ddk_module.linkopts`](#ddk_module-linkopts).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).<br><br>These are not exported to downstream targets that depends on the `ddk_module` that includes the current target.   |  `None` |
| <a id="ddk_submodule-conditional_srcs"></a>conditional_srcs |  See [`ddk_module.conditional_srcs`](#ddk_module-conditional_srcs).   |  `None` |
| <a id="ddk_submodule-crate_root"></a>crate_root |  See [`ddk_module.crate_root`](#ddk_module-crate_root).   |  `None` |
| <a id="ddk_submodule-autofdo_profile"></a>autofdo_profile |  See [`ddk_module.autofdo_profile`](#ddk_module-autofdo_profile).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).   |  `None` |
| <a id="ddk_submodule-debug_info_for_profiling"></a>debug_info_for_profiling |  See [`ddk_module.debug_info_for_profiling`](#ddk_module-debug_info_for_profiling).<br><br>These are only effective in the current submodule, not other submodules declared in the same [`ddk_module.deps`](#ddk_module-deps).   |  `None` |
| <a id="ddk_submodule-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="dependency_graph"></a>

## dependency_graph

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "dependency_graph")

dependency_graph(<a href="#dependency_graph-name">name</a>, <a href="#dependency_graph-kernel_build">kernel_build</a>, <a href="#dependency_graph-kernel_modules">kernel_modules</a>, <a href="#dependency_graph-colorful">colorful</a>, <a href="#dependency_graph-exclude_base_kernel_modules">exclude_base_kernel_modules</a>,
                 <a href="#dependency_graph-kwargs">**kwargs</a>)
</pre>

Declare targets for dependency graph visualization.

Output:
    File with a diagram representing a graph in DOT language.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="dependency_graph-name"></a>name |  Name of this target.   |  none |
| <a id="dependency_graph-kernel_build"></a>kernel_build |  The [`kernel_build`](#kernel_build).   |  none |
| <a id="dependency_graph-kernel_modules"></a>kernel_modules |  A list of external [`kernel_module()`](#kernel_module)s.   |  none |
| <a id="dependency_graph-colorful"></a>colorful |  When set to True, outgoing edges from every node are colored differently.   |  `None` |
| <a id="dependency_graph-exclude_base_kernel_modules"></a>exclude_base_kernel_modules |  Whether the analysis should made for only external modules.   |  `None` |
| <a id="dependency_graph-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="initramfs_modules_lists_test"></a>

## initramfs_modules_lists_test

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "initramfs_modules_lists_test")

initramfs_modules_lists_test(<a href="#initramfs_modules_lists_test-name">name</a>, <a href="#initramfs_modules_lists_test-kernel_images">kernel_images</a>, <a href="#initramfs_modules_lists_test-expected_modules_list">expected_modules_list</a>,
                             <a href="#initramfs_modules_lists_test-expected_modules_recovery_list">expected_modules_recovery_list</a>, <a href="#initramfs_modules_lists_test-expected_modules_charger_list">expected_modules_charger_list</a>,
                             <a href="#initramfs_modules_lists_test-build_vendor_boot">build_vendor_boot</a>, <a href="#initramfs_modules_lists_test-build_vendor_kernel_boot">build_vendor_kernel_boot</a>, <a href="#initramfs_modules_lists_test-kwargs">**kwargs</a>)
</pre>

Tests that the initramfs has modules.load* files with the given content.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="initramfs_modules_lists_test-name"></a>name |  name of the test   |  none |
| <a id="initramfs_modules_lists_test-kernel_images"></a>kernel_images |  name of the `kernel_images` target. It must build initramfs.   |  none |
| <a id="initramfs_modules_lists_test-expected_modules_list"></a>expected_modules_list |  file with the expected content for `modules.load`   |  `None` |
| <a id="initramfs_modules_lists_test-expected_modules_recovery_list"></a>expected_modules_recovery_list |  file with the expected content for `modules.load.recovery`   |  `None` |
| <a id="initramfs_modules_lists_test-expected_modules_charger_list"></a>expected_modules_charger_list |  file with the expected content for `modules.load.charger`   |  `None` |
| <a id="initramfs_modules_lists_test-build_vendor_boot"></a>build_vendor_boot |  If the `kernel_images` target builds vendor_boot.img   |  `None` |
| <a id="initramfs_modules_lists_test-build_vendor_kernel_boot"></a>build_vendor_kernel_boot |  If the `kernel_images` target builds vendor_kernel_boot.img   |  `None` |
| <a id="initramfs_modules_lists_test-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_abi"></a>

## kernel_abi

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_abi")

kernel_abi(<a href="#kernel_abi-name">name</a>, <a href="#kernel_abi-kernel_build">kernel_build</a>, <a href="#kernel_abi-define_abi_targets">define_abi_targets</a>, <a href="#kernel_abi-kernel_modules">kernel_modules</a>, <a href="#kernel_abi-module_grouping">module_grouping</a>,
           <a href="#kernel_abi-abi_definition_stg">abi_definition_stg</a>, <a href="#kernel_abi-kmi_enforced">kmi_enforced</a>, <a href="#kernel_abi-unstripped_modules_archive">unstripped_modules_archive</a>, <a href="#kernel_abi-kmi_symbol_list_add_only">kmi_symbol_list_add_only</a>,
           <a href="#kernel_abi-kernel_modules_exclude_list">kernel_modules_exclude_list</a>, <a href="#kernel_abi-enable_add_vmlinux">enable_add_vmlinux</a>, <a href="#kernel_abi-kwargs">**kwargs</a>)
</pre>

Declare multiple targets to support ABI monitoring.

This macro is meant to be used alongside [`kernel_build`](#kernel_build)
macro.

For example, you may have the following declaration. (For actual definition
of `kernel_aarch64`, see
[`define_common_kernels()`](#define_common_kernels).

```
kernel_build(name = "kernel_aarch64", ...)
kernel_abi(
    name = "kernel_aarch64_abi",
    kernel_build = ":kernel_aarch64",
    ...
)
```

The `kernel_abi` invocation above defines the following targets:
- `kernel_aarch64_abi_dump`
  - Building this target extracts the ABI.
  - Include this target in a [`kernel_abi_dist`](#kernel_abi_dist)
    target to copy ABI dump to `--dist-dir`.
- `kernel_aarch64_abi`
  - A filegroup that contains `kernel_aarch64_abi_dump`. It also contains other targets
    if `define_abi_targets = True`; see below.

In addition, the following targets are defined if `define_abi_targets = True`:
- `kernel_aarch64_abi_update_symbol_list`
  - Running this target updates `kmi_symbol_list`.
- `kernel_aarch64_abi_update`
  - Running this target updates `abi_definition`.
- `kernel_aarch64_abi_dump`
  - Building this target extracts the ABI.
  - Include this target in a [`kernel_abi_dist`](#kernel_abi_dist)
    target to copy ABI dump to `--dist-dir`.

To create a distribution, see
[`kernel_abi_wrapped_dist`](#kernel_abi_wrapped_dist).

See build/kernel/kleaf/abi.md for a conversion chart from `build_abi.sh`
commands to Bazel commands.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_abi-name"></a>name |  Name of this target.   |  none |
| <a id="kernel_abi-kernel_build"></a>kernel_build |  The [`kernel_build`](#kernel_build).   |  none |
| <a id="kernel_abi-define_abi_targets"></a>define_abi_targets |  Whether the target contains other files to support ABI monitoring. If `None`, defaults to `True`.<br><br>If `False`, this macro is equivalent to just calling <pre><code>kernel_build(name = name, **kwargs)&#10;filegroup(name = name + "_abi", data = [name, abi_dump_target])</code></pre><br><br>If `True`, implies `collect_unstripped_modules = True`. See [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).   |  `None` |
| <a id="kernel_abi-kernel_modules"></a>kernel_modules |  A list of external [`kernel_module()`](#kernel_module)s to extract symbols from.   |  `None` |
| <a id="kernel_abi-module_grouping"></a>module_grouping |  If unspecified or `None`, it is `True` by default. If `True`, then the symbol list will group symbols based on the kernel modules that reference the symbol. Otherwise the symbol list will simply be a sorted list of symbols used by all the kernel modules.   |  `None` |
| <a id="kernel_abi-abi_definition_stg"></a>abi_definition_stg |  Location of the ABI definition in STG format.   |  `None` |
| <a id="kernel_abi-kmi_enforced"></a>kmi_enforced |  This is an indicative option to signal that KMI is enforced. If set to `True`, KMI checking tools respects it and reacts to it by failing if KMI differences are detected.   |  `None` |
| <a id="kernel_abi-unstripped_modules_archive"></a>unstripped_modules_archive |  A [`kernel_unstripped_modules_archive`](#kernel_unstripped_modules_archive) which name is specified in `abi.prop`. DEPRECATED.   |  `None` |
| <a id="kernel_abi-kmi_symbol_list_add_only"></a>kmi_symbol_list_add_only |  If unspecified or `None`, it is `False` by default. If `True`, then any symbols in the symbol list that would have been removed are preserved (at the end of the file). Symbol list update will fail if there is no pre-existing symbol list file to read from. This property is intended to prevent unintentional shrinkage of a stable ABI.<br><br>This should be set to `True` if `KMI_SYMBOL_LIST_ADD_ONLY=1`.   |  `None` |
| <a id="kernel_abi-kernel_modules_exclude_list"></a>kernel_modules_exclude_list |  List of base names for in-tree kernel modules to exclude from. i.e. This is the modules built in `kernel_build`, not the `kernel_modules` mentioned above.   |  `None` |
| <a id="kernel_abi-enable_add_vmlinux"></a>enable_add_vmlinux |  If unspecified or `None`, it is `True` by default. If `True`, enable the `kernel_build_add_vmlinux` [transition](https://bazel.build/extending/config#user-defined-transitions) from all targets instantiated by this macro (e.g. produced by abi_dump, extracted_symbols, etc).   |  `None` |
| <a id="kernel_abi-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_abi_dist"></a>

## kernel_abi_dist

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_abi_dist")

kernel_abi_dist(<a href="#kernel_abi_dist-name">name</a>, <a href="#kernel_abi_dist-kernel_abi">kernel_abi</a>, <a href="#kernel_abi_dist-kernel_build_add_vmlinux">kernel_build_add_vmlinux</a>, <a href="#kernel_abi_dist-ignore_diff">ignore_diff</a>, <a href="#kernel_abi_dist-no_ignore_diff_target">no_ignore_diff_target</a>,
                <a href="#kernel_abi_dist-kwargs">**kwargs</a>)
</pre>

This macro is no longer supported. Invoking this macro triggers an error.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_abi_dist-name"></a>name |  ignored   |  none |
| <a id="kernel_abi_dist-kernel_abi"></a>kernel_abi |  ignored   |  none |
| <a id="kernel_abi_dist-kernel_build_add_vmlinux"></a>kernel_build_add_vmlinux |  ignored   |  `None` |
| <a id="kernel_abi_dist-ignore_diff"></a>ignore_diff |  ignored   |  `None` |
| <a id="kernel_abi_dist-no_ignore_diff_target"></a>no_ignore_diff_target |  ignored   |  `None` |
| <a id="kernel_abi_dist-kwargs"></a>kwargs |  ignored   |  none |

**DEPRECATED**

Use [`kernel_abi_wrapped_dist`](#kernel_abi_wrapped_dist) instead.


<a id="kernel_abi_wrapped_dist"></a>

## kernel_abi_wrapped_dist

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_abi_wrapped_dist")

kernel_abi_wrapped_dist(<a href="#kernel_abi_wrapped_dist-name">name</a>, <a href="#kernel_abi_wrapped_dist-dist">dist</a>, <a href="#kernel_abi_wrapped_dist-kernel_abi">kernel_abi</a>, <a href="#kernel_abi_wrapped_dist-ignore_diff">ignore_diff</a>, <a href="#kernel_abi_wrapped_dist-no_ignore_diff_target">no_ignore_diff_target</a>, <a href="#kernel_abi_wrapped_dist-kwargs">**kwargs</a>)
</pre>

A wrapper over `dist` for [`kernel_abi`](#kernel_abi).

After calling the `dist`, return the exit code from `diff_abi`.

Example:

```
kernel_build(
    name = "tuna",
    base_kernel = "//common:kernel_aarch64",
    ...
)
kernel_abi(name = "tuna_abi", ...)
pkg_files(
    name = "tuna_abi_dist_internal_files",
    srcs = [
        ":tuna",
        # "//common:kernel_aarch64", # remove GKI
        ":tuna_abi", ...             # Add kernel_abi to pkg_files
    ],
    strip_prefix = strip_prefix.files_only(),
    visibility = ["//visibility:private"],
)
pkg_install(
    name = "tuna_abi_dist_internal",
    srcs = [":tuna_abi_dist_internal_files"],
    visibility = ["//visibility:private"],
)
kernel_abi_wrapped_dist(
    name = "tuna_abi_dist",
    dist = ":tuna_abi_dist_internal",
    kernel_abi = ":tuna_abi",
)
```

**Implementation notes**:

`with_vmlinux_transition` is applied on all targets by default. In
particular, the `kernel_build` targets in `data` automatically builds
`vmlinux` regardless of whether `vmlinux` is specified in `outs`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_abi_wrapped_dist-name"></a>name |  name of the ABI dist target   |  none |
| <a id="kernel_abi_wrapped_dist-dist"></a>dist |  The actual dist target (usually a `pkg_install`).<br><br>Note: This dist target should include `kernel_abi` in `pkg_files` that the `pkg_install` installs, e.g.<br><br><pre><code>kernel_abi(name = "tuna_abi", ...)&#10;pkg_files(&#10;    name = "tuna_abi_dist_files",&#10;    srcs = [":tuna_abi", ...], # Add kernel_abi to pkg_files()&#10;    # ...&#10;)&#10;pkg_install(&#10;    name = "tuna_abi_dist_internal",&#10;    srcs = [":tuna_abi_dist_files"],&#10;    # ...&#10;)&#10;kernel_abi_wrapped_dist(&#10;    name = "tuna_abi_dist",&#10;    dist = ":tuna_abi_dist_internal",&#10;    # ...&#10;)</code></pre>   |  none |
| <a id="kernel_abi_wrapped_dist-kernel_abi"></a>kernel_abi |  [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes). name of the [`kernel_abi`](#kernel_abi) invocation.   |  none |
| <a id="kernel_abi_wrapped_dist-ignore_diff"></a>ignore_diff |  [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes). If `True` and the return code of `stgdiff` signals the ABI difference, then the result is ignored.   |  `None` |
| <a id="kernel_abi_wrapped_dist-no_ignore_diff_target"></a>no_ignore_diff_target |  [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes). If `ignore_diff` is `True`, this need to be set to a name of the target that doesn't have `ignore_diff`. This target will be recommended as an alternative to a user. If `no_ignore_diff_target` is None, there will be no alternative recommended.   |  `None` |
| <a id="kernel_abi_wrapped_dist-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_build"></a>

## kernel_build

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_build")

kernel_build(<a href="#kernel_build-name">name</a>, <a href="#kernel_build-outs">outs</a>, <a href="#kernel_build-build_config">build_config</a>, <a href="#kernel_build-makefile">makefile</a>, <a href="#kernel_build-keep_module_symvers">keep_module_symvers</a>, <a href="#kernel_build-keep_dot_config">keep_dot_config</a>, <a href="#kernel_build-srcs">srcs</a>,
             <a href="#kernel_build-module_outs">module_outs</a>, <a href="#kernel_build-implicit_outs">implicit_outs</a>, <a href="#kernel_build-module_implicit_outs">module_implicit_outs</a>, <a href="#kernel_build-generate_vmlinux_btf">generate_vmlinux_btf</a>, <a href="#kernel_build-deps">deps</a>, <a href="#kernel_build-arch">arch</a>,
             <a href="#kernel_build-base_kernel">base_kernel</a>, <a href="#kernel_build-make_goals">make_goals</a>, <a href="#kernel_build-kconfig_ext">kconfig_ext</a>, <a href="#kernel_build-dtstree">dtstree</a>, <a href="#kernel_build-kmi_symbol_list">kmi_symbol_list</a>,
             <a href="#kernel_build-protected_module_names_list">protected_module_names_list</a>, <a href="#kernel_build-additional_kmi_symbol_lists">additional_kmi_symbol_lists</a>, <a href="#kernel_build-trim_nonlisted_kmi">trim_nonlisted_kmi</a>,
             <a href="#kernel_build-kmi_symbol_list_strict_mode">kmi_symbol_list_strict_mode</a>, <a href="#kernel_build-collect_unstripped_modules">collect_unstripped_modules</a>, <a href="#kernel_build-kbuild_symtypes">kbuild_symtypes</a>, <a href="#kernel_build-strip_modules">strip_modules</a>,
             <a href="#kernel_build-module_signing_key">module_signing_key</a>, <a href="#kernel_build-system_trusted_key">system_trusted_key</a>, <a href="#kernel_build-modules_prepare_force_generate_headers">modules_prepare_force_generate_headers</a>,
             <a href="#kernel_build-generated_headers_for_module">generated_headers_for_module</a>, <a href="#kernel_build-defconfig">defconfig</a>, <a href="#kernel_build-pre_defconfig_fragments">pre_defconfig_fragments</a>,
             <a href="#kernel_build-post_defconfig_fragments">post_defconfig_fragments</a>, <a href="#kernel_build-defconfig_fragments">defconfig_fragments</a>, <a href="#kernel_build-check_defconfig">check_defconfig</a>, <a href="#kernel_build-page_size">page_size</a>,
             <a href="#kernel_build-pack_module_env">pack_module_env</a>, <a href="#kernel_build-sanitizers">sanitizers</a>, <a href="#kernel_build-ddk_module_defconfig_fragments">ddk_module_defconfig_fragments</a>, <a href="#kernel_build-ddk_module_headers">ddk_module_headers</a>, <a href="#kernel_build-kcflags">kcflags</a>,
             <a href="#kernel_build-clang_autofdo_profile">clang_autofdo_profile</a>, <a href="#kernel_build-kwargs">**kwargs</a>)
</pre>

Defines a kernel build target with all dependent targets.

It uses a `build_config` to construct a deterministic build environment (e.g.
`common/build.config.gki.aarch64`). The kernel sources need to be declared
via srcs (using a `glob()`). outs declares the output files that are surviving
the build. The effective output file names will be
`$(name)/$(output_file)`. Any other artifact is not guaranteed to be
accessible after the rule has run.

A few additional labels are generated.
For example, if name is `"kernel_aarch64"`:
- `kernel_aarch64_uapi_headers` provides the UAPI kernel headers.
- `kernel_aarch64_headers` provides the kernel headers.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_build-name"></a>name |  The final kernel target name, e.g. `"kernel_aarch64"`.   |  none |
| <a id="kernel_build-outs"></a>outs |  The expected output files.<br><br>Note: in-tree modules should be specified in `module_outs` instead.<br><br>This attribute must be either a `dict` or a `list`. If it is a `list`, for each item in `out`:<br><br>- If `out` does not contain a slash, the build rule   automatically finds a file with name `out` in the kernel   build output directory `${OUT_DIR}`. <pre><code>  find ${OUT_DIR} -name {out}</code></pre>   There must be exactly one match.   The file is copied to the following in the output directory   `{name}/{out}`<br><br>  Example: <pre><code>  kernel_build(name = "kernel_aarch64", outs = ["vmlinux"])</code></pre>   The bulid system copies `${OUT_DIR}/[<optional subdirectory>/]vmlinux`   to `kernel_aarch64/vmlinux`.   `kernel_aarch64/vmlinux` is the label to the file.<br><br>- If `out` contains a slash, the build rule locates the file in the   kernel build output directory `${OUT_DIR}` with path `out`   The file is copied to the following in the output directory     1. `{name}/{out}`     2. `{name}/$(basename {out})`<br><br>  Example: <pre><code>  kernel_build(&#10;    name = "kernel_aarch64",&#10;    outs = ["arch/arm64/boot/vmlinux"])</code></pre>   The bulid system copies     `${OUT_DIR}/arch/arm64/boot/vmlinux`   to:     - `kernel_aarch64/arch/arm64/boot/vmlinux`     - `kernel_aarch64/vmlinux`   They are also the labels to the output files, respectively.<br><br>  See `search_and_cp_output.py` for details.<br><br>Files in `outs` are part of the [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html) that this `kernel_build` returns. For example: <pre><code>kernel_build(name = "kernel", outs = ["vmlinux"], ...)&#10;pkg_files(name = "kernel_files", srcs = ["kernel"], ...)&#10;pkg_install(name = "kernel_dist", srcs = [":kernel_files"])</code></pre> `vmlinux` will be included in the distribution.<br><br>If it is a `dict`, it is wrapped in [`select()`](https://docs.bazel.build/versions/main/configurable-attributes.html).<br><br>Example: <pre><code>kernel_build(&#10;  name = "kernel_aarch64",&#10;  outs = {"config_foo": ["vmlinux"]})</code></pre> If conditions in `config_foo` is met, the rule is equivalent to <pre><code>kernel_build(&#10;  name = "kernel_aarch64",&#10;  outs = ["vmlinux"])</code></pre> As explained above, the bulid system copies `${OUT_DIR}/[<optional subdirectory>/]vmlinux` to `kernel_aarch64/vmlinux`. `kernel_aarch64/vmlinux` is the label to the file.<br><br>Note that a `select()` may not be passed into `kernel_build()` because [`select()` cannot be evaluated in macros](https://docs.bazel.build/versions/main/configurable-attributes.html#why-doesnt-select-work-in-macros). Hence: - [combining `select()`s](https://docs.bazel.build/versions/main/configurable-attributes.html#combining-selects)   is not allowed. Instead, expand the cartesian product. - To use   [`AND` chaining](https://docs.bazel.build/versions/main/configurable-attributes.html#or-chaining)   or   [`OR` chaining](https://docs.bazel.build/versions/main/configurable-attributes.html#selectsconfig_setting_group),   use `selects.config_setting_group()`.   |  none |
| <a id="kernel_build-build_config"></a>build_config |  Label of the build.config file, e.g. `"build.config.gki.aarch64"`.<br><br>If it contains no files, the list of constants in `@kernel_toolchain_info` is used. This is `//common:build.config.constants` by default, unless otherwise specified.<br><br>If it contains no files, [`makefile`](#kernel_build-makefile) must be set as the anchor to the directory to run `make`.   |  `None` |
| <a id="kernel_build-makefile"></a>makefile |  `Makefile` governing the kernel tree sources (see `srcs`). Example values:<br><br>*   `None` (default): Falls back to the value of `KERNEL_DIR` from `build_config`.     `kernel_build()` executes `make` in `KERNEL_DIR`.<br><br>    Note: The usage of specifying `KERNEL_DIR` in `build_config` is deprecated and will     trigger a warning/error in the future.<br><br>*   `"//common:Makefile"` (most common): the kernel sources are located in     `//common`. This means `kernel_build()` executes `make` to build the kernel image     and in-tree drivers in `common`.<br><br>    This usually replaces `//common:set_kernel_dir_build_config` in your `build_config`;     that is, if you set `kernel_build.makefile`, it is likely that you may drop     `//common:set_kernel_dir_build_config` from components of     `kernel_build.build_config`.<br><br>    This replaces `KERNEL_DIR=common` in your `build_config`.<br><br>*   `"@kleaf//common:Makefile"`: If you set up a DDK workspace such that Kleaf     tooling and your kernel source tree are located in the `@kleaf` submodule, you     should specify the full label in the package. *   the `Makefile` next to the build config:<br><br>    For example:<br><br>    ```     kernel_build(         name = "tuna",         build_config = "//package:build.config.tuna", # the build.config.tuna is in //package         makefile = "//package:Makefile", # so set KERNEL_DIR to "package"     )     ```<br><br>    In this example, `build.config.tuna` is in `//package`. Hence,     setting `makefile = "Makefile"` is equivalent to the     legacy behavior of not setting `KERNEL_DIR` in `build.config`, and allowing     `_setup_env.sh` to decide the value by inferring from the directory containing the     build config, which is the `//package`.<br><br>*   `Makefile` in the current package: the kernel sources are in the current package     where `kernel_build()` is called.<br><br>    For example:<br><br>    ```     kernel_build(         name = "tuna",         build_config = "build.config.tuna", # the build.config.tuna is in this package         makefile = "Makefile", # so set KERNEL_DIR to this package     )     ```   |  `None` |
| <a id="kernel_build-keep_module_symvers"></a>keep_module_symvers |  If set to True, a copy of the default output `Module.symvers` is kept. * To avoid collisions in mixed build distribution packages, the file is renamed   as `$(name)_Module.symvers`. * Default is False.   |  `None` |
| <a id="kernel_build-keep_dot_config"></a>keep_dot_config |  If set to True, a copy of the default output `.config` is kept. * To avoid collisions in mixed build distribution packages, the file is renamed   as `$(name)_dot_config`. * Default is False.   |  `None` |
| <a id="kernel_build-srcs"></a>srcs |  The kernel sources (a `glob()`). If unspecified or `None`, it is the following: <pre><code>glob(&#10;    ["**"],&#10;    exclude = [&#10;        "**/.*",          # Hidden files&#10;        "**/.*/**",       # Files in hidden directories&#10;        "**/BUILD.bazel", # build files&#10;        "**/*.bzl",       # build files&#10;    ],&#10;)</code></pre>   |  `None` |
| <a id="kernel_build-module_outs"></a>module_outs |  A list of in-tree drivers. Similar to `outs`, but for `*.ko` files.<br><br>If a `*.ko` kernel module should not be copied to `${DIST_DIR}`, it must be included `implicit_outs` instead of `module_outs`. The list `implicit_outs + module_outs` must include **all** `*.ko` files in `${OUT_DIR}`. If not, a build error is raised.<br><br>Like `outs`, `module_outs` are part of the [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html) that this `kernel_build` returns. For example: <pre><code>kernel_build(name = "kernel", module_outs = ["foo.ko"], ...)&#10;pkg_files(name = "kernel_files", srcs = ["kernel"], ...)&#10;pkg_install(name = "kernel_dist", srcs = [":kernel_files"])</code></pre> `foo.ko` will be included in the distribution.<br><br>Like `outs`, this may be a `dict`. If so, it is wrapped in [`select()`](https://docs.bazel.build/versions/main/configurable-attributes.html). See documentation for `outs` for more details.   |  `None` |
| <a id="kernel_build-implicit_outs"></a>implicit_outs |  Like `outs`, but not copied to the distribution directory.<br><br>Labels are created for each item in `implicit_outs` as in `outs`.   |  `None` |
| <a id="kernel_build-module_implicit_outs"></a>module_implicit_outs |  like `module_outs`, but not copied to the distribution directory.<br><br>Labels are created for each item in `module_implicit_outs` as in `outs`.   |  `None` |
| <a id="kernel_build-generate_vmlinux_btf"></a>generate_vmlinux_btf |  If `True`, generates `vmlinux.btf` that is stripped of any debug symbols, but contains type and symbol information within a .BTF section. This is suitable for ABI analysis through BTF.<br><br>Requires that `"vmlinux"` is in `outs`.   |  `None` |
| <a id="kernel_build-deps"></a>deps |  Additional dependencies to build this kernel.   |  `None` |
| <a id="kernel_build-arch"></a>arch |  [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes). Target architecture. Default is `arm64`.<br><br>Value should be one of: * `arm64` * `x86_64` * `riscv64` * `arm` (for 32-bit, uncommon) * `i386` (for 32-bit, uncommon)<br><br>This must be consistent to `ARCH` in build configs if the latter is specified. Otherwise, a warning / error may be raised.   |  `None` |
| <a id="kernel_build-base_kernel"></a>base_kernel |  A label referring the base kernel build.<br><br>If set, the list of files specified in the `DefaultInfo` of the rule specified in `base_kernel` is copied to a directory, and `KBUILD_MIXED_TREE` is set to the directory. Setting `KBUILD_MIXED_TREE` effectively enables mixed build.<br><br>To set additional flags for mixed build, change `build_config` to a `kernel_build_config` rule, with a build config fragment that contains the additional flags.<br><br>The label specified by `base_kernel` must produce a list of files similar to what a `kernel_build` rule does. Usually, this points to one of the following: - `//common:kernel_{arch}` - A `kernel_filegroup` rule, e.g. <pre><code>  load("//build/kernel/kleaf:constants.bzl, "DEFAULT_GKI_OUTS")&#10;  kernel_filegroup(&#10;    name = "my_kernel_filegroup",&#10;    srcs = DEFAULT_GKI_OUTS,&#10;  )</code></pre>   |  `None` |
| <a id="kernel_build-make_goals"></a>make_goals |  A list of strings defining targets for the kernel build. This overrides `MAKE_GOALS` from build config if provided.   |  `None` |
| <a id="kernel_build-kconfig_ext"></a>kconfig_ext |  Label of an external Kconfig.ext file sourced by the GKI kernel.   |  `None` |
| <a id="kernel_build-dtstree"></a>dtstree |  Device tree support.   |  `None` |
| <a id="kernel_build-kmi_symbol_list"></a>kmi_symbol_list |  A label referring to the main KMI symbol list file. See `additional_kmi_symbol_lists`.<br><br>This is the Bazel equivalent of `ADDITIONAL_KMI_SYMBOL_LISTS`.   |  `None` |
| <a id="kernel_build-protected_module_names_list"></a>protected_module_names_list |  A file containing list of protected module names, For example: <pre><code>protected_module_names_list = "//common:gki/aarch64/protected_module_names"</code></pre>   |  `None` |
| <a id="kernel_build-additional_kmi_symbol_lists"></a>additional_kmi_symbol_lists |  A list of labels referring to additional KMI symbol list files.<br><br>This is the Bazel equivalent of `ADDITIONAL_KMI_SYMBOL_LISTS`.<br><br>Let <pre><code>all_kmi_symbol_lists = [kmi_symbol_list] + additional_kmi_symbol_list</code></pre><br><br>If `all_kmi_symbol_lists` is a non-empty list, `abi_symbollist` and `abi_symbollist.report` are created and added to the [`DefaultInfo`](https://docs.bazel.build/versions/main/skylark/lib/DefaultInfo.html), and copied to `DIST_DIR` during distribution.<br><br>If `all_kmi_symbol_lists` is `None` or an empty list, `abi_symbollist` and `abi_symbollist.report` are not created.<br><br>It is possible to use a `glob()` to determine whether `abi_symbollist` and `abi_symbollist.report` should be generated at build time. For example: <pre><code>kmi_symbol_list = "gki/aarch64/symbols/base",&#10;additional_kmi_symbol_lists = glob(["gki/aarch64/symbols/*"], exclude = ["gki/aarch64/symbols/base"]),</code></pre>   |  `None` |
| <a id="kernel_build-trim_nonlisted_kmi"></a>trim_nonlisted_kmi |  If `True`, trim symbols not listed in `kmi_symbol_list` and `additional_kmi_symbol_lists`. This is the Bazel equivalent of `TRIM_NONLISTED_KMI`.<br><br>Requires `all_kmi_symbol_lists` to be non-empty. If `kmi_symbol_list` or `additional_kmi_symbol_lists` is a `glob()`, it is possible to set `trim_nonlisted_kmi` to be a value based on that `glob()`. For example: <pre><code>trim_nonlisted_kmi = len(glob(["gki/aarch64/symbols/*"])) &gt; 0</code></pre><br><br>For mixed builds (`base_kernel` is set), the value of `trim_nonlisted_kmi` of the `base_kernel` does not affect the value of `trim_nonlisted_kmi` of this `kernel_build()`. This may change in the future.   |  `None` |
| <a id="kernel_build-kmi_symbol_list_strict_mode"></a>kmi_symbol_list_strict_mode |  If `True`, add a build-time check between `[kmi_symbol_list] + additional_kmi_symbol_lists` and the KMI resulting from the build, to ensure they match 1-1.   |  `None` |
| <a id="kernel_build-collect_unstripped_modules"></a>collect_unstripped_modules |  If `True`, provide all unstripped in-tree.   |  `None` |
| <a id="kernel_build-kbuild_symtypes"></a>kbuild_symtypes |  The value of `KBUILD_SYMTYPES`.<br><br>This can be set to one of the following:<br><br>- `"true"` - `"false"` - `"auto"` - `None`, which defaults to `"auto"`<br><br>If the value is `"auto"`, it is determined by the `--kbuild_symtypes` flag.<br><br>If the value is `"true"`; or the value is `"auto"` and `--kbuild_symtypes` is specified, then `KBUILD_SYMTYPES=1`. **Note**: kernel build time can be significantly longer.<br><br>If the value is `"false"`; or the value is `"auto"` and `--kbuild_symtypes` is not specified, then `KBUILD_SYMTYPES=`.   |  `None` |
| <a id="kernel_build-strip_modules"></a>strip_modules |  If `None` or not specified, default is `False`. If set to `True`, debug information for distributed modules is stripped.<br><br>This corresponds to negated value of `DO_NOT_STRIP_MODULES` in `build.config`.   |  `None` |
| <a id="kernel_build-module_signing_key"></a>module_signing_key |  A label referring to a module signing key.<br><br>This is to allow for dynamic setting of `CONFIG_MODULE_SIG_KEY` from Bazel.   |  `None` |
| <a id="kernel_build-system_trusted_key"></a>system_trusted_key |  A label referring to a trusted system key.<br><br>This is to allow for dynamic setting of `CONFIG_SYSTEM_TRUSTED_KEY` from Bazel.   |  `None` |
| <a id="kernel_build-modules_prepare_force_generate_headers"></a>modules_prepare_force_generate_headers |  For 6.12 and earlier: If `True` it forces generation of additional headers as part of modules_prepare. This is replaced by `generated_headers_for_module` on `base_kernel` for 6.13 and later.   |  `None` |
| <a id="kernel_build-generated_headers_for_module"></a>generated_headers_for_module |  **INTERNAL FOR ACK ONLY.** For 6.13 and later, this is a list of additional generated headers below $OUT_DIR for building external modules. This replaces `modules_prepare_force_generate_headers`. If a non-empty list, an archive with the given list of generated headers is created.   |  `None` |
| <a id="kernel_build-defconfig"></a>defconfig |  Label to the base defconfig.<br><br>As a convention, files should usually be named `<device>_defconfig` (e.g. `tuna_defconfig`) to provide human-readable hints during the build. The prefix should be the name of the `kernel_build`. However, this is not a requirement. These configs are also applied to external modules, including `kernel_module`s and `ddk_module`s.<br><br>For mixed builds (`base_kernel` is set), this is usually set to the `defconfig` of the `base_kernel`, e.g. `//common:arch/arm64/configs/gki_defconfig`.<br><br>If `check_defconfig` is not `disabled`, Items must be present in the intermediate `.config` before `post_defconfig_fragments` are applied. See `build/kernel/kleaf/docs/kernel_config.md` for details.<br><br>As a special case, if this is evaluated to `//build/kernel/kleaf:allmodconfig`, Kleaf builds all modules except those exluded in `post_defconfig_fragments`. In this case, `pre_defconfig_fragments` must not be set.<br><br>If this attribute is not set (value is `None`), falls back to `DEFCONFIG` from build_config for backwards compatibility. If `DEFCONFIG` is also not set, falls back to `defconfig` of `base_kernel`. If `base_kernel` also do not have `defconfig` set, error.<br><br>See [`build/kernel/kleaf/docs/kernel_config.md`](../kernel_config.md) for details.   |  `None` |
| <a id="kernel_build-pre_defconfig_fragments"></a>pre_defconfig_fragments |  A list of fragments that are applied to the defconfig **before** `make defconfig`.<br><br>Even though this is a list, it is highly recommended that the list contains **at most one item**. This is so that `tools/bazel run <name>_config` applies to the single pre defconfig fragment correctly.<br><br>As a convention, files should usually be named `<prop>_defconfig` (e.g. `16k_defconfig`) or `<prop>_<value>_defconfig` (e.g. `page_size_16k_defconfig`) to provide human-readable hints during the build. The prefix should describe what the defconfig does. However, this is not a requirement. These configs are also applied to external modules, including `kernel_module`s and `ddk_module`s.<br><br>For mixed builds (`base_kernel` is set), the file usually contains additional in-tree modules to build on top of `gki_defconfig`, e.g. `CONFIG_FOO=m`.<br><br>For mixed builds (`base_kernel` is set), the `pre_defconfig_fragments` of the `base_kernel` is implicitly included when --incompatible_inherit_pre_defconfig_fragments_from_base_kernel is set.<br><br>**NOTE**: `pre_defconfig_fragments` are applied **before** `make defconfig`, similar to `PRE_DEFCONFIG_CMDS`. If you had `POST_DEFCONFIG_CMDS` applying fragments in your build configs, consider using `post_defconfig_fragments` instead.<br><br>**NOTE**: **Order matters**, unlike `post_defconfig_fragments`. If there are conflicting items, later items overrides earlier items.<br><br>If `check_defconfig` is not `disabled`, Items must be present in the intermediate `.config` before `post_defconfig_fragments` are applied. See `build/kernel/kleaf/docs/kernel_config.md` for details.   |  `None` |
| <a id="kernel_build-post_defconfig_fragments"></a>post_defconfig_fragments |  A list of fragments that are applied to the defconfig **after** `make defconfig`.<br><br>As a convention, files should usually be named `<prop>_defconfig` (e.g. `kasan_defconfig`) or `<prop>_<value>_defconfig` (e.g. `lto_none_defconfig`) to provide human-readable hints during the build. The prefix should describe what the defconfig does. However, this is not a requirement. These configs are also applied to external modules, including `kernel_module`s and `ddk_module`s.<br><br>For mixed builds (`base_kernel` is set), the `post_defconfig_fragments` of the `base_kernel` is implicitly included when `--incompatible_inherit_post_defconfig_fragments_from_base_kernel` is set (the default).<br><br>Files usually contain debug options. If you want to build in-tree modules, adding them to `pre_defconfig_fragments` may be a better choice.<br><br>**NOTE**: `post_defconfig_fragments` are applied **after** `make defconfig`, similar to `POST_DEFCONFIG_CMDS`. If you had `PRE_DEFCONFIG_CMDS` applying fragments in your build configs, consider using `pre_defconfig_fragments` instead.<br><br>If `check_defconfig` is not `disabled`, Items must be present in the final `.config`. See `build/kernel/kleaf/docs/kernel_config.md` for details.   |  `None` |
| <a id="kernel_build-defconfig_fragments"></a>defconfig_fragments |  **Deprecated**. Same as `post_defconfig_fragments`.   |  `None` |
| <a id="kernel_build-check_defconfig"></a>check_defconfig |  Whether to check `.config` against `defconfig`, `pre_defconfig_fragments` and `post_defconfig_fragments`.<br><br>Value is one of `disabled`, `match` or `minimized`.<br><br>For `defconfig` and `pre_defconfig_fragments`, if `check_defconfig` is unspecified, and `--incompatible_inherit_pre_defconfig_fragments_from_base_kernel`:<br><br>-   If `base_kernel` is set, and `base_kernel` checks `defconfig` and     `pre_defconfig_fragments` using the `match` or `minimized` strategy,     this `kernel_build()` checks `defconfig` and `pre_defconfig_fragments` using the     `match` strategy. -   If `base_kernel` is set, and `base_kernel` does not check against `defconfig` and     `pre_defconfig_fragments` (`disabled`),     this `kernel_build()` does not check against `defconfig` and     `pre_defconfig_fragments` (`disabled`). -   If `base_kernel` is not set, this `kernel_build()` checks `defconfig` and     `pre_defconfig_fragments` using the `match` strategy.<br><br>For `defconfig` and `pre_defconfig_fragments`, if `check_defconfig` is unspecified, and `--noincompatible_inherit_defconfig_fragments_from_base_kernel`, this `kernel_build()` checks `defconfig` and `pre_defconfig_fragments` using the `match` strategy.<br><br>For `post_defconfig_fragments`, if `check_defconfig` is unspecified, this `kernel_build()` checks `post_defconfig_fragments` using the `match` strategy.<br><br>`disabled` startegy: no check is performed.<br><br>`match` strategy: -   For each requirement item in `defconfig` + `pre_defconfig_fragments`, before     `post_defconfig_fragments` is applied, `.config` is checked against the item. -   For each requirement item in `post_defconfig_fragments`, after     `post_defconfig_fragments` is applied, `.config` is checked against the item.<br><br>`minimized` strategy: -   checks `.config` against the result of     `make savedefconfig` right after `make defconfig`, but before     `post_defconfig_fragments` are applied. -   For each requirement item in `post_defconfig_fragments`, after     `post_defconfig_fragments` is applied, `.config` is checked against the item.<br><br>`check_defconfig` can be set to `minimized` **only if** `defconfig` is set and `pre_defconfig_fragments` is not set (including those inherited from `base_kernel`).   |  `None` |
| <a id="kernel_build-page_size"></a>page_size |  Default is `"default"`. Page size of the kernel build.<br><br>Value may be one of `"default"`, `"4k"`, `"16k"` or `"64k"`. If `"default"`, the defconfig is left as-is.<br><br>16k / 64k page size is only supported on `arch = "arm64"`.<br><br>For mixed builds (`base_kernel` is set), the value of `page_size` of the `base_kernel` is used if `--incompatible_inherit_post_defconfig_fragments_from_base_kernel` is set (the default).   |  `None` |
| <a id="kernel_build-pack_module_env"></a>pack_module_env |  If `True`, create `{name}_module_env.tar.gz` and other archives as part of the default output of this target.<br><br>These archives contains necessary files to build external modules.   |  `None` |
| <a id="kernel_build-sanitizers"></a>sanitizers |  **non-configurable**. A list of sanitizer configurations. By default, no sanitizers are explicity configured; values in defconfig are respected. Possible values are:   - `["kasan_any_mode"]`   - `["kasan_sw_tags"]`   - `["kasan_generic"]`   - `["kcsan"]`<br><br>For mixed builds (`base_kernel` is set), the value of `sanitizers` of the `base_kernel` is used if `--incompatible_inherit_post_defconfig_fragments_from_base_kernel` is set (the default).   |  `None` |
| <a id="kernel_build-ddk_module_defconfig_fragments"></a>ddk_module_defconfig_fragments |  A list of additional defconfigs, to be used in `ddk_module`s building against this kernel. Unlike `post_defconfig_fragments`, `ddk_module_defconfig_fragments` is not applied to this `kernel_build` target, nor dependent legacy `kernel_module`s.   |  `None` |
| <a id="kernel_build-ddk_module_headers"></a>ddk_module_headers |  A list of `ddk_headers`, to be used in `ddk_module`s building against this kernel.<br><br>Inherits `ddk_module_headers` from `base_kernel`, with a lower priority than `ddk_module_headers` of this kernel_build.<br><br>These headers are not applied to this `kernel_build` target.   |  `None` |
| <a id="kernel_build-kcflags"></a>kcflags |  Extra `KCFLAGS`. Empty by default.<br><br>To add common KCFLAGS, you must explicitly set it to `COMMON_KCFLAGS` (see `//build/kernel/kleaf:constants.bzl`).   |  `None` |
| <a id="kernel_build-clang_autofdo_profile"></a>clang_autofdo_profile |  Path to an AutoFDO profile, For example: <pre><code>  clang_autofdo_profile = "//toolchain/pgo-profiles/kernel:aarch64/android16-6.12/kernel.afdo"</code></pre>   |  `None` |
| <a id="kernel_build-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_dtstree"></a>

## kernel_dtstree

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_dtstree")

kernel_dtstree(<a href="#kernel_dtstree-name">name</a>, <a href="#kernel_dtstree-srcs">srcs</a>, <a href="#kernel_dtstree-makefile">makefile</a>, <a href="#kernel_dtstree-kwargs">**kwargs</a>)
</pre>

Specify a kernel DTS tree.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_dtstree-name"></a>name |  name of the module   |  none |
| <a id="kernel_dtstree-srcs"></a>srcs |  sources of the DTS tree. Default is<br><br><pre><code>glob(["**"], exclude = [&#10;    "**/.*",&#10;    "**/.*/**",&#10;    "**/BUILD.bazel",&#10;    "**/*.bzl",&#10;])</code></pre>   |  `None` |
| <a id="kernel_dtstree-makefile"></a>makefile |  Makefile of the DTS tree. Default is `:Makefile`, i.e. the `Makefile` at the root of the package.   |  `None` |
| <a id="kernel_dtstree-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_images"></a>

## kernel_images

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_images")

kernel_images(<a href="#kernel_images-name">name</a>, <a href="#kernel_images-kernel_modules_install">kernel_modules_install</a>, <a href="#kernel_images-kernel_build">kernel_build</a>, <a href="#kernel_images-base_kernel_images">base_kernel_images</a>, <a href="#kernel_images-build_initramfs">build_initramfs</a>,
              <a href="#kernel_images-build_vendor_dlkm">build_vendor_dlkm</a>, <a href="#kernel_images-build_vendor_dlkm_flatten">build_vendor_dlkm_flatten</a>, <a href="#kernel_images-build_boot">build_boot</a>, <a href="#kernel_images-build_vendor_boot">build_vendor_boot</a>,
              <a href="#kernel_images-build_vendor_kernel_boot">build_vendor_kernel_boot</a>, <a href="#kernel_images-build_system_dlkm">build_system_dlkm</a>, <a href="#kernel_images-build_system_dlkm_flatten">build_system_dlkm_flatten</a>, <a href="#kernel_images-build_dtbo">build_dtbo</a>,
              <a href="#kernel_images-dtbo_srcs">dtbo_srcs</a>, <a href="#kernel_images-dtbo_config">dtbo_config</a>, <a href="#kernel_images-mkbootimg">mkbootimg</a>, <a href="#kernel_images-deps">deps</a>, <a href="#kernel_images-boot_image_outs">boot_image_outs</a>, <a href="#kernel_images-modules_list">modules_list</a>,
              <a href="#kernel_images-modules_recovery_list">modules_recovery_list</a>, <a href="#kernel_images-modules_charger_list">modules_charger_list</a>, <a href="#kernel_images-modules_blocklist">modules_blocklist</a>, <a href="#kernel_images-modules_options">modules_options</a>,
              <a href="#kernel_images-vendor_ramdisk_binaries">vendor_ramdisk_binaries</a>, <a href="#kernel_images-vendor_ramdisk_dev_nodes">vendor_ramdisk_dev_nodes</a>, <a href="#kernel_images-system_dlkm_fs_type">system_dlkm_fs_type</a>,
              <a href="#kernel_images-system_dlkm_fs_types">system_dlkm_fs_types</a>, <a href="#kernel_images-system_dlkm_modules_list">system_dlkm_modules_list</a>, <a href="#kernel_images-system_dlkm_modules_blocklist">system_dlkm_modules_blocklist</a>,
              <a href="#kernel_images-system_dlkm_props">system_dlkm_props</a>, <a href="#kernel_images-vendor_dlkm_archive">vendor_dlkm_archive</a>, <a href="#kernel_images-vendor_dlkm_etc_files">vendor_dlkm_etc_files</a>, <a href="#kernel_images-vendor_dlkm_fs_type">vendor_dlkm_fs_type</a>,
              <a href="#kernel_images-vendor_dlkm_modules_list">vendor_dlkm_modules_list</a>, <a href="#kernel_images-vendor_dlkm_modules_blocklist">vendor_dlkm_modules_blocklist</a>, <a href="#kernel_images-vendor_dlkm_props">vendor_dlkm_props</a>,
              <a href="#kernel_images-ramdisk_compression">ramdisk_compression</a>, <a href="#kernel_images-ramdisk_compression_args">ramdisk_compression_args</a>, <a href="#kernel_images-unpack_ramdisk">unpack_ramdisk</a>, <a href="#kernel_images-avb_sign_boot_img">avb_sign_boot_img</a>,
              <a href="#kernel_images-avb_boot_partition_size">avb_boot_partition_size</a>, <a href="#kernel_images-avb_boot_key">avb_boot_key</a>, <a href="#kernel_images-avb_boot_algorithm">avb_boot_algorithm</a>, <a href="#kernel_images-avb_boot_partition_name">avb_boot_partition_name</a>,
              <a href="#kernel_images-dedup_dlkm_modules">dedup_dlkm_modules</a>, <a href="#kernel_images-create_modules_order">create_modules_order</a>, <a href="#kernel_images-kwargs">**kwargs</a>)
</pre>

Build multiple kernel images.

You may use `filegroup.output_group` to request certain files. Example:

```
kernel_images(
    name = "my_images",
    build_vendor_dlkm = True,
)
filegroup(
    name = "my_vendor_dlkm",
    srcs = [":my_images"],
    output_group = "vendor_dlkm.img",
)
```

Allowed strings in `filegroup.output_group`:
* `vendor_dlkm.img`, if `build_vendor_dlkm` is set
* `vendor_dlkm_flatten.img` if `build_vendor_dlkm_flatten` is not empty
* `system_dlkm.img`, if `build_system_dlkm` and `system_dlkm_fs_type` is set
* `system_dlkm.<type>.img` for each of `system_dlkm_fs_types`, if
    `build_system_dlkm` is set and `system_dlkm_fs_types` is not empty.
* `system_dlkm.flatten.<type>.img` for each of `sytem_dlkm_fs_types, if
    `build_system_dlkm_flatten` is set and `system_dlkm_fs_types` is not empty.

If no output files are found, the filegroup resolves to an empty one.
You may also read `OutputGroupInfo` on the `kernel_images` rule directly
in your rule implementation.

For details, see
[Requesting output files](https://bazel.build/extending/rules#requesting_output_files).


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_images-name"></a>name |  name of this rule, e.g. `kernel_images`,   |  none |
| <a id="kernel_images-kernel_modules_install"></a>kernel_modules_install |  A `kernel_modules_install` rule.<br><br>The main kernel build is inferred from the `kernel_build` attribute of the specified `kernel_modules_install` rule. The main kernel build must contain `System.map` in `outs` (which is included if you use `DEFAULT_GKI_OUTS` or `X86_64_OUTS` from `common_kernels.bzl`).   |  none |
| <a id="kernel_images-kernel_build"></a>kernel_build |  A `kernel_build` rule. Must specify if `build_boot`.   |  `None` |
| <a id="kernel_images-base_kernel_images"></a>base_kernel_images |  The `kernel_images()` corresponding to the `base_kernel` of the `kernel_build`. This is required for building a device-specific `system_dlkm` image. For example, if `base_kernel` of `kernel_build()` is `//common:kernel_aarch64`, then `base_kernel_images` is `//common:kernel_aarch64_images`.<br><br>This is also required if `dedup_dlkm_modules and not build_system_dlkm`.   |  `None` |
| <a id="kernel_images-build_initramfs"></a>build_initramfs |  Whether to build initramfs. Keep in sync with `BUILD_INITRAMFS`.   |  `None` |
| <a id="kernel_images-build_vendor_dlkm"></a>build_vendor_dlkm |  Whether to build `vendor_dlkm` image. It must be set if `vendor_dlkm_modules_list` is set.   |  `None` |
| <a id="kernel_images-build_vendor_dlkm_flatten"></a>build_vendor_dlkm_flatten |  Whether to build `vendor_dlkm_flatten` image. The image have directory structure as `/lib/modules/*.ko` i.e. no `uname -r` in the path<br><br>Note: at the time of writing (Jan 2022), `vendor_dlkm.modules.blocklist` is **always** created regardless of the value of `VENDOR_DLKM_MODULES_BLOCKLIST`. If `build_vendor_dlkm()` in `build_utils.sh` does not generate `vendor_dlkm.modules.blocklist`, an empty file is created.   |  `None` |
| <a id="kernel_images-build_boot"></a>build_boot |  Whether to build boot image. It must be set if either `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set.<br><br>This depends on `kernel_build`. Hence, if this is set to `True`, `kernel_build` must be set.<br><br>If `True`, adds `boot.img` to `boot_image_outs` if not already in the list.   |  `None` |
| <a id="kernel_images-build_vendor_boot"></a>build_vendor_boot |  Whether to build `vendor_boot.img`. It must be set if either `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set, and `BUILD_VENDOR_KERNEL_BOOT` is not set.<br><br>At most **one** of `build_vendor_boot` and `build_vendor_kernel_boot` may be set to `True`.<br><br>If `True`, adds `vendor_boot.img` to `boot_image_outs` if not already in the list.   |  `None` |
| <a id="kernel_images-build_vendor_kernel_boot"></a>build_vendor_kernel_boot |  Whether to build `vendor_kernel_boot.img`. It must be set if either `BUILD_BOOT_IMG` or `BUILD_VENDOR_BOOT_IMG` is set, and `SKIP_VENDOR_BOOT` is not set, and `BUILD_VENDOR_KERNEL_BOOT` is set.<br><br>At most **one** of `build_vendor_boot` and `build_vendor_kernel_boot` may be set to `True`.<br><br>If `True`, adds `vendor_kernel_boot.img` to `boot_image_outs` if not already in the list.   |  `None` |
| <a id="kernel_images-build_system_dlkm"></a>build_system_dlkm |  Whether to build system_dlkm.img an image with GKI modules.   |  `None` |
| <a id="kernel_images-build_system_dlkm_flatten"></a>build_system_dlkm_flatten |  Whether to build system_dlkm.flatten.<fs>.img. This image have directory structure as `/lib/modules/*.ko` i.e. no `uname -r` in the path.   |  `None` |
| <a id="kernel_images-build_dtbo"></a>build_dtbo |  Whether to build dtbo image. Keep this in sync with `BUILD_DTBO_IMG`.<br><br>If `dtbo_srcs` is non-empty, `build_dtbo` is `True` by default. Otherwise it is `False` by default.   |  `None` |
| <a id="kernel_images-dtbo_srcs"></a>dtbo_srcs |  list of `*.dtbo` files used to package the `dtbo.img`. Keep this in sync with `MKDTIMG_DTBOS`; see example below.<br><br>If `dtbo_srcs` is non-empty, `build_dtbo` must not be explicitly set to `False`.<br><br>Example: <pre><code>kernel_build(&#10;    name = "tuna_kernel",&#10;    outs = [&#10;        "path/to/foo.dtbo",&#10;        "path/to/bar.dtbo",&#10;    ],&#10;)&#10;kernel_images(&#10;    name = "tuna_images",&#10;    kernel_build = ":tuna_kernel",&#10;    dtbo_srcs = [&#10;        ":tuna_kernel/path/to/foo.dtbo",&#10;        ":tuna_kernel/path/to/bar.dtbo",&#10;    ]&#10;)</code></pre>   |  `None` |
| <a id="kernel_images-dtbo_config"></a>dtbo_config |  a config file to create dtbo image by cfg_create command.   |  `None` |
| <a id="kernel_images-mkbootimg"></a>mkbootimg |  Path to the mkbootimg.py script which builds boot.img. Only used if `build_boot`. If `None`, default to `//tools/mkbootimg:mkbootimg.py`. NOTE: This overrides `MKBOOTIMG_PATH`.   |  `None` |
| <a id="kernel_images-deps"></a>deps |  Additional dependencies to build images.<br><br>This must include the following: - For `initramfs`:   - The file specified by `MODULES_LIST`   - The file specified by `MODULES_BLOCKLIST`, if `MODULES_BLOCKLIST` is set   - The file containing the list of modules needed for booting into recovery.   - The file containing the list of modules needed for booting into charger mode. - For `vendor_dlkm` image:   - The file specified by `VENDOR_DLKM_MODULES_LIST`   - The file specified by `VENDOR_DLKM_MODULES_BLOCKLIST`, if set   - The file specified by `VENDOR_DLKM_PROPS`, if set   - The file specified by `selinux_fc` in `VENDOR_DLKM_PROPS`, if set   |  `None` |
| <a id="kernel_images-boot_image_outs"></a>boot_image_outs |  A list of output files that will be installed to `DIST_DIR` when `build_boot_images` in `build/kernel/build_utils.sh` is executed.<br><br>You may leave out `vendor_boot.img` from the list. It is automatically added when `build_vendor_boot = True`.<br><br>If `build_boot` is equal to `False`, the default is empty.<br><br>If `build_boot` is equal to `True`, the default list assumes the following: - `BOOT_IMAGE_FILENAME` is not set (which takes default value `boot.img`), or is set to   `"boot.img"` - `vendor_boot.img` if `build_vendor_boot` - `RAMDISK_EXT=lz4`. Is used when `ramdisk_compression`(see below) is not specified.   - The list contains `ramdisk.<ramdisk_ext>` which means it assumes `build_boot_images`     generates this file. See `build_utils.sh` on conditions for when it is actually     generated. - if `build_vendor_boot`, it assumes `VENDOR_BOOTCONFIG` is set and   `BOOT_IMAGE_HEADER_VERSION >= 4`, which creates `vendor-bootconfig.img` to contain   `VENDOR_BOOTCONFIG` . - The list contains `dtb.img`   |  `None` |
| <a id="kernel_images-modules_list"></a>modules_list |  A file containing list of modules to use for `vendor_boot.modules.load`.   |  `None` |
| <a id="kernel_images-modules_recovery_list"></a>modules_recovery_list |  A file containing a list of modules to load when booting into recovery.   |  `None` |
| <a id="kernel_images-modules_charger_list"></a>modules_charger_list |  A file containing a list of modules to load when booting into charger mode.   |  `None` |
| <a id="kernel_images-modules_blocklist"></a>modules_blocklist |  A file containing a list of modules which are blocked from being loaded.<br><br>This file is copied directly to staging directory, and should be in the format: <pre><code>blocklist module_name</code></pre>   |  `None` |
| <a id="kernel_images-modules_options"></a>modules_options |  Label to a file copied to `/lib/modules/<kernel_version>/modules.options` on the ramdisk.<br><br>Lines in the file should be of the form: <pre><code>options &lt;modulename&gt; &lt;param1&gt;=&lt;val&gt; &lt;param2&gt;=&lt;val&gt; ...</code></pre>   |  `None` |
| <a id="kernel_images-vendor_ramdisk_binaries"></a>vendor_ramdisk_binaries |  List of vendor ramdisk binaries which includes the device-specific components of ramdisk like the fstab file and the device-specific rc files. If specifying multiple vendor ramdisks and identical file paths exist in the ramdisks, the file from last ramdisk is used.<br><br>Note: **order matters**. To prevent buildifier from sorting the list, add the following: <pre><code># do not sort</code></pre>   |  `None` |
| <a id="kernel_images-vendor_ramdisk_dev_nodes"></a>vendor_ramdisk_dev_nodes |  List of dev nodes description files which describes special device files to be added to the vendor ramdisk. File format is as accepted by mkbootfs.   |  `None` |
| <a id="kernel_images-system_dlkm_fs_type"></a>system_dlkm_fs_type |  Deprecated. Use `system_dlkm_fs_types` instead.<br><br>Supported filesystems for `system_dlkm` image are `ext4` and `erofs`. Defaults to `ext4` if not specified.   |  `None` |
| <a id="kernel_images-system_dlkm_fs_types"></a>system_dlkm_fs_types |  List of file systems type for `system_dlkm` images.<br><br>Supported filesystems for `system_dlkm` image are `ext4` and `erofs`. If not specified, builds `system_dlkm.img` with ext4 else builds `system_dlkm.<fs>.img` for each file system type in the list.   |  `None` |
| <a id="kernel_images-system_dlkm_modules_list"></a>system_dlkm_modules_list |  location of an optional file containing the list of kernel modules which shall be copied into a system_dlkm partition image.   |  `None` |
| <a id="kernel_images-system_dlkm_modules_blocklist"></a>system_dlkm_modules_blocklist |  location of an optional file containing a list of modules which are blocked from being loaded.<br><br>This file is copied directly to the staging directory and should be in the format: <pre><code>blocklist module_name</code></pre>   |  `None` |
| <a id="kernel_images-system_dlkm_props"></a>system_dlkm_props |  location of a text file containing the properties to be used for creation of a `system_dlkm` image (filesystem, partition size, etc). If this is not set (and `build_system_dlkm` is), a default set of properties will be used which assumes an ext4 filesystem and a dynamic partition.   |  `None` |
| <a id="kernel_images-vendor_dlkm_archive"></a>vendor_dlkm_archive |  If set, enable archiving the vendor_dlkm staging directory.   |  `None` |
| <a id="kernel_images-vendor_dlkm_etc_files"></a>vendor_dlkm_etc_files |  Files that need to be copied to `vendor_dlkm.img` etc/ directory.   |  `None` |
| <a id="kernel_images-vendor_dlkm_fs_type"></a>vendor_dlkm_fs_type |  Supported filesystems for `vendor_dlkm.img` are `ext4` and `erofs`. Defaults to `ext4` if not specified.   |  `None` |
| <a id="kernel_images-vendor_dlkm_modules_list"></a>vendor_dlkm_modules_list |  location of an optional file containing the list of kernel modules which shall be copied into a `vendor_dlkm` partition image. Any modules passed into `MODULES_LIST` which become part of the `vendor_boot.modules.load` will be trimmed from the `vendor_dlkm.modules.load`.   |  `None` |
| <a id="kernel_images-vendor_dlkm_modules_blocklist"></a>vendor_dlkm_modules_blocklist |  location of an optional file containing a list of modules which are blocked from being loaded.<br><br>This file is copied directly to the staging directory and should be in the format: <pre><code>blocklist module_name</code></pre>   |  `None` |
| <a id="kernel_images-vendor_dlkm_props"></a>vendor_dlkm_props |  location of a text file containing the properties to be used for creation of a `vendor_dlkm` image (filesystem, partition size, etc). If this is not set (and `build_vendor_dlkm` is), a default set of properties will be used which assumes an ext4 filesystem and a dynamic partition.   |  `None` |
| <a id="kernel_images-ramdisk_compression"></a>ramdisk_compression |  If provided it specfies the format used for any ramdisks generated. If not provided a fallback value from build.config is used. Possible values are `lz4`, `gzip`, None.   |  `None` |
| <a id="kernel_images-ramdisk_compression_args"></a>ramdisk_compression_args |  Command line arguments passed only to lz4 command to control compression level. It only has effect when used with `ramdisk_compression` equal to "lz4".   |  `None` |
| <a id="kernel_images-unpack_ramdisk"></a>unpack_ramdisk |  When set to `False`, skips unpacking the vendor ramdisk and copy it as is, without modifications, into the boot image. Also skips the mkbootfs step.   |  `None` |
| <a id="kernel_images-avb_sign_boot_img"></a>avb_sign_boot_img |  If set to `True` signs the boot image using the avb_boot_key. The kernel prebuilt tool `avbtool` is used for signing.   |  `None` |
| <a id="kernel_images-avb_boot_partition_size"></a>avb_boot_partition_size |  Size of the boot partition in bytes. Used when `avb_sign_boot_img` is True.   |  `None` |
| <a id="kernel_images-avb_boot_key"></a>avb_boot_key |  Path to the key used for signing. Used when `avb_sign_boot_img` is True.   |  `None` |
| <a id="kernel_images-avb_boot_algorithm"></a>avb_boot_algorithm |  `avb_boot_key` algorithm used e.g. SHA256_RSA2048. Used when `avb_sign_boot_img` is True.   |  `None` |
| <a id="kernel_images-avb_boot_partition_name"></a>avb_boot_partition_name |  = Name of the boot partition. Used when `avb_sign_boot_img` is True.   |  `None` |
| <a id="kernel_images-dedup_dlkm_modules"></a>dedup_dlkm_modules |  If set, modules already in `system_dlkm` is excluded in `vendor_dlkm.modules.load`. Modules in `vendor_dlkm` is allowed to link to modules in `system_dlkm`.<br><br>The `system_dlkm` image is defined by the following:<br><br>- If `build_system_dlkm` is set, the `system_dlkm` image built by   this rule. - If `build_system_dlkm` is not set, the `system_dlkm` image in   `base_kernel_images`. If `base_kernel_images` is not set, build   fails.<br><br>If set, **additional changes in the userspace is required** so that `system_dlkm` modules are loaded before `vendor_dlkm` modules.   |  `None` |
| <a id="kernel_images-create_modules_order"></a>create_modules_order |  Whether to create and keep a modules.order file generated by a postorder traversal of the `kernel_modules_install` sources. It applies to building `initramfs` and `vendor_dlkm`.   |  `None` |
| <a id="kernel_images-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_module"></a>

## kernel_module

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_module")

kernel_module(<a href="#kernel_module-name">name</a>, <a href="#kernel_module-kernel_build">kernel_build</a>, <a href="#kernel_module-outs">outs</a>, <a href="#kernel_module-srcs">srcs</a>, <a href="#kernel_module-deps">deps</a>, <a href="#kernel_module-makefile">makefile</a>, <a href="#kernel_module-generate_btf">generate_btf</a>, <a href="#kernel_module-kwargs">**kwargs</a>)
</pre>

Generates a rule that builds an external kernel module.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_module-name"></a>name |  Name of this kernel module.   |  none |
| <a id="kernel_module-kernel_build"></a>kernel_build |  Label referring to the kernel_build module.   |  none |
| <a id="kernel_module-outs"></a>outs |  The expected output files. If unspecified or value is `None`, it is `["{name}.ko"]` by default.<br><br>For each token `out`, the build rule automatically finds a file named `out` in the legacy kernel modules staging directory. The file is copied to the output directory of this package, with the label `name/out`.<br><br>- If `out` doesn't contain a slash, subdirectories are searched.<br><br>  Example: <pre><code>  kernel_module(name = "nfc", outs = ["nfc.ko"])</code></pre><br><br>  The build system copies <pre><code>  &lt;legacy modules staging dir&gt;/lib/modules/*/extra/&lt;some subdir&gt;/nfc.ko</code></pre>   to <pre><code>  &lt;package output dir&gt;/nfc.ko</code></pre><br><br>  `nfc/nfc.ko` is the label to the file.<br><br>- If `out` contains slashes, its value is used. The file is   also copied to the top of package output directory.<br><br>  For example: <pre><code>  kernel_module(name = "nfc", outs = ["foo/nfc.ko"])</code></pre><br><br>  The build system copies <pre><code>  &lt;legacy modules staging dir&gt;/lib/modules/*/extra/foo/nfc.ko</code></pre>   to <pre><code>  foo/nfc.ko</code></pre><br><br>  `nfc/foo/nfc.ko` is the label to the file.<br><br>  The file is also copied to `<package output dir>/nfc.ko`.<br><br>  `nfc/nfc.ko` is the label to the file.<br><br>  See `search_and_cp_output.py` for details.   |  `None` |
| <a id="kernel_module-srcs"></a>srcs |  Source files to build this kernel module. If unspecified or value is `None`, it is by default the list in the above example: <pre><code>glob([&#10;  "**/*.c",&#10;  "**/*.h",&#10;  "**/Kbuild",&#10;  "**/Makefile",&#10;])</code></pre>   |  `None` |
| <a id="kernel_module-deps"></a>deps |  A list of other `kernel_module` or `ddk_module` dependencies.<br><br>Before building this target, `Modules.symvers` from the targets in `deps` are restored, so this target can be built against them.<br><br>It is an undefined behavior to put targets of other types to this list (e.g. `ddk_headers`).   |  `None` |
| <a id="kernel_module-makefile"></a>makefile |  `Makefile` for the module. By default, this is `Makefile` in the current package.<br><br>This file determines where `make modules` is executed.<br><br>This is useful when the Makefile is located in a different package or in a subdirectory.   |  `None` |
| <a id="kernel_module-generate_btf"></a>generate_btf |  Allows generation of BTF type information for the module. If enabled, passes `vmlinux` image to module build, which is required by BTF generator makefile scripts.<br><br>Disabled by default.<br><br>Requires `CONFIG_DEBUG_INFO_BTF` enabled in base kernel.<br><br>Requires rebuild of module if `vmlinux` changed, which may lead to an increase of incremental build time.<br><br>BTF type information increases size of module binary.   |  `None` |
| <a id="kernel_module-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_module_test"></a>

## kernel_module_test

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_module_test")

kernel_module_test(<a href="#kernel_module_test-name">name</a>, <a href="#kernel_module_test-modules">modules</a>, <a href="#kernel_module_test-kwargs">**kwargs</a>)
</pre>

A test on artifacts produced by [kernel_module](kernel.md#kernel_module).

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_module_test-name"></a>name |  name of test   |  none |
| <a id="kernel_module_test-modules"></a>modules |  The list of `*.ko` kernel modules, or targets that produces `*.ko` kernel modules (e.g. [kernel_module](kernel.md#kernel_module)).   |  `None` |
| <a id="kernel_module_test-kwargs"></a>kwargs |  Additional attributes to the internal rule, e.g. [`visibility`](https://docs.bazel.build/versions/main/visibility.html). See complete list [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).   |  none |


<a id="kernel_uapi_headers_cc_library"></a>

## kernel_uapi_headers_cc_library

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kernel_uapi_headers_cc_library")

kernel_uapi_headers_cc_library(<a href="#kernel_uapi_headers_cc_library-name">name</a>, <a href="#kernel_uapi_headers_cc_library-kernel_build">kernel_build</a>)
</pre>

Defines a native cc_library based on a kernel's UAPI headers.

Example:

```
kernel_uapi_headers_cc_library(
    name = "uapi_header_lib",
    kernel_build = "//common:kernel_aarch64",
)

cc_binary(
    name = "foo",
    srcs = ["foo.c"],
    deps = [":uapi_header_lib"],
)
```

Internally, the `kernel_build`'s UAPI header output tarball is unpacked. Then, a header-only
[`cc_library`](https://bazel.build/reference/be/c-cpp#cc_library) is generated. This allows
other native Bazel C/C++ rules to add the kernel's UAPI headers as a dependency.

The library will automatically include the header directory in the dependent build, so source
files are free to simply include the UAPI headers they need.

Note: the `kernel_build`'s output UAPI header tarball includes the `usr/include` prefix. The
prefix is stripped while creating this library. To include the file `usr/include/linux/time.h`
from the tarball, a source file would `#include <linux/time.h>`.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kernel_uapi_headers_cc_library-name"></a>name |  Name of target.   |  none |
| <a id="kernel_uapi_headers_cc_library-kernel_build"></a>kernel_build |  [`kernel_build`](#kernel_build)   |  none |


<a id="kunit_test"></a>

## kunit_test

<pre>
load("@kleaf//build/kernel/kleaf:kernel.bzl", "kunit_test")

kunit_test(<a href="#kunit_test-name">name</a>, <a href="#kunit_test-test_name">test_name</a>, <a href="#kunit_test-modules">modules</a>, <a href="#kunit_test-deps">deps</a>, <a href="#kunit_test-kwargs">**kwargs</a>)
</pre>

A kunit test.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kunit_test-name"></a>name |  name of the test   |  none |
| <a id="kunit_test-test_name"></a>test_name |  name of the kunit test suite   |  none |
| <a id="kunit_test-modules"></a>modules |  list of modules to be installed for kunit test   |  none |
| <a id="kunit_test-deps"></a>deps |  dependencies for kunit test runner   |  none |
| <a id="kunit_test-kwargs"></a>kwargs |  additional arguments for py_test   |  none |


