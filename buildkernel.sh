#!/bin/bash -xE

# Usage:
#   build/build.sh <make options>*
#
# The kernel is built in ${COMMON_OUT_DIR}/${KERNEL_DIR}.
#
# TODO: External module compilation

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
FILES="
vmlinux
System.map
"

cd ${ROOT_DIR}

if [ ! -e ${OUT_DIR} ]; then
	mkdir -p ${OUT_DIR}
fi

if [ -z "${FORCE_KERNEL_BUILD}" ]; then
	if [ -d ${KERNEL_PREBUILT_DIR} ]; then
		echo "Kernel Prebuilt directory exist, copying binaries..."
		# Copy headers
		mkdir -p ${KERNEL_HEADERS_INSTALL}
		cd ${KERNEL_PREBUILT_DIR}/usr;find  -name *.h -exec cp --parents {} ${ROOT_DIR}/${KERNEL_HEADERS_INSTALL} \;
		cd ${ROOT_DIR}

		# Copy Image, vmlinux, System.map
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
		if [ ! -e ${OUT_DIR}/${IMAGE_FILE_PATH} ]; then
			mkdir -p ${OUT_DIR}/${IMAGE_FILE_PATH}
		fi
		cp -p ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE} ${OUT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE}

		cd ${ROOT_DIR}
		# Copy Modules
		MODULES=$(find ${KERNEL_PREBUILT_DIR} -type f -name "*.ko")
		if [ ! -e  ${KERNEL_MODULES_OUT} ]; then
			mkdir -p  ${KERNEL_MODULES_OUT}
		fi
		for FILE in ${MODULES}; do
			echo "Copy ${FILE#${KERNEL_MODULES_OUT}/}"
			cp -p ${FILE} ${KERNEL_MODULES_OUT}
		done

		#return success
		exit 0
	else
		echo "Kernel Prebuilt directory doesn't exist, compiling..."
	fi
fi


if [ -z "${SKIP_DEFCONFIG}" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make O=${OUT_DIR} ${MAKE_ARGS} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} ${DEFCONFIG})
  set +x
fi

if [ -n "${CC}" ]; then
  CC_ARG="CC=${CC}"
fi

#Install headers
set -x
  (cd ${OUT_DIR} && make HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${OUT_DIR} ${CC_ARG} ${MAKE_ARGS} headers_install)
set +x

# Building Kernel
set -x
  (cd ${OUT_DIR} && make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} HOSTCFLAGS="${TARGET_INCLUDES}" HOSTLDFLAGS="${TARGET_LINCLUDES}" O=${OUT_DIR} ${CC_ARG} ${MAKE_ARGS} -j$(nproc))
set +x

# Modules Install
rm -rf ${MODULES_STAGING_DIR}
mkdir -p ${MODULES_STAGING_DIR}
set -x
(cd ${OUT_DIR} && \
   make O=${OUT_DIR} ${CC_ARG} INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=${MODULES_STAGING_DIR} ${MAKE_ARGS} modules_install)
set +x

echo ${KERNEL_PREBUILT_DIR}

if [[ ! -e ${KERNEL_PREBUILT_DIR} ]]; then
	mkdir -p ${KERNEL_PREBUILT_DIR}
fi

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

echo "============="
echo "Copying files"
for FILE in ${FILES}; do
  if [ -f ${OUT_DIR}/${FILE} ]; then
    # Copy for prebuilt
    echo "  $FILE ${KERNEL_PREBUILT_DIR}"
    cp -p ${OUT_DIR}/${FILE} ${KERNEL_PREBUILT_DIR}/
    echo $FILE copied to ${KERNEL_PREBUILT_DIR}
  else
    echo "  $FILE does not exist, skipping"
  fi
done


if [ ! -e ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH} ]; then
	mkdir -p ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH}
fi

cp -p ${OUT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE} ${KERNEL_PREBUILT_DIR}/${IMAGE_FILE_PATH}/${PREBUILT_KERNEL_IMAGE}

CUR_DIR=$(pwd)
echo "============"
echo "Copy headers"
mkdir -p ${KERNEL_PREBUILT_DIR}/usr
cd ${KERNEL_HEADERS_INSTALL};find  -name *.h -exec cp --parents {} ${KERNEL_PREBUILT_DIR}/usr \;
cd $CUR_DIR

exit 0
