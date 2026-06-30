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

from absl.testing import absltest
import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ddk_config_exec", type=pathlib.Path, required=True)
    parser.add_argument("--defconfig", type=pathlib.Path, required=True)
    return parser.parse_known_args()


arguments = argparse.Namespace()


class DdkMenuconfigTest(unittest.TestCase):
    def setUp(self):
        # Replace the symlink with an actual file.
        with tempfile.NamedTemporaryFile() as temp:
            shutil.copyfile(arguments.defconfig, temp.name)
            # pylint: disable=line-too-long
            self.backup_symlink = (arguments.defconfig.parent /
                                   (arguments.defconfig.name + ".tmp"))
            arguments.defconfig.rename(self.backup_symlink)
            shutil.copyfile(temp.name, arguments.defconfig)

    def tearDown(self):
        # Restore the symlink to avoid breaking future tests.
        arguments.defconfig.unlink(missing_ok=True)
        self.backup_symlink.rename(arguments.defconfig)

    @staticmethod
    def _non_empty_lines(s: str):
        return [line for line in s.splitlines() if line.strip()]

    def test_config_is_updated(self):
        subprocess.check_call([arguments.ddk_config_exec, "olddefconfig"])

        actual = arguments.defconfig.read_text()
        expected = self.backup_symlink.read_text()

        # The actual file is intentionally not in the correct order so we
        # can check here that it is actually updated.
        self.assertNotEqual(actual, expected,
                            "The defconfig file is not updated")

        self.assertCountEqual(
            self._non_empty_lines(actual),
            self._non_empty_lines(expected),
            "The defconfig file should not change content with olddefconfig"
        )

    def test_stdout(self):
        actual = subprocess.check_output(
            [arguments.ddk_config_exec, "--stdout", "olddefconfig"], text=True)
        expected = self.backup_symlink.read_text()

        # The actual file is intentionally not in the correct order so we
        # can check here that it is actually updated.
        self.assertNotEqual(actual, expected,
                            "The defconfig file is not updated")
        self.assertCountEqual(
            self._non_empty_lines(actual),
            self._non_empty_lines(expected),
            "The defconfig file should not change content with olddefconfig"
        )


if __name__ == "__main__":
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
