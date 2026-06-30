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
import subprocess
import sys
import unittest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--error_message", required=True)
    parser.add_argument("args", nargs="+")
    return parser.parse_known_args()


arguments = argparse.Namespace()


class FailBinaryTest(unittest.TestCase):

    def test_binary_fails(self):
        proc = subprocess.Popen(arguments.args,
                                text=True, stderr=subprocess.PIPE)
        _, stderr = proc.communicate()
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn(arguments.error_message, stderr)


if __name__ == "__main__":
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
