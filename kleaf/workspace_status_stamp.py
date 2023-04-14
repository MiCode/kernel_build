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

import logging
import os
import shutil
import subprocess
import sys
from typing import Optional


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

        self.find_setlocalversion()

    def main(self) -> int:
        kernel_dir_scmversion_obj = self.call_setlocalversion_kernel_dir()
        ext_modules = self.get_ext_modules()
        ext_mod_scmversion_objs = self.call_setlocalversion_ext_modules(
            ext_modules)

        source_date_epoch, source_date_epoch_obj = \
            self.async_get_source_date_epoch_kernel_dir()

        self.print_result(
            kernel_dir_scmversion_obj=kernel_dir_scmversion_obj,
            ext_modules=ext_modules,
            ext_mod_scmversion_objs=ext_mod_scmversion_objs,
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

    def call_setlocalversion_kernel_dir(self):
        if not self.setlocalversion or not self.kernel_dir:
            return None

        return call_setlocalversion(self.setlocalversion, self.kernel_dir)

    def get_ext_modules(self):
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

    def call_setlocalversion_ext_modules(self, ext_modules):
        if not self.setlocalversion:
            return []

        ret = []
        for ext_mod in ext_modules:
            popen = call_setlocalversion(self.setlocalversion,
                                         os.path.realpath(ext_mod))
            ret.append(popen)
        return ret

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

    def print_result(
        self,
        kernel_dir_scmversion_obj,
        ext_modules,
        ext_mod_scmversion_objs,
        source_date_epoch,
        source_date_epoch_obj,
    ) -> None:
        if kernel_dir_scmversion_obj:
            print("STABLE_SCMVERSION", collect(kernel_dir_scmversion_obj))

        if source_date_epoch_obj:
            source_date_epoch = collect(source_date_epoch_obj)
        print("STABLE_SOURCE_DATE_EPOCH", source_date_epoch)

        # If the list is empty, this prints "STABLE_SCMVERSION_EXT_MOD", and is
        # filtered by Bazel.
        print(
            "STABLE_SCMVERSION_EXT_MOD",
            " ".join("{}:{}".format(ext_mod, result) for ext_mod, result in
                     zip(ext_modules,
                         [collect(obj) for obj in ext_mod_scmversion_objs])))


if __name__ == '__main__':
    logging.basicConfig(stream=sys.stderr,
                        level=logging.WARNING,
                        format="%(levelname)s: %(message)s")
    sys.exit(Stamp().main())
