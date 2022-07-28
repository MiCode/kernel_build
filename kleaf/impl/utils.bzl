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

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load(":common_providers.bzl", "KernelModuleInfo")

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
    """Find a file named |name| in the list of |files|. Expect zero or one match."""
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
            files = ":\n  " + ("\n  ".join(result)) if result else "",
        ))
    return result[0] if result else None

def find_files(files, what, suffix = None):
    """Find files with given condition. The following conditions are accepted:

    - Looking for files ending with a given suffix.
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

# Utilities that applies to all Bazel stuff in general. These functions are
# not Kleaf specific.
utils = struct(
    intermediates_dir = _intermediates_dir,
    reverse_dict = _reverse_dict,
    getoptattr = _getoptattr,
    find_file = find_file,
    find_files = find_files,
    compare_file_names = _compare_file_names,
)

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

def _kernel_build_outs_add_vmlinux(name, outs):
    """Add vmlinux etc. to the outs attribute of a `kernel_build`.

    The logic should be in par with `_transform_kernel_build_outs`.
    """
    files_to_add = ("vmlinux", "System.map")
    outs_changed = False
    if outs == None:
        outs = ["vmlinux"]
        outs_changed = True
    if type(outs) == type([]):
        for file in files_to_add:
            if file not in outs:
                # don't use append to avoid changing outs
                outs = outs + [file]
                outs_changed = True
    elif type(outs) == type({}):
        outs_new = {}
        for k, v in outs.items():
            for file in files_to_add:
                if file not in v:
                    # don't use append to avoid changing outs
                    v = v + [file]
                    outs_changed = True
            outs_new[k] = v
        outs = outs_new
    else:
        fail("{}: Invalid type for outs: {}".format(name, type(outs)))
    return outs, outs_changed

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

kernel_utils = struct(
    filter_module_srcs = _filter_module_srcs,
    transform_kernel_build_outs = _transform_kernel_build_outs,
    check_kernel_build = _check_kernel_build,
    kernel_build_outs_add_vmlinux = _kernel_build_outs_add_vmlinux,
)
