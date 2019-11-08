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
#
#   ABI_DEFINITION
#     Specify an expected Kernel ABI representation. If defined, this script
#     will, in addition to extracting the ABI representation from the currently
#     built kernel, compare the extracted ABI to the expected one. In case of
#     any significant differences, it will exit with the return code of
#     diff_abi and optionally (-r) print a report.
#     ABI_DEFINITION is supposed to be defined relative to $KERNEL_DIR/
#
#   KMI_WHITELIST
#     Define a Kernel Module Interface white list description. If defined, it
#     will be taken into account when extracting Kernel ABI information from
#     vmlinux and kernel modules.
#     KMI_WHITELIST is supposed to be defined relative to $KERNEL_DIR/
#

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

function show_help {
    echo "USAGE: $0 [-u|--update] [-n|--nodiff]"
    echo
    echo "  -u | --update         Update the abi.xml in the source directory"
    echo "  -n | --nodiff         Do not generate a ABI report with abidiff"
    echo "  -r | --print-report   Print ABI report in case of differences"
}

UPDATE=0
DIFF=1
PRINT_REPORT=0

ARGS=()
for i in "$@"
do
case $i in
    -u|--update)
    UPDATE=1
    shift # past argument=value
    ;;
    -n|--nodiff)
    DIFF=0
    shift # past argument=value
    ;;
    -r|--print-report)
    PRINT_REPORT=1
    shift # past argument=value
    ;;
    -h|--help)
    show_help
    exit 0
    ;;
    *)
    ARGS+=("$1")
    shift
    ;;
esac
done

set -- "${ARGS[@]}"

set -e
set -a

source "${ROOT_DIR}/build/_setup_env.sh"

# inject CONFIG_DEBUG_INFO=y
export POST_DEFCONFIG_CMDS="${POST_DEFCONFIG_CMDS} : && update_config_for_abi_dump"
function update_config_for_abi_dump() {
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
         -e CONFIG_DEBUG_INFO
    (cd ${OUT_DIR} && \
     make O=${OUT_DIR} "${TOOL_ARGS[@]}" $archsubarch CROSS_COMPILE=${CROSS_COMPILE} olddefconfig)
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

# delegate the actual build to build.sh.
# suppress possible values of ABI_DEFINITION when invoking build.sh to avoid
# the generated abi.xml to be copied to <DIST_DIR>/abi.out.
ABI_DEFINITION= ${ROOT_DIR}/build/build.sh $*

# define a common KMI whitelist flag for the abi tools
KMI_WHITELIST_FLAG=
if [ -n "$KMI_WHITELIST" ]; then
    KMI_WHITELIST_FLAG="--kmi-whitelist $KERNEL_DIR/$KMI_WHITELIST"
fi

echo "========================================================"
echo " Creating ABI dump"

# create abi dump
COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out/${BRANCH}})
id=${ABI_OUT_TAG:-$(git -C $KERNEL_DIR describe --dirty --always)}
abi_out_file=abi-${id}.xml
${ROOT_DIR}/build/abi/dump_abi                \
    --linux-tree $OUT_DIR                     \
    --out-file ${DIST_DIR}/${abi_out_file}    \
    $KMI_WHITELIST_FLAG

# sanitize the abi.xml by removing any occurences of the kernel path
sed -i "s#${ROOT_DIR}/${KERNEL_DIR}/##g" ${DIST_DIR}/${abi_out_file}
# now also do that with any left over paths sneaking in
# (e.g. from the prebuilts)
sed -i "s#${ROOT_DIR}/##g" ${DIST_DIR}/${abi_out_file}

ln -sf ${abi_out_file} ${DIST_DIR}/abi.xml

echo "========================================================"
echo " ABI dump has been created at ${DIST_DIR}/${abi_out_file}"

rc=0
if [ -n "$ABI_DEFINITION" ]; then
    if [ $DIFF -eq 1 ]; then
        echo "========================================================"
        echo " Comparing ABI against expected definition ($ABI_DEFINITION)"
        abi_report=${DIST_DIR}/abi.report
        set +e
        ${ROOT_DIR}/build/abi/diff_abi --baseline $KERNEL_DIR/$ABI_DEFINITION \
                                       --new      ${DIST_DIR}/${abi_out_file} \
                                       --report   ${abi_report}               \
                                       $KMI_WHITELIST_FLAG
        rc=$?
        set -e
        echo "========================================================"
        echo " ABI report has been created at ${abi_report}"

        if [ $rc -ne 0 ]; then
            echo " ABI DIFFERENCES HAVE BEEN DETECTED! (RC=$rc)"
        fi

        if [ $PRINT_REPORT -eq 1 ] && [ $rc -ne 0 ] ; then
            echo "========================================================"
            cat ${abi_report}
        fi
    fi
    if [ $UPDATE -eq 1 ] ; then
        echo "========================================================"
        echo " Updating expected ABI definition ($ABI_DEFINITION)"
        cp -v ${DIST_DIR}/${abi_out_file} $KERNEL_DIR/$ABI_DEFINITION
    fi
fi

exit $rc

