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

"""Rules to enable ABI monitoring."""

load("//build/bazel_common_rules/exec:exec.bzl", "exec")
load("//build/kernel/kleaf:update_source_file.bzl", "update_source_file")
load(":abi/abi_diff.bzl", "abi_diff")
load(":abi/abi_dump.bzl", "abi_dump")
load(":abi/abi_prop.bzl", "abi_prop")
load(":abi/extracted_symbols.bzl", "extracted_symbols")
load(":abi/get_src_kmi_symbol_list.bzl", "get_src_kmi_symbol_list")
load(":kernel_build.bzl", "kernel_build")
load(":utils.bzl", "utils")

# TODO(b/242072873): Delete once all use cases migrate to kernel_abi.
def kernel_build_abi(
        name,
        define_abi_targets = None,
        # for kernel_abi
        kernel_modules = None,
        module_grouping = None,
        abi_definition = None,
        kmi_enforced = None,
        unstripped_modules_archive = None,
        kmi_symbol_list_add_only = None,
        # A subset of common attributes accepted by kernel_build_abi.
        # https://bazel.build/reference/be/common-definitions#common-attributes
        tags = None,
        features = None,
        testonly = None,
        visibility = None,
        # for kernel_build
        **kwargs):
    """**Deprecated**. Use [`kernel_build`](#kernel_build) (with `collect_unstripped_modules = True`) and [`kernel_abi`](#kernel_abi) directly.

    Declare multiple targets to support ABI monitoring.

    This macro is meant to be used in place of the [`kernel_build`](#kernel_build)
    marco. All arguments in `kwargs` are passed to `kernel_build` directly.

    For example, you may have the following declaration. (For actual definition
    of `kernel_aarch64`, see
    [`define_common_kernels()`](#define_common_kernels).

    ```
    kernel_build_abi(name = "kernel_aarch64", ...)
    ```

    The `kernel_build_abi` invocation is equivalent to the following:

    ```
    kernel_build(
        name = "kernel_aarch64",
        collect_unstripped_modules = True,
        ...
    )
    kernel_abi(name = "kernel_aarch64_abi", ...)
    ```

    Args:
      name: Name of the main `kernel_build`.
      define_abi_targets: See [`kernel_abi.define_abi_targets`](#kernel_abi-define_abi_targets)
      kernel_modules: See [`kernel_abi.kernel_modules`](#kernel_abi-kernel_modules)
      module_grouping: See [`kernel_abi.module_grouping`](#kernel_abi-module_grouping)
      abi_definition: See [`kernel_abi.abi_definition`](#kernel_abi-abi_definition)
      kmi_enforced: See [`kernel_abi.kmi_enforced`](#kernel_abi-kmi_enforced)
      unstripped_modules_archive: See [`kernel_abi.unstripped_modules_archive`](#kernel_abi-unstripped_modules_archive)
      kmi_symbol_list_add_only: See [`kernel_abi.kmi_symbol_list_add_only`](#kernel_abi-kmi_symbol_list_add_only)
      tags: [tags](https://bazel.build/reference/be/common-definitions#common.tags)
      visibility: [visibility](https://bazel.build/reference/be/common-definitions#common.visibility)
      features: [features](https://bazel.build/reference/be/common-definitions#common.features)
      testonly: [testonly](https://bazel.build/reference/be/common-definitions#common.testonly)
      **kwargs: Passed directly to [`kernel_build`](#kernel_build).

    Deprecated:
      Use [`kernel_build`](#kernel_build) (with `collect_unstripped_modules = True`) and
      [`kernel_abi`](#kernel_abi) directly.
    """

    kwargs = dict(kwargs)
    if kwargs.get("collect_unstripped_modules") == None:
        kwargs["collect_unstripped_modules"] = True

    # buildifier: disable=print
    print("""
WARNING: kernel_build_abi is deprecated. Split into kernel_build and kernel_abi.

You may try copy-pasting the following definition to BUILD.bazel
(note: this is not necessarily accurate and likely unformatted):

kernel_build(
    {kwargs},
)

kernel_abi(
    {abi_kwargs},
)
""".format(
        kwargs = utils.kwargs_to_def(
            name = name,
            tags = tags,
            visibility = visibility,
            features = features,
            testonly = testonly,
            **kwargs
        ),
        abi_kwargs = utils.kwargs_to_def(
            name = name + "_abi",
            define_abi_targets = define_abi_targets,
            kernel_modules = kernel_modules,
            module_grouping = module_grouping,
            abi_definition = abi_definition,
            kmi_enforced = kmi_enforced,
            unstripped_modules_archive = unstripped_modules_archive,
            kmi_symbol_list_add_only = kmi_symbol_list_add_only,
            tags = tags,
            visibility = visibility,
            features = features,
            testonly = testonly,
        ),
    ))

    kernel_abi(
        name = name + "_abi",
        kernel_build = name,
        define_abi_targets = define_abi_targets,
        kernel_modules = kernel_modules,
        module_grouping = module_grouping,
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        abi_definition = abi_definition,
        kmi_enforced = kmi_enforced,
        unstripped_modules_archive = unstripped_modules_archive,
        # common attributes
        tags = tags,
        visibility = visibility,
        features = features,
        testonly = testonly,
    )

    kernel_build(
        name = name,
        # common attributes
        tags = tags,
        visibility = visibility,
        features = features,
        testonly = testonly,
        **kwargs
    )

