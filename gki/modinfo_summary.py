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
"""Script to gather information about ACK modules."""

import argparse
import concurrent.futures
import dataclasses
import hashlib
import pathlib
import subprocess
import xml_handler


@dataclasses.dataclass(frozen=True)
class KernelModule:
    """Class representing minimal description of an ACK module."""

    name: str
    author: str
    license: str

    def hexdigest(self) -> str:
        return hashlib.sha256(
            (self.name + self.author + self.license).encode()
        ).hexdigest()


def _get_module_hexdigest(module: pathlib.Path) -> str:
    modinfo_name = subprocess.check_output(
        ["modinfo", "-F", "name", module], text=True
    ).strip()
    modinfo_author = subprocess.check_output(
        ["modinfo", "-F", "author", module], text=True
    ).strip()
    modinfo_license = subprocess.check_output(
        ["modinfo", "-F", "license", module], text=True
    ).strip()
    return KernelModule(
        name=modinfo_name,
        author=modinfo_author,
        license=modinfo_license,
    ).hexdigest()


def _get_modules(directory: pathlib.Path) -> list[str]:
    module_hashes = set()
    with concurrent.futures.ProcessPoolExecutor() as executor:
        module_hashes = set(
            executor.map(_get_module_hexdigest, directory.glob("**/*.ko"))
        )

    # Keep it deterministic and make it easy for searchs.
    return sorted(module_hashes)


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--directory",
        type=pathlib.Path,
        help="Path to directory with all .ko binaries.",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        help="Path to .xml file to store the result.",
    )
    return parser.parse_args()


def generate_report(
    directory: pathlib.Path,
    output: pathlib.Path,
) -> None:

    module_hashes = _get_modules(directory)
    # Populate the XML document with information from modules.
    xml_handler.create_report(module_hashes, output)


if __name__ == "__main__":
    arguments = load_arguments()
    generate_report(**vars(arguments))
