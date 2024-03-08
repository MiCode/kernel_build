#!/usr/bin/env python3
#
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

"""Configures the project layout to build DDK modules."""

import argparse
import logging
import pathlib
import sys

_TOOLS_BAZEL = "tools/bazel"
_MODULE_BAZEL_FILE = "MODULE.bazel"

_KLEAF_DEPENDENCY_TEMPLATE = """\
\"""Kleaf: Build Android kernels with Bazel.\"""
bazel_dep(name = "kleaf")
local_path_override(
    module_name = "kleaf",
    path = "{kleaf_repo_dir}",
)
"""


class KleafProjectSetterError(RuntimeError):
    pass


class KleafProjectSetter:
    """Configures the project layout to build DDK modules."""

    def __init__(self, cmd_args: argparse.Namespace):
        self.ddk_workspace: pathlib.Path | None = cmd_args.ddk_workspace
        self.kleaf_repo_dir: pathlib.Path | None = cmd_args.kleaf_repo_dir

    def _symlink_tools_bazel(self):
        if not self.ddk_workspace or not self.kleaf_repo_dir:
            return
        # TODO: b/328770706 -- Error handling.
        # Calculate the paths.
        tools_bazel = self.ddk_workspace / _TOOLS_BAZEL
        kleaf_tools_bazel = self.kleaf_repo_dir / _TOOLS_BAZEL
        # Prepare the location and clean up if necessary
        tools_bazel.parent.mkdir(parents=True, exist_ok=True)
        tools_bazel.unlink(missing_ok=True)

        tools_bazel.symlink_to(kleaf_tools_bazel)

    def _generate_module_bazel(self):
        if not self.ddk_workspace:
            return
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        with open(module_bazel, "w", encoding="utf-8") as f:
            # TODO: b/328770706 -- Use markers to avoid overriding user overrides.
            if self.kleaf_repo_dir:
                f.write(
                    _KLEAF_DEPENDENCY_TEMPLATE.format(
                        kleaf_repo_dir=self.kleaf_repo_dir
                    )
                )

    def _handle_local_kleaf(self):
        self._symlink_tools_bazel()
        self._generate_module_bazel()

    def run(self):
        self._handle_local_kleaf()


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--ddk_workspace",
        help="DDK workspace root.",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--kleaf_repo_dir",
        help="Path to Kleaf's repo dir.",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--url_fmt",
        help="URL format endpoint for CI downloads.",
        default=None,
    )
    parser.add_argument(
        "--build_id",
        type=str,
        help="the build id to download the build for, e.g. 6148204",
    )
    parser.add_argument(
        "--build_target",
        type=str,
        help='the build target to download, e.g. "kernel_aarch64"',
        default="kernel_aarch64",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    try:
        KleafProjectSetter(cmd_args=args).run()
    except KleafProjectSetterError as e:
        logging.error(e, exc_info=e)
        sys.exit(1)
