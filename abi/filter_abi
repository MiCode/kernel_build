#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
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

import argparse
import subprocess
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--symbol-list', '--kmi-symbol-list', required=True,
                        help='KMI symbol list to filter for')
    parser.add_argument('--in-file', default=None,
                        help='where to read the ABI dump from')
    parser.add_argument('--out-file', default=None,
                        help='where to write the ABI dump to')
    args = parser.parse_args()
    command = [
        "abitidy",
        # remove unlisted symbols
        "--symbols", args.symbol_list,
        # prune XML elements now unreachable from symbols
        "--prune-unreachable",
        # inhibit warnings about symbols without types
        "--no-report-untyped",
        # drop XML elements now empty
        "--drop-empty",
    ]
    if args.in_file is not None:
        command.extend(["--input", args.in_file])
    if args.out_file is not None:
        command.extend(["--output", args.out_file])
    subprocess.check_call(command)

if __name__ == "__main__":
    sys.exit(main())
