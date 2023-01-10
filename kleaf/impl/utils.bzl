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

"""
Utilities for kleaf.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    ":common_providers.bzl",
    "DdkSubmoduleInfo",
    "KernelEnvInfo",
    "KernelModuleInfo",
    "ModuleSymversInfo",
)
load(":ddk/ddk_headers.bzl", "DdkHeadersInfo")

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
    """Return attribute value if |thing| has attribute named |attr|, otherwise return |default_value|."""
    if hasattr(thing, attr):
        return getattr(thing, attr)
    return default_value

def find_file(name, files, what, required = False):
    """Find a file named |name| in the list of |files|. Expect zero or one match.

    Args:
        name: Name of the file to be searched.
        files: List of files.
        what: Target.
        required: whether to fail if a non exact result is produced.

    Returns:
        A match when found or `None`.
    """
    result = []
    for file in files:
        if file.basename == name:
            result.append(file)
    if len(result) > 1 or (not result and required):
        fail("{what} contains {actual_len} file(s) named {name}, expected {expected_len}{files}".format(
            what = what,
            actual_len = len(result),
            name = name,
            expected_len = "1" if required else "0 or 1",
            files = ":\n  " + ("\n  ".join([e.path for e in result])) if result else "",
        ))
    return result[0] if result else None

def find_files(files, suffix = None):
    """Find files which names end with a given |suffix|.

    Args:
        files: list of files to inspect.
        suffix: Looking for files ending with this given suffix.

    Returns:
        A list of files.
    """
    result = []
    for file in files:
        if suffix != None and file.basename.endswith(suffix):
            result.append(file)
    return result

def _intermediates_dir(ctx):
    """Return a good directory for intermediates.

    This generally ensures that different targets have their own intermediates
    dir. This is similar to

    ```
    ctx.actions.declare_directory(ctx.attr.name + "_intermediates")
    ```

    ... but not actually declaring the directory, so there's no `File` object
    and no need to add it to the list of outputs of an action. It also won't
    conflict with any other actions that generates outputs of
    `declare_file(ctx.attr.name + "_intermediates/" + file_name)`.

    For sandboxed actions, this means the intermediates dir does not need to be
    cleaned up. However, for local actions, the result of intermediates dir from
    a previous build may remain and affect a later build. Use with caution.
    """
    return paths.join(
        ctx.genfiles_dir.path,
        paths.dirname(ctx.build_file_path),
        ctx.attr.name + "_intermediates",
    )

def _compare_file_names(files, expected_file_names, what):
    """Check that the list of files matches the given expected list.

    The basenames of files are checked.

    Args:
      files: A list of [File](https://bazel.build/rules/lib/File)s.
      expected_file_names: A list of file names to check files against.
      what: description of the caller that compares the file names.
    """

    actual_file_names = [file.basename for file in files]
    actual_set = sets.make(actual_file_names)
    expected_set = sets.make(expected_file_names)
    if not sets.is_equal(actual_set, expected_set):
        fail("{}: Actual: {}\nExpected: {}".format(
            what,
            actual_file_names,
            expected_file_names,
        ))

def _sanitize_label_as_filename(label):
    """Sanitize a Bazel label so it is safe to be used as a filename."""
    label_text = str(label)
    return "".join([c if c.isalnum() else "_" for c in label_text.elems()])

def _kwargs_to_def(**kwargs):
    """Turns d into text that can be copied to BUILD files. May be inaccurate."""
    for key, value in list(kwargs.items()):
        if value == None:
            kwargs.pop(key)

    return ",\n    ".join(sorted(["{key} = {value_repr}".format(
        key = key,
        value_repr = repr(value),
    ) for key, value in kwargs.items()]))

def _hash_hex(x):
    """Returns `hash(x)` in hex format."""
    ret = "%x" % hash(x)
    if len(ret) < 8:
        ret = "0" * (8 - len(ret)) + ret
    return ret

def _get_check_sandbox_cmd():
    """Returns a script that tries to check if we are running in a sandbox.

    Note: This is not always accurate."""

    return """
           if [[ $PWD != */sandbox/* ]]; then
             echo "FATAL: this action must be executed in a sandbox!" >&2
             exit 1
           fi
    """

# Utilities that applies to all Bazel stuff in general. These functions are
# not Kleaf specific.
utils = struct(
    intermediates_dir = _intermediates_dir,
    reverse_dict = _reverse_dict,
    getoptattr = _getoptattr,
    find_file = find_file,
    find_files = find_files,
    compare_file_names = _compare_file_names,
    sanitize_label_as_filename = _sanitize_label_as_filename,
    kwargs_to_def = _kwargs_to_def,
    hash_hex = _hash_hex,
    get_check_sandbox_cmd = _get_check_sandbox_cmd,
)

def _filter_module_srcs(files):
    """Filters and categorizes sources for building `kernel_module`."""
    hdrs = []
    scripts = []
    for file in files:
        if file.path.endswith(".h"):
            hdrs.append(file)
        elif "Makefile" in file.path or "scripts/" in file.path:
            scripts.append(file)
    return struct(
        module_scripts = depset(scripts),
        module_hdrs = depset(hdrs),
    )

def _transform_kernel_build_outs(name, what, outs):
    """Transform `*outs` attributes for `kernel_build`.

    - If `outs` is a list, return it directly.
    - If `outs` is a dict, return `select(outs)`.
    - Otherwise fail

    The logic should be in par with `_kernel_build_outs_add_vmlinux`.
    """
    if outs == None:
        return None
    if type(outs) == type([]):
        return outs
    elif type(outs) == type({}):
        return select(outs)
    else:
        fail("{}: Invalid type for {}: {}".format(name, what, type(outs)))

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
        if kernel_build == None:
            kernel_build = kernel_module[KernelModuleInfo].kernel_build
            continue

        if kernel_module[KernelModuleInfo].kernel_build.label != \
           kernel_build.label:
            fail((
                "{this_label} refers to kernel_build {kernel_build}, but " +
                "depended kernel_module {dep} refers to kernel_build " +
                "{dep_kernel_build}. They must refer to the same kernel_build."
            ).format(
                this_label = this_label,
                kernel_build = kernel_build.label,
                dep = kernel_module.label,
                dep_kernel_build = kernel_module[KernelModuleInfo].kernel_build.label,
            ))

def _local_exec_requirements(ctx):
    """Returns the execution requirement for `--config=local`.

    This should only be used on the actions that are proven to be safe to be
    built outside of the sandbox.
    """
    if ctx.attr._config_is_local[BuildSettingInfo].value:
        return {"local": "1"}
    return None

def _split_kernel_module_deps(deps, this_label):
    """Splits `deps` for a `kernel_module` or `ddk_module`.

    Args:
        deps: The list of deps
        this_label: label of the module being checked.
    """

    kernel_module_deps = []
    hdr_deps = []
    submodule_deps = []
    module_symvers_deps = []
    for dep in deps:
        is_valid_dep = False
        if DdkHeadersInfo in dep:
            hdr_deps.append(dep)
            is_valid_dep = True
        if all([info in dep for info in [KernelEnvInfo, KernelModuleInfo, ModuleSymversInfo]]):
            kernel_module_deps.append(dep)
            is_valid_dep = True
        if all([info in dep for info in [DdkHeadersInfo, DdkSubmoduleInfo]]):
            submodule_deps.append(dep)
            is_valid_dep = True
        if ModuleSymversInfo in dep:
            module_symvers_deps.append(dep)
            is_valid_dep = True
        if not is_valid_dep:
            fail("{}: {} is not a valid item in deps. Only kernel_module, ddk_module, ddk_headers, ddk_submodule are accepted.".format(this_label, dep.label))
    return struct(
        kernel_modules = kernel_module_deps,
        hdrs = hdr_deps,
        submodules = submodule_deps,
        module_symvers_deps = module_symvers_deps,
    )

kernel_utils = struct(
    filter_module_srcs = _filter_module_srcs,
    transform_kernel_build_outs = _transform_kernel_build_outs,
    check_kernel_build = _check_kernel_build,
    local_exec_requirements = _local_exec_requirements,
    split_kernel_module_deps = _split_kernel_module_deps,
)
