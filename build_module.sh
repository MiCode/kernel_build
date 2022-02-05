#!/bin/bash
# Copyright (c) 2020, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
#     * Neither the name of The Linux Foundation nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT
# ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Usage:
#   build/build_module.sh <make options>*
# or:
#   OUT_DIR=<out dir> DIST_DIR=<dist dir> build/build_module.sh <make options>*
#
# Example:
#   OUT_DIR=output DIST_DIR=dist build/build_module.sh -j24 V=1#
#
# The following environment variables are considered during execution:
#
#   BUILD_CONFIG
#     Build config file to initialize the build environment from. The location
#     is to be defined relative to the repo root directory.
#     Defaults to 'build.config'.
#
#   MODULE_CONFIG
#     Build config file for module to initialize the build environment from.
#     The location is to be defined relative to the repo root directory.
#     Defaults to 'module.config'.
#
#   EXT_MODULES
#     Space separated list of external kernel modules to be build.
#
#   UNSTRIPPED_MODULES
#     Space separated list of modules to be copied to <DIST_DIR>/unstripped
#     for debugging purposes.
#
#   MODULE_OUT
#     Location to place compiled module output. When this option is specified,
#     Only one EXT_MODULES may be specified. A symlink is created from the
#     output Kbuild will use to MODULE_OUT.
#
# Environment variables to influence the stages of the kernel build.
#
#   SKIP_MRPROPER
#     if defined, skip `make mrproper`
#
#   INSTALL_MODULE_HEADERS
#     if defined, install uapi headers from the module.
#
#   BUILD_DTBS
#     if defined, install uapi headers from the module.

set -e

# rel_path <to> <from>
# Generate relative directory path to reach directory <to> from <from>
function rel_path() {
  python -c "import os.path; import sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

source "${ROOT_DIR}/build/_setup_env.sh"

export MAKE_ARGS="$* ${KBUILD_OPTIONS}"
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export MODULE_UAPI_HEADERS_DIR=$(readlink -m ${COMMON_OUT_DIR}/module_uapi_headers)

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

MODULE_CONFIG=${MODULE_CONFIG:-module.config}
if [ -e "${ROOT_DIR}/${MODULE_CONFIG}" ]; then
  source "${ROOT_DIR}/${MODULE_CONFIG}"
fi


# KERNEL_KIT should be explicitly defined, but default it to something sensible
KERNEL_KIT="${KERNEL_KIT:-${COMMON_OUT_DIR}}"
HOST_DIR="${KERNEL_KIT}/host"

if [ ! -e "${KERNEL_KIT}/.config" ]; then
  # Try a couple reasonable/reliable fallback locations
  if [ -e "${KERNEL_KIT}/dist/.config" ]; then
    HOST_DIR="${KERNEL_KIT}/host"
    KERNEL_KIT="${KERNEL_KIT}/dist"
  elif [ -e "${KERNEL_KIT}/${KERNEL_DIR}/.config" ]; then
    HOST_DIR="${KERNEL_KIT}/host"
    KERNEL_KIT="${KERNEL_KIT}/${KERNEL_DIR}"
  fi
fi
if [ ! -e "${KERNEL_KIT}/.config" ]; then
  echo "ERROR! Could not find prebuilt kernel artifacts in ${KERNEL_KIT}"
  exit 1
fi


if [ ! -e "${OUT_DIR}/Makefile" -o -z "${EXT_MODULES}" ]; then
  echo "========================================================"
  echo " Prepare to compile modules from ${KERNEL_KIT}"

  set -x
  mkdir -p ${OUT_DIR}/
  cp ${KERNEL_KIT}/.config ${KERNEL_KIT}/Module.symvers ${OUT_DIR}/

  if [ -z "${EXT_MODULES}" -a ! ${HOST_DIR} -ef ${COMMON_OUT_DIR}/host ]; then
    rm -rf ${COMMON_OUT_DIR}/host
  fi
  if [ -e ${HOST_DIR} -a ! -e ${COMMON_OUT_DIR}/host ]; then
    cp -r ${HOST_DIR} ${COMMON_OUT_DIR}
  fi

  # Install .config from kernel platform
  (
    cd "${KERNEL_DIR}"
    make O="${OUT_DIR}" "${TOOL_ARGS[@]}" ${MAKE_ARGS} olddefconfig
  )
  set +x

  GENERATED_CONFIG=$(mktemp)
  cp ${OUT_DIR}/.config ${GENERATED_CONFIG}

  # To guard against .config silently diverging from the one kernel platform created,
  # set KCONFIG_NOSILENTUPDATE=1. If doing an incremental build, this also guards against
  # the kernel platform .config changing since autoconf.h and related files would need an update
  # in OUT_DIR. To get around this valid change, do "make olddefconfig", copy the .config again,
  # then do the NOSILENTUPDATE check
  cp ${KERNEL_KIT}/.config ${OUT_DIR}/

  if ! KCONFIG_NOSILENTUPDATE=1 make -C "${KERNEL_DIR}" O="${OUT_DIR}" "${TOOL_ARGS[@]}" \
      ${MAKE_ARGS} modules_prepare ; then
    if [ -n "$(${ROOT_DIR}/${KERNEL_DIR}/scripts/diffconfig ${KERNEL_KIT}/.config ${GENERATED_CONFIG})" ]; then
      echo "ERROR! Current kernel platform sources did not generate expected .config"
      echo "Possibly kernel sources do not match those which generated kernel output?"
      echo "Kernel platform sources differ from the prebuilt .config:"
      ${ROOT_DIR}/${KERNEL_DIR}/scripts/diffconfig ${KERNEL_KIT}/.config ${GENERATED_CONFIG}
    fi
    rm ${GENERATED_CONFIG}
    exit 1
  fi
  rm ${GENERATED_CONFIG}
fi
# Set KBUILD_MIXED_TREE in case an out-of-tree Makefile does "make all". This causes
# kbuild to also want to compile vmlinux
MAKE_ARGS+=" KBUILD_MIXED_TREE=${KERNEL_KIT}"

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
  set -x
  if [ -n "${MODULE_OUT}" ]; then
    mkdir -p $(dirname ${OUT_DIR}/${EXT_MOD_REL})
    mkdir -p ${MODULE_OUT}
    rm -rf ${OUT_DIR}/${EXT_MOD_REL}
    ln -srT ${MODULE_OUT} ${OUT_DIR}/${EXT_MOD_REL}
  else
    mkdir -p ${OUT_DIR}/${EXT_MOD_REL}
  fi
  make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                      O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS}
  if [ -n "${INSTALL_MODULE_HEADERS}" ]; then
    echo "========================================================"
    echo " Installing UAPI module headers:"
    mkdir -p "${KERNEL_UAPI_HEADERS_DIR}/usr"
    make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                      O=${OUT_DIR} "${TOOL_ARGS[@]}"                         \
                      INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr"      \
                      ${MAKE_ARGS} headers_install
  fi
  set +x
done

