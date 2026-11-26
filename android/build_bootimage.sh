#SPDX-License-Identifier: GPL-2.0-only
#Copyright (c) 2025 Qualcomm Innovation Center, Inc. All rights reserved.

#!/bin/bash

# build_bootimage.sh build boot.img in Vendor Build environment
# Script assumes running after lunch w/Android build environment variables available

set -e

if [ -z "${TARGET_BOARD_PLATFORM}" ] || [ -z "${TARGET_BUILD_VARIANT}" ]; then
    echo "TARGET_BOARD_PLATFORM or TARGET_BUILD_VARIANT is not set. . Have you run lunch yet?" 1>&2
    exit 1
fi

ROOT_DIR=$(readlink -f $PWD)
source "${ROOT_DIR}/kernel_platform/build/kernel/android/_setup_env.sh"

command "source ./build/envsetup.sh"
if [ "$TARGET_RELEASE" = "next" ] || [ "$TARGET_RELEASE" = "trunk_food" ]; then
    command "lunch ${TARGET_BOARD_PLATFORM}-${TARGET_RELEASE}-${TARGET_BUILD_VARIANT}"
else
    command "lunch ${TARGET_BOARD_PLATFORM}-${TARGET_BUILD_VARIANT}"
fi

# Prepare boot related files
croot
RECOMPILE_KERNEL=1  RECOMPILE_ABL=0 RECOMPILE_MODULE=0  RECOMPILE_DTBO=0 ${ROOT_DIR}/kernel_platform/build/android/prepare_vendor.sh < /dev/null

# Building boot image
command "make bootimage "
