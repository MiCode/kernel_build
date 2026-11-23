#SPDX-License-Identifier: GPL-2.0-only
#Copyright (c) 2025 Qualcomm Innovation Center, Inc. All rights reserved.

#!/bin/bash

# build_abl.sh build abl.elf in Vendor Build environment
# Script assumes running after lunch w/Android build environment variables available

set -e

SECTOOLS_V1_TARGET_LIST=("gen3auto" "blair" "sdmsteppeauto" "bengal")

function sec_abl_image_generate () {
    unset SECTOOLS_SECURITY_PROFILE
    SECTOOLS_SECURITY_PROFILE=$(_get_abs_build_var_cached SECTOOLS_SECURITY_PROFILE)
    if [ -z "${SECTOOLS_SECURITY_PROFILE}" ]; then
        echo " FAILED: could not find the security profile"
        return 1
    fi

    QCPATH=$(_get_abs_build_var_cached QCPATH)
    SECIMAGE_BASE=${QCPATH}/sectools
    SECTOOLSV2_BIN=${QCPATH}/sectools/Linux/sectools
    if [ ! -d "${SECIMAGE_BASE}" ] || [ ! -e "${SECTOOLSV2_BIN}" ]; then
        echo " FAILED: could not find the sectools"
        return 1
    fi

    KERNEL_PREBUILT_DIR=${ROOT_DIR}/device/qcom/${TARGET_BOARD_PLATFORM}-kernel
    TARGET_EMMC_BOOTLOADER=${KERNEL_PREBUILT_DIR}/kernel-abl/abl-${TARGET_BUILD_VARIANT}/unsigned_abl.elf
    if [ ! -e "${TARGET_EMMC_BOOTLOADER}" ]; then
        echo " FAILED: could not find the unsign abl"
        return 1
    fi

    SIGN_ABL=${ANDROID_PRODUCT_OUT}/abl.elf
    if [ ! -d "${ANDROID_PRODUCT_OUT}" ]; then
        echo " FAILED: could not find the product out dir"
        return 1
    fi

    USE_SECTOOLSV1=0
    for TARGET in ${SECTOOLS_V1_TARGET_LIST[@]}
    do
        if [ "$TARGET_BOARD_PLATFORM" == "$TARGET" ]; then
            USE_SECTOOLSV1=1
            break
        fi
    done

    [ -e "${SIGN_ABL}" ] && rm -rf ${SIGN_ABL}
    [ -d "${ANDROID_PRODUCT_OUT}/signed" ] && rm -rf ${ANDROID_PRODUCT_OUT}/signed
    # Add the target check for signing sectool v1
    if [ ${USE_SECTOOLSV1} == "1" ]; then
        echo "Generating signed appsbl using secimagev1 tool"
        USES_SEC_POLICY_MULTIPLE_DEFAULT_SIGN=1
        USES_SEC_POLICY_INTEGRITY_CHECK=1
        SECABL_PRE_ARGS=("SECIMAGE_LOCAL_DIR=${SECIMAGE_BASE}")
        SECABL_PRE_ARGS+=("USES_SEC_POLICY_MULTIPLE_DEFAULT_SIGN=${USES_SEC_POLICY_MULTIPLE_DEFAULT_SIGN}")
        SECABL_PRE_ARGS+=("USES_SEC_POLICY_INTEGRITY_CHECK=${USES_SEC_POLICY_INTEGRITY_CHECK}")
        SECABL_ARGS=("-i" "${TARGET_EMMC_BOOTLOADER}")
        SECABL_ARGS+=("-t" "${ANDROID_PRODUCT_OUT}/signed")
        SECABL_ARGS+=("-g" "abl")
        SECABL_ARGS+=("--config" "${SECTOOLS_SECURITY_PROFILE}")
        SECABL_ARGS+=("--install_base_dir" "${ANDROID_PRODUCT_OUT}")

        SECABL_CMD=("${SECABL_PRE_ARGS[@]}" "python" "${SECIMAGE_BASE}/sectools_builder.py" "${SECABL_ARGS[@]}")
    else
        echo "Generating signed appsbl using secimagev2 tool"
        SECABL_ARGS=("secure-image" "${TARGET_EMMC_BOOTLOADER}")
        SECABL_ARGS+=("--outfile" "${ANDROID_PRODUCT_OUT}/abl.elf")
        SECABL_ARGS+=("--image-id" "ABL")
        SECABL_ARGS+=("--security-profile" "${SECTOOLS_SECURITY_PROFILE}")
        SECABL_ARGS+=("--sign" "--signing-mode" "TEST")

        SECABL_CMD=("${SECTOOLSV2_BIN}" "${SECABL_ARGS[@]}")
    fi

    echo Running: "${SECABL_CMD[@]}"
    "${SECABL_CMD[@]}" > ${ANDROID_PRODUCT_OUT}/secimage.log 2>&1
    echo "Completed signed appsbl (ABL) (logs in ${ANDROID_PRODUCT_OUT}/secimage.log)"
}

if [ -z "${TARGET_BOARD_PLATFORM}" ] || [ -z "${TARGET_BUILD_VARIANT}" ]; then
    echo "TARGET_BOARD_PLATFORM or TARGET_BUILD_VARIANT is not set. . Have you run lunch yet?" 1>&2
    exit 1
fi

export ROOT_DIR=$(readlink -f $PWD)
source "${ROOT_DIR}/kernel_platform/build/kernel/android/_setup_env.sh"

command "source build/envsetup.sh"

# Prepare abl related files
croot
RECOMPILE_KERNEL=0 RECOMPILE_ABL=1 RECOMPILE_MODULE=0 RECOMPILE_DTBO=0 ${ROOT_DIR}/kernel_platform/build/android/prepare_vendor.sh < /dev/null

# Building abl
sec_abl_image_generate
