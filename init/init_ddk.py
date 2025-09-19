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
import shutil
import sys
import tempfile
import textwrap

_TOOLS_BAZEL = "tools/bazel"
_DEVICE_BAZELRC = "device.bazelrc"
_FILE_MARKER_BEGIN = "### GENERATED SECTION - DO NOT MODIFY - BEGIN ###\n"
_FILE_MARKER_END = "### GENERATED SECTION - DO NOT MODIFY - END ###\n"
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

    @staticmethod
    def _update_file(path: pathlib.Path | str, update: str):
        """Updates the content of a section between markers in a file."""
        add_content: bool = False
        skip_line: bool = False
        update_written: bool = False
        open_mode = "r" if path.exists() else "a+"
        with (
            open(path, open_mode, encoding="utf-8") as input_file,
            tempfile.NamedTemporaryFile(mode="w", delete=False) as output_file,
        ):
            for line in input_file:
                if add_content:
                    output_file.write(_FILE_MARKER_BEGIN)
                    output_file.write(update + "\n")
                    update_written = True
                    add_content = False
                if _FILE_MARKER_END in line:
                    skip_line = False
                if _FILE_MARKER_BEGIN in line:
                    skip_line = True
                    add_content = True
                if not skip_line:
                    output_file.write(line)
            if not update_written:
                output_file.write(_FILE_MARKER_BEGIN)
                output_file.write(update + "\n")
                output_file.write(_FILE_MARKER_END)
            shutil.move(output_file.name, path)

    def _generate_module_bazel(self):
        if not self.ddk_workspace or not self.kleaf_repo_dir:
            return
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        self._update_file(
            module_bazel,
            _KLEAF_DEPENDENCY_TEMPLATE.format(
                kleaf_repo_dir=self.kleaf_repo_dir
            ),
        )

    def _generate_bazelrc(self):
        if not self.ddk_workspace or not self.kleaf_repo_dir:
            return
        bazelrc = self.ddk_workspace / _DEVICE_BAZELRC
        self._update_file(
            bazelrc,
            textwrap.dedent(f"""\
            common --config=internet
            common --registry=file:{self.kleaf_repo_dir}/external/bazelbuild-bazel-central-registry
            """),
        )

    def _handle_local_kleaf(self):
        self._symlink_tools_bazel()
        self._generate_module_bazel()
        self._generate_bazelrc()

    def run(self):
        self._handle_local_kleaf()


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--ddk_workspace",
        help="Absolute path to DDK workspace root.",
        type=pathlib.Path,
        default=None,
    )
    parser.add_argument(
        "--kleaf_repo_dir",
        help="Absolute path to Kleaf's repo dir.",
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
