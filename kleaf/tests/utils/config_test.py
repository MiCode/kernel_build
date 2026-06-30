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
import json
import pathlib
import unittest
import sys

from parse_config import parse_config, ConfigFormat, ConfigValue


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--actual", type=pathlib.Path, required=True)
    parser.add_argument("--expects", type=json.loads, required=True)
    return parser.parse_known_args()


arguments = argparse.Namespace()


class ConfigTest(unittest.TestCase):
    def test_config_matches(self):
        parsed = parse_config(arguments.actual, ConfigFormat.DOT_CONFIG)
        for expected_key, expected_value in arguments.expects.items():
            with self.subTest(config=expected_key):
                actual_value = parsed.get(
                    expected_key,
                    ConfigValue("", pathlib.Path(arguments.actual)))
                self.assertEqual(expected_value, actual_value.value)


if __name__ == "__main__":
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
