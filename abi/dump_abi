#!/usr/bin/env python3
#
# Copyright (C) 2019-2022 The Android Open Source Project
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
import os
import sys

from abitool import dump_kernel_abi

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--linux-tree",
                        help="Path to kernel tree containing "
                             "vmlinux and modules",
                        required=True)
    parser.add_argument("--vmlinux",
                        help="Path to the vmlinux binary to consider to "
                             "emit the ABI of the union of vmlinux and its "
                             "modules", default=None)
    parser.add_argument("--abi-tool", default=None,
                        help="deprecated and ignored")
    parser.add_argument("--out-file", default=None,
                        help="where to write the abi dump to")
    parser.add_argument("--kmi-symbol-list", "--kmi-whitelist", default=None,
                        help="KMI symbol list to filter for")

    args = parser.parse_args()

    if args.abi_tool:
        print("warning: --abi-tool is deprecated and ignored", file=sys.stderr)

    dump_kernel_abi(args.linux_tree,
                    args.out_file or os.path.join(args.linux_tree, "abi.xml"),
                    args.kmi_symbol_list,
                    args.vmlinux)

if __name__ == "__main__":
    sys.exit(main())
