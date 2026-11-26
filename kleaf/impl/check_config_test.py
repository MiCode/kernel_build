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

"""Tests for check_config."""

from absl.testing import absltest
import pathlib
import tempfile
import unittest
from typing import Iterable

from check_config import CheckConfig, Mismatch
from parse_config import parse_config, ConfigValue, ConfigFormat


class CheckConfigTest(unittest.TestCase):
    def setUp(self):
        # pylint: disable=invalid-name
        self.maxDiff = None
        self.tempdir = tempfile.TemporaryDirectory()
        self.tempdir_path = pathlib.Path(self.tempdir.name)
        self.dot_config = self.tempdir_path / ".config"
        self.defconfig = self.tempdir_path / "defconfig"
        self.defconfig2 = self.tempdir_path / "defconfig2"

    def tearDown(self):
        self.tempdir.cleanup()

    def test_parse_dot_config(self):
        self.dot_config.write_text("""\
CONFIG_A=y
CONFIG_B="hello world"
CONFIG_C=m
# CONFIG_D is not set
CONFIG_E=""
# Blank lines are okay

""")
        self.assertEqual(
            # pylint: disable=protected-access
            parse_config(self.dot_config, ConfigFormat.DOT_CONFIG),
            {
                "CONFIG_A": ConfigValue("y", self.dot_config),
                "CONFIG_B": ConfigValue("hello world", self.dot_config),
                "CONFIG_C": ConfigValue("m", self.dot_config),
                "CONFIG_D": ConfigValue("", self.dot_config),
                "CONFIG_E": ConfigValue("", self.dot_config),
            },
        )

    def test_parse_defconfig(self):
        self.defconfig.write_text("""\
CONFIG_A=y
CONFIG_B=hello world
CONFIG_C=m
# CONFIG_D is not set
CONFIG_E=y # nocheck: this is a test
CONFIG_F=n
CONFIG_G="quoted string"
CONFIG_H=""
CONFIG_I=
CONFIG_J= # nocheck: empty string with comment
CONFIG_K="n"
# Blank lines are okay

""")
        self.assertEqual(
            # pylint: disable=protected-access
            parse_config(self.defconfig, ConfigFormat.DEFCONFIG),
            {
                "CONFIG_A": ConfigValue("y", self.defconfig),
                "CONFIG_B": ConfigValue("hello world", self.defconfig),
                "CONFIG_C": ConfigValue("m", self.defconfig),
                "CONFIG_D": ConfigValue("", self.defconfig),
                "CONFIG_E": ConfigValue("y", self.defconfig, "this is a test"),
                "CONFIG_F": ConfigValue("", self.defconfig),
                "CONFIG_G": ConfigValue("quoted string", self.defconfig),
                "CONFIG_H": ConfigValue("", self.defconfig),
                "CONFIG_I": ConfigValue("", self.defconfig),
                "CONFIG_J": ConfigValue("", self.defconfig,
                                        "empty string with comment"),
                "CONFIG_K": ConfigValue("n", self.defconfig)
            }
        )

    def test_nocheck_reasons(self):
        self.defconfig.write_text("""\
CONFIG_A=y # nocheck
CONFIG_B=y # nocheck:
CONFIG_C=y # nocheck: with reason
""")
        self.assertEqual(
            # pylint: disable=protected-access
            parse_config(self.defconfig, ConfigFormat.DEFCONFIG),
            {
                "CONFIG_A": ConfigValue("y", self.defconfig, ""),
                "CONFIG_B": ConfigValue("y", self.defconfig, ""),
                "CONFIG_C": ConfigValue("y", self.defconfig, "with reason"),
            }
        )

    def test_bad_line(self):
        self.defconfig.write_text("""\
bad line
""")
        with self.assertRaises(ValueError):
            # pylint: disable=protected-access
            parse_config(self.defconfig, ConfigFormat.DEFCONFIG)

    def test_merge(self):
        self.dot_config.write_text("")
        self.defconfig.write_text("""\
CONFIG_A=y
CONFIG_B=y
""")
        self.defconfig2.write_text("""\
# CONFIG_A is not set # nocheck: not enforced
CONFIG_C=y
""")
        dut = CheckConfig(
            dot_config=self.dot_config,
            post_defconfig_fragments=[self.defconfig, self.defconfig2],
        )
        # pylint: disable=protected-access
        self.assertEqual(
            dut._expected,
            [
                ("CONFIG_A", ConfigValue("y", self.defconfig)),
                ("CONFIG_B", ConfigValue("y", self.defconfig)),
                ("CONFIG_A", ConfigValue("", self.defconfig2, "not enforced")),
                ("CONFIG_C", ConfigValue("y", self.defconfig2)),
            ]
        )

    def test_check_simple(self):
        content = """\
CONFIG_A=y
# CONFIG_B is not set
"""
        self._test_check_single(
            dot_config_content=content,
            defconfig_content=content,
            expected_errors=[],
            expected_warnings=[])

    def test_check_fail(self):
        self._test_check_single(
            dot_config_content="CONFIG_A=y\n",
            defconfig_content="# CONFIG_A is not set\n",
            expected_errors=[
                Mismatch("CONFIG_A",
                         ConfigValue("", self.defconfig),
                         ConfigValue("y", self.dot_config))
            ],
            expected_warnings=[])

    def test_check_n(self):
        """See b/364938352."""
        self._test_check_single(
            dot_config_content="# CONFIG_A is not set\n",
            defconfig_content="CONFIG_A=n\n",
            expected_errors=[],
            expected_warnings=[])

    def test_check_n_missing(self):
        self._test_check_single(
            dot_config_content="",
            defconfig_content="CONFIG_A=n\n",
            expected_errors=[],
            expected_warnings=[])

    def test_check_not_set_missing(self):
        self._test_check_single(
            dot_config_content="",
            defconfig_content="# CONFIG_A is not set\n",
            expected_errors=[],
            expected_warnings=[])

    def test_check_warn(self):
        self._test_check_single(
            dot_config_content="# CONFIG_A is not set\n",
            defconfig_content="CONFIG_A=y # nocheck\n",
            expected_errors=[],
            expected_warnings=[
                Mismatch("CONFIG_A",
                         ConfigValue("y", self.defconfig, ""),
                         ConfigValue("", self.dot_config))
            ])

    def test_check_warn_opposite(self):
        self._test_check_single(
            dot_config_content="CONFIG_A=y\n",
            defconfig_content="# CONFIG_A is not set # nocheck\n",
            expected_errors=[],
            expected_warnings=[
                Mismatch("CONFIG_A",
                         ConfigValue("", self.defconfig, ""),
                         ConfigValue("y", self.dot_config))
            ])

    def test_pre_overrides_defconfig(self):
        self._test_check_common(
            dot_config_content="CONFIG_A=y\n",
            defconfig_content="# CONFIG_A is not set\n",
            pre_defconfig_contents=["CONFIG_A=y\n"],
            expected_errors=[],
            expected_warnings=[])

    def test_pre_later_overrides_earlier(self):
        self._test_check_common(
            dot_config_content="CONFIG_A=y\n",
            pre_defconfig_contents=[
                "# CONFIG_A is not set\n",
                "CONFIG_A=y\n"],
            expected_errors=[],
            expected_warnings=[])

    def test_post_overrides_pre(self):
        self._test_check_common(
            dot_config_content="CONFIG_A=y\n",
            pre_defconfig_contents=["# CONFIG_A is not set\n"],
            post_defconfig_contents=["CONFIG_A=y\n"],
            expected_errors=[],
            expected_warnings=[])

    def test_post_overrides_defconfig(self):
        self._test_check_common(
            dot_config_content="CONFIG_A=y\n",
            defconfig_content="# CONFIG_A is not set\n",
            post_defconfig_contents=["CONFIG_A=y\n"],
            expected_errors=[],
            expected_warnings=[])

    def test_merge_conflicting_y(self):
        self._test_check_common(
            dot_config_content="CONFIG_A=y\n",
            post_defconfig_contents=[
                "CONFIG_A=y\n",
                "# CONFIG_A is not set\n"
            ],
            expected_errors=[
                Mismatch("CONFIG_A",
                         ConfigValue("", self.tempdir_path /
                                     "post_defconfig1"),
                         ConfigValue("y", self.dot_config))
            ],
            expected_warnings=[])

    def test_merge_conflicting_n(self):
        self._test_check_common(
            dot_config_content="# CONFIG_A is not set\n",
            post_defconfig_contents=[
                "CONFIG_A=y\n",
                "# CONFIG_A is not set\n"
            ],
            expected_errors=[
                Mismatch("CONFIG_A",
                         ConfigValue("y", self.tempdir_path /
                                     "post_defconfig0"),
                         ConfigValue("", self.dot_config))
            ],
            expected_warnings=[])

    def test_merge_conflicting_warn_y(self):
        self._test_check_common(
            dot_config_content="CONFIG_A=y\n",
            post_defconfig_contents=[
                "CONFIG_A=y\n",
                "# CONFIG_A is not set # nocheck\n"
            ],
            expected_errors=[],
            expected_warnings=[
                Mismatch("CONFIG_A",
                         ConfigValue("", self.tempdir_path /
                                     "post_defconfig1", ""),
                         ConfigValue("y", self.dot_config))
            ])

    def test_merge_conflicting_warn_n(self):
        self._test_check_common(
            dot_config_content="# CONFIG_A is not set\n",
            post_defconfig_contents=[
                "CONFIG_A=y # nocheck\n",
                "# CONFIG_A is not set\n"
            ],
            expected_errors=[],
            expected_warnings=[
                Mismatch("CONFIG_A",
                         ConfigValue("y", self.tempdir_path /
                                     "post_defconfig0", ""),
                         ConfigValue("", self.dot_config))
            ])

    def _test_check_single(
            self,
            dot_config_content: str,
            defconfig_content: str,
            expected_errors: list[Mismatch],
            expected_warnings: list[Mismatch]):
        for kwarg_key in ("defconfig", "pre_defconfig_fragments",
                          "post_defconfig_fragments",):
            with self.subTest(kwarg_key=kwarg_key):
                self.dot_config.write_text(dot_config_content)
                self.defconfig.write_text(defconfig_content)

                if kwarg_key == "defconfig":
                    kwarg_value = self.defconfig
                else:
                    kwarg_value = [self.defconfig]

                check_config = CheckConfig(
                    dot_config=self.dot_config,
                    **{kwarg_key: kwarg_value})
                # pylint: disable=protected-access
                check_config._check()
                self.assertEqual(check_config._errors, expected_errors)
                self.assertEqual(check_config._warnings, expected_warnings)

    def _test_check_common(
            self,
            dot_config_content: str,
            expected_errors: list[Mismatch],
            expected_warnings: list[Mismatch],
            defconfig_content: str | None = None,
            pre_defconfig_contents: Iterable[str] = (),
            post_defconfig_contents: Iterable[str] = ()):
        self.dot_config.write_text(dot_config_content)

        if defconfig_content:
            self.defconfig.write_text(defconfig_content)

        pre_defconfig_fragment_paths = []
        for index, content in enumerate(pre_defconfig_contents):
            defconfig_path = self.tempdir_path / f"pre_defconfig{index}"
            defconfig_path.write_text(content)
            pre_defconfig_fragment_paths.append(defconfig_path)

        post_defconfig_fragment_paths = []
        for index, content in enumerate(post_defconfig_contents):
            defconfig_path = self.tempdir_path / f"post_defconfig{index}"
            defconfig_path.write_text(content)
            post_defconfig_fragment_paths.append(defconfig_path)

        check_config = CheckConfig(
            dot_config=self.dot_config,
            defconfig=self.defconfig if defconfig_content else None,
            pre_defconfig_fragments=pre_defconfig_fragment_paths,
            post_defconfig_fragments=post_defconfig_fragment_paths)
        # pylint: disable=protected-access
        check_config._check()
        self.assertEqual(check_config._errors, expected_errors)
        self.assertEqual(check_config._warnings, expected_warnings)


if __name__ == "__main__":
    absltest.main()
