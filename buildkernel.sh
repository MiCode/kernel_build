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

export ROOT_DIR=$(readlink -f $(dirname $0)/../../..)
export MAKE_ARGS=$@
export COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out/${BRANCH}})
export OUT_DIR=$(readlink -m ${COMMON_OUT_DIR})
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export KERNEL_PREBUILT_DIR=$(readlink -m ${KERNEL_DIR}/../ship_prebuilt)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export DIST_DIR=$(readlink -m ${DIST_DIR:-${COMMON_OUT_DIR}/dist})
export UNSTRIPPED_DIR=${ROOT_DIR}/${KERNEL_MODULES_OUT}/unstripped
export CLANG_TRIPLE CROSS_COMPILE CROSS_COMPILE_ARM32 ARCH SUBARCH

if [ -z ${TZ} ]
then
    TZ=$(cat /etc/timezone)
fi
echo "timezone for kernel: ${TZ}"

#Setting up for build
PREBUILT_KERNEL_IMAGE=$(basename ${TARGET_PREBUILT_INT_KERNEL})
IMAGE_FILE_PATH=arch/${ARCH}/boot
KERNEL_GEN_HEADERS=include
ARCH_GEN_HEADERS=arch/${ARCH}/include
ARCH_GEN_HEADERS_LOC=arch/${ARCH}
KERNEL_SCRIPTS=scripts
FILES="
vmlinux
System.map
"
PRIMARY_KERN_BINS=${KERNEL_PREBUILT_DIR}/primary_kernel
SECONDARY_KERN_BINS=${KERNEL_PREBUILT_DIR}/secondary_kernel
KERN_SHA1_LOC=${KERNEL_PREBUILT_DIR}/kernel_sha1.txt

#defconfig
make_defconfig()
{
	if [ -z "${SKIP_DEFCONFIG}" ] ; then
		echo "======================"
		echo "Building defconfig"
		set -x
		(cd ${KERNEL_DIR} && \
		${MAKE_PATH}make TZ=${TZ} O=${OUT_DIR} ${MAKE_ARGS} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} ${DEFCONFIG})
		set +x
	fi

	if [ ! -z "${KERNEL_CONFIG_OVERRIDE_FACTORY}"  ]; then
		echo "Rebuilding defconfig"
		echo "Overriding kernel config with" ${KERNEL_CONFIG_OVERRIDE_FACTORY};
		echo ${KERNEL_CONFIG_OVERRIDE_FACTORY} >> ${OUT_DIR}/.config;
		set -x
		(cd ${KERNEL_DIR} && \
		make O=${OUT_DIR} ${MAKE_ARGS} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} oldconfig)
		set +x
	fi

        if [ ! -z "${KERNEL_CONFIG_OVERRIDE_REGION}"  ]; then
                echo "Rebuilding defconfig"
                echo "Overriding kernel config with" ${KERNEL_CONFIG_OVERRIDE_REGION};
                echo ${KERNEL_CONFIG_OVERRIDE_REGION} >> ${OUT_DIR}/.config;
                set -x
                (cd ${KERNEL_DIR} && \
                make O=${OUT_DIR} ${MAKE_ARGS} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} oldconfig)
                set +x
        fi

}

#Install headers
headers_install()
{
	echo "======================"
	echo "Installing kernel headers"
	set -x
	(cd ${OUT_DIR} && \
	${MAKE_PATH}make TZ=${TZ} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUT_DIR} ${CC_ARG} ${MAKE_ARGS} headers_install)
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
	${MAKE_PATH}make TZ=${TZ} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" O=${OUT_DIR} ${CC_ARG} ${MAKE_ARGS} -j${NCORES})
	set +x
}

# Modules Install
modules_install()
{
	echo "======================"
	echo "Installing kernel modules"
	rm -rf ${MODULES_STAGING_DIR}
	mkdir -p ${MODULES_STAGING_DIR}
	set -x
	(cd ${OUT_DIR} && \
	${MAKE_PATH}make TZ=${TZ} O=${OUT_DIR} ${CC_ARG} INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=${MODULES_STAGING_DIR} ${MAKE_ARGS} modules_install)
	set +x
}


