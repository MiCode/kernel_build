#!/usr/bin/env python3

# Copyright (C) 2023 The Android Open Source Project
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

"""Kleaf SBOM generator: Generate SBOM for kernel build.

Inputs:
1. --version: The android kernel build version string.
              example: 5.15.110-android14-11-00098-gbdd2312e95c7-ab10365441
2. --dist_dir: Output dir where all the kernel build artifacts are.
              example: out/kernel_aarch64/dist
3. --output_file: File where SBOM should be written.
              example: kernel_sbom.spdx.json

Examples:

    # Generate SBOM after a kernel build with dist.
    build/kernel/kleaf/kernel_sbom.py \
      --version "5.15.110-android14-11-00098-gbdd2312e95c7-ab10365441" \
      --dist_dir "out/kernel_aarch64/dist" \
      --output_file "kernel_sbom.spdx.json"
"""

import argparse
from collections.abc import Iterable
import dataclasses
import datetime
import glob
import hashlib
import json
import os
import pathlib
from typing import Any


_SPDX_VERSION = "SPDX-2.3"
_DATA_LICENSE = "CC0-1.0"
_GOOGLE_ORGANIZATION_NAME = "Google"
_LINUX_ORGANIZATION_NAME = "The Linux Kernel Organization"
_LINUX_UPSTREAM_WEBSITE = "kernel.org"
_NAMESPACE_PREFIX = "https://www.google.com/sbom/spdx/android/kernel/"
_MAIN_PACKAGE_NAME = "kernel"
_SOURCE_CODE_PACKAGE_NAME = "KernelSourceCode"
_LINUX_UPSTREAM_PACKAGE_NAME = "LinuxUpstreamPackage"
_GENERATED_FROM_RELATIONSHIP = "GENERATED_FROM"
_VARIANT_OF_RELATIONSHIP = "VARIANT_OF"
_SPDX_REF = "SPDXRef"


@dataclasses.dataclass(order=True)
class File:
  id: str
  name: str
  path: pathlib.Path
  checksum: str


