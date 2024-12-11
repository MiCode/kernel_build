#!/bin/bash -e
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

# Use host readlink. b/348003050
MYPATH=$(readlink -f "$0")
MYDIR=${MYPATH%/*}
KLEAF_REPO_DIR=${MYDIR%build/kernel/kleaf}
KLEAF_REPO_DIR=${KLEAF_REPO_DIR%/}

exec "$KLEAF_REPO_DIR"/prebuilts/build-tools/linux_musl-x86/bin/py3-cmd "$MYDIR"/bazel.py "$@"
