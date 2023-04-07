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

        source_date_epoch, source_date_epoch_obj = \
            self.async_get_source_date_epoch_kernel_dir()

        scmversion_result_map = self.collect_map(scmversion_map)

        self.print_result(
            scmversion_result_map=scmversion_result_map,
            source_date_epoch=source_date_epoch,
            source_date_epoch_obj=source_date_epoch_obj,
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

    def async_get_source_date_epoch_kernel_dir(self):
        stable_source_date_epoch = os.environ.get("SOURCE_DATE_EPOCH")
        stable_source_date_epoch_obj = None
        if not stable_source_date_epoch and self.kernel_dir and \
                shutil.which("git"):
            stable_source_date_epoch_obj = subprocess.Popen(
                ["git", "-C", self.kernel_dir, "log", "-1", "--pretty=%ct"],
                text=True,
                stdout=subprocess.PIPE)
        else:
            stable_source_date_epoch = 0
        return stable_source_date_epoch, stable_source_date_epoch_obj

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
        source_date_epoch,
        source_date_epoch_obj,
    ) -> None:
        if source_date_epoch_obj:
            source_date_epoch = collect(source_date_epoch_obj)
        print("STABLE_SOURCE_DATE_EPOCH", source_date_epoch)

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
