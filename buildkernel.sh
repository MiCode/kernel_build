#!/bin/bash -xE

# Copyright (c) 2019-2020 The Linux Foundation. All rights reserved.
# Not a Contribution.
#
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
#   build/build.sh <make options>*
#
# The kernel is built in ${COMMON_OUT_DIR}/${KERNEL_DIR}.

set -e

export ROOT_DIR=$(readlink -f $(dirname $0)/../..)

# Save environment parameters before being overwritten by sourcing
# BUILD_CONFIG.
CC_ARG="${CC}"

export BUILD_CONFIG=${KERNEL_DIR}/build.config.${TARGET_PRODUCT}
source "${ROOT_DIR}/kernel/build/_setup_env.sh"

export MAKE_ARGS=$*
export MAKEFLAGS="${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/../staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export KERNEL_UAPI_HEADERS_DIR=$(readlink -m ${OUT_DIR})

cd ${ROOT_DIR}

export CLANG_TRIPLE CROSS_COMPILE CROSS_COMPILE_ARM32 ARCH SUBARCH

# Restore the previously saved CC argument that might have been overridden by
# the BUILD_CONFIG.
[ -n "${CC_ARG}" ] && CC="${CC_ARG}"

# CC=gcc is effectively a fallback to the default gcc including any target
# triplets. An absolute path (e.g., CC=/usr/bin/gcc) must be specified to use a
# custom compiler.
[ "${CC}" == "gcc" ] && unset CC && unset CC_ARG

TOOL_ARGS=()

if [ -n "${CC}" ]; then
  TOOL_ARGS+=("CC=${CC}" "HOSTCC=${CC}")
fi

if [ -n "${LD}" ]; then
  TOOL_ARGS+=("LD=${LD}")
fi

if [ -n "${NM}" ]; then
  TOOL_ARGS+=("NM=${NM}")
fi

if [ -n "${OBJCOPY}" ]; then
  TOOL_ARGS+=("OBJCOPY=${OBJCOPY}")
fi

# Allow hooks that refer to $CC_LD_ARG to keep working until they can be
# updated.
CC_LD_ARG="${TOOL_ARGS[@]}"

#defconfig
make_defconfig()
{
	if [ -z "${SKIP_DEFCONFIG}" ] ; then
		echo "======================"
		echo "Building defconfig"
		set -x
		(cd ${KERNEL_DIR} && \
		make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} ${DEFCONFIG})
		set +x
	fi
}

#Install headers
headers_install()
{
	echo "======================"
	echo "Installing kernel headers"
	set -x
	mkdir -p "${KERNEL_UAPI_HEADERS_DIR}/usr"
	(cd ${OUT_DIR} && \
	make "${TOOL_ARGS[@]}" INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUT_DIR} ${MAKE_ARGS} headers_install)
	set +x
}

# Building Kernel
build_kernel()
{
	echo "======================"
	echo "Building kernel"
	set -x
	if [ -f "${ROOT_DIR}/prebuilts/build-tools/linux-x86/bin/toybox" ]; then
		NCORES=$(${ROOT_DIR}/prebuilts/build-tools/linux-x86/bin/toybox nproc)
	else
		NCORES=8
	fi
	(cd ${OUT_DIR} && \
	make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} -j${NCORES})
	set +x
}

# Modules Install
modules_install()
{
	echo "======================"
	echo "Installing kernel modules"
	rm -rf ${MODULES_STAGING_DIR}
	mkdir -p ${MODULES_STAGING_DIR}

	if [ -z "${DO_NOT_STRIP_MODULES}" ]; then
		MODULE_STRIP_FLAG="INSTALL_MOD_STRIP=1"
	fi

	set -x
	(cd ${OUT_DIR} && \
	make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG} INSTALL_MOD_PATH=${MODULES_STAGING_DIR} ${MAKE_ARGS} modules_install)
	set +x
}


archive_kernel_modules()
{
	echo "======================"
	pushd ${DIST_DIR}

	# Zip the vendor-ramdisk kernel modules
	FINAL_RAMDISK_KERNEL_MODULES=""
	for MODULE in ${VENDOR_RAMDISK_KERNEL_MODULES}; do
		if [ -f "${MODULE}" ]; then
			FINAL_RAMDISK_KERNEL_MODULES="${FINAL_RAMDISK_KERNEL_MODULES} ${MODULE}"
		fi
	done

	echo "Archiving vendor ramdisk kernel modules: "
	echo ${FINAL_RAMDISK_KERNEL_MODULES}

	if [ ! -z "${FINAL_RAMDISK_KERNEL_MODULES}" ]; then
		zip -r ${ROOT_DIR}/${VENDOR_RAMDISK_KERNEL_MODULES_ARCHIVE} ${FINAL_RAMDISK_KERNEL_MODULES}
	fi

	# Filter-out the modules in vendor-ramdisk and zip the vendor kernel modules
	VENDOR_KERNEL_MODULES=""
	__ALL_MODULES=`ls *.ko`
	for MODULE in ${__ALL_MODULES}; do
		if [[ ! " ${FINAL_RAMDISK_KERNEL_MODULES} " == *" ${MODULE} "* ]]; then
			VENDOR_KERNEL_MODULES="${VENDOR_KERNEL_MODULES} ${MODULE}"
		fi
	done

	echo "Archiving vendor kernel modules: "
	echo ${VENDOR_KERNEL_MODULES}

	# Also package the modules.blocklist file
	set -x
	BLOCKLIST_FILE=""
	if [ -f "modules.blocklist" ]; then
		BLOCKLIST_FILE="modules.blocklist"
	fi

	zip -r ${ROOT_DIR}/${VENDOR_KERNEL_MODULES_ARCHIVE} ${VENDOR_KERNEL_MODULES} ${BLOCKLIST_FILE}
	set +x

	popd
}


copy_all_to_prebuilt()
{
  mkdir -p ${DIST_DIR}
  echo "========================================================"
  echo " Copying files"
  for FILE in $(cd ${OUT_DIR} && ls -1 ${FILES}); do
    if [ -f ${OUT_DIR}/${FILE} ]; then
      echo "  $FILE"
      cp -p ${OUT_DIR}/${FILE} ${DIST_DIR}/
    else
      echo "  $FILE is not a file, skipping"
    fi
  done

  MODULES=$(find ${MODULES_STAGING_DIR} -type f -name "*.ko")
  if [ -n "${MODULES}" ]; then
    if [ -n "${IN_KERNEL_MODULES}" -o -n "${EXT_MODULES}" ]; then
      echo "========================================================"
      echo " Copying modules files"
      for FILE in ${MODULES}; do
        echo "  ${FILE#${MODULES_STAGING_DIR}/}"
        cp -p ${FILE} ${DIST_DIR}
      done
      archive_kernel_modules
    fi
  fi

  echo "========================================================"
  echo " Files copied to ${DIST_DIR}"
}


mkdir -p ${OUT_DIR}
#use kernel source for building
if [ "${HEADERS_INSTALL}" -ne "0" ]; then
	make_defconfig
	headers_install
else
	make_defconfig
	build_kernel
	modules_install
	copy_all_to_prebuilt
	headers_install
fi

exit 0
