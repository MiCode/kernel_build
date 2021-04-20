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
#   To define custom out and dist directories:
#     OUT_DIR=<out dir> DIST_DIR=<dist dir> build/build.sh <make options>*
#   To use a custom build config:
#     BUILD_CONFIG=<path to the build.config> <make options>*
#
# Examples:
#   To define custom out and dist directories:
#     OUT_DIR=output DIST_DIR=dist build/build.sh -j24 V=1
#   To use a custom build config:
#     BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j24 V=1
#
# The following environment variables are considered during execution:
#
#   BUILD_CONFIG
#     Build config file to initialize the build environment from. The location
#     is to be defined relative to the repo root directory.
#     Defaults to 'build.config'.
#
#   BUILD_CONFIG_FRAGMENTS
#     A whitespace-separated list of additional build config fragments to be
#     sourced after the main build config file. Typically used for sanitizers or
#     other special builds.
#
#   OUT_DIR
#     Base output directory for the kernel build.
#     Defaults to <REPO_ROOT>/out/<BRANCH>.
#
#   DIST_DIR
#     Base output directory for the kernel distribution.
#     Defaults to <OUT_DIR>/dist
#
#   MAKE_GOALS
#     List of targets passed to Make when compiling the kernel.
#     Typically: Image, modules, and a DTB (if applicable).
#
#   EXT_MODULES
#     Space separated list of external kernel modules to be build.
#
#   UNSTRIPPED_MODULES
#     Space separated list of modules to be copied to <DIST_DIR>/unstripped
#     for debugging purposes.
#
#   COMPRESS_UNSTRIPPED_MODULES
#     If set to "1", then compress the unstripped modules into a tarball.
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
#   HERMETIC_TOOLCHAIN
#     When set, the PATH during kernel build will be restricted to a set of
#     known prebuilt directories and selected host tools that are usually not
#     provided by prebuilt toolchains.
#
#  ADDITIONAL_HOST_TOOLS
#     A whitespace separated set of tools that will be allowed to be used from
#     the host when running the build with HERMETIC_TOOLCHAIN=1.
#
#   ABI_DEFINITION
#     Location of the abi definition file relative to <REPO_ROOT>/KERNEL_DIR
#     If defined (usually in build.config), also copy that abi definition to
#     <OUT_DIR>/dist/abi.xml when creating the distribution.
#
#   KMI_SYMBOL_LIST
#     Location of the main KMI symbol list file relative to
#     <REPO_ROOT>/KERNEL_DIR If defined (usually in build.config), also copy
#     that symbol list definition to <OUT_DIR>/dist/abi_symbollist when
#     creating the distribution.
#
#   ADDITIONAL_KMI_SYMBOL_LISTS
#     Location of secondary KMI symbol list files relative to
#     <REPO_ROOT>/KERNEL_DIR. If defined, these additional symbol lists will be
#     appended to the main one before proceeding to the distribution creation.
#
#   KMI_ENFORCED
#     This is an indicative option to signal that KMI is enforced in this build
#     config. If set to "1", downstream KMI checking tools might respect it and
#     react to it by failing if KMI differences are detected.
#
#   GENERATE_VMLINUX_BTF
#     If set to "1", generate a vmlinux.btf that is stripped off any debug
#     symbols, but contains type and symbol information within a .BTF section.
#     This is suitable for ABI analysis through BTF.
#
# Environment variables to influence the stages of the kernel build.
#
#   SKIP_MRPROPER
#     if set to "1", skip `make mrproper`
#
#   SKIP_DEFCONFIG
#     if set to "1", skip `make defconfig`
#
#   SKIP_IF_VERSION_MATCHES
#     if defined, skip compiling anything if the kernel version in vmlinux
#     matches the expected kernel version. This is useful for mixed build, where
#     GKI kernel does not change frequently and we can simply skip everything
#     in build.sh. Note: if the expected version string contains "dirty", then
#     this flag would have not cause build.sh to exit early.
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
#   LTO=[full|thin|none]
#     If set to "full", force any kernel with LTO_CLANG support to be built
#     with full LTO, which is the most optimized method. This is the default,
#     but can result in very slow build times, especially when building
#     incrementally. (This mode does not require CFI to be disabled.)
#     If set to "thin", force any kernel with LTO_CLANG support to be built
#     with ThinLTO, which trades off some optimizations for incremental build
#     speed. This is nearly always what you want for local development. (This
#     mode does not require CFI to be disabled.)
#     If set to "none", force any kernel with LTO_CLANG support to be built
#     without any LTO (upstream default), which results in no optimizations
#     and also disables LTO-dependent features like CFI. This mode is not
#     recommended because CFI will not be able to catch bugs if it is
#     disabled.
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
#     if set to "1", keep debug information for distributed modules.
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
#     - KERNEL_VENDOR_CMDLINE=<string of kernel parameters for vendor boot image,
#       vendor_boot when BOOT_IMAGE_HEADER_VERSION >= 3; boot otherwise>
#     - VENDOR_FSTAB=<Path to the vendor fstab to be included in the vendor
#       ramdisk>
#     - TAGS_OFFSET=<physical address for kernel tags>
#     - RAMDISK_OFFSET=<ramdisk physical load address>
#     If the BOOT_IMAGE_HEADER_VERSION is less than 3, two additional variables must
#     be defined:
#     - BASE_ADDRESS=<base address to load the kernel at>
#     - PAGE_SIZE=<flash page size>
#     If the BOOT_IMAGE_HEADER_VERSION is 3, a vendor_boot image will be built unless
#     SKIP_VENDOR_BOOT is defined.
#     - MODULES_LIST=<file to list of modules> list of modules to use for
#       modules.load. If this property is not set, then the default modules.load
#       is used.
#     - TRIM_UNUSED_MODULES. If set, then modules not mentioned in
#       modules.load are removed from initramfs. If MODULES_LIST is unset, then
#       having this variable set effectively becomes a no-op.
#     - MODULES_BLOCKLIST=<modules.blocklist file> A list of modules which are
#       blocked from being loaded. This file is copied directly to staging directory,
#       and should be in the format:
#       blocklist module_name
#
#   VENDOR_RAMDISK_CMDS
#     When building vendor boot image, VENDOR_RAMDISK_CMDS enables the build
#     config file to specify command(s) for further altering the prebuilt vendor
#     ramdisk binary. For example, the build config file could add firmware files
#     on the vendor ramdisk (lib/firmware) for testing purposes.
#
#   AVB_SIGN_BOOT_IMG
#     if defined, sign the boot image using the AVB_BOOT_KEY. Refer to
#     https://android.googlesource.com/platform/external/avb/+/master/README.md
#     for details on what Android Verified Boot is and how it works. The kernel
#     prebuilt tool `avbtool` is used for signing.
#
#     When AVB_SIGN_BOOT_IMG is defined, the following flags need to be
#     defined:
#     - AVB_BOOT_PARTITION_SIZE=<size of the boot partition in bytes>
#     - AVB_BOOT_KEY=<absolute path to the key used for signing> The Android test
#       key has been uploaded to the kernel/prebuilts/build-tools project here:
#       https://android.googlesource.com/kernel/prebuilts/build-tools/+/refs/heads/master/linux-x86/share/avb
#     - AVB_BOOT_ALGORITHM=<AVB_BOOT_KEY algorithm used> e.g. SHA256_RSA2048. For the
#       full list of supported algorithms, refer to the enum AvbAlgorithmType in
#       https://android.googlesource.com/platform/external/avb/+/refs/heads/master/libavb/avb_crypto.h
#
#   BUILD_INITRAMFS
#     if set to "1", build a ramdisk containing all .ko files and resulting
#     depmod artifacts
#
#   MODULES_OPTIONS
#     A /lib/modules/modules.options file is created on the ramdisk containing
#     the contents of this variable, lines should be of the form: options
#     <modulename> <param1>=<val> <param2>=<val> ...
#
#   MODULES_ORDER
#     location of an optional file containing the list of modules that are
#     expected to be built for the current configuration, in the modules.order
#     format, relative to the kernel source tree.
#
#   GKI_MODULES_LIST
#     location of an optional file containing the list of GKI modules, relative
#     to the kernel source tree. This should be set in downstream builds to
#     ensure the ABI tooling correctly differentiates vendor/OEM modules and GKI
#     modules. This should not be set in the upstream GKI build.config.
#
#   VENDOR_DLKM_MODULES_LIST
#     location (relative to the repo root directory) of an optional file
#     containing the list of kernel modules which shall be copied into a
#     vendor_dlkm partition image.
#
#   VENDOR_DLKM_MODULES_BLOCKLIST
#     location (relative to the repo root directory) of an optional file
#     containing a list of modules which are blocked from being loaded. This
#     file is copied directly to the staging directory and should be in the
#     format: blocklist module_name
#
#   VENDOR_DLKM_PROPS
#     location (relative to the repo root directory) of a text file containing
#     the properties to be used for creation of a vendor_dlkm image
#     (filesystem, partition size, etc). If this is not set (and
#     VENDOR_DLKM_MODULES_LIST is), a default set of properties will be used
#     which assumes an ext4 filesystem and a dynamic partition.
#
#   LZ4_RAMDISK
#     if set to "1", any ramdisks generated will be lz4 compressed instead of
#     gzip compressed.
#
#   TRIM_NONLISTED_KMI
#     if set to "1", enable the CONFIG_UNUSED_KSYMS_WHITELIST kernel config
#     option to un-export from the build any un-used and non-symbol-listed
#     (as per KMI_SYMBOL_LIST) symbol.
#
#   KMI_SYMBOL_LIST_STRICT_MODE
#     if set to "1", add a build-time check between the KMI_SYMBOL_LIST and the
#     KMI resulting from the build, to ensure they match 1-1.
#
#   KMI_STRICT_MODE_OBJECTS
#     optional list of objects to consider for the KMI_SYMBOL_LIST_STRICT_MODE
#     check. Defaults to 'vmlinux'.
#
#   GKI_DIST_DIR
#     optional directory from which to copy GKI artifacts into DIST_DIR
#
#   GKI_BUILD_CONFIG
#     If set, builds a second set of kernel images using GKI_BUILD_CONFIG to
#     perform a "mixed build." Mixed builds creates "GKI kernel" and "vendor
#     modules" from two different trees. The GKI kernel tree can be the Android
#     Common Kernel and the vendor modules tree can be a complete vendor kernel
#     tree. GKI_DIST_DIR (above) is set and the GKI kernel's DIST output is
#     copied to this DIST output. This allows a vendor tree kernel image to be
#     effectively discarded and a GKI kernel Image used from an Android Common
#     Kernel. Any variables prefixed with GKI_ are passed into into the GKI
#     kernel's build.sh invocation.
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

