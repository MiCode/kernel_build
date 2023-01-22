#!/usr/bin/env python3
#
# Copyright (C) 2019 The Android Open Source Project
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
#

import subprocess


def extract_exported_symbols(binary):
  """Extracts the ksymtab exported symbols from an ELF binary."""
  symbols = []
  out = subprocess.check_output(["llvm-nm", "--defined-only", binary],
                                stderr=subprocess.DEVNULL).decode("ascii")
  for line in out.splitlines():
    pos = line.find(" __ksymtab_")
    if pos != -1:
      symbols.append(line[pos + len(" __ksymtab_"):])

  return symbols
