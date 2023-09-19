# Copyright (C) 2023 The Android Open Source Project
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

"""A genrule that uses hermetic tools."""

load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _hermetic_genrule_toolchain_setup_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    setup_sh = ctx.actions.declare_file("{}/setup.sh".format(ctx.label.name))
    ctx.actions.write(setup_sh, hermetic_tools.setup, is_executable = True)
    return DefaultInfo(files = depset([setup_sh]))

_hermetic_genrule_toolchain_setup = rule(
    implementation = _hermetic_genrule_toolchain_setup_impl,
    toolchains = [hermetic_toolchain.type],
)

def _hermetic_genrule_toolchain_deps_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    return DefaultInfo(files = hermetic_tools.deps)

_hermetic_genrule_toolchain_deps = rule(
    implementation = _hermetic_genrule_toolchain_deps_impl,
    toolchains = [hermetic_toolchain.type],
)

def hermetic_genrule(
        name,
        cmd,
        tools = None,
        **kwargs):
    """A genrule that uses hermetic tools.

    Hermetic tools are resolved from toolchain resolution. To replace it,
    register a different hermetic toolchain.

    Only `cmd` is expected and used. `cmd_bash`, `cmd_ps`, `cmd_bat` etc. are
    ignored.

    Args:
        name: name of the target
        cmd: See [genrule.cmd](https://bazel.build/reference/be/general#genrule.cmd)
        tools: See [genrule.tools](https://bazel.build/reference/be/general#genrule.tools)
        **kwargs: See [genrule](https://bazel.build/reference/be/general#genrule)
    """

    # Not using a global target here because it is hard to be referred to
    # in pre_cmd below, especially when this macro is invoked in another
    # repository.
    _hermetic_genrule_toolchain_setup(
        name = name + "_hermetic_genrule_toolchain_setup",
    )

    _hermetic_genrule_toolchain_deps(
        name = name + "_hermetic_genrule_toolchain_deps",
    )

    if tools == None:
        tools = []

    # tools may not be a list (it may be a select()), so use a explicit expr
    tools = tools + [
        name + "_hermetic_genrule_toolchain_setup",
        name + "_hermetic_genrule_toolchain_deps",
    ]

    pre_cmd = """
        . $(execpath {name}_hermetic_genrule_toolchain_setup)
    """.format(name = name)

    native.genrule(
        name = name,
        tools = tools,
        cmd = pre_cmd + cmd,
        **kwargs
    )
