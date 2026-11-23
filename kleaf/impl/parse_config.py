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

"""Parses a .config or defconfig."""

import dataclasses
import enum
import pathlib
import re


@dataclasses.dataclass(frozen=True)
class ConfigValue:
    value: str
    source: pathlib.Path
    nocheck_reason: str | None = None


ParsedConfig = dict[str, ConfigValue]


class ConfigFormat(enum.Enum):
    DOT_CONFIG = 1
    DEFCONFIG = 2


def parse_config(path: pathlib.Path, config_format: ConfigFormat) \
        -> ParsedConfig:
    """Parses a .config and defconfig.

    Args:
        path: file to parse
        config_type: whether this is a .config or a defconfig
    """

    match config_format:
        case ConfigFormat.DOT_CONFIG:
            # For .config, no # nocheck comments are parsed.
            config_set_value = re.compile(
                r"^(?P<key>CONFIG_\w*)=(?P<maybe_quoted_value>.*)")
            config_unset = re.compile(r"^# (?P<key>CONFIG_\w*) is not set$")
        case ConfigFormat.DEFCONFIG:
            nocheck = r"(\s*# nocheck:?\s*(?P<reason>.*))?"
            config_set_value = re.compile(
                r"^(?P<key>CONFIG_\w*)=(?P<maybe_quoted_value>.*?)" +
                nocheck + "$")
            config_unset = re.compile(
                r"^# (?P<key>CONFIG_\w*) is not set" + nocheck + "$")
    ret = ParsedConfig()

    with path.open() as f:
        for line in f:
            line = line.rstrip()  # strip new line character

            # If line matches CONFIG_X=..., set the value for this fragment
            mo = config_set_value.match(line)
            if mo:
                match config_format:
                    case ConfigFormat.DOT_CONFIG:
                        ret[mo.group("key")] = ConfigValue(
                            _unquote(mo.group("maybe_quoted_value")),
                            path)
                    case ConfigFormat.DEFCONFIG:
                        reason = mo.group("reason")
                        if reason is not None:
                            reason = reason.strip()
                        val = mo.group("maybe_quoted_value")
                        # As a special case, CONFIG_X=n in defconfig means
                        # unsetting it.
                        if val == "n":
                            val = ""
                        ret[mo.group("key")] = ConfigValue(
                            _unquote(val), path, reason)
                continue  # to next line

            # If the line matches # CONFIG_X is not set, set the value to
            # empty. Technically we could also just leave it alone since
            # the default is empty, but let's handle this case for
            # completeness.
            mo = config_unset.match(line)
            if mo:
                reason = mo.groupdict().get("reason")
                if reason is not None:
                    reason = reason.strip()
                ret[mo.group(1)] = ConfigValue("", path, reason)
                continue  # to next line

            if line.lstrip().startswith("#"):
                # ignore comment lines
                continue  # to next line

            if not line.strip():
                # ignore empty lines
                continue  # to next line

            raise ValueError(f"Unexpected line in {path}: {line}")

    return ret


def _unquote(s: str) -> str:
    """Unquote a string in .config.

    Note: This is a naive algorithm and it doesn't necessarily match
    how kconfig handles things.
    """
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    return s