# Save environment for mixed build support.
OLD_ENVIRONMENT=$(mktemp)
export -p > ${OLD_ENVIRONMENT}

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

# $1 directory of kernel modules ($1/lib/modules/x.y)
# $2 flags to pass to depmod
# $3 kernel version
function run_depmod() {
  (
    local ramdisk_dir=$1
    local DEPMOD_OUTPUT

    cd ${ramdisk_dir}
    if ! DEPMOD_OUTPUT="$(depmod $2 -F ${DIST_DIR}/System.map -b . $3 2>&1)"; then
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
# $3 IMAGE_STAGING_DIR  <The destination directory in which MODULES_LIST is
#                        expected, and it's corresponding modules.* files>
# $4 MODULES_BLOCKLIST, <File contains the list of modules to prevent from loading>
# $5 flags to pass to depmod
function create_modules_staging() {
  local modules_list_file=$1
  local src_dir=$(echo $2/lib/modules/*)
  local version=$(basename "${src_dir}")
  local dest_dir=$3/lib/modules/${version}
  local dest_stage=$3
  local modules_blocklist_file=$4
  local depmod_flags=$5

  rm -rf ${dest_dir}
  mkdir -p ${dest_dir}/kernel
  find ${src_dir}/kernel/ -maxdepth 1 -mindepth 1 \
    -exec cp -r {} ${dest_dir}/kernel/ \;
  # The other modules.* files will be generated by depmod
  cp ${src_dir}/modules.order ${dest_dir}/modules.order
  cp ${src_dir}/modules.builtin ${dest_dir}/modules.builtin

  if [ -n "${EXT_MODULES}" ]; then
    mkdir -p ${dest_dir}/extra/
    cp -r ${src_dir}/extra/* ${dest_dir}/extra/
    (cd ${dest_dir}/ && \
      find extra -type f -name "*.ko" | sort >> modules.order)
  fi

  if [ "${DO_NOT_STRIP_MODULES}" = "1" ]; then
    # strip debug symbols off initramfs modules
    find ${dest_dir} -type f -name "*.ko" \
      -exec ${OBJCOPY:-${CROSS_COMPILE}objcopy} --strip-debug {} \;
  fi

  if [ -n "${modules_list_file}" ]; then
    echo "========================================================"
    echo " Reducing modules.order to:"
    # Need to make sure we can find modules_list_file from the staging dir
    if [[ -f "${ROOT_DIR}/${modules_list_file}" ]]; then
      modules_list_file="${ROOT_DIR}/${modules_list_file}"
    elif [[ "${modules_list_file}" != /* ]]; then
      echo "modules list must be an absolute path or relative to ${ROOT_DIR}: ${modules_list_file}"
      exit 1
    elif [[ ! -f "${modules_list_file}" ]]; then
      echo "Failed to find modules list: ${modules_list_file}"
      exit 1
    fi

    local modules_list_filter=$(mktemp)
    local old_modules_list=$(mktemp)

    # Remove all lines starting with "#" (comments)
    # Exclamation point makes interpreter ignore the exit code under set -e
    ! grep -v "^\#" ${modules_list_file} > ${modules_list_filter}

    # grep the modules.order for any KOs in the modules list
    cp ${dest_dir}/modules.order ${old_modules_list}
    ! grep -w -f ${modules_list_filter} ${old_modules_list} > ${dest_dir}/modules.order
    rm -f ${modules_list_filter} ${old_modules_list}
    cat ${dest_dir}/modules.order | sed -e "s/^/  /"
  fi

  if [ -n "${modules_blocklist_file}" ]; then
    # Need to make sure we can find modules_blocklist_file from the staging dir
    if [[ -f "${ROOT_DIR}/${modules_blocklist_file}" ]]; then
      modules_blocklist_file="${ROOT_DIR}/${modules_blocklist_file}"
    elif [[ "${modules_blocklist_file}" != /* ]]; then
      echo "modules blocklist must be an absolute path or relative to ${ROOT_DIR}: ${modules_blocklist_file}"
      exit 1
    elif [[ ! -f "${modules_blocklist_file}" ]]; then
      echo "Failed to find modules blocklist: ${modules_blocklist_file}"
      exit 1
    fi

    cp ${modules_blocklist_file} ${dest_dir}/modules.blocklist
  fi

  if [ -n "${TRIM_UNUSED_MODULES}" ]; then
    echo "========================================================"
    echo " Trimming unused modules"
    local used_blocklist_modules=$(mktemp)
    if [ -f ${dest_dir}/modules.blocklist ]; then
      # TODO: the modules blocklist could contain module aliases instead of the filename
      sed -n -E -e 's/blocklist (.+)/\1/p' ${dest_dir}/modules.blocklist > $used_blocklist_modules
    fi

    # Trim modules from tree that aren't mentioned in modules.order
    (
      cd ${dest_dir}
      find * -type f -name "*.ko" | grep -v -w -f modules.order -f $used_blocklist_modules - | xargs -r rm
    )
    rm $used_blocklist_modules
  fi

  # Re-run depmod to detect any dependencies between in-kernel and external
  # modules. Then, create modules.order based on all the modules compiled.
  run_depmod ${dest_stage} "${depmod_flags}" "${version}"
  cp ${dest_dir}/modules.order ${dest_dir}/modules.load
}

function build_vendor_dlkm() {
  echo "========================================================"
  echo " Creating vendor_dlkm image"

  create_modules_staging "${VENDOR_DLKM_MODULES_LIST}" "${MODULES_STAGING_DIR}" \
    "${VENDOR_DLKM_STAGING_DIR}" "${VENDOR_DLKM_MODULES_BLOCKLIST}"

  local vendor_dlkm_props_file

  if [ -z "${VENDOR_DLKM_PROPS}" ]; then
    vendor_dlkm_props_file="$(mktemp)"
    echo -e "vendor_dlkm_fs_type=ext4\n" >> ${vendor_dlkm_props_file}
    echo -e "use_dynamic_partition_size=true\n" >> ${vendor_dlkm_props_file}
    echo -e "ext_mkuserimg=mkuserimg_mke2fs\n" >> ${vendor_dlkm_props_file}
    echo -e "ext4_share_dup_blocks=true\n" >> ${vendor_dlkm_props_file}
  else
    vendor_dlkm_props_file="${VENDOR_DLKM_PROPS}"
    if [[ -f "${ROOT_DIR}/${vendor_dlkm_props_file}" ]]; then
      vendor_dlkm_props_file="${ROOT_DIR}/${vendor_dlkm_props_file}"
    elif [[ "${vendor_dlkm_props_file}" != /* ]]; then
      echo "VENDOR_DLKM_PROPS must be an absolute path or relative to ${ROOT_DIR}: ${vendor_dlkm_props_file}"
      exit 1
    elif [[ ! -f "${vendor_dlkm_props_file}" ]]; then
      echo "Failed to find VENDOR_DLKM_PROPS: ${vendor_dlkm_props_file}"
      exit 1
    fi
  fi
  build_image "${VENDOR_DLKM_STAGING_DIR}" "${vendor_dlkm_props_file}" \
    "${DIST_DIR}/vendor_dlkm.img" /dev/null
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

MAKE_ARGS=( "$@" )
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export KERNEL_UAPI_HEADERS_DIR=$(readlink -m ${COMMON_OUT_DIR}/kernel_uapi_headers)
export INITRAMFS_STAGING_DIR=${MODULES_STAGING_DIR}/initramfs_staging
export VENDOR_DLKM_STAGING_DIR=${MODULES_STAGING_DIR}/vendor_dlkm_staging

if [ -n "${GKI_BUILD_CONFIG}" ]; then
  GKI_OUT_DIR=${GKI_OUT_DIR:-${COMMON_OUT_DIR}/gki_kernel}
  GKI_DIST_DIR=${GKI_DIST_DIR:-${GKI_OUT_DIR}/dist}

  if [[ "${MAKE_GOALS}" =~ image|Image|vmlinux ]]; then
    echo " Compiling Image and vmlinux in device kernel is not supported in mixed build mode"
    exit 1
  fi

  # Inherit SKIP_MRPROPER, LTO, SKIP_DEFCONFIG unless overridden by corresponding GKI_* variables
  GKI_ENVIRON=("SKIP_MRPROPER=${SKIP_MRPROPER}" "LTO=${LTO}" "SKIP_DEFCONFIG=${SKIP_DEFCONFIG}" "SKIP_IF_VERSION_MATCHES=${SKIP_IF_VERSION_MATCHES}")
  # Explicitly unset GKI_BUILD_CONFIG in case it was set by in the old environment
  # e.g. GKI_BUILD_CONFIG=common/build.config.gki.x86 ./build/build.sh would cause
  # gki build recursively
  GKI_ENVIRON+=("GKI_BUILD_CONFIG=")
  # Any variables prefixed with GKI_ get set without that prefix in the GKI build environment
  # e.g. GKI_BUILD_CONFIG=common/build.config.gki.aarch64 -> BUILD_CONFIG=common/build.config.gki.aarch64
  GKI_ENVIRON+=($(export -p | sed -n -E -e 's/.*GKI_([^=]+=.*)$/\1/p' | tr '\n' ' '))
  GKI_ENVIRON+=("OUT_DIR=${GKI_OUT_DIR}")
  GKI_ENVIRON+=("DIST_DIR=${GKI_DIST_DIR}")
  ( env -i bash -c "source ${OLD_ENVIRONMENT}; rm -f ${OLD_ENVIRONMENT}; export ${GKI_ENVIRON[*]} ; ./build/build.sh" ) || exit 1

  # Dist dir must have vmlinux.symvers, modules.builtin.modinfo, modules.builtin
  MAKE_ARGS+=("KBUILD_MIXED_TREE=${GKI_DIST_DIR}")
else
  rm -f ${OLD_ENVIRONMENT}
fi

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

# LLVM=1 implies what is otherwise set below; it is a more concise way of
# specifying CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy <etc>, for
# newer kernel versions.
if [[ -n "${LLVM}" ]]; then
  TOOL_ARGS+=("LLVM=1")
  # Reset a bunch of variables that the kernel's top level Makefile does, just
  # in case someone tries to use these binaries in this script such as in
  # initramfs generation below.
  HOSTCC=clang
  HOSTCXX=clang++
  CC=clang
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  READELF=llvm-readelf
  OBJSIZE=llvm-size
  STRIP=llvm-strip
else
  if [ -n "${HOSTCC}" ]; then
    TOOL_ARGS+=("HOSTCC=${HOSTCC}")
  fi

  if [ -n "${CC}" ]; then
    TOOL_ARGS+=("CC=${CC}")
    if [ -z "${HOSTCC}" ]; then
      TOOL_ARGS+=("HOSTCC=${CC}")
    fi
  fi

  if [ -n "${LD}" ]; then
    TOOL_ARGS+=("LD=${LD}" "HOSTLD=${LD}")
    custom_ld=${LD##*.}
    if [ -n "${custom_ld}" ]; then
      TOOL_ARGS+=("HOSTLDFLAGS=-fuse-ld=${custom_ld}")
    fi
  fi

  if [ -n "${NM}" ]; then
    TOOL_ARGS+=("NM=${NM}")
  fi

  if [ -n "${OBJCOPY}" ]; then
    TOOL_ARGS+=("OBJCOPY=${OBJCOPY}")
  fi
fi

if [ -n "${LLVM_IAS}" ]; then
  TOOL_ARGS+=("LLVM_IAS=${LLVM_IAS}")
  # Reset $AS for the same reason that we reset $CC etc above.
  AS=clang
fi

if [ -n "${DEPMOD}" ]; then
  TOOL_ARGS+=("DEPMOD=${DEPMOD}")
fi

if [ -n "${DTC}" ]; then
  TOOL_ARGS+=("DTC=${DTC}")
fi

# Allow hooks that refer to $CC_LD_ARG to keep working until they can be
# updated.
CC_LD_ARG="${TOOL_ARGS[@]}"

DECOMPRESS_GZIP="gzip -c -d"
DECOMPRESS_LZ4="lz4 -c -d -l"
if [ -z "${LZ4_RAMDISK}" ] ; then
  RAMDISK_COMPRESS="gzip -c -f"
  RAMDISK_DECOMPRESS="${DECOMPRESS_GZIP}"
  RAMDISK_EXT="gz"
else
  RAMDISK_COMPRESS="lz4 -c -l -12 --favor-decSpeed"
  RAMDISK_DECOMPRESS="${DECOMPRESS_LZ4}"
  RAMDISK_EXT="lz4"
fi

if [ -n "${SKIP_IF_VERSION_MATCHES}" ]; then
  if [ -f "${DIST_DIR}/vmlinux" ]; then
    kernelversion="$(cd ${KERNEL_DIR} && make -s "${TOOL_ARGS[@]}" O=${OUT_DIR} kernelrelease)"
    # Split grep into 2 steps. "Linux version" will always be towards top and fast to find. Don't
    # need to search the entire vmlinux for it
    if [[ ! "$kernelversion" =~ .*dirty.* ]] && \
       grep -o -a -m1 "Linux version [^ ]* " ${DIST_DIR}/vmlinux | grep -q " ${kernelversion} " ; then
      echo "========================================================"
      echo " Skipping build because kernel version matches ${kernelversion}"
      exit 0
    fi
  fi
fi

mkdir -p ${OUT_DIR} ${DIST_DIR}

echo "========================================================"
echo " Setting up for build"
if [ "${SKIP_MRPROPER}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} "${MAKE_ARGS[@]}" mrproper)
  set +x
fi

# Store a copy of the effective kernel config from a potential previous run. In
# particular, we are interested in preserving the modification timestamp.
KERNEL_CONFIG=${OUT_DIR}/.config
[ -f ${KERNEL_CONFIG} ] && cp -p ${KERNEL_CONFIG} ${KERNEL_CONFIG}.before

if [ -n "${PRE_DEFCONFIG_CMDS}" ]; then
  echo "========================================================"
  echo " Running pre-defconfig command(s):"
  set -x
  eval ${PRE_DEFCONFIG_CMDS}
  set +x
fi

if [ "${SKIP_DEFCONFIG}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} "${MAKE_ARGS[@]}" ${DEFCONFIG})
  set +x

  if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
    echo "========================================================"
    echo " Running pre-make command(s):"
    set -x
    eval ${POST_DEFCONFIG_CMDS}
    set +x
  fi
fi

if [ "${LTO}" = "none" -o "${LTO}" = "thin" -o "${LTO}" = "full" ]; then
  echo "========================================================"
  echo " Modifying LTO mode to '${LTO}'"

  set -x
  if [ "${LTO}" = "none" ]; then
    ${KERNEL_DIR}/scripts/config --file ${KERNEL_CONFIG} \
      -d LTO_CLANG \
      -e LTO_NONE \
      -d LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -d THINLTO
  elif [ "${LTO}" = "thin" ]; then
    # This is best-effort; some kernels don't support LTO_THIN mode
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${KERNEL_CONFIG} \
      -e LTO_CLANG \
      -d LTO_NONE \
      -e LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -e THINLTO
  elif [ "${LTO}" = "full" ]; then
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${KERNEL_CONFIG} \
      -e LTO_CLANG \
      -d LTO_NONE \
      -d LTO_CLANG_THIN \
      -e LTO_CLANG_FULL \
      -d THINLTO
  fi
  (cd ${OUT_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} "${MAKE_ARGS[@]}" olddefconfig)
  set +x
elif [ -n "${LTO}" ]; then
  echo "LTO= must be one of 'none', 'thin' or 'full'."
  exit 1
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

  if [ "${KMI_ENFORCED}" = "1" ]; then
    echo "KMI_ENFORCED=1" >> ${ABI_PROP}
  fi
fi

if [ -n "${KMI_SYMBOL_LIST}" ]; then
  ABI_SL=${DIST_DIR}/abi_symbollist
  echo "KMI_SYMBOL_LIST=abi_symbollist" >> ${ABI_PROP}
fi

# define the kernel binary and modules archive in the $ABI_PROP
echo "KERNEL_BINARY=vmlinux" >> ${ABI_PROP}
if [ "${COMPRESS_UNSTRIPPED_MODULES}" = "1" ]; then
  echo "MODULES_ARCHIVE=${UNSTRIPPED_MODULES_ARCHIVE}" >> ${ABI_PROP}
fi

# Copy the abi_${arch}.xml file from the sources into the dist dir
if [ -n "${ABI_DEFINITION}" ]; then
  echo "========================================================"
  echo " Copying abi definition to ${ABI_XML}"
  pushd $ROOT_DIR/$KERNEL_DIR
    cp "${ABI_DEFINITION}" ${ABI_XML}
  popd
fi

# Copy the abi symbol list file from the sources into the dist dir
if [ -n "${KMI_SYMBOL_LIST}" ]; then
  echo "========================================================"
  echo " Generating abi symbol list definition to ${ABI_SL}"
  pushd $ROOT_DIR/$KERNEL_DIR
  cp "${KMI_SYMBOL_LIST}" ${ABI_SL}

  # If there are additional symbol lists specified, append them
  if [ -n "${ADDITIONAL_KMI_SYMBOL_LISTS}" ]; then
    for symbol_list in ${ADDITIONAL_KMI_SYMBOL_LISTS}; do
        echo >> ${ABI_SL}
        cat "${symbol_list}" >> ${ABI_SL}
    done
  fi
  if [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
      # Create the raw symbol list 
      cat ${ABI_SL} | \
              ${ROOT_DIR}/build/abi/flatten_symbol_list > \
              ${OUT_DIR}/abi_symbollist.raw

      # Update the kernel configuration
      ./scripts/config --file ${KERNEL_CONFIG} \
              -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
              --set-str UNUSED_KSYMS_WHITELIST ${OUT_DIR}/abi_symbollist.raw
      (cd ${OUT_DIR} && \
              make O=${OUT_DIR} "${TOOL_ARGS[@]}" "${MAKE_ARGS[@]}" olddefconfig)
      # Make sure the config is applied
      grep CONFIG_UNUSED_KSYMS_WHITELIST ${KERNEL_CONFIG} > /dev/null || {
        echo "ERROR: Failed to apply TRIM_NONLISTED_KMI kernel configuration" >&2
        echo "Does your kernel support CONFIG_UNUSED_KSYMS_WHITELIST?" >&2
        exit 1
      }

    elif [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
      echo "ERROR: KMI_SYMBOL_LIST_STRICT_MODE requires TRIM_NONLISTED_KMI=1" >&2
    exit 1
  fi
  popd # $ROOT_DIR/$KERNEL_DIR
elif [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
  echo "ERROR: TRIM_NONLISTED_KMI requires a KMI_SYMBOL_LIST" >&2
  exit 1
elif [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
  echo "ERROR: KMI_SYMBOL_LIST_STRICT_MODE requires a KMI_SYMBOL_LIST" >&2
  exit 1
fi

# If all the above configuration steps did not actually change the content of
# $KERNEL_CONFIG (usually, .config), we restore the previously stored copy
# along with its previous modification time stamp. That allows the kernel build
# to skip all rules that directly depend on the config changing. In particular,
# it might skip linking the kernel again if there haven't been any
# modifications requiring a relink.
if [ -f ${KERNEL_CONFIG}.before ]; then
  if `cmp -s ${KERNEL_CONFIG}.before ${KERNEL_CONFIG}`; then
    mv ${KERNEL_CONFIG}.before ${KERNEL_CONFIG}  # preserve timestamp
  else
    rm ${KERNEL_CONFIG}.before
  fi
fi

echo "========================================================"
echo " Building kernel"

set -x
(cd ${OUT_DIR} && make O=${OUT_DIR} "${TOOL_ARGS[@]}" "${MAKE_ARGS[@]}" ${MAKE_GOALS})
set +x

if [ -n "${POST_KERNEL_BUILD_CMDS}" ]; then
  echo "========================================================"
  echo " Running post-kernel-build command(s):"
  set -x
  eval ${POST_KERNEL_BUILD_CMDS}
  set +x
fi

if [ -n "${MODULES_ORDER}" ]; then
  echo "========================================================"
  echo " Checking the list of modules:"
  if ! diff -u "${KERNEL_DIR}/${MODULES_ORDER}" "${OUT_DIR}/modules.order"; then
    echo "ERROR: modules list out of date" >&2
    echo "Update it with:" >&2
    echo "cp ${OUT_DIR}/modules.order ${KERNEL_DIR}/${MODULES_ORDER}" >&2
    exit 1
  fi
fi

if [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
  echo "========================================================"
  echo " Comparing the KMI and the symbol lists:"
  set -x
  ${ROOT_DIR}/build/abi/compare_to_symbol_list "${OUT_DIR}/Module.symvers" \
                                               "${OUT_DIR}/abi_symbollist.raw"
  set +x
fi

rm -rf ${MODULES_STAGING_DIR}
mkdir -p ${MODULES_STAGING_DIR}

if [ "${DO_NOT_STRIP_MODULES}" != "1" ]; then
  MODULE_STRIP_FLAG="INSTALL_MOD_STRIP=1"
fi

if [ "${BUILD_INITRAMFS}" = "1" -o  -n "${IN_KERNEL_MODULES}" ]; then
  echo "========================================================"
  echo " Installing kernel modules into staging directory"

  (cd ${OUT_DIR} &&                                                           \
   make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}                   \
        INSTALL_MOD_PATH=${MODULES_STAGING_DIR} "${MAKE_ARGS[@]}" modules_install)
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
                       O=${OUT_DIR} "${TOOL_ARGS[@]}" "${MAKE_ARGS[@]}"
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                       O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}    \
                       INSTALL_MOD_PATH=${MODULES_STAGING_DIR}                \
                       "${MAKE_ARGS[@]}" modules_install
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
                           OUT_DIR=${OVERLAY_OUT_DIR} "${MAKE_ARGS[@]}"
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

if [ -z "${SKIP_CP_KERNEL_HDR}" ]; then
  echo "========================================================"
  echo " Installing UAPI kernel headers:"
  mkdir -p "${KERNEL_UAPI_HEADERS_DIR}/usr"
  make -C ${OUT_DIR} O=${OUT_DIR} "${TOOL_ARGS[@]}"                           \
          INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr" "${MAKE_ARGS[@]}"      \
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

if [ "${GENERATE_VMLINUX_BTF}" = "1" ]; then
  echo "========================================================"
  echo " Generating ${DIST_DIR}/vmlinux.btf"

  (
    cd ${DIST_DIR}
    cp -a vmlinux vmlinux.btf
    pahole -J vmlinux.btf
    llvm-strip --strip-debug vmlinux.btf
  )

fi

if [ -n "${GKI_DIST_DIR}" ]; then
  echo "========================================================"
  echo " Copying files from GKI kernel"
  cp -rv ${GKI_DIST_DIR}/* ${DIST_DIR}/
fi

if [ -n "${DIST_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra dist command(s):"
  # if DIST_CMDS requires UAPI headers, make sure a warning appears!
  if [ ! -d "${KERNEL_UAPI_HEADERS_DIR}/usr" ]; then
    echo "WARN: running without UAPI headers"
  fi
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
  if [ "${BUILD_INITRAMFS}" = "1" ]; then
    echo "========================================================"
    echo " Creating initramfs"
    rm -rf ${INITRAMFS_STAGING_DIR}
    create_modules_staging "${MODULES_LIST}" ${MODULES_STAGING_DIR} \
      ${INITRAMFS_STAGING_DIR} "${MODULES_BLOCKLIST}" "-e"

    MODULES_ROOT_DIR=$(echo ${INITRAMFS_STAGING_DIR}/lib/modules/*)
    cp ${MODULES_ROOT_DIR}/modules.load ${DIST_DIR}/modules.load
    echo "${MODULES_OPTIONS}" > ${MODULES_ROOT_DIR}/modules.options

    if [ "${BOOT_IMAGE_HEADER_VERSION}" -ge "3" ]; then
      if [ -f "${VENDOR_FSTAB}" ]; then
        mkdir -p ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk
        cp ${VENDOR_FSTAB} ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk/.
      fi
    fi

    (
      cd ${INITRAMFS_STAGING_DIR}
      # In toybox cpio, --no-preserve-owner is a valid command line switch for the
      # create i.e. copy-out mode. It causes toybox to set uid/gid to 0 for all
      # directory entries. This is equivalent to the command line argument -R +0:+0
      # in GNU cpio. Keep in mind that, in GNU cpio, --no-preserve-owner means
      # something else and is only valid in copy-in and copy-pass modes.
      if cpio --version | grep -q "toybox"; then
        find * | cpio -H newc -o --no-preserve-owner --quiet > ${MODULES_STAGING_DIR}/initramfs.cpio
      else
        echo "WARN: Configuration error: using host cpio!"
        find * | cpio -H newc -o -R root:root --quiet > ${MODULES_STAGING_DIR}/initramfs.cpio
      fi
    )
    ${RAMDISK_COMPRESS} ${MODULES_STAGING_DIR}/initramfs.cpio > ${MODULES_STAGING_DIR}/initramfs.cpio.${RAMDISK_EXT}
    mv ${MODULES_STAGING_DIR}/initramfs.cpio.${RAMDISK_EXT} ${DIST_DIR}/initramfs.img
  fi
fi

if [ -n "${VENDOR_DLKM_MODULES_LIST}" ]; then
  build_vendor_dlkm
fi

if [ -n "${UNSTRIPPED_MODULES}" ]; then
  echo "========================================================"
  echo " Copying unstripped module files for debugging purposes (not loaded on device)"
  mkdir -p ${UNSTRIPPED_DIR}
  for MODULE in ${UNSTRIPPED_MODULES}; do
    find ${MODULES_PRIVATE_DIR} -name ${MODULE} -exec cp {} ${UNSTRIPPED_DIR} \;
  done
  if [ "${COMPRESS_UNSTRIPPED_MODULES}" = "1" ]; then
    tar -czf ${DIST_DIR}/${UNSTRIPPED_MODULES_ARCHIVE} -C $(dirname ${UNSTRIPPED_DIR}) $(basename ${UNSTRIPPED_DIR})
    rm -rf ${UNSTRIPPED_DIR}
  fi
fi

[ -n "${GKI_MODULES_LIST}" ] && cp ${KERNEL_DIR}/${GKI_MODULES_LIST} ${DIST_DIR}/

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
  if [ -n "${KERNEL_VENDOR_CMDLINE}" -a "${BOOT_IMAGE_HEADER_VERSION}" -lt "3" ]; then
    KERNEL_CMDLINE+=" ${KERNEL_VENDOR_CMDLINE}"
  fi
  if [ -n "${KERNEL_CMDLINE}" ]; then
    MKBOOTIMG_ARGS+=("--cmdline" "${KERNEL_CMDLINE}")
  fi
  if [ -n "${TAGS_OFFSET}" ]; then
    MKBOOTIMG_ARGS+=("--tags_offset" "${TAGS_OFFSET}")
  fi
  if [ -n "${RAMDISK_OFFSET}" ]; then
    MKBOOTIMG_ARGS+=("--ramdisk_offset" "${RAMDISK_OFFSET}")
  fi

  DTB_FILE_LIST=$(find ${DIST_DIR} -name "*.dtb" | sort)
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

  CPIO_NAME=""
  if [ -n "${VENDOR_RAMDISK_BINARY}" ]; then
    if ! [ -f "${VENDOR_RAMDISK_BINARY}" ]; then
      echo "Unable to locate vendor ramdisk ${VENDOR_RAMDISK_BINARY}."
      exit 1
    fi
    CPIO_NAME="$(mktemp -t build.sh.ramdisk.cpio.XXXXXXXX)"
    if ${DECOMPRESS_GZIP} "${VENDOR_RAMDISK_BINARY}" 2>/dev/null > "${CPIO_NAME}"; then
      echo "${VENDOR_RAMDISK_BINARY} is GZIP compressed"
    elif ${DECOMPRESS_LZ4} "${VENDOR_RAMDISK_BINARY}" 2>/dev/null > "${CPIO_NAME}"; then
      echo "${VENDOR_RAMDISK_BINARY} is LZ4 compressed"
    elif cpio -t < "${VENDOR_RAMDISK_BINARY}" &>/dev/null; then
      echo "${VENDOR_RAMDISK_BINARY} is plain CPIO archive"
      cp -f "${VENDOR_RAMDISK_BINARY}" "${CPIO_NAME}"
    else
      echo "Unable to identify type of vendor ramdisk ${VENDOR_RAMDISK_BINARY}"
      rm -f "${CPIO_NAME}"
      exit 1
    fi
    MKBOOTIMG_RAMDISKS+=("${CPIO_NAME}")

    # Remove lib/modules from the vendor ramdisk binary
    # Also execute ${VENDOR_RAMDISK_CMDS} for further modifications
    RAMDISK_TMP_DIR="$(mktemp -d -t build.sh.ramdisk.XXXXXXXX)"
    (cd "${RAMDISK_TMP_DIR}"
     cpio -idu --quiet -F "${CPIO_NAME}"
     rm -rf lib/modules
     eval ${VENDOR_RAMDISK_CMDS}
     find * | cpio -H newc -o --no-preserve-owner --quiet > "${CPIO_NAME}"
    )
    rm -rf "${RAMDISK_TMP_DIR}"
  fi

  if [ -f "${MODULES_STAGING_DIR}/initramfs.cpio" ]; then
    MKBOOTIMG_RAMDISKS+=("${MODULES_STAGING_DIR}/initramfs.cpio")
  fi

  if [ "${#MKBOOTIMG_RAMDISKS[@]}" -gt 0 ]; then
    cat ${MKBOOTIMG_RAMDISKS[*]} | ${RAMDISK_COMPRESS} - > ${DIST_DIR}/ramdisk.${RAMDISK_EXT}
    [ -n "${CPIO_NAME}" ] && rm -f "${CPIO_NAME}"
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

  if [ "${BOOT_IMAGE_HEADER_VERSION}" -ge "3" ]; then
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

  "$MKBOOTIMG_PATH" --kernel "${DIST_DIR}/${KERNEL_BINARY}" \
    --header_version "${BOOT_IMAGE_HEADER_VERSION}" \
    "${MKBOOTIMG_ARGS[@]}" -o "${DIST_DIR}/boot.img"
  if [ -f "${DIST_DIR}/boot.img" ]; then
    echo "boot image created at ${DIST_DIR}/boot.img"

    if [ -n "${AVB_SIGN_BOOT_IMG}" ]; then
      if [ -n "${AVB_BOOT_PARTITION_SIZE}" ] \
          && [ -n "${AVB_BOOT_KEY}" ] \
          && [ -n "${AVB_BOOT_ALGORITHM}" ]; then
        echo "Signing the boot.img..."
        avbtool add_hash_footer --partition_name boot \
            --partition_size ${AVB_BOOT_PARTITION_SIZE} \
            --image ${DIST_DIR}/boot.img \
            --algorithm ${AVB_BOOT_ALGORITHM} \
            --key ${AVB_BOOT_KEY}
      else
        echo "Missing the AVB_* flags. Failed to sign the boot image" 1>&2
        exit 1
      fi
    fi
  fi

  [ -z "${SKIP_VENDOR_BOOT}" ] \
    && [ "${BOOT_IMAGE_HEADER_VERSION}" -ge "3" ] \
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
