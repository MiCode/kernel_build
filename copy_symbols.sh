#!/bin/bash -eu

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

# This is an internal helper script used by build.sh and build_abi.sh

# arguments are:
#   abi_sl - the dist directory ABI symbol list
#   kernel_dir
#   main_symbol_list_file_name
#   (additional_symbol_list_file_name)*

abi_sl="$1"; shift
kernel_dir="$1"; shift
symbol_list="$1"; shift

# Copy the abi symbol list file from the sources into the dist dir.
verb=Generating
test -e "$abi_sl" && verb=Refreshing
echo "========================================================"
echo " $verb abi symbol list definition in $abi_sl"
cp -- "$kernel_dir/$symbol_list" "$abi_sl"

# If there are additional symbol lists specified, append them.
for symbol_list; do
  echo >> "$abi_sl"
  cat -- "$kernel_dir/$symbol_list" >> "$abi_sl"
done

exit 0
