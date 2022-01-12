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

ROOT_DIR=$($(dirname $(dirname $(readlink -f $0)))/gettop.sh)

BAZEL_PATH="${ROOT_DIR}/prebuilts/bazel/linux-x86_64/bazel"
BAZEL_JDK_PATH="${ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86"
BAZELRC_NAME="build/kleaf/common.bazelrc"

ABSOLUTE_OUT_DIR="${ROOT_DIR}/out"

export SOURCE_DATE_EPOCH=$(${ROOT_DIR}/build/kleaf/source_date_epoch.sh)
if [ -z "${SOURCE_DATE_EPOCH}" ]; then
  echo "Unable to determine SOURCE_DATE_EPOCH, fallback to 0" >&2
  export SOURCE_DATE_EPOCH=0
fi

exec "${BAZEL_PATH}" \
  --server_javabase="${BAZEL_JDK_PATH}" \
  --output_user_root="${ABSOLUTE_OUT_DIR}/bazel/output_user_root" \
  --host_jvm_args=-Djava.io.tmpdir="${ABSOLUTE_OUT_DIR}/bazel/javatmp" \
  --bazelrc="${ROOT_DIR}/${BAZELRC_NAME}" \
  "$@"

