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
#   FAST_BUILD
#     If defined, trade run-time optimizations for build speed. In other words,
#     if given a choice between a faster build and a run-time optimization,
#     choose the shorter build time. For example, use ThinLTO for faster
#     linking and reduce the lz4 compression level to speed up ramdisk
#     compression. This trade-off is desirable for incremental kernel
#     development where fast turnaround times are critical for productivity.
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
#   EXT_MODULES_MAKEFILE
#     Location of a makefile to build external modules. If set, it will get
#     called with all the necessary parameters to build and install external
#     modules.  This allows for building them in parallel using makefile
#     parallelization.
#
#   KCONFIG_EXT_PREFIX
#     Path prefix relative to either ROOT_DIR or KERNEL_DIR that points to
#     a directory containing an external Kconfig file named Kconfig.ext. When
#     set, kbuild will source ${KCONFIG_EXT_PREFIX}Kconfig.ext which can be
#     used to set configs for external modules in the defconfig.
#
#   UNSTRIPPED_MODULES
#     Space separated list of modules to be copied to <DIST_DIR>/unstripped
#     for debugging purposes.
#
#   COMPRESS_UNSTRIPPED_MODULES
#     If set to "1", then compress the unstripped modules into a tarball.
#
#   COMPRESS_MODULES
#     If set to "1", then compress all modules into a tarball. The default
#     is without defining COMPRESS_MODULES.
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
#     - VENDOR_RAMDISK_BINARY=<Space separated list of vendor ramdisk binaries
#        which includes the device-specific components of ramdisk like the fstab
#        file and the device-specific rc files. If specifying multiple vendor ramdisks
#        and identical file paths exist in the ramdisks, the file from last ramdisk is used.>
#     - KERNEL_BINARY=<name of kernel binary, eg. Image.lz4, Image.gz etc>
#     - BOOT_IMAGE_HEADER_VERSION=<version of the boot image header>
#       (defaults to 3)
#     - BOOT_IMAGE_FILENAME=<name of the output file>
#       (defaults to "boot.img")
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
#     If BOOT_IMAGE_HEADER_VERSION >= 3, a vendor_boot image will be built
#     unless SKIP_VENDOR_BOOT is defined. A vendor_boot will also be generated if
#     BUILD_VENDOR_BOOT_IMG is set.
#
#     BUILD_VENDOR_BOOT_IMG is incompatible with SKIP_VENDOR_BOOT, and is effectively a
#     nop if BUILD_BOOT_IMG is set.
#     - MODULES_LIST=<file to list of modules> list of modules to use for
#       vendor_boot.modules.load. If this property is not set, then the default
#       modules.load is used.
#     - TRIM_UNUSED_MODULES. If set, then modules not mentioned in
#       modules.load are removed from initramfs. If MODULES_LIST is unset, then
#       having this variable set effectively becomes a no-op.
#     - MODULES_BLOCKLIST=<modules.blocklist file> A list of modules which are
#       blocked from being loaded. This file is copied directly to staging directory,
#       and should be in the format:
#       blocklist module_name
#     - MKBOOTIMG_EXTRA_ARGS=<space-delimited mkbootimg arguments>
#       Refer to: ./mkbootimg.py --help
#     If BOOT_IMAGE_HEADER_VERSION >= 4, the following variable can be defined:
#     - VENDOR_BOOTCONFIG=<string of bootconfig parameters>
#     - INITRAMFS_VENDOR_RAMDISK_FRAGMENT_NAME=<name of the ramdisk fragment>
#       If BUILD_INITRAMFS is specified, then build the .ko and depmod files as
#       a standalone vendor ramdisk fragment named as the given string.
#     - INITRAMFS_VENDOR_RAMDISK_FRAGMENT_MKBOOTIMG_ARGS=<mkbootimg arguments>
#       Refer to: https://source.android.com/devices/bootloader/partitions/vendor-boot-partitions#mkbootimg-arguments
#
#   VENDOR_RAMDISK_CMDS
#     When building vendor boot image, VENDOR_RAMDISK_CMDS enables the build
#     config file to specify command(s) for further altering the prebuilt vendor
#     ramdisk binary. For example, the build config file could add firmware files
#     on the vendor ramdisk (lib/firmware) for testing purposes.
#
#   SKIP_UNPACKING_RAMDISK
#     If set, skip unpacking the vendor ramdisk and copy it as is, without
#     modifications, into the boot image. Also skip the mkbootfs step.
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
#     - AVB_BOOT_PARTITION_NAME=<name of the boot partition>
#       (defaults to BOOT_IMAGE_FILENAME without extension; by default, "boot")
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
#     vendor_dlkm partition image. Any modules passed into MODULES_LIST which
#     become part of the vendor_boot.modules.load will be trimmed from the
#     vendor_dlkm.modules.load.
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
#   LZ4_RAMDISK_COMPRESS_ARGS
#     Command line arguments passed to lz4 command to control compression
#     level (defaults to "-12 --favor-decSpeed"). For iterative kernel
#     development where faster compression is more desirable than a high
#     compression ratio, it can be useful to control the compression ratio.
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
#     This is incompatible with GKI_PREBUILTS_DIR.
#
#   GKI_PREBUILTS_DIR
#     If set, copies an existing set of GKI kernel binaries to the DIST_DIR to
#     perform a "mixed build," as with GKI_BUILD_CONFIG. This allows you to
#     skip the additional compilation, if interested.
#
#     This is incompatible with GKI_BUILD_CONFIG.
#
#     The following must be present:
#       vmlinux
#       System.map
#       vmlinux.symvers
#       modules.builtin
#       modules.builtin.modinfo
#       Image.lz4
#
#   BUILD_DTBO_IMG
#     if defined, package a dtbo.img using the provided *.dtbo files. The image
#     will be created under the DIST_DIR.
#
#     The following flags control how the dtbo image is packaged.
#     MKDTIMG_DTBOS=<list of *.dtbo files> used to package the dtbo.img. The
#     *.dtbo files should be compiled by kbuild via the "make dtbs" command or
#     by adding each *.dtbo to the MAKE_GOALS.
#     MKDTIMG_FLAGS=<list of flags> to be passed to mkdtimg.
#
#   DTS_EXT_DIR
#     Set this variable to compile an out-of-tree device tree. The value of
#     this variable is set to the kbuild variable "dtstree" which is used to
#     compile the device tree. If this is set, then it's likely the dt-bindings
#     are out-of-tree as well. So be sure to set DTC_INCLUDE in the
#     BUILD_CONFIG file to the include path containing the dt-bindings.
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

