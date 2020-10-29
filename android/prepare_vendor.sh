#!/bin/bash

# Copyright (c) 2020, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
#     * Neither the name of The Linux Foundation nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT
# ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## prepare_vendor.sh prepares kernel/build's output for direct consumption in AOSP
# - Script assumes running after lunch w/Android build environment variables available
# - Select which kernel target+variant (defconfig) to use
#    - Default target based on TARGET_PRODUCT from lunch
#    - Default variant based on corresponding target's build.config
# - Remove all Android.mk and Android.bp files from source so they don't conflict with Android's
#   Kernel Platform has same clang/gcc prebuilt projects, which both have Android.mk/Android.bp that
#   would conflict
# - Compile in-vendor-tree devicetrees
# - Overlay those devicetrees onto the kernel platform's dtb/dtbos
#
# The root folder for kernel prebuilts in Android build system is following:
# KP_OUT = device/qcom/$(TARGET_PRODUCT)-kernel
# Default boot.img kernel Image: $(KP_OUT)/Image
# All Kernel Platform DLKMs: $(KP_OUT)/*.ko
# Processed Board UAPI Headers: $(KP_OUT)/kernel-headers
# First-stage DLKMs listed in $(KP_OUT)/modules.load
#   - If not present, all modules are for first-stage init
# Second-stage blocklist listed in $(KP_OUT)/modules.blocklist
#   - If not present, no modules should be blocked
# DTBs, DTBOs, dtb.img, and dtbo.img in $(KP_OUT)/merged-dtbs/

set -e

# rel_path <to> <from>
# Generate relative directory path to reach directory <to> from <from>
function rel_path() {
  python -c "import os.path; import sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

ROOT_DIR=$(realpath $(dirname $(readlink -f $0))/../..) # build/android/prepare.sh -> .

################################################################################
# Discover where kernel_platform source and output is

if [ -z "${ANDROID_BUILD_TOP}" ]; then
  echo "ANDROID_BUILD_TOP is not set. Have you run lunch yet?"
  exit 1
fi

if [ -z "${ANDROID_PRODUCT_OUT}" ]; then
  echo "ANDROID_PRODUCT_OUT is not set. Have you run lunch yet?"
  exit 1
fi

ANDROID_KERNEL_OUT=${ANDROID_BUILD_TOP}/device/qcom/${TARGET_PRODUCT}-kernel

ANDROID_TO_KERNEL_PLATFORM=$(rel_path ${ROOT_DIR} ${ANDROID_BUILD_TOP})

echo "  kernel platform root: $ROOT_DIR (${ANDROID_TO_KERNEL_PLATFORM})"

if [ -z "${KERNEL_TARGET}" ]; then
  KERNEL_TARGET=${1:-${TARGET_PRODUCT}}
fi

if [ -z "${KERNEL_VARIANT}" ]; then
  KERNEL_VARIANT=${2}
fi

case "${KERNEL_TARGET}" in
  taro)
    KERNEL_TARGET="waipio"
    ;;
esac

(
  cd ${ROOT_DIR}
  ./build/brunch ${KERNEL_TARGET} ${KERNEL_VARIANT}
)

# ANDROID_KP_OUT_DIR is the output directory from Android Build System perspective
ANDROID_KP_OUT_DIR="${3:-${OUT_DIR}}"
if [ -z "${ANDROID_KP_OUT_DIR}" ]; then
  ANDROID_KP_OUT_DIR=out/$(
    cd ${ROOT_DIR}
    source build/_wrapper_common.sh
    get_branch
  )
fi

# KP_OUT_DIR is the output directory from kernel platform directory
KP_OUT_DIR=$(rel_path ${ANDROID_KP_OUT_DIR} ${ROOT_DIR})

echo "  kernel platform output directory: ${ANDROID_KP_OUT_DIR}"

if [ ! -e "${ANDROID_KP_OUT_DIR}" ]; then
  echo "!! kernel platform output directory doesn't exist. Bad path or output wasn't copied?"
  exit 1
fi

echo """OUT_DIR=${KP_OUT_DIR}
$(cat ${ROOT_DIR}/build.config)
""" > ${ROOT_DIR}/build.config

################################################################################
echo
echo "  setting up Android tree for compiling modules"

# The ROOT_DIR/la symlink exists so that the output folder can be properly controlled
# kbuild for external modules places the output in the same relative path to kernel
# that is, if module is at ${KP_SRC_DIR}/common/../../vendor/qcom/opensource/android-dlkm,
# the output is also at ${KP_OUT_DIR}/common/../../vendor/qcom/opensource/android-dlkm
# Given that there is no strict control for kernel platform source or output location,
# there is no consistent place to expect android-dlkm output to live
rm -f "${ROOT_DIR}/la"
rm -f "${ANDROID_KERNEL_OUT}"
set -x
ln -srT "${ANDROID_BUILD_TOP}" "${ROOT_DIR}/la"
# Android does not know which target or variant of kernel platform was used
# it just expects kernel platform build output to be in ${ANDROID_KERNEL_OUT}
ln -srT "${ANDROID_KP_OUT_DIR}/dist" "${ANDROID_KERNEL_OUT}"
set +x

################################################################################
echo
echo "  cleaning up kernel_platform tree for Android"

set -x
find ${ROOT_DIR} -name Android.mk -o -name Android.bp -delete
set +x

################################################################################
echo
echo "  Preparing UAPI headers for Android"

if [ ! -e ${ANDROID_KP_OUT_DIR}/kernel_uapi_headers/usr/include ]; then
  echo "!! Did not find exported kernel UAPI headers"
  echo "!! was kernel platform compiled with SKIP_CP_KERNEL_HDR?"
  exit 1
fi

set -x
rm -rf ${ANDROID_KP_OUT_DIR}/dist/kernel-headers

${ROOT_DIR}/build/android/export_headers.py \
  ${ANDROID_KP_OUT_DIR}/kernel_uapi_headers/usr/include \
  ${ANDROID_BUILD_TOP}/bionic/libc/kernel/uapi \
  ${ANDROID_KP_OUT_DIR}/dist/kernel-headers
set +x

################################################################################
echo
echo "  Compiling vendor devicetree overlays"

for project in $(cd ${ANDROID_BUILD_TOP} && find -L vendor/ -type d -name "*-devicetree")
do
  if [ ! -e "${project}/Makefile" ]; then
    echo "${project} does not have expected build configuration files, skipping..."
    continue
  fi

  echo "Building ${project}"

  (
    cd ${ROOT_DIR}
    set -x
    EXT_MODULES="la/${project}" \
    ./build/build_module.sh dtbs
    set +x
  )
done

################################################################################
echo
echo "  Merging vendor devicetree overlays"

(
  cd ${ROOT_DIR}
  ./build/android/merge_dtbs.sh ${KP_OUT_DIR}/dist ${KP_OUT_DIR}/la ${KP_OUT_DIR}/dist/merged-dtbs
)
