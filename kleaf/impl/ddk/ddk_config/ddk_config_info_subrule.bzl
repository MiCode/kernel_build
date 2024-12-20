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

def _ddk_config_info_subrule_impl(
        subrule_ctx,  # buildifier: disable=unused-variable
        kconfig_targets,
        defconfig_targets,
        deps,
        extra_defconfigs = None):
    """
    Create a regular DdkConfigInfo.

    Args:
        subrule_ctx: context
        kconfig_targets: list of targets containing Kconfig files
        defconfig_targets: list of targets containing defconfig files
        deps: list of dependencies. Only those with `DdkConfigInfo` are used.
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

    return DdkConfigInfo(
        kconfig = kconfig,
        kconfig_written = utils.write_depset(kconfig, "kconfig_depset.txt"),
        defconfig = defconfig,
        defconfig_written = utils.write_depset(defconfig, "defconfig_depset.txt"),
    )

ddk_config_info_subrule = subrule(
    implementation = _ddk_config_info_subrule_impl,
    subrules = [
        utils.write_depset,
    ],
)
