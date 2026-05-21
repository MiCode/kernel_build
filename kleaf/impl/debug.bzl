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

"""Utility functions for debugging Kleaf."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

visibility("//build/kernel/kleaf/...")

def _print_scripts(ctx, command, what = None):
    """Print scripts at analysis phase.

    Requires `_debug_print_scripts` to be in `attrs`.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
        command: The command passed to `ctx.actions.run_shell`
        what: an optional text to distinguish actions within a target.
    """
    _print_scripts_subrule_impl(
        subrule_ctx = ctx,
        command = command,
        what = what,
        _debug_print_scripts = ctx.attr._debug_print_scripts,
    )

def _print_scripts_subrule_impl(subrule_ctx, command, *, _debug_print_scripts, what = None):
    """Print scripts at analysis phase.

    Args:
        subrule_ctx: subrule_ctx
        command: The command passed to `ctx.actions.run_shell`
        _debug_print_scripts: target of the flag
        what: an optional text to distinguish actions within a target.
    """
    if _debug_print_scripts[BuildSettingInfo].value:
        # buildifier: disable=print
        print("""
        # Script that runs %s%s:%s""" % (subrule_ctx.label, (" " + what if what else ""), command))

_print_scripts_subrule = subrule(
    implementation = _print_scripts_subrule_impl,
    attrs = {
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
    },
)

def _trap():
    """Return a shell script that prints a date before each command afterwards.
    """
    return """set -x
              trap '>&2 /bin/date' DEBUG"""

def _modpost_warn(ctx):
    """Returns useful script snippets and files for --debug_modpost_warn."""

    if not ctx.attr._debug_modpost_warn[BuildSettingInfo].value:
        return struct(
            cmd = "",
            outputs = [],
            make_redirect = "",
        )

    cmd = """
          export KBUILD_MODPOST_WARN=1
          """

    # This file is used in build_cleaner.
    make_stderr = ctx.actions.declare_file("{}/make_stderr.txt".format(ctx.attr.name))
    make_redirect = " 2> >(tee {} >&2)".format(make_stderr.path)

    return struct(
        cmd = cmd,
        outputs = [make_stderr],
        make_redirect = make_redirect,
    )

def _target_platform_libc(ctx, _glibc, _musl):
    val = ""
    if ctx.target_platform_has_constraint(_glibc[platform_common.ConstraintValueInfo]):
        val += "glibc"
    if ctx.target_platform_has_constraint(_musl[platform_common.ConstraintValueInfo]):
        val += "musl"
    if not val:
        val = "?"
    return val

# Note: It defeats the purpose of using a subrule by passing the whole ctx into
# subrule implementation. But we need ctx.target_platform_has_constraint, and
# this is for debugging only.
def _print_platforms_impl(subrule_ctx, ctx, *, _should_print, _glibc, _musl):
    """Prints platform information.

    Args:
        subrule_ctx: with `fragments = ["platform"]`
        ctx: with `target_platform_has_constraint`
        _should_print: value of --debug_print_platforms
        _glibc: glibc constraint value
        _musl: musl constraint value

    Returns:
        whether debug platform information was printed.
    """

    if not _should_print[BuildSettingInfo].value:
        return False

    # buildifier: disable=print
    print("{}: libc={}, plat={}, host={}".format(
        subrule_ctx.label,
        _target_platform_libc(ctx, _glibc, _musl),
        subrule_ctx.fragments.platform.platform,
        subrule_ctx.fragments.platform.host_platform,
    ))
    return True

_print_platforms = subrule(
    implementation = _print_platforms_impl,
    attrs = {
        "_should_print": attr.label(default = "//build/kernel/kleaf:debug_print_platforms"),
        "_glibc": attr.label(default = "//build/kernel/kleaf/platforms/libc:glibc"),
        "_musl": attr.label(default = "//build/kernel/kleaf/platforms/libc:musl"),
    },
    fragments = ["platform"],
)

def _print_platforms_aspect_impl(_target, ctx):
    _print_platforms_impl(
        ctx,
        ctx,
        _should_print = ctx.attr._should_print,
        _glibc = ctx.attr._glibc,
        _musl = ctx.attr._musl,
    )
    return []

_print_platforms_aspect = aspect(
    doc = """
        If --debug_print_platforms, print debug info on platforms for the dependency the asepct
        is applied on.
    """,
    implementation = _print_platforms_aspect_impl,
    attrs = {
        "_should_print": attr.label(default = "//build/kernel/kleaf:debug_print_platforms"),
        "_glibc": attr.label(default = "//build/kernel/kleaf/platforms/libc:glibc"),
        "_musl": attr.label(default = "//build/kernel/kleaf/platforms/libc:musl"),
    },
    # We can't use `subrules = _print_platforms` due to
    # https://github.com/bazelbuild/bazel/issues/23282
)

debug = struct(
    print_scripts = _print_scripts,
    print_scripts_subrule = _print_scripts_subrule,
    trap = _trap,
    modpost_warn = _modpost_warn,
    print_platforms = _print_platforms,
    print_platforms_aspect = _print_platforms_aspect,
)
