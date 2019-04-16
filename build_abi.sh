#!/bin/bash

# Copyright (C) 2019 The Android Open Source Project
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

# Usage:
#   build/build_abi.sh
#
# The following environment variables are considered during execution:
#
#   ABI_OUT_TAG
#     Customize the output file name for the abi dump. If undefined, the tag is
#     derived from `git describe`.

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

set -e
set -a

source "${ROOT_DIR}/build/envsetup.sh"

# inject CONFIG_DEBUG_INFO=y
export POST_DEFCONFIG_CMDS="${POST_DEFCONFIG_CMDS} : && update_config_for_abi_dump"
function update_config_for_abi_dump() {
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
         -e CONFIG_DEBUG_INFO
    (cd ${OUT_DIR} && \
     make O=${OUT_DIR} $archsubarch CROSS_COMPILE=${CROSS_COMPILE} olddefconfig)
}

# ensure we have a sufficient abigail installation in path before continuing
if ! dpkg --compare-versions \
       $(abidiff --version | awk '{print $2}') ge 1.6.0; then
    echo "ERROR: no suitable libabigail (>= 1.6.0) in \$PATH."
    echo "Did you run abi/bootstrap and followed the instructions?"
    exit 1
fi

# delegate the actual build to build.sh
${ROOT_DIR}/build/build.sh $*

echo "========================================================"
echo " Creating ABI dump"

# create abi dump
COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out/${BRANCH}})
id=${ABI_OUT_TAG:-$(git -C $KERNEL_DIR describe --dirty --always)}
abi_out_file=abi-${id}.out
${ROOT_DIR}/build/abi/dump_abi                \
    --linux-tree $OUT_DIR                     \
    --out-file ${DIST_DIR}/${abi_out_file}

ln -sf ${abi_out_file} ${DIST_DIR}/abi.out

echo "========================================================"
echo " ABI dump has been created at ${DIST_DIR}/${abi_out_file}"