def kernel_abi(
        name,
        kernel_build,
        define_abi_targets = None,
        kernel_modules = None,
        module_grouping = None,
        abi_definition = None,
        kmi_enforced = None,
        unstripped_modules_archive = None,
        kmi_symbol_list_add_only = None,
        **kwargs):
    """Declare multiple targets to support ABI monitoring.

    This macro is meant to be used in place of the [`kernel_build`](#kernel_build)
    marco. All arguments in `kwargs` are passed to `kernel_build` directly.

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
    _dist_targets = ["kernel_aarch64", ...]
    copy_to_dist_dir(name = "kernel_aarch64_dist", data = _dist_targets)
    kernel_abi_dist(
        name = "kernel_aarch64_abi_dist",
        kernel_abi = "kernel_aarch64_abi",
        data = _dist_targets,
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

    See build/kernel/kleaf/abi.md for a conversion chart from `build_abi.sh`
    commands to Bazel commands.

    Args:
      name: Name of this target.
      kernel_build: The [`kernel_build`](#kernel_build).
      define_abi_targets: Whether the target contains other
        files to support ABI monitoring. If `None`, defaults to `True`.

        If `False`, this macro is equivalent to just calling
        ```
        kernel_build(name = name, **kwargs)
        filegroup(name = name + "_abi", data = [name, abi_dump_target])
        ```

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
      kmi_symbol_list_add_only: If unspecified or `None`, it is `False` by
        default. If `True`,
        then any symbols in the symbol list that would have been
        removed are preserved (at the end of the file). Symbol list update will
        fail if there is no pre-existing symbol list file to read from. This
        property is intended to prevent unintentional shrinkage of a stable ABI.

        This should be set to `True` if `KMI_SYMBOL_LIST_ADD_ONLY=1`.
      **kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if define_abi_targets == None:
        define_abi_targets = True

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    abi_dump(
        name = name + "_dump",
        kernel_build = kernel_build,
        kernel_modules = kernel_modules,
        **private_kwargs
    )

    if not define_abi_targets:
        _not_define_abi_targets(
            name = name,
            abi_dump_target = name + "_dump",
            **kwargs
        )
    else:
        _define_abi_targets(
            name = name,
            kernel_build = kernel_build,
            kernel_modules = kernel_modules,
            module_grouping = module_grouping,
            kmi_symbol_list_add_only = kmi_symbol_list_add_only,
            abi_definition = abi_definition,
            kmi_enforced = kmi_enforced,
            unstripped_modules_archive = unstripped_modules_archive,
            abi_dump_target = name + "_dump",
            **kwargs
        )

def _not_define_abi_targets(
        name,
        abi_dump_target,
        **kwargs):
    """Helper to `_define_other_targets` when `define_abi_targets = False.`

    Defines `{name}` filegroup that only contains the ABI dump, provided
    in `abi_dump_target`.

    Defines:
    * `{name}_diff_executable`
    * `{name}`
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    native.filegroup(
        name = name,
        srcs = [abi_dump_target],
        **kwargs
    )

    # For kernel_abi_dist to use when define_abi_targets is not set.
    exec(
        name = name + "_diff_executable",
        script = "",
        **private_kwargs
    )

