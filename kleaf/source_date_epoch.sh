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

# Determine the proper value of SOURCE_DATE_EPOCH, and print it.
# - If already set, print the preset value
# - Otherwise, try to determine from the youngest committer time that can be found across the repos
# - If that fails, fallback to 0
#
# https://github.com/bazelbuild/bazel/issues/7742: `git` cannot be executed in the sandbox. To
# avoid dependency on `.git` directory, determine SOURCE_DATE_EPOCH before Bazel is started.
#
# For details about SOURCE_DATE_EPOCH, see
# https://reproducible-builds.org/docs/source-date-epoch/

# Use pre-set values from the environement if it is already set.
if [ ! -z "${SOURCE_DATE_EPOCH}" ]; then
  echo ${SOURCE_DATE_EPOCH}
  exit 0
fi

ROOT_DIR=$($(dirname $(dirname $(readlink -f $0)))/gettop.sh)

# Use "git" from the environment.
if [ -d "${ROOT_DIR}/.source_date_epoch_dir" ]; then
  git -C "${ROOT_DIR}/.source_date_epoch_dir" log -1 --pretty=%ct
fi

