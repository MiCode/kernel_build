# Copyright (C) 2025 The Android Open Source Project
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
import pathlib
import subprocess
import sys
import unittest

from absl.testing import absltest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("modules", nargs="*", type=pathlib.Path, default=[])
    return parser.parse_known_args()


arguments = None


class PkvmModuleTestCase(unittest.TestCase):
    """Tests that the list of modules are pkvm modules"""

    def test_is_pkvm_module(self):
        """Test that all ko files are pKVM modules."""
        for module in arguments.modules:
            with self.subTest(module=module):
                self._assert_is_pkvm_module(module)

    def _assert_is_pkvm_module(self, module):
        if module.suffix != ".ko":
            self.skipTest(f"{module.name} is not a kernel module")
        try:
            hyp_text = subprocess.check_output(
                ["llvm-objcopy", module,
                 "--dump-section", ".hyp.text=/dev/stdout"],
                stderr=subprocess.PIPE)
        except subprocess.CalledProcessError as e:
            self.fail(
                f"llvm-objcopy exits with code {e.returncode}:\n{e.stderr}")

        self.assertTrue(hyp_text, "hyp_text section is empty")


if __name__ == "__main__":
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
