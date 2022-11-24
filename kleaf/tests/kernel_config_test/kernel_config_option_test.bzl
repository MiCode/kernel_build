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
Test kernel_config against options (e.g. lto).
Require //common package.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("//build/kernel/kleaf:constants.bzl", "LTO_VALUES")
load("//build/kernel/kleaf:kernel.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")
load("//build/kernel/kleaf/tests/utils:contain_lines_test.bzl", "contain_lines_test")
load(":kernel_config_aspect.bzl", "KernelConfigAspectInfo", "kernel_config_aspect")

# Helper functions and rules.

_KASAN_FLAG = "//build/kernel/kleaf:kasan"
_KGDB_FLAG = "//build/kernel/kleaf:kgdb"
_LTO_FLAG = "//build/kernel/kleaf:lto"
_ARCHS = ("aarch64", "x86_64")

def _symlink_config(ctx, kernel_build, filename):
    """Symlinks the `.config` file of the `kernel_build` to a file with file name `{filename}`.

    The config file is compared with `data/{filename}` later by the caller.

    Return:
        The file with name `{prefix}_config`, which points to the `.config` of the kernel.
    """
    kernel_config = kernel_build[KernelConfigAspectInfo].kernel_config
    config_file = utils.find_file(
        name = ".config",
        files = kernel_config.files.to_list(),
        what = "{}: kernel_config outputs".format(kernel_build.label),
    )

    # Create symlink so that the Python test script compares with the correct expected file.
    symlink = ctx.actions.declare_file("{}/{}".format(ctx.label.name, filename))
    ctx.actions.symlink(output = symlink, target_file = config_file)

    return symlink

def _get_config_attrs_common(transition):
    """Common attrs for rules to get `.config` of the given `kernel_build` with the given transition.

    Args:
      transition: The transition. May be `None` if no transition is needed.
    """
    attrs = {
        "kernel_build": attr.label(cfg = transition, aspects = [kernel_config_aspect], mandatory = True),
    }
    if transition != None:
        attrs.update({
            "_allowlist_function_transition": attr.label(
                default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
            ),
        })
    return attrs

def _get_transitioned_config_impl(ctx):
    """Common impl for getting `.config` of the given `kernel_build` with the given transition.

    Helper for testing a flag.
    """
    files = [
        _symlink_config(ctx, kernel_build, key + "_config")
        for key, kernel_build in ctx.split_attr.kernel_build.items()
    ]
    return DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files))

def _transition_test(name, kernel_build, test_data_rule, expected, **test_data_rule_kwargs):
    """Test the effect of a flag on `kernel_config`.

    Helper for testing a flag.

    Args:
        name: name of test
        test_data_rule: `rule()` to get the actual `.config` of a kernel.
        expected: A list of expected files.
        kernel_build: target under test
        **test_data_rule_kwargs: kwargs to `test_data_rule`.
    """
    test_data_rule(
        name = name + "_actual",
        kernel_build = kernel_build,
        **test_data_rule_kwargs
    )
    native.filegroup(
        name = name + "_expected",
        srcs = expected,
    )
    contain_lines_test(
        name = name,
        expected = name + "_expected",
        actual = name + "_actual",
    )

def _get_config_impl(ctx):
    symlink = _symlink_config(ctx, ctx.attr.kernel_build, ctx.attr.prefix + "_config")
    return DefaultInfo(files = depset([symlink]), runfiles = ctx.runfiles(files = [symlink]))

_get_config = rule(
    implementation = _get_config_impl,
    doc = "Generic way to get `.config` for a kernel without transition. Helper for testing attributes.",
    attrs = dicts.add(_get_config_attrs_common(None), {
        "prefix": attr.string(doc = "prefix of output file name"),
    }),
)

# Tests

## Tests on --lto

def _lto_transition_impl(_settings, _attr):
    return {value: {_LTO_FLAG: value} for value in LTO_VALUES}

_lto_transition = transition(
    implementation = _lto_transition_impl,
    inputs = [],
    outputs = [_LTO_FLAG],
)

_lto_test_data = rule(
    implementation = _get_transitioned_config_impl,
    doc = "Get `.config` for a kernel with the LTO transition.",
    attrs = _get_config_attrs_common(_lto_transition),
)

def _lto_test(name, kernel_build):
    """Test the effect of a `--lto` on `kernel_config`."""
    _transition_test(
        name = name,
        kernel_build = kernel_build,
        test_data_rule = _lto_test_data,
        expected = ["data/{}_config".format(lto) for lto in LTO_VALUES],
    )

