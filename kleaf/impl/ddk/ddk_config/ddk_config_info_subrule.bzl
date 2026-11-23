# Copyright (C) 2024 The Android Open Source Project
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

"""Subrules for creating DdkConfigInfo."""

load(
    ":common_providers.bzl",
    "DdkConfigInfo",
)
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/impl/...")

def _resolve_kernel_build_ddk_config_env_impl(
        subrule_ctx,
        kernel_build_ddk_config_env,
        deps):
    """Compares kernel_build_ddk_config_env against those in deps.

    Args:
        subrule_ctx: context
        kernel_build_ddk_config_env: represents kernel_build of this target
        deps: dependencies to compare

    Returns:
        Resolved kernel_build_ddk_config_env. This must be a single value consistent
        across this target and all dependencies. If none of this target or any dependencies
        provide a reference to `kernel_build`, returns `None`.
    """

    # key: the ddk_config_env; value: a target or subrule_ctx with the given ddk_config_env
    d = {}
    d[kernel_build_ddk_config_env] = [subrule_ctx]
    for dep in deps:
        if DdkConfigInfo in dep:
            d.setdefault(dep[DdkConfigInfo].kernel_build_ddk_config_env, []).append(dep)

    # We don't compare targets without a reference to kernel_build
    d.pop(None, None)

    if len(d) > 1:
        msg = "The following dependencies refers to a different kernel_build. They must refer to the same kernel_build.\n"
        for info, lst in d.items():
            msg += "    {} is used by\n".format(info.setup_script)
            for labeled_object in lst:
                msg += "        {}\n".format(labeled_object.label)
        fail("{}: {}".format(subrule_ctx.label, msg))

    if len(d) == 1:
        return list(d.keys())[0]

    return None

_resolve_kernel_build_ddk_config_env = subrule(
    implementation = _resolve_kernel_build_ddk_config_env_impl,
)

def _ddk_config_info_subrule_impl(
        subrule_ctx,  # buildifier: disable=unused-variable
        kconfig_targets,
        defconfig_targets,
        deps,
        kernel_build_ddk_config_env,
        extra_defconfigs = None):
    """
    Create a regular DdkConfigInfo.

    Args:
        subrule_ctx: context
        kconfig_targets: list of targets containing Kconfig files
        defconfig_targets: list of targets containing defconfig files
        deps: list of dependencies. Only those with `DdkConfigInfo` are used.
        kernel_build_ddk_config_env: Optional `ddk_config_env` from `kernel_build`.
        extra_defconfigs: extra depset of defconfig files. Lowest priority.
    """

    if extra_defconfigs == None:
        extra_defconfigs = depset()

    kconfig = depset(
        transitive = [dep[DdkConfigInfo].kconfig for dep in deps if DdkConfigInfo in dep] +
                     [target.files for target in kconfig_targets],
        order = "postorder",
    )
    defconfig = depset(
        transitive = [extra_defconfigs] +
                     [dep[DdkConfigInfo].defconfig for dep in deps if DdkConfigInfo in dep] +
                     [target.files for target in defconfig_targets],
        order = "postorder",
    )

    resolved_kernel_build_ddk_config_env = _resolve_kernel_build_ddk_config_env(
        kernel_build_ddk_config_env = kernel_build_ddk_config_env,
        deps = deps,
    )

    return DdkConfigInfo(
        kconfig = kconfig,
        kconfig_written = utils.write_depset(kconfig, "kconfig_depset.txt"),
        defconfig = defconfig,
        defconfig_written = utils.write_depset(defconfig, "defconfig_depset.txt"),
        kernel_build_ddk_config_env = resolved_kernel_build_ddk_config_env,
    )

ddk_config_info_subrule = subrule(
    implementation = _ddk_config_info_subrule_impl,
    subrules = [
        utils.write_depset,
        _resolve_kernel_build_ddk_config_env,
    ],
)

def _empty_ddk_config_info_impl(_subrule_ctx, *, kernel_build_ddk_config_env):
    """Create an empty DdkConfigInfo."""
    empty = depset(order = "postorder")
    written = utils.write_depset(empty, "empty_depset.txt")
    return DdkConfigInfo(
        kconfig = empty,
        kconfig_written = written,
        defconfig = empty,
        defconfig_written = written,
        kernel_build_ddk_config_env = kernel_build_ddk_config_env,
    )

empty_ddk_config_info = subrule(
    implementation = _empty_ddk_config_info_impl,
    subrules = [
        utils.write_depset,
    ],
)

def _combine_ddk_config_info_impl(subrule_ctx, *, child, parent, parent_label):
    """Combine the depsets in two ddk_config_info for inheritance.

    Args:
        subrule_ctx: context
        child: DdkConfigInfo of this target.
        parent: DdkConfigInfo of parent target. Use empty_ddk_config_info if no parent.
        parent_label: optional parent label for logging.
    """

    # Parent goes first.
    kconfig = utils.combine_depset(
        parent.kconfig,
        child.kconfig,
        order = "postorder",
    )
    defconfig = utils.combine_depset(
        parent.defconfig,
        child.defconfig,
        order = "postorder",
    )

    # Check that child & parent has the same kernel_build_ddk_config_env.
    # In practice, this check is never hit because ddk_config_info_subrule fails prematurely.
    # However, we still put this check here for consistency.
    if (child.kernel_build_ddk_config_env and
        parent.kernel_build_ddk_config_env and
        child.kernel_build_ddk_config_env != parent.kernel_build_ddk_config_env):
        fail("""{this_label}: parent config has a different kernel_build.
    This target {this_label} uses {child_config}.
    Parent {parent_label} config uses {parent_config}.
""".format(
            this_label = subrule_ctx.label,
            child_config = child.kernel_build_ddk_config_env.setup_script,
            parent_config = parent.kernel_build_ddk_config_env.setup_script,
            parent_label = parent_label,
        ))

    resolved_kernel_build_ddk_config_env = (child.kernel_build_ddk_config_env or
                                            parent.kernel_build_ddk_config_env)

    return DdkConfigInfo(
        kconfig = kconfig,
        kconfig_written = utils.write_depset(kconfig, "combined_kconfig_depset.txt"),
        defconfig = defconfig,
        defconfig_written = utils.write_depset(defconfig, "combined_defconfig_depset.txt"),
        kernel_build_ddk_config_env = resolved_kernel_build_ddk_config_env,
    )

combine_ddk_config_info = subrule(
    implementation = _combine_ddk_config_info_impl,
    subrules = [
        utils.write_depset,
    ],
)
