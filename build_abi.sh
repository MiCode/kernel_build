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
export ENVSETUP_SH_INCLUDED=1

# inject CONFIG_DEBUG_INFO=y
export POST_DEFCONFIG_CMDS="${POST_DEFCONFIG_CMDS} : && update_config_for_abi_dump"
function update_config_for_abi_dump() {
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
         -e CONFIG_DEBUG_INFO
    (cd ${OUT_DIR} && \
     make O=${OUT_DIR} ${CC_LD_ARG} $archsubarch CROSS_COMPILE=${CROSS_COMPILE} olddefconfig)
}
export -f check_defconfig
export -f update_config_for_abi_dump

function version_greater_than() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

# ensure that abigail is present in path
if ! ( hash abidiff 2>/dev/null); then
    echo "ERROR: libabigail is not found in \$PATH at all!"
    echo "Have you run build/abi/bootstrap and followed the instructions?"
    exit 1
fi

# ensure we have a "new enough" version of abigail present before continuing
if ! ( version_greater_than "$(abidiff --version | awk '{print $2}')"  \
			    "1.6.0" ); then
    echo "ERROR: no suitable libabigail (>= 1.6.0) in \$PATH."
    echo "Have you run build/abi/bootstrap and followed the instructions?"
    exit 1
fi

# delegate the actual build to build.sh
ABI_DEFINITION= ${ROOT_DIR}/build/build.sh $*

echo "========================================================"
echo " Creating ABI dump"

# create abi dump
COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out/${BRANCH}})
id=${ABI_OUT_TAG:-$(git -C $KERNEL_DIR describe --dirty --always)}
abi_out_file=abi-${id}.xml
${ROOT_DIR}/build/abi/dump_abi                \
    --linux-tree $OUT_DIR                     \
    --out-file ${DIST_DIR}/${abi_out_file}

# sanitize the abi.xml by removing any occurences of the kernel path
sed -i "s#${ROOT_DIR}/${KERNEL_DIR}/##g" ${DIST_DIR}/${abi_out_file}
# now also do that with any left over paths sneaking in
# (e.g. from the prebuilts)
sed -i "s#${ROOT_DIR}/##g" ${DIST_DIR}/${abi_out_file}

ln -sf ${abi_out_file} ${DIST_DIR}/abi.xml

echo "========================================================"
echo " ABI dump has been created at ${DIST_DIR}/${abi_out_file}"

if [ -n "$ABI_DEFINITION" ]; then
    echo "========================================================"
    echo " Comparing ABI against expected definition ($ABI_DEFINITION)"
    abi_report=${DIST_DIR}/abi.report
    set +e
    ${ROOT_DIR}/build/abi/diff_abi --baseline $KERNEL_DIR/$ABI_DEFINITION \
                                   --new      ${DIST_DIR}/${abi_out_file} \
                                   --report   ${abi_report}
    rc=$?
    set -e
    echo "========================================================"
    echo " ABI report has been created at ${abi_report}"
    if [ $rc -ne 0 ] ; then
        echo " ABI DIFFERENCES HAVE BEEN DETECTED! (RC=$rc)"
        exit $rc
    fi
fi