class KernelSbom:

  def __init__(
      self, android_kernel_version: str, file_list: Iterable[pathlib.Path]
  ):
    self._android_kernel_version = android_kernel_version
    self._upstream_kernel_version = android_kernel_version.split("-")[0]
    self._files = sorted(
        [
            File(
                id=f"{_SPDX_REF}-{file.name}",
                name=file.name,
                path=file,
                checksum=self._checksum(file),
            )
            for file in file_list
        ]
    )
    self._sbom_doc = self._generate_sbom()

  def _checksum(self, file_path: pathlib.Path) -> str:
    with file_path.open("rb") as f:
      return str(hashlib.file_digest(f, "sha1").hexdigest())

  def _generate_package_verification_code(self, files: list[File]) -> str:
    hash = hashlib.sha1()
    for checksum in sorted(f.checksum.encode() for f in files):
      hash.update(checksum)
    return hash.hexdigest()

  def _generate_doc_headers(self) -> dict[str, Any]:
    timestamp = datetime.datetime.now(tz=datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    namespace = os.path.join(_NAMESPACE_PREFIX, self._android_kernel_version)
    headers = {
        "spdxVersion": _SPDX_VERSION,
        "dataLicense": _DATA_LICENSE,
        "SPDXID": f"{_SPDX_REF}-DOCUMENT",
        "name": self._android_kernel_version,
        "documentNamespace": namespace,
        "creationInfo": {
            "creators": [f"Organization: {_GOOGLE_ORGANIZATION_NAME}"],
            "created": timestamp,
        },
        "documentDescribes": [f"SPDXRef-{_MAIN_PACKAGE_NAME}"],
    }
    return headers

  def _generate_package_dict(
      self,
      version: str,
      package_name: str,
      file_list: list[File] | None = None,
      organization: str = _GOOGLE_ORGANIZATION_NAME,
      download_location: str | None = None,
  ) -> dict[str, Any]:
    package_dict: dict[str, Any] = {
        "name": package_name,
        "SPDXID": f"{_SPDX_REF}-{package_name}",
        "downloadLocation": download_location,
        "filesAnalyzed": False,
        "versionInfo": version,
        "supplier": f"Organization: {organization}",
    }
    if file_list:
      package_dict["hasFiles"] = [file.name for file in file_list]
      verification_hash = self._generate_package_verification_code(file_list)
      package_dict["packageVerificationCode"] = {
          "packageVerificationCodeValue": verification_hash
      }
      package_dict["filesAnalyzed"] = True
    return package_dict

  def _generate_file_dict(self, file: File) -> dict[str, Any]:
    return {
        "fileName": file.name,
        "SPDXID": file.id,
        "checksums": [
            {
                "algorithm": "SHA1",
                "checksumValue": file.checksum,
            },
        ],
    }

  def _generate_relationship_dict(
      self, element: str, related_element: str, relationship_type: str
  ) -> dict[str, str]:
    return {
        "spdxElementId": element,
        "relatedSpdxElement": related_element,
        "relationshipType": relationship_type,
    }

  def _generate_sbom(self) -> dict[str, Any]:
    sbom = self._generate_doc_headers()
    sbom["packages"] = [
        self._generate_package_dict(
            self._android_kernel_version, _MAIN_PACKAGE_NAME, self._files
        ),
        self._generate_package_dict(
            self._android_kernel_version, _SOURCE_CODE_PACKAGE_NAME
        ),
        self._generate_package_dict(
            self._upstream_kernel_version,
            _LINUX_UPSTREAM_PACKAGE_NAME,
            None,
            _LINUX_ORGANIZATION_NAME,
            _LINUX_UPSTREAM_WEBSITE,
        ),
    ]
    sbom["files"] = [self._generate_file_dict(f) for f in self._files]

    sbom["relationships"] = [
        self._generate_relationship_dict(
            f"{_SPDX_REF}-{_MAIN_PACKAGE_NAME}",
            f"{_SPDX_REF}-{_SOURCE_CODE_PACKAGE_NAME}",
            _GENERATED_FROM_RELATIONSHIP,
        ),
        self._generate_relationship_dict(
            f"{_SPDX_REF}-{_SOURCE_CODE_PACKAGE_NAME}",
            f"{_SPDX_REF}-{_LINUX_UPSTREAM_PACKAGE_NAME}",
            _VARIANT_OF_RELATIONSHIP,
        ),
    ] + [
        self._generate_relationship_dict(
            f.id,
            f"{_SPDX_REF}-{_SOURCE_CODE_PACKAGE_NAME}",
            _GENERATED_FROM_RELATIONSHIP,
        )
        for f in self._files
    ]

    return sbom

  def write_sbom_file(self, output_path: pathlib.Path):
    # omit all error handling to fatally fail with stacktrace in that case
    with output_path.open("w") as output_file:
      json.dump(self._sbom_doc, output_file, indent=4)


def get_args():
  parser = argparse.ArgumentParser()
  parser.add_argument(
      "--output_file",
      required=True,
      type=pathlib.Path,
      help="The generated SBOM file in SPDX format.",
  )
  parser.add_argument(
      "--dist_dir",
      required=True,
      type=pathlib.Path,
      help="Directory containing generated artifacts.",
  )
  parser.add_argument(
      "--version", required=True, help="The android kernel version."
  )
  return parser.parse_args()


def get_file_list(dist_dir: pathlib.Path) -> Iterable[pathlib.Path]:
  if dist_dir.is_dir():
    return [p for p in pathlib.Path(dist_dir).glob("*") if p.is_file()]
  else:
    raise FileNotFoundError(
        f"Distribution directory '{dist_dir}' is not a directory."
    )


def main():
  args = get_args()
  files = get_file_list(args.dist_dir)
  sbom = KernelSbom(args.version, files)
  sbom.write_sbom_file(args.output_file)


if __name__ == "__main__":
  main()
