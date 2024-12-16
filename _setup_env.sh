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

export KERNEL_DIR
# for case that KERNEL_DIR is not specified in environment
if [ -z "${KERNEL_DIR}" ]; then
    # for the case that KERNEL_DIR is not specified in the BUILD_CONFIG file
    # use the directory of the build config file as KERNEL_DIR
    # for the case that KERNEL_DIR is specified in the BUILD_CONFIG file,
    # or via the config files sourced, the value of KERNEL_DIR
    # set here would be overwritten, and the specified value would be used.
    build_config_path=$(realpath ${ROOT_DIR}/${BUILD_CONFIG})
    build_config_dir=$(dirname ${build_config_path})
    build_config_dir=${build_config_dir##${ROOT_DIR}/}
    KERNEL_DIR="${build_config_dir}"
    echo "= Set default KERNEL_DIR: ${KERNEL_DIR}"
else
    echo "= User environment KERNEL_DIR: ${KERNEL_DIR}"
fi

set -a
. ${ROOT_DIR}/${BUILD_CONFIG}
for fragment in ${BUILD_CONFIG_FRAGMENTS}; do
  . ${ROOT_DIR}/${fragment}
done
set +a

echo "= The final value for KERNEL_DIR: ${KERNEL_DIR}"

export COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out${OUT_DIR_SUFFIX}/${BRANCH}})
export OUT_DIR=$(readlink -m ${COMMON_OUT_DIR}/${KERNEL_DIR})
export DIST_DIR=$(readlink -m ${DIST_DIR:-${COMMON_OUT_DIR}/dist})
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export UNSTRIPPED_MODULES_ARCHIVE=unstripped_modules.tar.gz

echo "========================================================"
echo "= build config: ${ROOT_DIR}/${BUILD_CONFIG}"
cat ${ROOT_DIR}/${BUILD_CONFIG}

export TZ=UTC
export LC_ALL=C
export SOURCE_DATE_EPOCH=$(git -C ${ROOT_DIR}/${KERNEL_DIR} log -1 --pretty=%ct)
export KBUILD_BUILD_TIMESTAMP="$(date -d @${SOURCE_DATE_EPOCH})"
export KBUILD_BUILD_HOST=build-host
export KBUILD_BUILD_USER=build-user
export KBUILD_BUILD_VERSION=1

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

if [ "${HERMETIC_TOOLCHAIN:-0}" -eq 1 ]; then
  HOST_TOOLS=${OUT_DIR}/host_tools
  rm -rf ${HOST_TOOLS}
  mkdir -p ${HOST_TOOLS}
  for tool in \
      bash \
      git \
      perl \
      rsync \
      sh \
      tar \
      ${ADDITIONAL_HOST_TOOLS}
  do
      ln -sf $(which $tool) ${HOST_TOOLS}
  done
  PATH=${HOST_TOOLS}

  # use relative paths for file name references in the binaries
  # (e.g. debug info)
  export KCPPFLAGS="-ffile-prefix-map=${ROOT_DIR}/${KERNEL_DIR}/= -ffile-prefix-map=${ROOT_DIR}/="

  # set the common sysroot
  sysroot_flags+="--sysroot=${ROOT_DIR}/build/build-tools/sysroot "

  # add openssl (via boringssl) and other prebuilts into the lookup path
  cflags+="-I${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/include "

  # add openssl and further prebuilt libraries into the lookup path
  ldflags+="-Wl,-rpath,${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/lib64 "
  ldflags+="-L ${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/lib64 "

  # Have host compiler use LLD and compiler-rt.
  ldflags+="-fuse-ld=lld --rtlib=compiler-rt"

  export HOSTCFLAGS="$sysroot_flags $cflags"
  export HOSTLDFLAGS="$sysroot_flags $ldflags"
fi

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
unset PYTHONPATH
unset PYTHONHOME
unset PYTHONSTARTUP

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
    diff -u ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG} ${OUT_DIR}/defconfig >&2 ||
      RES=$?
    if [ ${RES} -ne 0 ]; then
        echo ERROR: savedefconfig does not match ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG} >&2
    fi
    return ${RES}
}
export -f check_defconfig
