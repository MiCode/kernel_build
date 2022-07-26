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

"""
Compare pairs of files. The files specified in --actual must
contain all lines from the corresponding file specified in --expected.

Order of lines does not matter. For example, if actual contains lines
["foo", "bar", "baz"] and expected contains ["bar", "foo"], test passes.

Duplicated lines are counted. For example, if actual contains lines
["foo"] and expected contains ["foo", "foo"], test fails because two "foo"s
are expected.

The actual and expected file are correlated by the file name.
Example:
  contain_lines_test \
    --actual foo.txt bar.txt \
    --expected expected/bar.txt expected/foo.txt
This command checks that foo.txt contains all lines in expected/foo.txt
and bar.txt contains all lines in expected/bar.txt.

If any duplication of filenames are found in --actual and/or --expected, a
cross-product is used.
Example:
  contain_lines_test \
    --actual actual/1/foo.txt actual/2/foo.txt \
    --expected expected/1/foo.txt expected/2/foo.txt
This command checks:
- actual/1/foo.txt against expected/1/foo.txt
- actual/1/foo.txt against expected/2/foo.txt
- actual/2/foo.txt against expected/1/foo.txt
- actual/2/foo.txt against expected/2/foo.txt
"""

import argparse
import collections
import unittest
import sys
import pathlib

from absl.testing import absltest
from typing import List


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--actual", nargs="+", type=pathlib.Path, help="actual files")
    parser.add_argument("--expected", nargs="+", type=pathlib.Path, help="expected files")
    return parser.parse_known_args()


arguments = None


def _read_non_empty_lines(path: pathlib.Path) -> List[str]:
    with path.open() as f:
        return [line.strip() for line in f.readlines() if line.strip()]


class CompareTest(unittest.TestCase):
    def test_all(self):
        # Turn lists into a dictionary from basename to a list of values with that basename.
        actual = collections.defaultdict(list)
        for path in arguments.actual:
            actual[path.name].append(path)

        expected = collections.defaultdict(list)
        for path in arguments.expected:
            expected[path.name].append(path)

        basenames = set() | actual.keys() | expected.keys()

        for basename in basenames:
            actual_with_basename = actual[basename]
            expected_with_basename = expected[basename]

            self.assertTrue(actual_with_basename, f"missing actual file for {basename}")
            self.assertTrue(expected_with_basename, f"missing expected file for {basename}")

            for actual_file in actual_with_basename:
                for expected_file in expected_with_basename:
                    with self.subTest(actual=actual_file, expected=expected_file):
                        self._expect_contain_lines(actual=actual_file, expected=expected_file)

    def _expect_contain_lines(self, actual: pathlib.Path, expected: pathlib.Path):
        actual_lines = collections.Counter(_read_non_empty_lines(actual))
        expected_lines = collections.Counter(_read_non_empty_lines(expected))
        diff = expected_lines - actual_lines
        self.assertFalse(diff,
                         f"{actual} does not contain all lines from {expected}, missing\n" +
                         ("\n".join(diff.elements())))


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
