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

"""Tests for init_ddk.py"""

import logging
import pathlib
import tempfile
from typing import Any

from absl.testing import absltest
from absl.testing import parameterized
from init_ddk import (KleafProjectSetter, _FILE_MARKER_BEGIN, _FILE_MARKER_END)

# pylint: disable=protected-access


def join(*args: Any) -> str:
    return "\n".join([*args])


_HELLO_WORLD = "Hello World!"


class KleafProjectSetterTest(parameterized.TestCase):

    @parameterized.named_parameters([
        ("Empty", "", join(_FILE_MARKER_BEGIN, _HELLO_WORLD, _FILE_MARKER_END)),
        (
            "BeforeNoMarkers",
            "Existing test\n",
            join(
                "Existing test",
                _FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                _FILE_MARKER_END,
            ),
        ),
        (
            "AfterMarkers",
            join(_FILE_MARKER_BEGIN, _FILE_MARKER_END, "Existing test after."),
            join(
                _FILE_MARKER_BEGIN,
                _HELLO_WORLD,
                _FILE_MARKER_END,
                "Existing test after.",
            ),
        ),
    ])
    def test_update_file_existing(self, current_content, wanted_content):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            with open(tmp_file, "w+", encoding="utf-8") as tf:
                tf.write(current_content)
            KleafProjectSetter._update_file(tmp_file, "\n" + _HELLO_WORLD)
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(wanted_content, got.read())

    def test_update_file_no_existing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_file = pathlib.Path(tmp) / "some_file"
            KleafProjectSetter._update_file(tmp_file, "\n" + _HELLO_WORLD)
            with open(tmp_file, "r", encoding="utf-8") as got:
                self.assertEqual(
                    join(_FILE_MARKER_BEGIN, _HELLO_WORLD, _FILE_MARKER_END),
                    got.read(),
                )


# This could be run as: tools/bazel test //build/kernel:init_ddk_test --test_output=all
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG, format="%(levelname)s: %(message)s"
    )
    absltest.main()
