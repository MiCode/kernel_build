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

load("//build/bazel_common_rules/exec:exec.bzl", "exec")
load("//build/kernel/kleaf:update_source_file.bzl", "update_source_file")
load(":abi/abi_diff.bzl", "abi_diff")
load(":abi/abi_dump.bzl", "abi_dump")
load(":abi/abi_prop.bzl", "abi_prop")
load(":abi/extracted_symbols.bzl", "extracted_symbols")
load(":kernel_build.bzl", "kernel_build")
load(":utils.bzl", "kernel_utils")

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
    kernel_build_abi_dist(
        name = "kernel_aarch64_abi_dist",
        kernel_build_abi = "kernel_aarch64",
        data = _dist_targets,
    )
    ```

    The `kernel_build_abi` invocation is equivalent to the following:

    ```
    kernel_build(name = "kernel_aarch64", **kwargs)
    # if define_abi_targets, also define some other targets
    ```

    See [`kernel_build`](#kernel_build) for the targets defined.

    In addition, the following targets are defined:
    - `kernel_aarch64_abi_dump`
      - Building this target extracts the ABI.
      - Include this target in a [`kernel_build_abi_dist`](#kernel_build_abi_dist)
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
      - Include this target in a [`kernel_build_abi_dist`](#kernel_build_abi_dist)
        target to copy ABI dump to `--dist-dir`.

    See build/kernel/kleaf/abi.md for a conversion chart from `build_abi.sh`
    commands to Bazel commands.

    Args:
      name: Name of the main `kernel_build`.
      define_abi_targets: Whether the `<name>_abi` target contains other
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
      kwargs: See [`kernel_build.kwargs`](#kernel_build-kwargs)
    """

    if define_abi_targets == None:
        define_abi_targets = True

    kwargs = dict(kwargs)
    if kwargs.get("collect_unstripped_modules") == None:
        kwargs["collect_unstripped_modules"] = True

    _define_other_targets(
        name = name,
        define_abi_targets = define_abi_targets,
        kernel_modules = kernel_modules,
        module_grouping = module_grouping,
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        abi_definition = abi_definition,
        kmi_enforced = kmi_enforced,
        unstripped_modules_archive = unstripped_modules_archive,
        kernel_build_kwargs = kwargs,
    )

    kernel_build(name = name, **kwargs)

def _define_other_targets(
        name,
        define_abi_targets,
        kernel_modules,
        module_grouping,
        kmi_symbol_list_add_only,
        abi_definition,
        kmi_enforced,
        unstripped_modules_archive,
        kernel_build_kwargs):
    """Helper to `kernel_build_abi`.

    Defines targets other than the main `kernel_build()`.

    Defines:
    * `{name}_with_vmlinux`
    * `{name}_notrim` (if `define_abi_targets`)
    * `{name}_abi_diff_executable`
    * `{name}_abi`
    """
    new_outs, outs_changed = kernel_utils.kernel_build_outs_add_vmlinux(name, kernel_build_kwargs.get("outs"))

    # with_vmlinux: outs += [vmlinux]; base_kernel = None; kbuild_symtypes = True
    # Technically we may skip creating the _with_vmlinux target when
    # kbuild_symtypes = "auto" and --kbuild_symtypes, but there's no easy way
    # to determine flag values at loading phase.
    need_separate_with_vmlinux_target = outs_changed or kernel_build_kwargs.get("base_kernel") or kernel_build_kwargs.get("kbuild_symtypes") != "true"

    if need_separate_with_vmlinux_target:
        with_vmlinux_kwargs = dict(kernel_build_kwargs)
        with_vmlinux_kwargs["outs"] = kernel_utils.transform_kernel_build_outs(name + "_with_vmlinux", "outs", new_outs)
        with_vmlinux_kwargs["base_kernel_for_module_outs"] = with_vmlinux_kwargs.pop("base_kernel", default = None)
        kernel_build(name = name + "_with_vmlinux", **with_vmlinux_kwargs)
    else:
        native.alias(name = name + "_with_vmlinux", actual = name)

    abi_dump(
        name = name + "_abi_dump",
        kernel_build = name + "_with_vmlinux",
        kernel_modules = [module + "_with_vmlinux" for module in kernel_modules] if kernel_modules else kernel_modules,
    )

    if not define_abi_targets:
        _not_define_abi_targets(
            name = name,
            abi_dump_target = name + "_abi_dump",
        )
    else:
        _define_abi_targets(
            name = name,
            kernel_modules = kernel_modules,
            module_grouping = module_grouping,
            kmi_symbol_list_add_only = kmi_symbol_list_add_only,
            abi_definition = abi_definition,
            kmi_enforced = kmi_enforced,
            unstripped_modules_archive = unstripped_modules_archive,
            outs_changed = outs_changed,
            new_outs = new_outs,
            abi_dump_target = name + "_abi_dump",
            kernel_build_with_vmlinux_target = name + "_with_vmlinux",
            need_separate_with_vmlinux_target = need_separate_with_vmlinux_target,
            kernel_build_kwargs = kernel_build_kwargs,
        )

def _not_define_abi_targets(
        name,
        abi_dump_target):
    """Helper to `_define_other_targets` when `define_abi_targets = False.`

    Defines `{name}_abi` filegroup that only contains the ABI dump, provided
    in `abi_dump_target`.

    Defines:
    * `{name}_abi_diff_executable`
    * `{name}_abi`
    """
    native.filegroup(
        name = name + "_abi",
        srcs = [abi_dump_target],
    )

    # For kernel_build_abi_dist to use when define_abi_targets is not set.
    exec(
        name = name + "_abi_diff_executable",
        script = "",
    )

def _define_abi_targets(
        name,
        kernel_modules,
        module_grouping,
        kmi_symbol_list_add_only,
        abi_definition,
        kmi_enforced,
        unstripped_modules_archive,
        outs_changed,
        new_outs,
        abi_dump_target,
        kernel_build_with_vmlinux_target,
        need_separate_with_vmlinux_target,
        kernel_build_kwargs):
    """Helper to `_define_other_targets` when `define_abi_targets = True.`

    Define targets to extract symbol list, extract ABI, update them, etc.

    Defines:
    * `{name}_notrim`
    * `{name}_abi_diff_executable`
    * `{name}_abi`
    """

    default_outputs = [abi_dump_target]

    # notrim: like _with_vmlinux, but trim_nonlisted_kmi = False
    if need_separate_with_vmlinux_target or kernel_build_kwargs.get("trim_nonlisted_kmi"):
        notrim_kwargs = dict(kernel_build_kwargs)
        notrim_kwargs["outs"] = kernel_utils.transform_kernel_build_outs(name + "_notrim", "outs", new_outs)
        notrim_kwargs["trim_nonlisted_kmi"] = False
        notrim_kwargs["kmi_symbol_list_strict_mode"] = False
        notrim_kwargs["base_kernel_for_module_outs"] = notrim_kwargs.pop("base_kernel", default = None)
        kernel_build(name = name + "_notrim", **notrim_kwargs)
    else:
        native.alias(name = name + "_notrim", actual = name)

    # extract_symbols ...
    extracted_symbols(
        name = name + "_abi_extracted_symbols",
        kernel_build_notrim = name + "_notrim",
        kernel_modules = [module + "_notrim" for module in kernel_modules] if kernel_modules else kernel_modules,
        module_grouping = module_grouping,
        src = kernel_build_kwargs.get("kmi_symbol_list"),
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        # If base_kernel is set, this is a device build, so use the GKI
        # modules list from base_kernel (GKI). If base_kernel is not set, this
        # likely a GKI build, so use modules_outs from itself.
        gki_modules_list_kernel_build = kernel_build_kwargs.get("base_kernel", name),
    )
    update_source_file(
        name = name + "_abi_update_symbol_list",
        src = name + "_abi_extracted_symbols",
        dst = kernel_build_kwargs.get("kmi_symbol_list"),
    )

    default_outputs += _define_abi_definition_targets(
        name = name,
        abi_definition = abi_definition,
        kmi_enforced = kmi_enforced,
        kmi_symbol_list = kernel_build_kwargs.get("kmi_symbol_list"),
    )

    abi_prop(
        name = name + "_abi_prop",
        kmi_definition = name + "_abi_out_file" if abi_definition else None,
        kmi_enforced = kmi_enforced,
        kernel_build = kernel_build_with_vmlinux_target,
        modules_archive = unstripped_modules_archive,
    )
    default_outputs.append(name + "_abi_prop")

    native.filegroup(
        name = name + "_abi",
        srcs = default_outputs,
    )

def _define_abi_definition_targets(
        name,
        abi_definition,
        kmi_enforced,
        kmi_symbol_list):
    """Helper to `_define_abi_targets`.

    Defines targets to extract ABI, update ABI, compare ABI, etc. etc.

    Defines `{name}_abi_diff_executable`.
    """
    if not abi_definition:
        # For kernel_build_abi_dist to use when abi_definition is empty.
        exec(
            name = name + "_abi_diff_executable",
            script = "",
        )
        return []

    default_outputs = []

    native.filegroup(
        name = name + "_abi_out_file",
        srcs = [name + "_abi_dump"],
        output_group = "abi_out_file",
    )

    abi_diff(
        name = name + "_abi_diff",
        baseline = abi_definition,
        new = name + "_abi_out_file",
        kmi_enforced = kmi_enforced,
    )
    default_outputs.append(name + "_abi_diff")

    # The default outputs of _abi_diff does not contain the executable,
    # but the reports. Use this filegroup to select the executable
    # so rootpath in _abi_update works.
    native.filegroup(
        name = name + "_abi_diff_executable",
        srcs = [name + "_abi_diff"],
        output_group = "executable",
    )

    native.filegroup(
        name = name + "_abi_diff_git_message",
        srcs = [name + "_abi_diff"],
        output_group = "git_message",
    )

    update_source_file(
        name = name + "_abi_update_definition",
        src = name + "_abi_out_file",
        dst = abi_definition,
    )

    exec(
        name = name + "_abi_nodiff_update",
        data = [
            name + "_abi_extracted_symbols",
            name + "_abi_update_definition",
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
            src_symbol_list = name + "_abi_extracted_symbols",
            dst_symbol_list = kmi_symbol_list,
            package = native.package_name(),
            update_symbol_list_label = name + "_abi_update_symbol_list",
            update_definition = name + "_abi_update_definition",
        ),
    )

    exec(
        name = name + "_abi_update",
        data = [
            abi_definition,
            name + "_abi_diff_git_message",
            name + "_abi_diff_executable",
            name + "_abi_nodiff_update",
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
            diff = name + "_abi_diff_executable",
            nodiff_update = name + "_abi_nodiff_update",
            abi_definition = abi_definition,
            git_message = name + "_abi_diff_git_message",
        ),
    )

    return default_outputs
