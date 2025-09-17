#!/bin/bash -e
# Copyright (C) 2022 The Android Open Source Project
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

# Script used as --workspace_status_command for common variables.
# Must execute at the root of workspace.
# https://docs.bazel.build/versions/main/command-line-reference.html#flag--workspace_status_command

if [[ ! -f "WORKSPACE" ]]; then
  echo "ERROR: workspace_status.sh must be executed at the root of Bazel workspace." >&2
  exit 1
fi

if [[ -n "$KLEAF_MAKE_JOBS" ]]; then
  echo "MAKE_JOBS $KLEAF_MAKE_JOBS"
fi