export ROOT_DIR=$(readlink -f $(dirname $0)/..)
source "${ROOT_DIR}/build/build_utils.sh"
source "${ROOT_DIR}/build/_setup_env.sh"

MAKE_ARGS=( "$@" )
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export KERNEL_UAPI_HEADERS_DIR=$(readlink -m ${COMMON_OUT_DIR}/kernel_uapi_headers)
export INITRAMFS_STAGING_DIR=${MODULES_STAGING_DIR}/initramfs_staging
export VENDOR_DLKM_STAGING_DIR=${MODULES_STAGING_DIR}/vendor_dlkm_staging
export MKBOOTIMG_STAGING_DIR="${MODULES_STAGING_DIR}/mkbootimg_staging"

if [ -n "${SKIP_VENDOR_BOOT}" -a -n "${BUILD_VENDOR_BOOT_IMG}" ]; then
  echo "ERROR: SKIP_VENDOR_BOOT is incompatible with BUILD_VENDOR_BOOT_IMG." >&2
  exit 1
fi

if [ -n "${GKI_BUILD_CONFIG}" ]; then
  if [ -n "${GKI_PREBUILTS_DIR}" ]; then
      echo "ERROR: GKI_BUILD_CONFIG is incompatible with GKI_PREBUILTS_DIR." >&2
      exit 1
  fi

  GKI_OUT_DIR=${GKI_OUT_DIR:-${COMMON_OUT_DIR}/gki_kernel}
  GKI_DIST_DIR=${GKI_DIST_DIR:-${GKI_OUT_DIR}/dist}

  if [[ "${MAKE_GOALS}" =~ image|Image|vmlinux ]]; then
    echo " Compiling Image and vmlinux in device kernel is not supported in mixed build mode"
    exit 1
  fi

  # Inherit SKIP_MRPROPER, LTO, SKIP_DEFCONFIG unless overridden by corresponding GKI_* variables
  GKI_ENVIRON=("SKIP_MRPROPER=${SKIP_MRPROPER}" "LTO=${LTO}" "SKIP_DEFCONFIG=${SKIP_DEFCONFIG}" "SKIP_IF_VERSION_MATCHES=${SKIP_IF_VERSION_MATCHES}")
  # Explicitly unset EXT_MODULES since they should be compiled against the device kernel
  GKI_ENVIRON+=("EXT_MODULES=")
  # Explicitly unset GKI_BUILD_CONFIG in case it was set by in the old environment
  # e.g. GKI_BUILD_CONFIG=common/build.config.gki.x86 ./build/build.sh would cause
  # gki build recursively
  GKI_ENVIRON+=("GKI_BUILD_CONFIG=")
  # Explicitly unset KCONFIG_EXT_PREFIX in case it was set by the older environment.
  GKI_ENVIRON+=("KCONFIG_EXT_PREFIX=")
  # Any variables prefixed with GKI_ get set without that prefix in the GKI build environment
  # e.g. GKI_BUILD_CONFIG=common/build.config.gki.aarch64 -> BUILD_CONFIG=common/build.config.gki.aarch64
  GKI_ENVIRON+=($(export -p | sed -n -E -e 's/.* GKI_([^=]+=.*)$/\1/p' | tr '\n' ' '))
  GKI_ENVIRON+=("OUT_DIR=${GKI_OUT_DIR}")
  GKI_ENVIRON+=("DIST_DIR=${GKI_DIST_DIR}")
  ( env -i bash -c "source ${OLD_ENVIRONMENT}; rm -f ${OLD_ENVIRONMENT}; export ${GKI_ENVIRON[*]} ; ./build/build.sh" ) || exit 1

  # Dist dir must have vmlinux.symvers, modules.builtin.modinfo, modules.builtin
  MAKE_ARGS+=("KBUILD_MIXED_TREE=$(readlink -m ${GKI_DIST_DIR})")
