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
    echo "  -u | --update         Update ABI representation and main whitelist in the source directory"
    echo "  -n | --nodiff         Do not generate an ABI report with diff_abi"
    echo "  -r | --print-report   Print ABI short report in case of any differences"
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

# if we are using the default OUT_DIR, add a suffix so we are free to wipe it
# before building to ensure a clean build/analysis. That is the default case.
if [[ -z "$OUT_DIR" ]]; then
    export OUT_DIR_SUFFIX="_abi"
    wipe_out_dir=1
fi

source "${ROOT_DIR}/build/_setup_env.sh"

# Now actually do the wipe out as above.
if [[ $wipe_out_dir -eq 1 ]]; then
    rm -rf "${COMMON_OUT_DIR}"
fi

# inject CONFIG_DEBUG_INFO=y
append_cmd POST_DEFCONFIG_CMDS 'update_config_for_abi_dump'
export POST_DEFCONFIG_CMDS
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

# For now we require a specific versions of libabigail identified by a commit
# hash. That is a bit inconvenient, but we do not have another reliable
# identifier at this time.
required_abigail_version="1.8.0-$(cat ${ROOT_DIR}/build/abi/bootstrap| grep 'ABIGAIL_VERSION=' | cut -d= -f2)"
if [[ ! $(abidiff --version) =~ $required_abigail_version ]]; then
    echo "ERROR: required libabigail version is $required_abigail_version"
    echo "Have you run build/abi/bootstrap and followed the instructions?"
    exit 1
fi

function build_kernel() {
  # delegate the actual build to build.sh.
  # suppress possible values of ABI_DEFINITION when invoking build.sh to avoid
  # the generated abi.xml to be copied to <DIST_DIR>/abi.out.
  # similarly, disable the KMI trimming, as the whitelist may be out of date.
  ABI_DEFINITION= TRIM_NONLISTED_KMI= KMI_WHITELIST_STRICT_MODE= \
	  ${ROOT_DIR}/build/build.sh "$@"
}

build_kernel "$@"

# define a common KMI whitelist flag for the abi tools
KMI_WHITELIST_FLAG=

# We want to track whether the main whitelist (i.e. KMI_WHITELIST) actually got
# updated. If so we need to rerun the kernel build.
WHITELIST_GOT_UPDATE=0
if [ -n "$KMI_WHITELIST" ]; then

    if [ $UPDATE -eq 1 ]; then
        echo "========================================================"
        echo " Updating the ABI whitelist"
        WL_SHA1_BEFORE=$(sha1sum $KERNEL_DIR/$KMI_WHITELIST 2>&1)
        ${ROOT_DIR}/build/abi/extract_symbols       \
            --whitelist $KERNEL_DIR/$KMI_WHITELIST  \
            ${DIST_DIR}
        WL_SHA1_AFTER=$(sha1sum $KERNEL_DIR/$KMI_WHITELIST 2>&1)

        if [ "$WL_SHA1_BEFORE" != "$WL_SHA1_AFTER" ]; then
            WHITELIST_GOT_UPDATE=1
        fi
    fi

    KMI_WHITELIST_FLAG="--kmi-whitelist ${DIST_DIR}/abi_whitelist"
fi

# Rerun the kernel build as the main whitelist changed. That influences the
# combined whitelist as well as the list of exported symbols in the kernel
# binary. Possibly more.
if [ $WHITELIST_GOT_UPDATE -eq 1 ]; then
  echo "========================================================"
  echo " Whitelist got updated, rerunning the build"
  SKIP_MRPROPER=1 build_kernel "$@"
fi

echo "========================================================"
echo " Creating ABI dump"

# create abi dump
COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out/${BRANCH}})
id=${ABI_OUT_TAG:-$(git -C $KERNEL_DIR describe --dirty --always)}
abi_out_file=abi-${id}.xml
${ROOT_DIR}/build/abi/dump_abi                \
    --linux-tree ${DIST_DIR}                  \
    --out-file ${DIST_DIR}/${abi_out_file}    \
    $KMI_WHITELIST_FLAG

# sanitize the abi.xml by removing any occurences of the kernel path
effective_kernel_dir=$(readlink -f ${ROOT_DIR}/${KERNEL_DIR})
sed -i "s#${effective_kernel_dir}/##g" ${DIST_DIR}/${abi_out_file}
sed -i "s#${ROOT_DIR}/${KERNEL_DIR}/##g" ${DIST_DIR}/${abi_out_file}
# now also do that with any left over paths sneaking in
# (e.g. from the prebuilts)
sed -i "s#${ROOT_DIR}/##g" ${DIST_DIR}/${abi_out_file}

# Append debug information to abi file
echo "
<!--
     libabigail: $(abidw --version)
     built with: $CC: $($CC --version | head -n1)
-->" >> ${DIST_DIR}/${abi_out_file}

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
                                       --short-report ${abi_report}.short     \
                                       $KMI_WHITELIST_FLAG
        rc=$?
        set -e
        echo "========================================================"
        echo " A brief ABI report has been created at ${abi_report}.short"
        echo
        echo " The detailed report is available in the same directory."

        if [ $rc -ne 0 ]; then
            echo " ABI DIFFERENCES HAVE BEEN DETECTED! (RC=$rc)"
        fi

        if [ $PRINT_REPORT -eq 1 ] && [ $rc -ne 0 ] ; then
            echo "========================================================"
            cat ${abi_report}.short
        fi
    fi
    if [ $UPDATE -eq 1 ] ; then
        echo "========================================================"
        echo " Updating expected ABI definition ($ABI_DEFINITION)"
        cp -v ${DIST_DIR}/${abi_out_file} $KERNEL_DIR/$ABI_DEFINITION
    fi
fi

exit $rc