## Tests on --kasan
def _kasan_str(kasan):
    return "kasan" if kasan else "nokasan"

def _kasan_transition_impl(_settings, _attr):
    return {_kasan_str(kasan): {_KASAN_FLAG: kasan} for kasan in (True, False)}

_kasan_transition = transition(
    implementation = _kasan_transition_impl,
    inputs = [],
    outputs = [_KASAN_FLAG],
)

_kasan_test_data = rule(
    implementation = _get_transitioned_config_impl,
    doc = "Get `.config` for a kernel with the KASAN transition.",
    attrs = _get_config_attrs_common(_kasan_transition),
)

def _kasan_test(name, kernel_build):
    """Test the effect of a `--kasan` on `kernel_config`."""
    _transition_test(
        name = name,
        kernel_build = kernel_build,
        test_data_rule = _kasan_test_data,
        expected = ["data/{}_config".format(_kasan_str(kasan)) for kasan in (True, False)],
    )

## Tests on --kgdb
def _kgdb_str(kgdb, arch):
    return ("kgdb" if kgdb else "nokgdb") + "_" + arch

def _kgdb_transition_impl(_settings, attr):
    return {_kgdb_str(kgdb, attr.arch): {_KGDB_FLAG: kgdb} for kgdb in (True, False)}

_kgdb_transition = transition(
    implementation = _kgdb_transition_impl,
    inputs = [],
    outputs = [_KGDB_FLAG],
)

_kgdb_test_data = rule(
    implementation = _get_transitioned_config_impl,
    doc = "Get `.config` for a kernel with the kgdb transition.",
    attrs = dicts.add(_get_config_attrs_common(_kgdb_transition), {
        "arch": attr.string(),
    }),
)

def _kgdb_test(name, arch, kernel_build):
    """Test the effect of a `--kgdb` on `kernel_config`."""

    _transition_test(
        name = name,
        kernel_build = kernel_build,
        test_data_rule = _kgdb_test_data,
        expected = ["data/{}_config".format(_kgdb_str(kgdb, arch)) for kgdb in (True, False)],
        arch = arch,
    )

## Tests on `trim_nonlisted_kmi`

def _trim_str(trim):
    return "trim" if trim else "notrim"

def _trim_test(name, kernels):
    """Test the effect of `trim_nonlisted_kmi` on `kernel_config`.

    Args:
        name: name of test
        kernels: a dict, where key is a struct, and value is
          the label to the target under test (`kernel_build`).

          The key struct contains:
          - trim: whether trimming is enabled
          - arch: architecture
    """
    tests = []
    for key, kernel_build in kernels.items():
        trim_str = _trim_str(key.trim)
        prefix = key.arch + "_" + trim_str
        test_name = "{name}_{prefix}".format(name = name, prefix = prefix)

        _get_config(
            name = test_name + "_config",
            prefix = trim_str,
            kernel_build = kernel_build,
        )
        contain_lines_test(
            name = test_name,
            expected = "data/{}_config".format(trim_str),
            actual = test_name + "_config",
        )
        tests.append(test_name)
    native.test_suite(
        name = name,
        tests = tests,
    )

## Tests on all combinations.

def _combined_transition_impl(_settings, attr):
    ret = {}
    for lto in LTO_VALUES:
        for kasan in (True, False):
            for kgdb in (True, False):
                if kasan and lto not in ("default", "none"):
                    continue

                key = {
                    "lto": lto,
                    "kasan": kasan,
                    "kgdb": kgdb,
                    "arch": attr.arch,
                }
                key_str = json.encode(key)
                ret[key_str] = {
                    _LTO_FLAG: lto,
                    _KASAN_FLAG: kasan,
                    _KGDB_FLAG: kgdb,
                }
    return ret

_combined_transition = transition(
    implementation = _combined_transition_impl,
    inputs = [],
    outputs = [_KASAN_FLAG, _KGDB_FLAG, _LTO_FLAG],
)

def _combined_test_actual_impl(ctx):
    files = []
    for key_str, kernel_build in ctx.split_attr.kernel_build.items():
        key = json.decode(key_str)

        # Directory to store symlinks for that specific flag combination
        flag_dir = paths.join(
            key["lto"],
            _kasan_str(key["kasan"]),
            _kgdb_str(key["kgdb"], key["arch"]),
        )

        files += [
            # Test LTO setting
            _symlink_config(ctx, kernel_build, paths.join(flag_dir, key["lto"] + "_config")),
            # Test kasan setting
            _symlink_config(ctx, kernel_build, paths.join(flag_dir, _kasan_str(key["kasan"]) + "_config")),
            # Test kgdb setting
            _symlink_config(ctx, kernel_build, paths.join(flag_dir, _kgdb_str(key["kgdb"], key["arch"]) + "_config")),
            # Test trim setting
            _symlink_config(ctx, kernel_build, paths.join(flag_dir, ctx.attr.trim_str + "_config")),
        ]

    return DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files))

