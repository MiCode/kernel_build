#!/bin/bash -xE

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
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export CLANG_TRIPLE CROSS_COMPILE CROSS_COMPILE_ARM32 ARCH SUBARCH

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

#defconfig
make_defconfig()
{
	if [ -z "${SKIP_DEFCONFIG}" ] ; then
		echo "======================"
		echo "Building defconfig"
		set -x
		(cd ${KERNEL_DIR} && \
		make O=${OUT_DIR} ${MAKE_ARGS} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} ${DEFCONFIG})
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
	make HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUT_DIR} ${CC_ARG} ${MAKE_ARGS} headers_install)
	set +x
}

# Building Kernel
build_kernel()
{
	echo "======================"
	echo "Building kernel"
	set -x
	(cd ${OUT_DIR} && \
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" O=${OUT_DIR} ${CC_ARG} ${MAKE_ARGS} -j$(nproc))
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
	make O=${OUT_DIR} ${CC_ARG} INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=${MODULES_STAGING_DIR} ${MAKE_ARGS} modules_install)
	set +x
}

copy_modules_to_prebuilt()
{
	if [[ ! -e ${KERNEL_MODULES_OUT} ]]; then
		mkdir -p ${KERNEL_MODULES_OUT}
	fi

	MODULES=$(find ${MODULES_STAGING_DIR} -type f -name "*.ko")
	if [ -n "${MODULES}" ]; then
		echo "======================"
		echo " Copying modules files"
		for FILE in ${MODULES}; do
			echo "${FILE#${KERNEL_MODULES_OUT}/}"
			cp -p ${FILE} ${KERNEL_MODULES_OUT}

			# Copy for prebuilt
			if [ ! -e ${KERNEL_PREBUILT_DIR}/${KERNEL_MODULES_OUT} ]; then
				mkdir -p ${KERNEL_PREBUILT_DIR}/${KERNEL_MODULES_OUT}
			fi
			cp -p ${FILE} ${KERNEL_PREBUILT_DIR}/${KERNEL_MODULES_OUT}
		done
	fi
}

copy_all_to_prebuilt()
{
	echo ${KERNEL_PREBUILT_DIR}

	if [[ ! -e ${KERNEL_PREBUILT_DIR} ]]; then
		mkdir -p ${KERNEL_PREBUILT_DIR}
	fi

	copy_modules_to_prebuilt

	#copy necessary files from the out directory
	echo "============="
	echo "Copying files to prebuilt"
	for FILE in ${FILES}; do
	  if [ -f ${OUT_DIR}/${FILE} ]; then
	    # Copy for prebuilt
	    echo "$FILE ${KERNEL_PREBUILT_DIR}"
	    cp -p ${OUT_DIR}/${FILE} ${KERNEL_PREBUILT_DIR}/
	    echo $FILE copied to ${KERNEL_PREBUILT_DIR}
	  else
	    echo "$FILE does not exist, skipping"
	  fi
	done

	#copy kernel image
	echo "============="
	echo "Copying kernel image to prebuilt"
	if [ ! -e ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH} ]; then
		mkdir -p ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH}
	fi
	cp -p ${OUT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE} ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE}

	#copy arch generated headers
	echo "============="
	echo "Copying arch-specific generated headers to prebuilt"
	cp -p -r ${OUT_DIR}/${ARCH_GEN_HEADERS} ${KERNEL_PREBUILT_DIR}/${ARCH_GEN_HEADERS}

	#copy kernel generated headers
	echo "============="
	echo "Copying kernel generated headers to prebuilt"
	cp -p -r ${OUT_DIR}/${KERNEL_GEN_HEADERS} ${KERNEL_PREBUILT_DIR}

	#copy userspace facing headers
	echo "============"
	echo "Copying userspace headers to prebuilt"
	mkdir -p ${KERNEL_PREBUILT_DIR}/usr
	cp -p -r ${KERNEL_HEADERS_INSTALL}/include ${KERNEL_PREBUILT_DIR}/usr

	#copy kernel scripts
	echo "============"
	echo "Copying kernel scripts to prebuilt"
	cp -p -r ${OUT_DIR}/${KERNEL_SCRIPTS} ${KERNEL_PREBUILT_DIR}
}

copy_from_prebuilt()
{
	cd ${ROOT_DIR}

	if [ ! -e ${OUT_DIR} ]; then
		mkdir -p ${OUT_DIR}
	fi

	#Copy userspace headers
	echo "============"
	echo "Copying userspace headers from prebuilt"
	mkdir -p ${KERNEL_HEADERS_INSTALL}
	cp -p -r ${KERNEL_PREBUILT_DIR}/usr/include ${ROOT_DIR}/${KERNEL_HEADERS_INSTALL}

	#Copy files, such as System.map, vmlinux, etc
	echo "============"
	echo "Copying kernel files from prebuilt"
	cd ${KERNEL_PREBUILT_DIR}
	for FILE in ${FILES}; do
		if [ -f ${KERNEL_PREBUILT_DIR}/$FILE ]; then
			# Copy for prebuilt
			echo "  $FILE ${KERNEL_PREBUILT_DIR}"
			echo ${KERNEL_PREBUILT_DIR}/${FILE}
			cp -p ${KERNEL_PREBUILT_DIR}/${FILE} ${OUT_DIR}/
			echo $FILE copied to ${KERNEL_PREBUILT_DIR}
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
	cp -p ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE} ${OUT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE}

	#copy arch generated headers, and kernel generated headers
	echo "============"
	echo "Copying arch-specific generated headers from prebuilt"
	cp -p -r ${KERNEL_PREBUILT_DIR}/${ARCH_GEN_HEADERS} ${OUT_DIR}/${ARCH_GEN_HEADERS_LOC}
	echo "============"
	echo "Copying kernel generated headers from prebuilt"
	cp -p -r ${KERNEL_PREBUILT_DIR}/${KERNEL_GEN_HEADERS} ${OUT_DIR}

	#copy modules
	echo "============"
	echo "Copying kernel modules from prebuilt"
	cd ${ROOT_DIR}
	MODULES=$(find ${KERNEL_PREBUILT_DIR} -type f -name "*.ko")
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
	cp -p -r ${KERNEL_PREBUILT_DIR}/${KERNEL_SCRIPTS} ${OUT_DIR}
}

#script starts executing here
if [ -n "${CC}" ]; then
  CC_ARG="CC=${CC}"
fi

#use prebuilts if we want to use them, and they are available
if [ ! -z ${USE_PREBUILT_KERNEL} ] && [ -d ${KERNEL_PREBUILT_DIR} ]; then
	copy_from_prebuilt
	exit 0
fi

#use kernel source for building
if [ ! -z ${HEADERS_INSTALL} ]; then
	make_defconfig
	headers_install
else
	make_defconfig
	headers_install
	build_kernel
	modules_install
	copy_all_to_prebuilt
fi

exit 0
