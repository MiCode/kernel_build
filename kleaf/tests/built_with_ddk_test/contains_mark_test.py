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

import argparse
import pathlib
import subprocess
import sys
import unittest

from absl.testing import absltest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--kernel_module",
        nargs="+",
        type=pathlib.Path,
        help="Kernel module file",
    )
    parser.add_argument("--depmod", type=pathlib.Path, help="Depmod tool")
    return parser.parse_known_args()


arguments = None


class CheckMarkTest(unittest.TestCase):

    def test_signature_present_once(self):
        modules = [m for m in arguments.kernel_module if m.suffix == ".ko"]
        self.assertTrue(len(modules) > 0, "no .ko files found")
        modinfo = pathlib.Path(absltest.get_default_test_tmpdir()) / "modinfo"
        modinfo.parent.mkdir(parents=True, exist_ok=True)
        # The full path is needed for the symlink to work, otherwise the
        #  tool is not found.
        depmod = pathlib.Path.cwd() / arguments.depmod
        modinfo.symlink_to(depmod)
        for module in modules:
            with self.subTest(module=module):
                out = subprocess.check_output(
                    [modinfo, "-F", "built_with", module], text=True
                )
                tag_count = out.split("\n").count("DDK")
                self.assertEqual(
                    tag_count,
                    1,
                    "built with DDK tag should appear exactly once",
                )


if __name__ == "__main__":
    arguments, unknown_args = load_arguments()
    # Propagate unknown flags to absltest.
    sys.argv[1:] = unknown_args
    absltest.main()