def _define_abi_targets(
        name,
        kernel_build,
        kernel_modules,
        module_grouping,
        kmi_symbol_list_add_only,
        abi_definition,
        kmi_enforced,
        unstripped_modules_archive,
        abi_dump_target,
        **kwargs):
    """Helper to `_define_other_targets` when `define_abi_targets = True.`

    Define targets to extract symbol list, extract ABI, update them, etc.

    Defines:
    * `{name}_diff_executable`
    * `{name}`
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    default_outputs = [abi_dump_target]

    get_src_kmi_symbol_list(
        name = name + "_src_kmi_symbol_list",
        kernel_build = kernel_build,
        **private_kwargs
    )

    # extract_symbols ...
    extracted_symbols(
        name = name + "_extracted_symbols",
        kernel_build_notrim = kernel_build,
        kernel_modules = kernel_modules,
        module_grouping = module_grouping,
        src = name + "_src_kmi_symbol_list",
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        **private_kwargs
    )
    update_source_file(
        name = name + "_update_symbol_list",
        src = name + "_extracted_symbols",
        dst = name + "_src_kmi_symbol_list",
        **private_kwargs
    )

    default_outputs += _define_abi_definition_targets(
        name = name,
        abi_definition = abi_definition,
        kmi_enforced = kmi_enforced,
        kmi_symbol_list = name + "_src_kmi_symbol_list",
        **private_kwargs
    )

    abi_prop(
        name = name + "_prop",
        kmi_definition = name + "_out_file" if abi_definition else None,
        kmi_enforced = kmi_enforced,
        kernel_build = kernel_build,
        modules_archive = unstripped_modules_archive,
        **private_kwargs
    )
    default_outputs.append(name + "_prop")

    native.filegroup(
        name = name,
        srcs = default_outputs,
        **kwargs
    )

def _define_abi_definition_targets(
        name,
        abi_definition,
        kmi_enforced,
        kmi_symbol_list,
        **kwargs):
    """Helper to `_define_abi_targets`.

    Defines targets to extract ABI, update ABI, compare ABI, etc. etc.

    Defines `{name}_diff_executable`.
    """
    if not abi_definition:
        # For kernel_abi_dist to use when abi_definition is empty.
        exec(
            name = name + "_diff_executable",
            script = "",
            **kwargs
        )
        return []

    default_outputs = []

    native.filegroup(
        name = name + "_out_file",
        srcs = [name + "_dump"],
        output_group = "abi_out_file",
        **kwargs
    )

    abi_diff(
        name = name + "_diff",
        baseline = abi_definition,
        new = name + "_out_file",
        kmi_enforced = kmi_enforced,
        **kwargs
    )
    default_outputs.append(name + "_diff")

    # The default outputs of _diff does not contain the executable,
    # but the reports. Use this filegroup to select the executable
    # so rootpath in _update works.
    native.filegroup(
        name = name + "_diff_executable",
        srcs = [name + "_diff"],
        output_group = "executable",
        **kwargs
    )

    native.filegroup(
        name = name + "_diff_git_message",
        srcs = [name + "_diff"],
        output_group = "git_message",
        **kwargs
    )

    update_source_file(
        name = name + "_update_definition",
        src = name + "_out_file",
        dst = abi_definition,
        **kwargs
    )

    exec(
        name = name + "_nodiff_update",
        data = [
            name + "_extracted_symbols",
            name + "_update_definition",
            kmi_symbol_list,
        ],
        script = """
              # Ensure that symbol list is updated
                if ! diff -q $(rootpath {src_symbol_list}) $(rootpath {dst_symbol_list}); then
                  echo "ERROR: symbol list must be updated before updating ABI definition. To update, execute 'tools/bazel run //{package}:{update_symbol_list_label}'." >&2
                  exit 1
                fi
              # Update abi_definition
                $(rootpath {update_definition})
            """.format(
            src_symbol_list = name + "_extracted_symbols",
            dst_symbol_list = kmi_symbol_list,
            package = native.package_name(),
            update_symbol_list_label = name + "_update_symbol_list",
            update_definition = name + "_update_definition",
        ),
        **kwargs
    )

    exec(
        name = name + "_update",
        data = [
            abi_definition,
            name + "_diff_git_message",
            name + "_diff_executable",
            name + "_nodiff_update",
        ],
        script = """
              # Update abi_definition
                $(rootpath {nodiff_update})
              # Create git commit if requested
                if [[ $1 == "--commit" ]]; then
                    real_abi_def="$(realpath $(rootpath {abi_definition}))"
                    git -C $(dirname ${{real_abi_def}}) add $(basename ${{real_abi_def}})
                    git -C $(dirname ${{real_abi_def}}) commit -F $(realpath $(rootpath {git_message}))
                fi
              # Check return code of diff_abi and kmi_enforced
                set +e
                $(rootpath {diff})
                rc=$?
                set -e
              # Prompt for editing the commit message
                if [[ $1 == "--commit" ]]; then
                    echo
                    echo "INFO: git commit created. Execute the following to edit the commit message:"
                    echo "        git -C $(dirname $(rootpath {abi_definition})) commit --amend"
                fi
                exit $rc
            """.format(
            diff = name + "_diff_executable",
            nodiff_update = name + "_nodiff_update",
            abi_definition = abi_definition,
            git_message = name + "_diff_git_message",
        ),
        **kwargs
    )

    return default_outputs
