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

import dataclasses
import datetime
import re


@dataclasses.dataclass
class LinuxBanner:
    """Represents information extracted from a Linux banner."""

    banner: str
    uts_release: str
    scmversion: str
    commit: str
    build: str
    uts_version: str
    date: str
    epoch: int


def get_linux_banner(kernel: bytes) -> LinuxBanner:
    if m := re.search(
        rb'Linux version (?P<release>[^(\n\0]*) \([^\n\0]*\) (?P<version>#\d+'
        rb' [^\n\0]*)\n\0',
        kernel,
    ):
        banner, release, version = m.group(0, 'release', 'version')
        banner = banner[0:len(banner) - 2].decode()
        release = release.decode()
        version = version.decode()
    else:
        raise ValueError(f'did not find Linux banner')

    if m := re.fullmatch(r'^[^-]*-[^-]*-[^-]*-([^-]*)(.*)$', release):
        scmversion, trailer = m.group(1, 2)
    else:
        raise ValueError(f'bad UTS_RELEASE: {release}')

    commit = None
    if m := re.fullmatch(r'g(.*)', scmversion):
        commit = m[1]

    build = None
    if m := re.fullmatch(r'-ab([^-]*).*', trailer):
        build = m[1]

    if m := re.fullmatch(r'#\d+ (?:(?:SMP|PREEMPT)\ )*(.*)', version):
        date = m[1]
    else:
        raise ValueError(f'bad UTS_VERSION: {version}')

    # we don't want to mess with TZ and LC_TIME, so do this by hand
    match = re.fullmatch(
        r'(?:\w{3}) (\w{3}) {1,2}(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) UTC (\d{4})',
        date,
    )
    if not match:
        raise ValueError(f'bad date: {date}')
    month, day, hour, minute, second, year = match.group(1, 2, 3, 4, 5, 6)
    month_number = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
    }
    dt = datetime.datetime(
        int(year),
        month_number[month],
        int(day),
        int(hour),
        int(minute),
        int(second),
        tzinfo=datetime.timezone.utc,
    )
    # round floating point timestamp to the nearest second
    epoch = int(dt.timestamp() + 0.5)

    return LinuxBanner(
        banner=banner,
        uts_release=release,
        scmversion=scmversion,
        commit=commit,
        build=build,
        uts_version=version,
        date=date,
        epoch=epoch,
    )
