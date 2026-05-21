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
import dataclasses
import pathlib
import re
import shutil
import subprocess
import sys

import kunit_parser


@dataclasses.dataclass
class AdbDeviceHandle:
    """Handle for ADB connection to a device."""

    adb_path: pathlib.Path
    device: str

    def __post_init__(self):
        # Ensure device is connected
        subprocess.check_call([self.adb_path, 'connect', self.device])

    def check_call(self, *args) -> None:
        subprocess.check_call(
            [self.adb_path, '-s', self.device, 'shell', 'su', '0', *args]
        )

    def call(self, *args) -> int:
        return subprocess.call(
            [self.adb_path, '-s', self.device, 'shell', 'su', '0', *args]
        )

    def check_output(self, *args) -> str:
        return subprocess.check_output(
            [self.adb_path, '-s', self.device, 'shell', 'su', '0', *args],
            text=True,
        )

    def push(self, local: str, remote: str) -> None:
        subprocess.check_call(
            [self.adb_path, '-s', self.device, 'push', local, remote]
        )


class TestRunner:
    _ADB_DEVICE_RE = re.compile(r'(?P<device>\S+)\s+device')

    def __init__(
        self,
        name: str,
        adb_path: pathlib.Path,
        modules: list[pathlib.Path],
        device: str | None,
    ) -> None:
        self._name = name
        self._adb_path = adb_path
        self._modules = modules
        self._device = device
        self._module_name_by_pathstem: dict[str, str] = {}
        self._debugfs_available = True
        self._device_handle: AdbDeviceHandle | None = None

    def __enter__(self):
        # Ensure ADB server is running
        subprocess.check_call([self._adb_path, 'start-server'])

        # Find an ADB device if none is provided
        if self._device is None:
            self._device = self._find_device()

        # Create a device handle
        self._device_handle = AdbDeviceHandle(
            adb_path=self._adb_path,
            device=self._device,
        )
        return self

    def __exit__(self, type, value, traceback):
        del type, value, traceback

        # Clean up modules in reverse order since modules might be inter-dependent
        for module in reversed(self._modules):
            if module_name := self._module_name_by_pathstem.get(module.stem):
                self._device_handle.call('rmmod', module_name)
        self._device_handle.call('rm', '-rf', f'/data/local/tmp/{self._name}')

        # Unmount debugfs is needed if it was not mounted
        if not self._debugfs_available:
            self._device_handle.call('umount', '/sys/kernel/debug')

    def run_test(self) -> kunit_parser.Test:
        # Mount debugfs if it is not mounted
        if self._device_handle.call('mountpoint', '/sys/kernel/debug') != 0:
            self._device_handle.check_call(
                'mount', '-t', 'debugfs', 'debugfs', '/sys/kernel/debug'
            )
            self._debugfs_available = False

        # Create temporary directory for pushing test module
        self._device_handle.check_call(
            'mkdir', '-p', f'/data/local/tmp/{self._name}'
        )

        # Push and install modules to device
        for module in self._modules:
            remote_path = f'/data/local/tmp/{self._name}/{module.name}'
            self._device_handle.push(module, remote_path)
            self._module_name_by_pathstem[module.stem] = (
                self._device_handle.check_output(
                    'modinfo', '-F', 'name', remote_path
                ).splitlines()[0]
            )
            self._device_handle.check_call('insmod', remote_path)

        # Extract and parse test results
        results = self._device_handle.check_output(
            'cat', f'/sys/kernel/debug/kunit/{self._name}/results'
        )
        return kunit_parser.parse_run_tests(results.splitlines())

    def _find_device(self) -> str:
        devices_output = subprocess.check_output(
            [self._adb_path, 'devices'], text=True
        )
        devices = []
        for d in devices_output.splitlines():
            if match := TestRunner._ADB_DEVICE_RE.match(d):
                devices.append(match.group('device'))

        if len(devices) == 0:
            raise ValueError('No ADB devices provided or found')
        if len(devices) > 1:
            raise ValueError(
                'More than 1 ADB devices found, please specify device using'
                ' --device option'
            )
        return devices[0]


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--name')
    parser.add_argument(
        '--adb-path', default=shutil.which('adb'), type=pathlib.Path
    )
    parser.add_argument('--modules', nargs='*', default=[], type=pathlib.Path)
    parser.add_argument('--device', default=None)
    args = parser.parse_args()

    if not args.adb_path.is_file():
        raise ValueError(
            'ADB not found. Please provide correct ADB path using --adb-path'
            ' option'
        )

    # Filter out non-module files
    # TODO(b/381406396): Remove this once we have a mechanism to filter out
    # non-module files in the build system.
    filtered_modules = [m for m in args.modules if m.suffix == '.ko']

    with TestRunner(
        name=args.name,
        adb_path=args.adb_path,
        modules=filtered_modules,
        device=args.device,
    ) as tr:
        test_result = tr.run_test()
    if not test_result.ok_status():
        sys.exit(f'Test {args.name} failed')
