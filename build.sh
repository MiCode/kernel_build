#!/bin/bash

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
# or:
#   OUT_DIR=<out dir> DIST_DIR=<dist dir> build/build.sh <make options>*
#
# Example:
#   OUT_DIR=output DIST_DIR=dist build/build.sh -j24 V=1
#
#
# The following environment variables are considered during execution:
#
#   BUILD_CONFIG
#     Build config file to initialize the build environment from. The location
#     is to be defined relative to the repo root directory.
#     Defaults to 'build.config'.
#
#   OUT_DIR
#     Base output directory for the kernel build.
#     Defaults to <REPO_ROOT>/out/<BRANCH>.
#
#   DIST_DIR
#     Base output directory for the kernel distribution.
#     Defaults to <OUT_DIR>/dist
#
#   EXT_MODULES
#     Space separated list of external kernel modules to be build.
#
#   UNSTRIPPED_MODULES
#     Space separated list of modules to be copied to <DIST_DIR>/unstripped
#     for debugging purposes.
#
#   CC
#     Override compiler to be used. (e.g. CC=clang) Specifying CC=gcc
#     effectively unsets CC to fall back to the default gcc detected by kbuild
#     (including any target triplet). To use a custom 'gcc' from PATH, use an
#     absolute path, e.g.  CC=/usr/local/bin/gcc
#
#   LD
#     Override linker (flags) to be used.
#
#   ABI_DEFINITION
#     Location of the abi definition file relative to <REPO_ROOT>/KERNEL_DIR
#     If defined (usually in build.config), also copy that abi definition to
#     <OUT_DIR>/dist/abi.xml when creating the distribution.
#
#   KMI_WHITELIST
#     Location of the main KMI whitelist file relative to <REPO_ROOT>/KERNEL_DIR
#     If defined (usually in build.config), also copy that whitelist definition
#     to <OUT_DIR>/dist/abi_whitelist when creating the distribution.
#
#   ADDITIONAL_KMI_WHITELISTS
#     Location of secondary KMI whitelist files relative to
#     <REPO_ROOT>/KERNEL_DIR. If defined, these additional whitelists will be
#     appended to the main one before proceeding to the distribution creation.
#
#   KMI_ENFORCED
#     This is an indicative option to signal that KMI is enforced in this build
#     config. If set, downstream KMI checking tools might respect it and react
#     to it by failing if KMI differences are detected.
#
# Environment variables to influence the stages of the kernel build.
#
#   SKIP_MRPROPER
#     if defined, skip `make mrproper`
#
#   SKIP_DEFCONFIG
#     if defined, skip `make defconfig`
#
#   PRE_DEFCONFIG_CMDS
#     Command evaluated before `make defconfig`
#
#   POST_DEFCONFIG_CMDS
#     Command evaluated after `make defconfig` and before `make`.
#
#   POST_KERNEL_BUILD_CMDS
#     Command evaluated after `make`.
#
#   TAGS_CONFIG
#     if defined, calls ./scripts/tags.sh utility with TAGS_CONFIG as argument
#     and exit once tags have been generated
#
#   IN_KERNEL_MODULES
#     if defined, install kernel modules
#
#   SKIP_EXT_MODULES
#     if defined, skip building and installing of external modules
#
#   DO_NOT_STRIP_MODULES
#     Keep debug information for distributed modules.
#     Note, modules will still be stripped when copied into the ramdisk.
#
#   EXTRA_CMDS
#     Command evaluated after building and installing kernel and modules.
#
#   DIST_CMDS
#     Command evaluated after copying files to DIST_DIR
#
#   SKIP_CP_KERNEL_HDR
#     if defined, skip installing kernel headers.
#
#   BUILD_BOOT_IMG
#     if defined, build a boot.img binary that can be flashed into the 'boot'
#     partition of an Android device. The boot image contains a header as per the
#     format defined by https://source.android.com/devices/bootloader/boot-image-header
#     followed by several components like kernel, ramdisk, DTB etc. The ramdisk
#     component comprises of a GKI ramdisk cpio archive concatenated with a
#     vendor ramdisk cpio archive which is then gzipped. It is expected that
#     all components are present in ${DIST_DIR}.
#
#     When the BUILD_BOOT_IMG flag is defined, the following flags that point to the
#     various components needed to build a boot.img also need to be defined.
#     - MKBOOTIMG_PATH=<path to the mkbootimg.py script which builds boot.img>
#       (defaults to tools/mkbootimg/mkbootimg.py)
#     - GKI_RAMDISK_PREBUILT_BINARY=<Name of the GKI ramdisk prebuilt which includes
#       the generic ramdisk components like init and the non-device-specific rc files>
#     - VENDOR_RAMDISK_BINARY=<Name of the vendor ramdisk binary which includes the
#       device-specific components of ramdisk like the fstab file and the
#       device-specific rc files.>
#     - KERNEL_BINARY=<name of kernel binary, eg. Image.lz4, Image.gz etc>
#     - BOOT_IMAGE_HEADER_VERSION=<version of the boot image header>
#       (defaults to 3)
#     - KERNEL_CMDLINE=<string of kernel parameters for boot>
#     - KERNEL_VENDOR_CMDLINE=<string of kernel parameters for vendor_boot>
#     - VENDOR_FSTAB=<Path to the vendor fstab to be included in the vendor
#       ramdisk>
#     If the BOOT_IMAGE_HEADER_VERSION is less than 3, two additional variables must
#     be defined:
#     - BASE_ADDRESS=<base address to load the kernel at>
#     - PAGE_SIZE=<flash page size>
#     If the BOOT_IMAGE_HEADER_VERSION is 3, a vendor_boot image will be built unless
#     SKIP_VENDOR_BOOT is defined.
#     - MODULES_LIST=<file to list of modules> list of modules to use for
#       modules.load. If this property is not set, then the default modules.load
#       is used.
#
#   BUILD_INITRAMFS
#     if defined, build a ramdisk containing all .ko files and resulting depmod artifacts
#
#   MODULES_OPTIONS
#     A /lib/modules/modules.options file is created on the ramdisk containing
#     the contents of this variable, lines should be of the form: options
#     <modulename> <param1>=<val> <param2>=<val> ...
#
#   LZ4_RAMDISK
#     if defined, any ramdisks generated will be lz4 compressed instead of
#     gzip compressed.
#
#   TRIM_NONLISTED_KMI
#     if defined, enable the CONFIG_UNUSED_KSYMS_WHITELIST kernel config option
#     to un-export from the build any un-used and non-whitelisted (as per
#     KMI_WHITELIST) symbol.
#
#   KMI_WHITELIST_STRICT_MODE
#     if defined, add a build-time check between the KMI_WHITELIST and the
#     KMI resulting from the build, to ensure they match 1-1.
#
#   KMI_STRICT_MODE_OBJECTS
#     optional list of objects to consider for the KMI_WHITELIST_STRICT_MODE
#     check. Defaults to 'vmlinux'.
#
# Note: For historic reasons, internally, OUT_DIR will be copied into
# COMMON_OUT_DIR, and OUT_DIR will be then set to
# ${COMMON_OUT_DIR}/${KERNEL_DIR}. This has been done to accommodate existing
# build.config files that expect ${OUT_DIR} to point to the output directory of
# the kernel build.
#
# The kernel is built in ${COMMON_OUT_DIR}/${KERNEL_DIR}.
# Out-of-tree modules are built in ${COMMON_OUT_DIR}/${EXT_MOD} where
# ${EXT_MOD} is the path to the module source code.