else
  rm -f ${OLD_ENVIRONMENT}
fi

if [ -n "${KCONFIG_EXT_PREFIX}" ]; then
  # Since this is a prefix, make sure it ends with "/"
  if [[ ! "${KCONFIG_EXT_PREFIX}" =~ \/$ ]]; then
    KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}/
  fi

  # KCONFIG_EXT_PREFIX needs to be relative to KERNEL_DIR but we allow one to set
  # it relative to ROOT_DIR for ease of use. So figure out what was used.
  if [ -f "${ROOT_DIR}/${KCONFIG_EXT_PREFIX}Kconfig.ext" ]; then
    # KCONFIG_EXT_PREFIX is currently relative to ROOT_DIR. So recalcuate it to be
    # relative to KERNEL_DIR
    KCONFIG_EXT_PREFIX=$(rel_path ${ROOT_DIR}/${KCONFIG_EXT_PREFIX} ${KERNEL_DIR})
  elif [ ! -f "${KERNEL_DIR}/${KCONFIG_EXT_PREFIX}Kconfig.ext" ]; then
    echo "Couldn't find the Kconfig.ext in ${KCONFIG_EXT_PREFIX}" >&2
    exit 1
  fi

  # Since this is a prefix, make sure it ends with "/"
  if [[ ! "${KCONFIG_EXT_PREFIX}" =~ \/$ ]]; then
    KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}/
  fi
  MAKE_ARGS+=("KCONFIG_EXT_PREFIX=${KCONFIG_EXT_PREFIX}")
fi

if [ -n "${DTS_EXT_DIR}" ]; then
  if [[ "${MAKE_GOALS}" =~ dtbs|\.dtb|\.dtbo ]]; then
    # DTS_EXT_DIR needs to be relative to KERNEL_DIR but we allow one to set
    # it relative to ROOT_DIR for ease of use. So figure out what was used.
    if [ -d "${ROOT_DIR}/${DTS_EXT_DIR}" ]; then
      # DTS_EXT_DIR is currently relative to ROOT_DIR. So recalcuate it to be
      # relative to KERNEL_DIR
      DTS_EXT_DIR=$(rel_path ${ROOT_DIR}/${DTS_EXT_DIR} ${KERNEL_DIR})
    elif [ ! -d "${KERNEL_DIR}/${DTS_EXT_DIR}" ]; then
      echo "Couldn't find the dtstree -- ${DTS_EXT_DIR}" >&2
      exit 1
    fi
    MAKE_ARGS+=("dtstree=${DTS_EXT_DIR}")
  fi
