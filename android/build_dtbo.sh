#SPDX-License-Identifier: GPL-2.0-only
#Copyright (c) 2025 Qualcomm Innovation Center, Inc. All rights reserved.

#!/bin/bash

# build_dtbo.sh build dtbo.img in Vendor Build environment
# Script assumes running after lunch w/Android build environment variables available

set -e

if [ -z "${TARGET_BOARD_PLATFORM}" ] || [ -z "${TARGET_BUILD_VARIANT}" ]; then
    echo "TARGET_BOARD_PLATFORM or TARGET_BUILD_VARIANT is not set. . Have you run lunch yet?" 1>&2
    exit 1
fi

ROOT_DIR=$(readlink -f $PWD)
source "${ROOT_DIR}/kernel_platform/build/kernel/android/_setup_env.sh"

command "source ./build/envsetup.sh"

# Prepare dtbo related files
croot
RECOMPILE_KERNEL=1 RECOMPILE_ABL=0 RECOMPILE_MODULE=0  RECOMPILE_DTBO=1 ${ROOT_DIR}/kernel_platform/build/android/prepare_vendor.sh < /dev/null

# Building dtbo
command "make dtboimage "
