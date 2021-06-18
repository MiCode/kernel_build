#!/bin/bash -e

# This script is located at ${ROOT_DIR}/build/kleaf/bazel.sh.
ROOT_DIR=$(dirname $(dirname $(dirname $(readlink -f $0 ) ) ) )

BAZEL_PATH="${ROOT_DIR}/prebuilts/bazel/linux-x86_64/bazel"
BAZEL_JDK_PATH="${ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86"
BAZELRC_NAME="build/kleaf/common.bazelrc"

ABSOLUTE_OUT_DIR="${ROOT_DIR}/out"

exec "${BAZEL_PATH}" \
  --server_javabase="${BAZEL_JDK_PATH}" \
  --output_user_root="${ABSOLUTE_OUT_DIR}/bazel/output_user_root" \
  --host_jvm_args=-Djava.io.tmpdir="${ABSOLUTE_OUT_DIR}/bazel/javatmp" \
  --bazelrc="${ROOT_DIR}/${BAZELRC_NAME}" \
  "$@"

