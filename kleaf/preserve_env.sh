#!/bin/bash

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
# Script to preserve the environment for later reuse.
#
# It assumes that the only non-reusable fragment is the value of $PWD itself.
# Hence, drop the actual value of $PWD and keep the references to it dynamic.
#

sed=/bin/sed

( export -p; export -f ) | \
  # Remove the reference to PWD itself
  $sed '/^declare -x PWD=/d' | \
  # Now ensure, new new PWD gets expanded
  $sed "s|${PWD}|\$PWD|g"
