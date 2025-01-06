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
"""Utility to handle XMLs with modinfo reports."""

import pathlib
import xml.dom.minidom


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


def create_report(
    module_hashes: list[str],
    arch: str,
    branch: str,
    output: pathlib.Path,
) -> None:
    """Creates an XML report containing module hashes.

    This generates an XML report file containing a list of module
    hashes associated with a specific architecture and branch.

    Args:
        module_hashes: A list of module hashes to include in the report.
        arch: The architecture the report is for (e.g., "x86_64").
        branch: The branch the report is for (e.g., "android16-6.12").
        output: A pathlib.Path object representing the location where the report
          should be saved.

    Returns:
        None. The function writes the report to the specified file.
    """
    # Create the XML document.
    root_document, branch_element = _create_xml(arch, branch)

    # Populate the XML document with information from modules.
    for module_hash in module_hashes:
        module_element = root_document.createElement("module")
        module_element.setAttribute("value", module_hash)
        branch_element.appendChild(module_element)

    # Write down the information in the requested lcoation.
    _write_report(output, root_document)