fi

cd ${ROOT_DIR}

if [ -n "${SKIP_IF_VERSION_MATCHES}" ]; then
  if [ -f "${DIST_DIR}/vmlinux" ]; then
    kernelversion="$(cd ${KERNEL_DIR} && make -s ${TOOL_ARGS} O=${OUT_DIR} kernelrelease)"
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

if [ -n "${GKI_PREBUILTS_DIR}" ]; then
  echo "========================================================"
  echo " Copying GKI prebuilts"
  GKI_PREBUILTS_DIR=$(readlink -m ${GKI_PREBUILTS_DIR})
  if [ ! -d "${GKI_PREBUILTS_DIR}" ]; then
    echo "ERROR: ${GKI_PREBULTS_DIR} does not exist." >&2
    exit 1
  fi
  for file in ${GKI_PREBUILTS_DIR}/*; do
    filename=$(basename ${file})
    if ! $(cmp -s ${file} ${DIST_DIR}/${filename}); then
      cp -v ${file} ${DIST_DIR}/${filename}
    fi
  done
  MAKE_ARGS+=("KBUILD_MIXED_TREE=${GKI_PREBUILTS_DIR}")
fi

echo "========================================================"
echo " Setting up for build"
if [ "${SKIP_MRPROPER}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make ${TOOL_ARGS} O=${OUT_DIR} "${MAKE_ARGS[@]}" mrproper)
  set +x
fi

if [ -n "${PRE_DEFCONFIG_CMDS}" ]; then
  echo "========================================================"
  echo " Running pre-defconfig command(s):"
  set -x
  eval ${PRE_DEFCONFIG_CMDS}
  set +x
fi

if [ "${SKIP_DEFCONFIG}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make ${TOOL_ARGS} O=${OUT_DIR} "${MAKE_ARGS[@]}" ${DEFCONFIG})
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
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -d LTO_CLANG \
      -e LTO_NONE \
      -d LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -d THINLTO
  elif [ "${LTO}" = "thin" ]; then
    # This is best-effort; some kernels don't support LTO_THIN mode
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -e LTO_CLANG \
      -d LTO_NONE \
      -e LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -e THINLTO
  elif [ "${LTO}" = "full" ]; then
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -e LTO_CLANG \
      -d LTO_NONE \
      -d LTO_CLANG_THIN \
      -e LTO_CLANG_FULL \
      -d THINLTO
  fi
  (cd ${OUT_DIR} && make ${TOOL_ARGS} O=${OUT_DIR} "${MAKE_ARGS[@]}" olddefconfig)
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
  ${ROOT_DIR}/build/abi/process_symbols --out-dir="$DIST_DIR" --out-file=abi_symbollist \
    --report-file=abi_symbollist.report --in-dir="$ROOT_DIR/$KERNEL_DIR" \
    "${KMI_SYMBOL_LIST}" ${ADDITIONAL_KMI_SYMBOL_LISTS}
  pushd $ROOT_DIR/$KERNEL_DIR
  if [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
      # Create the raw symbol list
      cat ${ABI_SL} | \
              ${ROOT_DIR}/build/abi/flatten_symbol_list > \
              ${OUT_DIR}/abi_symbollist.raw

      # Update the kernel configuration
      ./scripts/config --file ${OUT_DIR}/.config \
              -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
              --set-str UNUSED_KSYMS_WHITELIST ${OUT_DIR}/abi_symbollist.raw
      (cd ${OUT_DIR} && \
              make O=${OUT_DIR} ${TOOL_ARGS} "${MAKE_ARGS[@]}" olddefconfig)
      # Make sure the config is applied
      grep CONFIG_UNUSED_KSYMS_WHITELIST ${OUT_DIR}/.config > /dev/null || {
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

echo "========================================================"
echo " Building kernel"

set -x
(cd ${OUT_DIR} && make O=${OUT_DIR} ${TOOL_ARGS} "${MAKE_ARGS[@]}" ${MAKE_GOALS})
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
   make O=${OUT_DIR} ${TOOL_ARGS} ${MODULE_STRIP_FLAG}                        \
        INSTALL_MOD_PATH=${MODULES_STAGING_DIR} "${MAKE_ARGS[@]}" modules_install)
fi

if [[ -z "${SKIP_EXT_MODULES}" ]] && [[ -n "${EXT_MODULES_MAKEFILE}" ]]; then
  echo "========================================================"
  echo " Building and installing external modules using ${EXT_MODULES_MAKEFILE}"

  make -f "${EXT_MODULES_MAKEFILE}" KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR} \
          O=${OUT_DIR} ${TOOL_ARGS} ${MODULE_STRIP_FLAG}                 \
          INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr"              \
          INSTALL_MOD_PATH=${MODULES_STAGING_DIR} "${MAKE_ARGS[@]}"
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
                       O=${OUT_DIR} ${TOOL_ARGS} "${MAKE_ARGS[@]}"
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                       O=${OUT_DIR} ${TOOL_ARGS} ${MODULE_STRIP_FLAG}         \
                       INSTALL_MOD_PATH=${MODULES_STAGING_DIR}                \
                       INSTALL_MOD_DIR="extra/${EXT_MOD}"                     \
                       INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr"      \
                       "${MAKE_ARGS[@]}" modules_install
    set +x
  done

fi

echo "========================================================"
echo " Generating test_mappings.zip"
TEST_MAPPING_FILES=${OUT_DIR}/test_mapping_files.txt
find ${ROOT_DIR} -name TEST_MAPPING \
  -not -path "${ROOT_DIR}/\.git*" \
  -not -path "${ROOT_DIR}/\.repo*" \
  -not -path "${ROOT_DIR}/out*" \
  > ${TEST_MAPPING_FILES}
soong_zip -o ${DIST_DIR}/test_mappings.zip -C ${ROOT_DIR} -l ${TEST_MAPPING_FILES}

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
  make -C ${OUT_DIR} O=${OUT_DIR} ${TOOL_ARGS}                                \
          INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr" "${MAKE_ARGS[@]}" \
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
  if [ -n "${IN_KERNEL_MODULES}" -o -n "${EXT_MODULES}" -o -n "${EXT_MODULES_MAKEFILE}" ]; then
    echo "========================================================"
    echo " Copying modules files"
    cp -p ${MODULES} ${DIST_DIR}
    if [ "${COMPRESS_MODULES}" = "1" ]; then
      echo " Archiving modules to ${MODULES_ARCHIVE}"
      tar --transform="s,.*/,," -czf ${DIST_DIR}/${MODULES_ARCHIVE} ${MODULES[@]}
    fi
  fi
  if [ "${BUILD_INITRAMFS}" = "1" ]; then
    echo "========================================================"
    echo " Creating initramfs"
    rm -rf ${INITRAMFS_STAGING_DIR}
    create_modules_staging "${MODULES_LIST}" ${MODULES_STAGING_DIR} \
      ${INITRAMFS_STAGING_DIR} "${MODULES_BLOCKLIST}" "-e"

    MODULES_ROOT_DIR=$(echo ${INITRAMFS_STAGING_DIR}/lib/modules/*)
    cp ${MODULES_ROOT_DIR}/modules.load ${DIST_DIR}/modules.load
    cp ${MODULES_ROOT_DIR}/modules.load ${DIST_DIR}/vendor_boot.modules.load
    echo "${MODULES_OPTIONS}" > ${MODULES_ROOT_DIR}/modules.options

    mkbootfs "${INITRAMFS_STAGING_DIR}" >"${MODULES_STAGING_DIR}/initramfs.cpio"
    ${RAMDISK_COMPRESS} "${MODULES_STAGING_DIR}/initramfs.cpio" >"${DIST_DIR}/initramfs.img"
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

if [ -n "${BUILD_BOOT_IMG}" -o -n "${BUILD_VENDOR_BOOT_IMG}" ] ; then
  build_boot_images
fi

if [ -n "${BUILD_DTBO_IMG}" ]; then
  make_dtbo
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
