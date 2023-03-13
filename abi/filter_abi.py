#!/usr/bin/env python3
#
# Copyright (C) 2021-2023 The Android Open Source Project
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
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--symbol-list', '--kmi-symbol-list', required=True)
    parser.add_argument('--in-file', default=None)
    parser.add_argument('--out-file', default=None)
    args = parser.parse_args()

    in_file = args.in_file or "/dev/stdin"
    out_file = args.out_file or "/dev/stdout"
    with open(in_file) as input:
        with open(out_file, "w") as output:
            text = input.read()
            output.write("<!-- filter_abi is no longer functional, use stg instead -->\n")
            output.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