set -e

# rel_path <to> <from>
# Generate relative directory path to reach directory <to> from <from>
function rel_path() {
	local to=$1
	local from=$2
	local path=
	local stem=
	local prevstem=
	[ -n "$to" ] || return 1
	[ -n "$from" ] || return 1
	to=$(readlink -e "$to")
	from=$(readlink -e "$from")
	[ -n "$to" ] || return 1
	[ -n "$from" ] || return 1
	stem=${from}/
	while [ "${to#$stem}" == "${to}" -a "${stem}" != "${prevstem}" ]; do
		prevstem=$stem
		stem=$(readlink -e "${stem}/..")
		[ "${stem%/}" == "${stem}" ] && stem=${stem}/
		path=${path}../
	done
	echo ${path}${to#$stem}
}

function run_depmod() {
	(
		local ramdisk_dir=$1
		local DEPMOD_OUTPUT

		cd ${ramdisk_dir}
		if ! DEPMOD_OUTPUT="$(depmod -e -F ${DIST_DIR}/System.map -b . 0.0 2>&1)"; then
			echo "$DEPMOD_OUTPUT" >&2
			exit 1
		fi
		echo "$DEPMOD_OUTPUT"
		if { echo "$DEPMOD_OUTPUT" | grep -q "needs unknown symbol"; }; then
			echo "ERROR: kernel module(s) need unknown symbol(s)" >&2
			exit 1
		fi
	)
}

# $1 MODULES_LIST, <File contains the list of modules that should go in the ramdisk>
# $2 MODULES_STAGING_DIR    <The directory to look for all the compiled modules>
# $3 INITRAMFS_STAGING_DIR  <The destination directory in which MODULES_LIST is
#                            expected, and it's corresponding modules.* files>
function create_reduced_modules_order() {
	echo "========================================================"
	echo " Creating reduced modules.order"
	local modules_list_file=$1
	local src_dir=$2/lib/modules/*
	local dest_dir=$3/lib/modules/0.0
	local staging_dir=$2/intermediate_ramdisk_staging
	local modules_staging_dir=${staging_dir}/lib/modules/0.0

	rm -rf ${staging_dir}/
	mkdir -p ${modules_staging_dir}

	# Need to make sure we can find modules_list_file from the staging dir
	if [[ -f "${ROOT_DIR}/${modules_list_file}" ]]; then
		modules_list_file="${ROOT_DIR}/${modules_list_file}"
	elif [[ "${modules_list_file}" != /* ]]; then
		echo "modules_list_file must be an absolute path or relative to ${ROOT_DIR}: ${modules_list_file}"
		exit 1
	elif [[ ! -f "${modules_list_file}" ]]; then
		echo "Failed to find modules_list_file: ${modules_list_file}"
		exit 1
	fi

	(
		cd ${src_dir}
		touch ${modules_staging_dir}/modules.order

		while read ko; do
			# Ignore comment lines starting with # sign
			[[ "${ko}" = \#* ]] && continue
			if grep -q $(basename ${ko}) ${modules_list_file}; then
				mkdir -p ${modules_staging_dir}/$(dirname ${ko})
				cp -p ${ko} ${modules_staging_dir}/${ko}
				echo ${ko} >> ${modules_staging_dir}/modules.order
			fi
		done < modules.order

		# External modules
		if [ -d "./extra" ]; then
			mkdir -p ${modules_staging_dir}/extra
			for ko in $(find extra/. -name "*.ko"); do
				if grep -q $(basename ${ko}) ${modules_list_file}; then
					mkdir -p ${modules_staging_dir}/extra
					cp -p ${ko} ${modules_staging_dir}/extra/$(basename ${ko})
					echo "extra/$(basename ${ko})" >> ${modules_staging_dir}/modules.order
				fi
			done
		fi
	)

	cp ${src_dir}/modules.builtin* ${modules_staging_dir}/.
	run_depmod ${staging_dir}
	cp ${modules_staging_dir}/modules.* ${dest_dir}/.

	# Clean up
	rm -rf ${staging_dir}
}

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

# For module file Signing with the kernel (if needed)
FILE_SIGN_BIN=scripts/sign-file
SIGN_SEC=certs/signing_key.pem
SIGN_CERT=certs/signing_key.x509
SIGN_ALGO=sha512

# Save environment parameters before being overwritten by sourcing
# BUILD_CONFIG.
CC_ARG="${CC}"

source "${ROOT_DIR}/build/_setup_env.sh"

export MAKE_ARGS=$*
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export KERNEL_UAPI_HEADERS_DIR=$(readlink -m ${COMMON_OUT_DIR}/kernel_uapi_headers)
export INITRAMFS_STAGING_DIR=${MODULES_STAGING_DIR}/initramfs_staging

BOOT_IMAGE_HEADER_VERSION=${BOOT_IMAGE_HEADER_VERSION:-3}

cd ${ROOT_DIR}

export CLANG_TRIPLE CROSS_COMPILE CROSS_COMPILE_COMPAT CROSS_COMPILE_ARM32 ARCH SUBARCH MAKE_GOALS

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

if [ -n "${DEPMOD}" ]; then
  TOOL_ARGS+=("DEPMOD=${DEPMOD}")
fi

# Allow hooks that refer to $CC_LD_ARG to keep working until they can be
# updated.
CC_LD_ARG="${TOOL_ARGS[@]}"

if [ -z "${LZ4_RAMDISK}" ] ; then
  RAMDISK_COMPRESS="gzip -c -f"
  RAMDISK_DECOMPRESS="gzip -c -d"
  RAMDISK_EXT="gz"
else
  RAMDISK_COMPRESS="lz4 -c -l -12 --favor-decSpeed"
  RAMDISK_DECOMPRESS="lz4 -c -d -l"
  RAMDISK_EXT="lz4"
fi

mkdir -p ${OUT_DIR} ${DIST_DIR}

echo "========================================================"
echo " Setting up for build"
if [ -z "${SKIP_MRPROPER}" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} mrproper)
  set +x
fi

if [ -n "${PRE_DEFCONFIG_CMDS}" ]; then
  echo "========================================================"
  echo " Running pre-defconfig command(s):"
  set -x
  eval ${PRE_DEFCONFIG_CMDS}
  set +x
fi

if [ -z "${SKIP_DEFCONFIG}" ] ; then
set -x
(cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} ${DEFCONFIG})
set +x

if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
  echo "========================================================"
  echo " Running pre-make command(s):"
  set -x
  eval ${POST_DEFCONFIG_CMDS}
  set +x
fi
fi

if [ -n "${TAGS_CONFIG}" ]; then
  echo "========================================================"
  echo " Running tags command:"
  set -x
  (cd ${KERNEL_DIR} && SRCARCH=${ARCH} ./scripts/tags.sh ${TAGS_CONFIG})
  set +x
  exit 0
fi

# Truncate abi.prop file
ABI_PROP=${DIST_DIR}/abi.prop
: > ${ABI_PROP}

if [ -n "${ABI_DEFINITION}" ]; then

  ABI_XML=${DIST_DIR}/abi.xml

  echo "KMI_DEFINITION=abi.xml" >> ${ABI_PROP}
  echo "KMI_MONITORED=1"        >> ${ABI_PROP}

  if [ -n "${KMI_ENFORCED}" ]; then
    echo "KMI_ENFORCED=1" >> ${ABI_PROP}
  fi
fi

if [ -n "${KMI_WHITELIST}" ]; then
  ABI_WL=${DIST_DIR}/abi_whitelist
  echo "KMI_WHITELIST=abi_whitelist" >> ${ABI_PROP}
fi

# Copy the abi_${arch}.xml file from the sources into the dist dir
if [ -n "${ABI_DEFINITION}" ]; then
  echo "========================================================"
  echo " Copying abi definition to ${ABI_XML}"
  pushd $ROOT_DIR/$KERNEL_DIR
    cp "${ABI_DEFINITION}" ${ABI_XML}
  popd
fi

# Copy the abi whitelist file from the sources into the dist dir
if [ -n "${KMI_WHITELIST}" ]; then
  echo "========================================================"
  echo " Generating abi whitelist definition to ${ABI_WL}"
  pushd $ROOT_DIR/$KERNEL_DIR
    cp "${KMI_WHITELIST}" ${ABI_WL}

    # If there are additional whitelists specified, append them
    if [ -n "${ADDITIONAL_KMI_WHITELISTS}" ]; then
      for whitelist in ${ADDITIONAL_KMI_WHITELISTS}; do
          echo >> ${ABI_WL}
          cat "${whitelist}" >> ${ABI_WL}
      done
    fi

    if [ -n "${TRIM_NONLISTED_KMI}" ]; then
        # Create the raw whitelist
        cat ${ABI_WL} | \
                ${ROOT_DIR}/build/abi/flatten_whitelist > \
                ${OUT_DIR}/abi_whitelist.raw

        # Update the kernel configuration
        ./scripts/config --file ${OUT_DIR}/.config \
                -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
                --set-str UNUSED_KSYMS_WHITELIST ${OUT_DIR}/abi_whitelist.raw
        (cd ${OUT_DIR} && \
                make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} olddefconfig)
        # Make sure the config is applied
        grep CONFIG_UNUSED_KSYMS_WHITELIST ${OUT_DIR}/.config > /dev/null || {
          echo "ERROR: Failed to apply TRIM_NONLISTED_KMI kernel configuration" >&2
          echo "Does your kernel support CONFIG_UNUSED_KSYMS_WHITELIST?" >&2
          exit 1
        }

    elif [ -n "${KMI_WHITELIST_STRICT_MODE}" ]; then
      echo "ERROR: KMI_WHITELIST_STRICT_MODE requires TRIM_NONLISTED_KMI=1" >&2
      exit 1
    fi
  popd # $ROOT_DIR/$KERNEL_DIR
elif [ -n "${TRIM_NONLISTED_KMI}" ]; then
  echo "ERROR: TRIM_NONLISTED_KMI requires a KMI_WHITELIST" >&2
  exit 1
elif [ -n "${KMI_WHITELIST_STRICT_MODE}" ]; then
  echo "ERROR: KMI_WHITELIST_STRICT_MODE requires a KMI_WHITELIST" >&2
  exit 1
fi

echo "========================================================"
echo " Building kernel"

set -x
(cd ${OUT_DIR} && make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} ${MAKE_GOALS})
set +x

if [ -n "${POST_KERNEL_BUILD_CMDS}" ]; then
  echo "========================================================"
  echo " Running post-kernel-build command(s):"
  set -x
  eval ${POST_KERNEL_BUILD_CMDS}
  set +x
fi

if [ -n "${KMI_WHITELIST_STRICT_MODE}" ]; then
  echo "========================================================"
  echo " Comparing the KMI and the whitelists:"
  set -x
  ${ROOT_DIR}/build/abi/compare_to_wl "${OUT_DIR}/Module.symvers" \
                                      "${OUT_DIR}/abi_whitelist.raw"
  set +x
fi

rm -rf ${MODULES_STAGING_DIR}
mkdir -p ${MODULES_STAGING_DIR}

if [ -z "${DO_NOT_STRIP_MODULES}" ]; then
    MODULE_STRIP_FLAG="INSTALL_MOD_STRIP=1"
fi

if [ -n "${BUILD_INITRAMFS}" -o  -n "${IN_KERNEL_MODULES}" ]; then
  echo "========================================================"
  echo " Installing kernel modules into staging directory"

  (cd ${OUT_DIR} &&                                                           \
   make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}                   \
        INSTALL_MOD_PATH=${MODULES_STAGING_DIR} ${MAKE_ARGS} modules_install)
fi

if [[ -z "${SKIP_EXT_MODULES}" ]] && [[ -n "${EXT_MODULES}" ]]; then
  echo "========================================================"
  echo " Building external modules and installing them into staging directory"

  for EXT_MOD in ${EXT_MODULES}; do
    # The path that we pass in via the variable M needs to be a relative path
    # relative to the kernel source directory. The source files will then be
    # looked for in ${KERNEL_DIR}/${EXT_MOD_REL} and the object files (i.e. .o
    # and .ko) files will be stored in ${OUT_DIR}/${EXT_MOD_REL}. If we
    # instead set M to an absolute path, then object (i.e. .o and .ko) files
    # are stored in the module source directory which is not what we want.
    EXT_MOD_REL=$(rel_path ${ROOT_DIR}/${EXT_MOD} ${KERNEL_DIR})
    # The output directory must exist before we invoke make. Otherwise, the
    # build system behaves horribly wrong.
    mkdir -p ${OUT_DIR}/${EXT_MOD_REL}
    set -x
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                       O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS}
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                       O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}    \
                       INSTALL_MOD_PATH=${MODULES_STAGING_DIR}                \
                       ${MAKE_ARGS} modules_install
    set +x
  done

fi

if [ -n "${EXTRA_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra build command(s):"
  set -x
  eval ${EXTRA_CMDS}
  set +x
fi

OVERLAYS_OUT=""
for ODM_DIR in ${ODM_DIRS}; do
  OVERLAY_DIR=${ROOT_DIR}/device/${ODM_DIR}/overlays

  if [ -d ${OVERLAY_DIR} ]; then
    OVERLAY_OUT_DIR=${OUT_DIR}/overlays/${ODM_DIR}
    mkdir -p ${OVERLAY_OUT_DIR}
    make -C ${OVERLAY_DIR} DTC=${OUT_DIR}/scripts/dtc/dtc                     \
                           OUT_DIR=${OVERLAY_OUT_DIR} ${MAKE_ARGS}
    OVERLAYS=$(find ${OVERLAY_OUT_DIR} -name "*.dtbo")
    OVERLAYS_OUT="$OVERLAYS_OUT $OVERLAYS"
  fi
done

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

for FILE in ${OVERLAYS_OUT}; do
  OVERLAY_DIST_DIR=${DIST_DIR}/$(dirname ${FILE#${OUT_DIR}/overlays/})
  echo "  ${FILE#${OUT_DIR}/}"
  mkdir -p ${OVERLAY_DIST_DIR}
  cp ${FILE} ${OVERLAY_DIST_DIR}/
done

if [ -n "${DIST_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra dist command(s):"
  set -x
  eval ${DIST_CMDS}
  set +x
fi

MODULES=$(find ${MODULES_STAGING_DIR} -type f -name "*.ko")
if [ -n "${MODULES}" ]; then
  if [ -n "${IN_KERNEL_MODULES}" -o -n "${EXT_MODULES}" ]; then
    echo "========================================================"
    echo " Copying modules files"
    for FILE in ${MODULES}; do
      echo "  ${FILE#${MODULES_STAGING_DIR}/}"
      cp -p ${FILE} ${DIST_DIR}
    done
  fi
  if [ -n "${BUILD_INITRAMFS}" ]; then
    echo "========================================================"
    echo " Creating initramfs"
    rm -rf ${INITRAMFS_STAGING_DIR}
    # Depmod requires a version number; use 0.0 instead of determining the
    # actual kernel version since it is not necessary and will be removed for
    # the final initramfs image.
    mkdir -p ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/kernel/
    cp -r ${MODULES_STAGING_DIR}/lib/modules/*/kernel/* ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/kernel/
    cp ${MODULES_STAGING_DIR}/lib/modules/*/modules.order ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.order
    cp ${MODULES_STAGING_DIR}/lib/modules/*/modules.builtin ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.builtin

    if [ -n "${EXT_MODULES}" ]; then
      mkdir -p ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/extra/
      cp -r ${MODULES_STAGING_DIR}/lib/modules/*/extra/* ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/extra/
      (cd ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/ && \
          find extra -type f -name "*.ko" | sort >> modules.order)
    fi

    if [ -n "${DO_NOT_STRIP_MODULES}" ]; then
      # strip debug symbols off initramfs modules
      find ${INITRAMFS_STAGING_DIR} -type f -name "*.ko" \
        -exec ${OBJCOPY:${CROSS_COMPILE}strip} --strip-debug {} \;
    fi

		# Re-run depmod to detect any dependencies between in-kernel and external
		# modules. Then, create modules.order based on all the modules compiled.
		if [[ -n "${MODULES_LIST}" ]]; then
			create_reduced_modules_order ${MODULES_LIST} ${MODULES_STAGING_DIR} \
					${INITRAMFS_STAGING_DIR}
		else
			run_depmod ${INITRAMFS_STAGING_DIR}
		fi

    cp ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.order ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.load
    cp ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.order ${DIST_DIR}/modules.load
    echo "${MODULES_OPTIONS}" > ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.options
    mv ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/* ${INITRAMFS_STAGING_DIR}/lib/modules/.
    rmdir ${INITRAMFS_STAGING_DIR}/lib/modules/0.0

    if [ "${BOOT_IMAGE_HEADER_VERSION}" -eq "3" ]; then
      mkdir -p ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk
      if [ -f "${VENDOR_FSTAB}" ]; then
        cp ${VENDOR_FSTAB} ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk/.
      fi
    fi

    (cd ${INITRAMFS_STAGING_DIR} && find . | cpio -H newc -o --quiet > ${MODULES_STAGING_DIR}/initramfs.cpio)
    ${RAMDISK_COMPRESS} ${MODULES_STAGING_DIR}/initramfs.cpio > ${MODULES_STAGING_DIR}/initramfs.cpio.${RAMDISK_EXT}
    mv ${MODULES_STAGING_DIR}/initramfs.cpio.${RAMDISK_EXT} ${DIST_DIR}/initramfs.img
  fi
fi

if [ -n "${UNSTRIPPED_MODULES}" ]; then
  echo "========================================================"
  echo " Copying unstripped module files for debugging purposes (not loaded on device)"
  mkdir -p ${UNSTRIPPED_DIR}
  for MODULE in ${UNSTRIPPED_MODULES}; do
    find ${MODULES_PRIVATE_DIR} -name ${MODULE} -exec cp {} ${UNSTRIPPED_DIR} \;
  done
fi

if [ -z "${SKIP_CP_KERNEL_HDR}" ]; then
  echo "========================================================"
  echo " Installing UAPI kernel headers:"
  mkdir -p "${KERNEL_UAPI_HEADERS_DIR}/usr"
  make -C ${OUT_DIR} O=${OUT_DIR} "${TOOL_ARGS[@]}"                           \
          INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr" ${MAKE_ARGS}      \
          headers_install
  # The kernel makefiles create files named ..install.cmd and .install which
  # are only side products. We don't want those. Let's delete them.
  find ${KERNEL_UAPI_HEADERS_DIR} \( -name ..install.cmd -o -name .install \) -exec rm '{}' +
  KERNEL_UAPI_HEADERS_TAR=${DIST_DIR}/kernel-uapi-headers.tar.gz
  echo " Copying kernel UAPI headers to ${KERNEL_UAPI_HEADERS_TAR}"
  tar -czf ${KERNEL_UAPI_HEADERS_TAR} --directory=${KERNEL_UAPI_HEADERS_DIR} usr/
fi

if [ -z "${SKIP_CP_KERNEL_HDR}" ] ; then
  echo "========================================================"
  KERNEL_HEADERS_TAR=${DIST_DIR}/kernel-headers.tar.gz
  echo " Copying kernel headers to ${KERNEL_HEADERS_TAR}"
  pushd $ROOT_DIR/$KERNEL_DIR
    find arch include $OUT_DIR -name *.h -print0               \
            | tar -czf $KERNEL_HEADERS_TAR                     \
              --absolute-names                                 \
              --dereference                                    \
              --transform "s,.*$OUT_DIR,,"                     \
              --transform "s,^,kernel-headers/,"               \
              --null -T -
  popd
fi

echo "========================================================"
echo " Files copied to ${DIST_DIR}"

if [ ! -z "${BUILD_BOOT_IMG}" ] ; then
	MKBOOTIMG_ARGS=()
	if [ -n  "${BASE_ADDRESS}" ]; then
		MKBOOTIMG_ARGS+=("--base" "${BASE_ADDRESS}")
	fi
	if [ -n  "${PAGE_SIZE}" ]; then
		MKBOOTIMG_ARGS+=("--pagesize" "${PAGE_SIZE}")
	fi
	if [ -n "${KERNEL_CMDLINE}" ]; then
		MKBOOTIMG_ARGS+=("--cmdline" "${KERNEL_CMDLINE}")
	fi

	DTB_FILE_LIST=$(find ${DIST_DIR} -name "*.dtb")
	if [ -z "${DTB_FILE_LIST}" ]; then
		if [ -z "${SKIP_VENDOR_BOOT}" ]; then
			echo "No *.dtb files found in ${DIST_DIR}"
			exit 1
		fi
	else
		cat $DTB_FILE_LIST > ${DIST_DIR}/dtb.img
		MKBOOTIMG_ARGS+=("--dtb" "${DIST_DIR}/dtb.img")
	fi

	MKBOOTIMG_RAMDISKS=()
	for ramdisk in ${VENDOR_RAMDISK_BINARY} \
		       "${MODULES_STAGING_DIR}/initramfs.cpio"; do
		if [ -f "${DIST_DIR}/${ramdisk}" ]; then
			MKBOOTIMG_RAMDISKS+=("${DIST_DIR}/${ramdisk}")
		else
			if [ -f "${ramdisk}" ]; then
				MKBOOTIMG_RAMDISKS+=("${ramdisk}")
			fi
		fi
	done
	for ((i=0; i<"${#MKBOOTIMG_RAMDISKS[@]}"; i++)); do
		CPIO_NAME="$(mktemp -t build.sh.ramdisk.XXXXXXXX)"
		if ${RAMDISK_DECOMPRESS} "${MKBOOTIMG_RAMDISKS[$i]}" 2>/dev/null > ${CPIO_NAME}; then
			MKBOOTIMG_RAMDISKS[$i]=${CPIO_NAME}
		else
			rm -f ${CPIO_NAME}
		fi
	done
	if [ "${#MKBOOTIMG_RAMDISKS[@]}" -gt 0 ]; then
		cat ${MKBOOTIMG_RAMDISKS[*]} | ${RAMDISK_COMPRESS} - > ${DIST_DIR}/ramdisk.${RAMDISK_EXT}
	elif [ -z "${SKIP_VENDOR_BOOT}" ]; then
		echo "No ramdisk found. Please provide a GKI and/or a vendor ramdisk."
		exit 1
	fi

	if [ -z "${MKBOOTIMG_PATH}" ]; then
		MKBOOTIMG_PATH="tools/mkbootimg/mkbootimg.py"
	fi
	if [ ! -f "$MKBOOTIMG_PATH" ]; then
		echo "mkbootimg.py script not found. MKBOOTIMG_PATH = $MKBOOTIMG_PATH"
		exit 1
	fi

	if [ ! -f "${DIST_DIR}/$KERNEL_BINARY" ]; then
		echo "kernel binary(KERNEL_BINARY = $KERNEL_BINARY) not present in ${DIST_DIR}"
		exit 1
	fi

	if [ "${BOOT_IMAGE_HEADER_VERSION}" -eq "3" ]; then
		if [ -f "${GKI_RAMDISK_PREBUILT_BINARY}" ]; then
			MKBOOTIMG_ARGS+=("--ramdisk" "${GKI_RAMDISK_PREBUILT_BINARY}")
		fi

		if [ -z "${SKIP_VENDOR_BOOT}" ]; then
			MKBOOTIMG_ARGS+=("--vendor_boot" "${DIST_DIR}/vendor_boot.img" \
				"--vendor_ramdisk" "${DIST_DIR}/ramdisk.${RAMDISK_EXT}")
			if [ -n "${KERNEL_VENDOR_CMDLINE}" ]; then
				MKBOOTIMG_ARGS+=("--vendor_cmdline" "${KERNEL_VENDOR_CMDLINE}")
			fi
		fi
	else
		MKBOOTIMG_ARGS+=("--ramdisk" "${DIST_DIR}/ramdisk.${RAMDISK_EXT}")
	fi

	python "$MKBOOTIMG_PATH" --kernel "${DIST_DIR}/${KERNEL_BINARY}" \
		--header_version "${BOOT_IMAGE_HEADER_VERSION}" \
		"${MKBOOTIMG_ARGS[@]}" -o "${DIST_DIR}/boot.img"

	[ -f "${DIST_DIR}/boot.img" ] && echo "boot image created at ${DIST_DIR}/boot.img"
	[ -z "${SKIP_VENDOR_BOOT}" ] \
	  && [ "${BOOT_IMAGE_HEADER_VERSION}" -eq "3" ] \
		&& [ -f "${DIST_DIR}/vendor_boot.img" ] \
		&& echo "vendor boot image created at ${DIST_DIR}/vendor_boot.img"
fi


# No trace_printk use on build server build
if readelf -a ${DIST_DIR}/vmlinux 2>&1 | grep -q trace_printk_fmt; then
  echo "========================================================"
  echo "WARN: Found trace_printk usage in vmlinux."
  echo ""
  echo "trace_printk will cause trace_printk_init_buffers executed in kernel"
  echo "start, which will increase memory and lead warning shown during boot."
  echo "We should not carry trace_printk in production kernel."
  echo ""
  if [ ! -z "${STOP_SHIP_TRACEPRINTK}" ]; then
    echo "ERROR: stop ship on trace_printk usage." 1>&2
    exit 1
  fi
fi