_combined_test_actual = rule(
    implementation = _combined_test_actual_impl,
    doc = "Test on all combinations of flags and attributes on `kernel_config`",
    attrs = dicts.add(_get_config_attrs_common(_combined_transition), {
        "trim_str": attr.string(),
        "arch": attr.string(),
    }),
)

def _combined_option_test(name, kernels):
    """Test the effect of all possible combinations of flags on `kernel_config`:

    Args:
        name: name of test
        kernels: a dict, where key is a struct, and value is
          the label to the target under test (`kernel_build`).

          The key struct contains:
          - trim: whether trimming is enabled
          - arch: architecture
    """
    tests = []
    for key, kernel_build in kernels.items():
        trim_str = _trim_str(key.trim)
        prefix = key.arch + "_" + trim_str
        test_name = "{name}_{prefix}".format(name = name, prefix = prefix)

        _combined_test_actual(
            name = test_name + "_actual",
            trim_str = trim_str,
            arch = key.arch,
            kernel_build = kernel_build,
        )
        native.filegroup(
            name = test_name + "_expected",
            srcs = ["data/{}_config".format(lto) for lto in LTO_VALUES] +
                   ["data/{}_config".format(_kasan_str(kasan)) for kasan in (True, False)] +
                   ["data/{}_config".format(_kgdb_str(kgdb, key.arch)) for kgdb in (True, False)] +
                   ["data/{}_config".format(trim_str)],
        )
        contain_lines_test(
            name = test_name,
            actual = test_name + "_actual",
            expected = test_name + "_expected",
        )
        tests.append(test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )

## Exported test suite.

def kernel_config_option_test_suite(name):
    """Tests for various flags on `kernel_config`.

    Args:
        name: name of the test.
    """
    for arch in _ARCHS:
        kernel_build(
            name = name + "_kernel_{}".format(arch),
            srcs = ["//common:kernel_{}_sources".format(arch)],
            build_config = "//common:build.config.gki.{}".format(arch),
            outs = [],
            tags = ["manual"],
        )

        kernel_build(
            name = name + "_kernel_{}_trim".format(arch),
            srcs = ["//common:kernel_{}_sources".format(arch)],
            build_config = "//common:build.config.gki.{}".format(arch),
            trim_nonlisted_kmi = True,
            kmi_symbol_list = "data/fake_kmi_symbol_list",
            outs = [],
            tags = ["manual"],
        )

        kernel_build(
            name = name + "_kernel_{}_notrim".format(arch),
            srcs = ["//common:kernel_{}_sources".format(arch)],
            build_config = "//common:build.config.gki.{}".format(arch),
            trim_nonlisted_kmi = False,
            kmi_symbol_list = "data/fake_kmi_symbol_list",
            outs = [],
            tags = ["manual"],
        )

    trim_kernels = {}
    for arch in _ARCHS:
        for trim in (True, False):
            trim_kernels[struct(trim = trim, arch = arch)] = \
                name + "_kernel_{}_{}".format(arch, _trim_str(trim))

    tests = []

    for arch in _ARCHS:
        _lto_test(
            name = name + "_lto_{}_test".format(arch),
            kernel_build = name + "_kernel_{}".format(arch),
        )
        tests.append(name + "_lto_{}_test".format(arch))

        _kasan_test(
            name = name + "_kasan_{}_test".format(arch),
            kernel_build = name + "_kernel_{}".format(arch),
        )
        tests.append(name + "_kasan_{}_test".format(arch))

        _kgdb_test(
            name = name + "_kgdb_{}_test".format(arch),
            kernel_build = name + "_kernel_{}".format(arch),
            arch = arch,
        )
        tests.append(name + "_kgdb_{}_test".format(arch))

    _trim_test(
        name = name + "_trim_test",
        kernels = trim_kernels,
    )
    tests.append(name + "_trim_test")

    _combined_option_test(
        name = name + "_combined_option_test",
        kernels = trim_kernels,
    )
    tests.append(name + "_combined_option_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
