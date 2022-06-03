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

import argparse
import os
import re
import shlex
import subprocess
import sys
import unittest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modinfo", default="modinfo")
    parser.add_argument("--modules", nargs="*", default=[])
    return parser.parse_known_args()


arguments = None


class ScmVersionTestCase(unittest.TestCase):
    def test_contains_scmversion(self):
        """Test that all ko files have scmversion."""
        for module in arguments.modules:
            with self.subTest(module=module):
                self._assert_contains_scmversion(module)

    # TODO(b/202077908): Investigate why modinfo doesn't work for these modules
    _modinfo_exempt_list = ["spidev.ko"]
    _scmversion_pattern = re.compile(r"g[0-9a-f]{12,40}")

    def _assert_contains_scmversion(self, module):
        basename = os.path.basename(module)
        if os.path.splitext(basename)[1] != ".ko":
            self.skipTest("{} is not a kernel module".format(basename))
        try:
            scmversion = subprocess.check_output(
                [arguments.modinfo, module, "-F", "scmversion"],
                text=True, stderr=subprocess.PIPE).strip()
        except subprocess.CalledProcessError as e:
            self.fail("modinfo returns {}: {}".format(e.returncode, e.stderr))
        mo = ScmVersionTestCase._scmversion_pattern.match(scmversion)

        if basename not in ScmVersionTestCase._modinfo_exempt_list:
            self.assertTrue(mo, "no matching scmversion, found {}".format(
                scmversion))

    # Version.PatchLevel.SubLevel-AndroidRelease-KmiGeneration[-Tag]-Sha1
    # e.g. 5.4.42-android12-0-00544-ged21d463f856
    # e.g. 5.4.42-mainline-00544-ged21d463f856
    _vermagic_pattern = re.compile(
        r"[0-9]+[.][0-9]+[.][0-9]+(-android[0-9]+-[0-9]+|-mainline)(-[0-9]+)?-g[0-9a-f]{12,40}")

    def _assert_contains_vermagic(self, module):
        basename = os.path.basename(module)
        try:
            vermagic = subprocess.check_output(
                [arguments.modinfo, module, "-F", "vermagic"],
                text=True).strip()
        except subprocess.CalledProcessError:
            vermagic = None

        mo = ScmVersionTestCase._vermagic_pattern.match(vermagic)

        if basename not in ScmVersionTestCase._modinfo_exempt_list:
            self.assertTrue(mo, "no matching vermagic, found {}".format(
                vermagic))


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    unittest.main()
