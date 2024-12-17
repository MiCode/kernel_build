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
import xml.dom.minidom


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


def _add_modules(
    branch_element: xml.dom.minidom.Element,
    directory: pathlib.Path,
    root_document: xml.dom.minidom.Document,
) -> None:

    module_hashes = []
    with concurrent.futures.ProcessPoolExecutor() as executor:
        module_hashes = list(
            executor.map(_get_module_hexdigest, directory.glob("**/*.ko"))
        )

    # Sort before writing.
    for module_hash in sorted(module_hashes):
        module_element = root_document.createElement("module")
        module_element.setAttribute("value", module_hash)
        branch_element.appendChild(module_element)


def _create_xml(
    arch: str,
    branch: str,
) -> tuple[xml.dom.minidom.Document, xml.dom.minidom.Element]:
    root_document = xml.dom.minidom.Document()
    kernel_modules = root_document.createElement("kernel-modules")
    kernel_modules.setAttribute("version", "0")
    root_document.appendChild(kernel_modules)
    branch_element = root_document.createElement("branch")
    branch_element.setAttribute("name", branch)
    branch_element.setAttribute("arch", arch)
    kernel_modules.appendChild(branch_element)
    return root_document, branch_element


def _write_report(
    output: pathlib.Path,
    root_document: xml.dom.minidom.Document,
) -> None:
    kernel_modules_str = root_document.toprettyxml()
    output.write_text(kernel_modules_str)


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", help="String with target architecture.")
    parser.add_argument("--branch", help="String with branch version.")
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
    arch: str,
    branch: str,
    directory: pathlib.Path,
    output: pathlib.Path,
) -> None:

    # Create the XML document.
    root_document, branch_element = _create_xml(arch, branch)

    # Populate the XML document with information from modules.
    _add_modules(branch_element, directory, root_document)

    # Write down the information in the requested lcoation.
    _write_report(output, root_document)


if __name__ == "__main__":
    arguments = load_arguments()
    generate_report(**vars(arguments))
