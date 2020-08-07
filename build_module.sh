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

MAKE_GOALS="""
modules
"""

MODULE_CONFIG=${MODULE_CONFIG:-module.config}
if [ -e "${ROOT_DIR}/${MODULE_CONFIG}" ]; then
  source "${ROOT_DIR}/${MODULE_CONFIG}"
fi

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
                      O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} ${MAKE_GOALS}
  make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                      O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}    \
                      INSTALL_MOD_PATH=${MODULES_STAGING_DIR}                \
                      ${MAKE_ARGS} modules_install
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