archive_kernel_modules()
{
	echo "======================"
	pushd ${KERNEL_MODULES_OUT}

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
		zip -rq ${VENDOR_RAMDISK_KERNEL_MODULES_ARCHIVE} ${FINAL_RAMDISK_KERNEL_MODULES}
	fi

	# Filter-out the modules in vendor-ramdisk and zip the vendor kernel modules
	VENDOR_KERNEL_MODULES=`ls *.ko`
	for MODULE in ${FINAL_RAMDISK_KERNEL_MODULES}; do
		VENDOR_KERNEL_MODULES=`echo ${VENDOR_KERNEL_MODULES} | sed "s/${MODULE}//g"`
	done

	echo "Archiving vendor kernel modules: "
	echo ${VENDOR_KERNEL_MODULES}

	# Also package the modules.blocklist file
	set -x
	BLOCKLIST_FILE=""
	if [ -f "modules.blocklist" ]; then
		BLOCKLIST_FILE="modules.blocklist"
	fi

	zip -rq ${VENDOR_KERNEL_MODULES_ARCHIVE} ${VENDOR_KERNEL_MODULES} ${BLOCKLIST_FILE}
	set +x

	popd
}

copy_modules_to_prebuilt()
{
	PREBUILT_OUT=$1

	# Clean the DLKM directory to remove stale modules
	rm -rf ${KERNEL_MODULES_OUT}/*.ko
	rm -rf ${KERNEL_MODULES_OUT}/*.zip

	mkdir -p ${KERNEL_MODULES_OUT}

	MODULES=$(find ${MODULES_STAGING_DIR} -type f -name "*.ko")
	if [ -n "${MODULES}" ]; then
		echo "======================"
		echo " Copying modules files"
		for FILE in ${MODULES}; do
			echo "${FILE#${KERNEL_MODULES_OUT}/}"
			cp -p ${FILE} ${KERNEL_MODULES_OUT}

			# Copy for prebuilt
			if [ ! -e ${PREBUILT_OUT}/${KERNEL_MODULES_OUT} ]; then
				mkdir -p ${PREBUILT_OUT}/${KERNEL_MODULES_OUT}
			fi
			cp -p ${FILE} ${PREBUILT_OUT}/${KERNEL_MODULES_OUT}
		done
	fi

	echo "Copying module signing certificate into prebuilt"
	if [[ ! -e ${PREBUILT_OUT}/certs ]]; then
		mkdir -p ${PREBUILT_OUT}/certs
	fi
	cp -p ${OUT_DIR}/certs/*.*  ${PREBUILT_OUT}/certs/

	# Copy the modules.blocklist file
	set -x
	BLOCKLIST_FILE=${PWD}/device/qcom/kernelscripts/modules_blocklist/modules.blocklist.${TARGET_PRODUCT}
	if [ -f "${BLOCKLIST_FILE}" ]; then
		cp ${BLOCKLIST_FILE} ${KERNEL_MODULES_OUT}/modules.blocklist
		sed -i -e '/blocklist/ s/-/_/g' ${KERNEL_MODULES_OUT}/modules.blocklist
	fi
	set +x
}

copy_all_to_prebuilt()
{
	PREBUILT_OUT=$1
	echo ${PREBUILT_OUT}

	if [[ ! -e ${PREBUILT_OUT} ]]; then
		mkdir -p ${PREBUILT_OUT}
	fi

	copy_modules_to_prebuilt ${PREBUILT_OUT}

	#copy necessary files from the out directory
	echo "============="
	echo "Copying files to prebuilt"
	for FILE in ${FILES}; do
	  if [ -f ${OUT_DIR}/${FILE} ]; then
	    # Copy for prebuilt
	    echo "$FILE ${PREBUILT_OUT}"
	    cp -p ${OUT_DIR}/${FILE} ${PREBUILT_OUT}/
	    echo $FILE copied to ${PREBUILT_OUT}
	  else
	    echo "$FILE does not exist, skipping"
	  fi
	done

	#copy kernel image
	echo "============="
	echo "Copying kernel image to prebuilt"
	if [ ! -e ${PREBUILT_OUT}/${IMAGE_FILE_PATH} ]; then
		mkdir -p ${PREBUILT_OUT}/${IMAGE_FILE_PATH}
	fi
	cp -p ${OUT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE} ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE}

	#copy dtbo images to prebuilt
	echo "============="
	echo "Copying target dtb/dtbo files to prebuilt"
	if [ ! -e ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/dts/vendor/qcom ]; then
		mkdir -p ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/dts/vendor/qcom
	fi
	cp -p -r ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom/*.dtb ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/dts/vendor/qcom/

	if [ -f ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom/*.dtbo ]; then
		cp -p -r ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom/*.dtbo ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/dts/vendor/qcom/
	fi

	#copy arch generated headers
	echo "============="
	echo "Copying arch-specific generated headers to prebuilt"
	cp -p -r ${OUT_DIR}/${ARCH_GEN_HEADERS} ${PREBUILT_OUT}/${ARCH_GEN_HEADERS_LOC}

	#copy kernel generated headers
	echo "============="
	echo "Copying kernel generated headers to prebuilt"
	cp -p -r ${OUT_DIR}/${KERNEL_GEN_HEADERS} ${PREBUILT_OUT}

	#copy userspace facing headers
	echo "============"
	echo "Copying userspace headers to prebuilt"
	mkdir -p ${PREBUILT_OUT}/usr
	cp -p -r ${KERNEL_HEADERS_INSTALL}/include ${PREBUILT_OUT}/usr

	#copy kernel scripts
	echo "============"
	echo "Copying kernel scripts to prebuilt"
	cp -p -r ${OUT_DIR}/${KERNEL_SCRIPTS} ${PREBUILT_OUT}
}

copy_from_prebuilt()
{
	PREBUILT_OUT=$1
	cd ${ROOT_DIR}

	if [ ! -e ${OUT_DIR} ]; then
		mkdir -p ${OUT_DIR}
	fi

	#Copy userspace headers
	echo "============"
	echo "Copying userspace headers from prebuilt"
	mkdir -p ${KERNEL_HEADERS_INSTALL}
	cp -p -r ${PREBUILT_OUT}/usr/include ${ROOT_DIR}/${KERNEL_HEADERS_INSTALL}

	#Copy files, such as System.map, vmlinux, etc
	echo "============"
	echo "Copying kernel files from prebuilt"
	cd ${PREBUILT_OUT}
	for FILE in ${FILES}; do
		if [ -f ${PREBUILT_OUT}/$FILE ]; then
			# Copy for prebuilt
			echo "  $FILE ${PREBUILT_OUT}"
			echo ${PREBUILT_OUT}/${FILE}
			cp -p ${PREBUILT_OUT}/${FILE} ${OUT_DIR}/
			echo $FILE copied to ${PREBUILT_OUT}
		else
			echo "$FILE does not exist, skipping"
		fi
	done

	#copy kernel image
	echo "============"
	echo "Copying kernel image from prebuilt"
	if [ ! -e ${OUT_DIR}/${IMAGE_FILE_PATH} ]; then
		mkdir -p ${OUT_DIR}/${IMAGE_FILE_PATH}
	fi
	cp -p ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE} ${OUT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE}

	#copy dtbo images from prebuilt
	echo "============="
	echo "Copying dtb/dtbo files from prebuilt"
	if [ ! -e ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom ]; then
		mkdir -p ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom
	fi
	cp -p -r ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/dts/vendor/qcom/*.dtb ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom/
	cp -p -r ${PREBUILT_OUT}/${IMAGE_FILE_PATH}/dts/vendor/qcom/*.dtbo ${OUT_DIR}/${IMAGE_FILE_PATH}/dts/vendor/qcom/

	#copy arch generated headers, and kernel generated headers
	echo "============"
	echo "Copying arch-specific generated headers from prebuilt"
	cp -p -r ${PREBUILT_OUT}/${ARCH_GEN_HEADERS} ${OUT_DIR}/${ARCH_GEN_HEADERS_LOC}
	echo "============"
	echo "Copying kernel generated headers from prebuilt"
	cp -p -r ${PREBUILT_OUT}/${KERNEL_GEN_HEADERS} ${OUT_DIR}

	#copy modules
	echo "============"
	echo "Copying kernel modules from prebuilt"
	cd ${ROOT_DIR}
	MODULES=$(find ${PREBUILT_OUT} -type f -name "*.ko")
	if [ ! -e  ${KERNEL_MODULES_OUT} ]; then
		mkdir -p  ${KERNEL_MODULES_OUT}
	fi
	for FILE in ${MODULES}; do
		echo "Copy ${FILE#${KERNEL_MODULES_OUT}/}"
		cp -p ${FILE} ${KERNEL_MODULES_OUT}
	done

	#copy scripts directory
	echo "============"
	echo "Copying kernel scripts from prebuilt"
	cp -p -r ${PREBUILT_OUT}/${KERNEL_SCRIPTS} ${OUT_DIR}

	echo "Copying sign certificates from prebuilt"
	if [[ ! -e ${OUT_DIR}/certs ]]; then
		mkdir -p ${OUT_DIR}/certs
	fi
	cp -p -r ${PREBUILT_OUT}/certs ${OUT_DIR}

}

save_unstripped_modules()
{
	echo "======================"
	echo "Creating a copy of unstripped modules"
	rm -rf ${UNSTRIPPED_DIR}
	mkdir -p ${UNSTRIPPED_DIR}

	set -x

	(cd ${OUT_DIR} && \
	${MAKE_PATH}make TZ=${TZ} O=${OUT_DIR} ${CC_ARG} INSTALL_MOD_PATH=${UNSTRIPPED_DIR} ${MAKE_ARGS} modules_install)

	MODULES=$(find ${UNSTRIPPED_DIR} -type f -name "*.ko")
	for MODULE in ${MODULES}; do
		# Replace all hyphens in module name with underscores
		MODULE_NAME=$(basename ${MODULE})
		CORRECTED_NAME=$(echo "${MODULE_NAME//-/$'_'}")
		cp -p ${MODULE} ${UNSTRIPPED_DIR}
		# Rename all modules with hyphens to names wth underscores
		# As t32 expects module names with underscores to match
		# symbols of the modules actually loaded, rename and save
		# modules in unstripped folder for debugging
		if [ ${MODULE_NAME} != ${CORRECTED_NAME} ]; then
			mv ${UNSTRIPPED_DIR}/${MODULE_NAME} ${UNSTRIPPED_DIR}/${CORRECTED_NAME}
		fi
	done

	# Remove the /lib/modules/$(uname -r) hierarchy
	rm -rf ${UNSTRIPPED_DIR}/lib

	set +x
}

#script starts executing here
if [ -n "${CC}" ]; then
  CC_ARG="CC=${CC}"
fi

#choose between secondary and primary kernel image
if [[ ${DEFCONFIG} == *"perf_defconfig" ]]; then
	KERNEL_BINS=${SECONDARY_KERN_BINS}
else
	KERNEL_BINS=${PRIMARY_KERN_BINS}
fi

#use prebuilts if we want to use them, and they are available
if [ ! -z ${USE_PREBUILT_KERNEL} ] && [ -d ${KERNEL_BINS} ]; then
	make_defconfig
	copy_from_prebuilt ${KERNEL_BINS}
	exit 0
fi

#use kernel source for building
if [ "${HEADERS_INSTALL}" -ne "0" ]; then
	make_defconfig
	headers_install
else
	make_defconfig
	headers_install
	build_kernel
	modules_install
	copy_all_to_prebuilt ${KERNEL_BINS}
	archive_kernel_modules
	save_unstripped_modules
fi

exit 0
