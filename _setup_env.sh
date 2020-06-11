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

# This is an implementation detail of build.sh and friends. Do not source
# directly as it will spoil your shell and make build.sh unusable. You have
# been warned! If you have a good reason to source the result of this file into
# a shell, please let kernel-team@android.com know and we are happy to help
# with your use case.

[ -n "$_SETUP_ENV_SH_INCLUDED" ] && return || _SETUP_ENV_SH_INCLUDED=1

# TODO: Use a $(gettop) style method.
export ROOT_DIR=$(readlink -f $PWD)

export BUILD_CONFIG=${BUILD_CONFIG:-build.config}

# Helper function to let build.config files add command to PRE_DEFCONFIG_CMDS, EXTRA_CMDS, etc.
# Usage: append_cmd PRE_DEFCONFIG_CMDS 'the_cmd'
function append_cmd() {
  if [ ! -z "${!1}" ]; then
    eval "$1=\"${!1} && \$2\""
  else
    eval "$1=\"\$2\""
  fi
}

set -a
. ${ROOT_DIR}/${BUILD_CONFIG}
set +a

export COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out${OUT_DIR_SUFFIX}/${BRANCH}})
export OUT_DIR=$(readlink -m ${COMMON_OUT_DIR}/${KERNEL_DIR})
export DIST_DIR=$(readlink -m ${DIST_DIR:-${COMMON_OUT_DIR}/dist})

if sh -c 'which repo && repo info' >/dev/null 2>&1; then
  # extract the repo branch name (e.g. common-android-mainline)
  repo_branch=$(repo --color=never info -o | grep -E "Manifest merge branch" |
                                             sed "s|.*refs/heads/\(.*\)|\1|")
  export KBUILD_BUILD_VERSION="1 repo:$repo_branch"
fi

echo "========================================================"
echo "= build config: ${ROOT_DIR}/${BUILD_CONFIG}"
cat ${ROOT_DIR}/${BUILD_CONFIG}

# List of prebuilt directories shell variables to incorporate into PATH
PREBUILTS_PATHS=(
LINUX_GCC_CROSS_COMPILE_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_ARM32_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_COMPAT_PREBUILTS_BIN
CLANG_PREBUILT_BIN
LZ4_PREBUILTS_BIN
DTC_PREBUILTS_BIN
LIBUFDT_PREBUILTS_BIN
BUILDTOOLS_PREBUILT_BIN
)

for PREBUILT_BIN in "${PREBUILTS_PATHS[@]}"; do
    PREBUILT_BIN=\${${PREBUILT_BIN}}
    eval PREBUILT_BIN="${PREBUILT_BIN}"
    if [ -n "${PREBUILT_BIN}" ]; then
        # Mitigate dup paths
        PATH=${PATH//"${ROOT_DIR}\/${PREBUILT_BIN}:"}
        PATH=${ROOT_DIR}/${PREBUILT_BIN}:${PATH}
    fi
done
export PATH

echo
echo "PATH=${PATH}"
echo

# verifies that defconfig matches the DEFCONFIG
function check_defconfig() {
    (cd ${OUT_DIR} && \
     make "${TOOL_ARGS[@]}" O=${OUT_DIR} savedefconfig)
    [ "$ARCH" = "x86_64" -o "$ARCH" = "i386" ] && local ARCH=x86
    echo Verifying that savedefconfig matches ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}
    RES=0
    diff -u ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG} ${OUT_DIR}/defconfig ||
      RES=$?
    if [ ${RES} -ne 0 ]; then
        echo ERROR: savedefconfig does not match ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}
    fi
    return ${RES}
}
