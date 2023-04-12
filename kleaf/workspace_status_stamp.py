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

import dataclasses
import logging
import os
import shutil
import subprocess
import sys
from typing import Optional


@dataclasses.dataclass
class PathCollectible(object):
    """Represents a path and the result of an asynchronous task."""
    path: str

    def collect(self):
        return NotImplementedError


@dataclasses.dataclass
class PathPopen(PathCollectible):
    """Consists of a path and the result of a subprocess."""
    popen: subprocess.Popen

    def collect(self):
        return collect(self.popen)


@dataclasses.dataclass
class PresetResult(PathCollectible):
    """Consists of a path and a pre-defined result."""
    result: str

    def collect(self):
        return self.result


def call_setlocalversion(bin, srctree, *args) \
        -> Optional[subprocess.Popen[str]]:
    """Call setlocalversion.

    Args:
      bin: path to setlocalversion, or None if it does not exist.
      srctree: The argument to setlocalversion.
      args: additional arguments
    Return:
      A subprocess.Popen object, or None if bin or srctree does not exist.
    """
    working_dir = "build/kernel/kleaf/workspace_status_dir"
    if bin and os.path.isdir(srctree):
        return subprocess.Popen([bin, srctree] + list(args),
                                text=True,
                                stdout=subprocess.PIPE,
                                cwd=working_dir)
    return None


def list_projects():
    """Lists projects in the repository.

    Returns:
        a list of projects in the repository.
    """
    args = ["repo", "forall", "-c", 'echo "$REPO_PATH $REPO_LREV"']
    try:
        output = subprocess.check_output(args, text=True)
        return parse_repo_prop(output)
    except (subprocess.SubprocessError, FileNotFoundError) as e:
        logging.error("Unable to list projects: %s", e)

    return []


def parse_repo_prop(content: str):
    """Parses a repo.prop file

    Returns:
        a list of projects in the repository.
    """
    return [line.split()[0] for line in content.splitlines()]


def collect(popen_obj: subprocess.Popen) -> str:
    """Collect the result of a Popen object.

    Terminates the program if return code is non-zero.

    Return:
      stdout of the subprocess.
    """
    stdout, _ = popen_obj.communicate()
    if popen_obj.returncode != 0:
        logging.error("return code is %d", popen_obj.returncode)
        sys.exit(1)
    return stdout.strip()


class Stamp(object):

    def __init__(self):
        self.projects = list_projects()
        self.init_for_dot_source_date_epoch_dir()

    def init_for_dot_source_date_epoch_dir(self) -> None:
        self.kernel_dir = os.path.realpath(".source_date_epoch_dir")
        if not os.path.isdir(self.kernel_dir):
            self.kernel_dir = None
        if self.kernel_dir:
            self.kernel_rel = os.path.relpath(self.kernel_dir)

        self.find_setlocalversion()

    def main(self) -> int:
        scmversion_map = self.call_setlocalversion_all()

        source_date_epoch_map = self.async_get_source_date_epoch_all()

        scmversion_result_map = self.collect_map(scmversion_map)

        source_date_epoch_result_map = self.collect_map(source_date_epoch_map)

        self.print_result(
            scmversion_result_map=scmversion_result_map,
            source_date_epoch_result_map=source_date_epoch_result_map,
        )
        return 0

    def find_setlocalversion(self) -> None:
        self.setlocalversion = None
        if self.kernel_dir:
            candidate = os.path.join(self.kernel_dir,
                                     "scripts/setlocalversion")
            if os.access(candidate, os.X_OK):
                self.setlocalversion = candidate

    def call_setlocalversion_all(self) -> dict[str, PathCollectible]:
        if not self.setlocalversion:
            return {}

        all_projects = set()
        if self.kernel_dir:
            all_projects.add(self.kernel_rel)
        all_projects |= set(self.get_ext_modules())
        all_projects |= set(self.projects)

        scmversion_map = {}
        for project in all_projects:
            popen = call_setlocalversion(self.setlocalversion,
                                         os.path.realpath(project))
            scmversion_map[project] = PathPopen(project, popen)

        return scmversion_map

    def get_ext_modules(self) -> list[str]:
        if not self.setlocalversion:
            return []
        try:
            cmd = """
                    source build/build_utils.sh
                    source build/_setup_env.sh
                    echo $EXT_MODULES
                  """
            return subprocess.check_output(cmd,
                                           shell=True,
                                           text=True,
                                           stderr=subprocess.PIPE,
                                           executable="/bin/bash").split()
        except subprocess.CalledProcessError as e:
            logging.warning(
                "Unable to determine EXT_MODULES; scmversion "
                "for external modules may be incorrect. "
                "code=%d, stderr=%s", e.returncode, e.stderr.strip())
        return []

    def async_get_source_date_epoch_all(self) \
            -> dict[str, PathCollectible]:

        all_projects = set()
        if self.kernel_dir:
            all_projects.add(self.kernel_rel)
        all_projects |= set(self.projects)

        return {
            proj: self.async_get_source_date_epoch(proj)
            for proj in all_projects
        }

    def async_get_source_date_epoch(self, rel_path) -> PathCollectible:
        env_val = os.environ.get("SOURCE_DATE_EPOCH")
        if env_val:
            return PresetResult(rel_path, env_val)
        if shutil.which("git"):
            args = [
                "git", "-C",
                os.path.realpath(rel_path), "log", "-1", "--pretty=%ct"
            ]
            popen = subprocess.Popen(args, text=True, stdout=subprocess.PIPE)
            return PathPopen(rel_path, popen)
        return PresetResult(rel_path, "0")

    def collect_map(
        self,
        legacy_map: dict[str, PathCollectible],
    ) -> dict[str, str]:
        return {
            path: path_popen.collect()
            for path, path_popen in legacy_map.items()
        }

    def print_result(
        self,
        scmversion_result_map,
        source_date_epoch_result_map,
    ) -> None:
        stable_source_date_epochs = " ".join(
            "{}:{}".format(path, result)
            for path, result in sorted(source_date_epoch_result_map.items()))
        print("STABLE_SOURCE_DATE_EPOCHS", stable_source_date_epochs)

        # If the list is empty, this prints "STABLE_SCMVERSIONS", and is
        # filtered by Bazel.
        stable_scmversions = " ".join(
            "{}:{}".format(path, result)
            for path, result in sorted(scmversion_result_map.items()))
        print("STABLE_SCMVERSIONS", stable_scmversions)


if __name__ == '__main__':
    logging.basicConfig(stream=sys.stderr,
                        level=logging.WARNING,
                        format="%(levelname)s: %(message)s")
    sys.exit(Stamp().main())
