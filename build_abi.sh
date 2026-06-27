#!/bin/bash

# Copyright (C) 2019-2022 The Android Open Source Project
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
#   build/build_abi.sh
#
# The following environment variables are considered during execution:
#
#   ABI_OUT_TAG
#     Customize the output file name for the abi dump. If undefined, the tag is
#     derived from `git describe`.
#
#   ABI_DEFINITION
#     Specify an expected Kernel ABI representation. If defined, this script
#     will, in addition to extracting the ABI representation from the currently
#     built kernel, compare the extracted ABI to the expected one. In case of
#     any significant differences, it will exit with the return code of
#     diff_abi.
#     ABI_DEFINITION is supposed to be defined relative to $KERNEL_DIR/
#
#   KMI_SYMBOL_LIST
#     Define a Kernel Module Interface symbol list description. If defined, it
#     will be taken into account when extracting Kernel ABI information from
#     vmlinux and kernel modules.
#     KMI_SYMBOL_LIST is supposed to be defined relative to $KERNEL_DIR/
#
#   KMI_SYMBOL_LIST_MODULE_GROUPING
#     If set to 1, then the symbol list will group symbols based on the kernel
#     modules that reference the symbol. Otherwise the symbol list will simply
#     be a sorted list of symbols used by all the kernel modules. This property
#     is enabled by default.
#
#   KMI_SYMBOL_LIST_ADD_ONLY
#     If set to 1, then any symbols in the symbol list that would have been
#     removed are preserved (at the end of the file). Symbol list update will
#     fail if there is no pre-existing symbol list file to read from. This
#     property is intended to prevent unintentional shrinkage of a stable ABI.
#     It is disabled by default.
#
#   GKI_MODULES_LIST
#     If set to a file name, then this file will be read to determine the list
#     of GKI modules (those subject to ABI monitoring) and, by elimination, the
#     list of vendor modules (those which can rely on a stable ABI). Only vendor
#     modules' undefined symbols are considered when updating the symbol list.
#     GKI_MODULES_LIST is supposed to be defined relative to $KERNEL_DIR/
#
#   FULL_GKI_ABI
#     If this is set to 1 then, when updating the symbol list, use all defined
#     symbols from vmlinux and GKI modules, instead of the undefined symbols
#     from vendor modules. This property is disabled by default.

export ROOT_DIR=$($(dirname $(readlink -f $0))/gettop.sh)

function show_help {
    echo "USAGE: $0 [-u|--update] [-n|--nodiff]"
    echo
    echo "  -u | --update                Update ABI representation and main symbol list in the source directory"
    echo "  -s | --update-symbol-list    Update main symbol list in the source directory"
    echo "  -n | --nodiff                Do not generate an ABI report with diff_abi"
}

UPDATE=0
UPDATE_SYMBOL_LIST=0
DIFF=1

if [[ -z "${KMI_SYMBOL_LIST_MODULE_GROUPING}" ]]; then
  KMI_SYMBOL_LIST_MODULE_GROUPING=1
fi
if [[ -z "$KMI_SYMBOL_LIST_ADD_ONLY" ]]; then
  KMI_SYMBOL_LIST_ADD_ONLY=0
fi
if [[ -z "$FULL_GKI_ABI" ]]; then
  FULL_GKI_ABI=0
fi

ARGS=()
for i in "$@"
do
case $i in
    -u|--update)
    UPDATE=1
    shift # past argument=value
    ;;
    -s|--update-symbol-list)
    UPDATE_SYMBOL_LIST=1
    shift # past argument=value
    ;;
    -n|--nodiff)
    DIFF=0
    shift # past argument=value
    ;;
    -r|--print-report)
    # ignored
    shift # past argument=value
    ;;
    -a|--full-report)
    # ignored
    shift # past argument=value
    ;;
    -h|--help)
    show_help
    exit 0
    ;;
    *)
    ARGS+=("$1")
    shift
    ;;
esac
done

(
    [[ "$KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING" == "1" ]] && exit 0 || true
    echo     "Inferring equivalent Bazel command..."
    bazel_command_code=0
    eq_bazel_command=$(
        export UPDATE
        export UPDATE_SYMBOL_LIST
        export DIFF
        ${ROOT_DIR}/build/kernel/kleaf/convert_to_bazel.sh --abi # error messages goes to stderr
    ) || bazel_command_code=$?
    echo     "*******************************************************************************" >&2
    echo     "* WARNING: build_abi.sh is deprecated for this branch. Please migrate to Bazel." >&2
    echo     "*   See build/kernel/kleaf/README.md                                           " >&2
    if [[ $bazel_command_code -eq 0 ]]; then
        echo "*          Possibly equivalent Bazel command:                                  " >&2
        echo "*" >&2
        echo "*   \$ $eq_bazel_command" >&2
        echo "*" >&2
    else
        echo "WARNING: Unable to infer an equivalent Bazel command." >&2
    fi
    echo     "* To suppress this warning, set KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1  " >&2
    echo     "*******************************************************************************" >&2
    echo >&2
)
export KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1

set -- "${ARGS[@]}"

set -e
set -a

# if we are using the default OUT_DIR, add a suffix so we are free to wipe it
# before building to ensure a clean build/analysis. That is the default case.
if [[ -z "$OUT_DIR" ]]; then
    export OUT_DIR_SUFFIX="_abi"
    wipe_out_dir=1
fi

source "${ROOT_DIR}/build/build_utils.sh"
source "${ROOT_DIR}/build/_setup_env.sh"

if [ -z "${KMI_SYMBOL_LIST}" ]; then
    if [ $UPDATE_SYMBOL_LIST -eq 1 ]; then
        echo "ERROR: --update-symbol-list requires a KMI_SYMBOL_LIST" >&2
        exit 1
    fi
elif [ $UPDATE -eq 1 ]; then
    UPDATE_SYMBOL_LIST=1
fi

# Now actually do the wipe out as above.
if [[ $wipe_out_dir -eq 1 && -d ${COMMON_OUT_DIR} ]]; then
    find "${COMMON_OUT_DIR}" \( -name 'vmlinux' -o -name '*.ko' \) -delete -print
fi

# assert CONFIG_DEBUG_INFO=y
append_cmd POST_DEFCONFIG_CMDS 'check_config_for_abi_dump'
export POST_DEFCONFIG_CMDS
function check_config_for_abi_dump() {
    local debug=$(${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config -s DEBUG_INFO)
    if [ "$debug" != y ]; then
        echo "ERROR: DEBUG_INFO is not set in config" >&2
        exit 1
    fi
}
export -f check_config_for_abi_dump

if [ -n "${GKI_BUILD_CONFIG}" ]; then
  # Disable mixed build when comparing ABI snapshots. Device kernel ABI should compared, even in a
  # mixed build environment.
  GKI_BUILD_CONFIG=
  # Mixed build device kernels would not compile vmlinux. When using build_abi.sh to compile, we
  # do want to compile vmlinux since we are comparing the ABI of the device kernel.
  MAKE_GOALS+=" vmlinux ${KERNEL_BINARY}"
  FILES+="
  System.map
  vmlinux
  vmlinux.symvers
  modules.builtin
  modules.builtin.modinfo
  "
fi

function build_kernel() {
  # Delegate the actual build to build.sh.
  # Suppress possible values of ABI_DEFINITION when invoking build.sh to avoid
  # the generated abi.xml to be copied to <DIST_DIR>/abi.out.
  # Turn on symtypes generation to assist in the diagnosis of CRC differences.
  ABI_DEFINITION= \
    KBUILD_SYMTYPES=1 \
    ${ROOT_DIR}/build/build.sh "$@"
}

# define a common KMI symbol list flag for the abi tools
KMI_SYMBOL_LIST_FLAG=

# We want to track whether the main symbol list (i.e. KMI_SYMBOL_LIST) actually
# got updated. If so we need to rerun the kernel build.
if [ -n "$KMI_SYMBOL_LIST" ]; then

    if [ $UPDATE_SYMBOL_LIST -eq 1 ]; then
        # Disable KMI trimming as the symbol list may be out of date.
        TRIM_NONLISTED_KMI= KMI_SYMBOL_LIST_STRICT_MODE= build_kernel "$@"

        echo "========================================================"
        echo " Updating the ABI symbol list"

        # Exclude GKI modules from non-GKI builds
        if [ -n "${GKI_MODULES_LIST}" ]; then
            GKI_MOD_FLAG="--gki-modules ${DIST_DIR}/$(basename ${GKI_MODULES_LIST})"
        fi
        if [ "$KMI_SYMBOL_LIST_ADD_ONLY" -eq 1 ]; then
            ADD_ONLY_FLAG="--additions-only"
        fi
        # Specify a full GKI ABI if requested
        if [ "$FULL_GKI_ABI" -eq 1 ]; then
            FULL_ABI_FLAG="--full-gki-abi"
        fi

        if [ "${KMI_SYMBOL_LIST_MODULE_GROUPING}" -eq "0" ]; then
          SKIP_MODULE_GROUPING="--skip-module-grouping"
        fi

        ${ROOT_DIR}/build/abi/extract_symbols          \
            --symbol-list $KERNEL_DIR/$KMI_SYMBOL_LIST \
            ${SKIP_MODULE_GROUPING}                    \
            ${ADD_ONLY_FLAG}                           \
            ${GKI_MOD_FLAG}                            \
            ${FULL_ABI_FLAG}                           \
            ${DIST_DIR}

        # Redo what build.sh has done, with possibly fresher symbol lists.
        ${ROOT_DIR}/build/abi/process_symbols --out-dir="$DIST_DIR" --out-file=abi_symbollist \
          --report-file=abi_symbollist.report --in-dir="$ROOT_DIR/$KERNEL_DIR" \
          "${KMI_SYMBOL_LIST}" ${ADDITIONAL_KMI_SYMBOL_LISTS}

        # In case of a simple --update-symbol-list call we can bail out early
        [ $UPDATE -eq 0 ] && exit 0

        if [ "${TRIM_NONLISTED_KMI:-0}" = "1" ]; then
            # Rerun the kernel build with symbol list trimming enabled, as applicable. That
            # influences the combined symbol list as well as the list of exported symbols in
            # the kernel binary. Possibly more.
            echo "========================================================"
            echo " Rerunning the build with symbol trimming re-enabled"
            SKIP_MRPROPER=1
        fi
    fi

    KMI_SYMBOL_LIST_FLAG="--kmi-symbol-list ${DIST_DIR}/abi_symbollist"

fi

# Already built the final kernel if updating symbol list and trimming symbol list is disabled
if ! [ $UPDATE_SYMBOL_LIST -eq 1 -a ! "${TRIM_NONLISTED_KMI:-0}" = "1" -a "$FULL_GKI_ABI" -eq 0 ]; then
    SKIP_MRPROPER="${SKIP_MRPROPER}" build_kernel "$@"
fi

echo "========================================================"
echo " Creating ABI dump"

ABI_LINUX_TREE=${DIST_DIR}
ABI_VMLINUX_PATH=
DELETE_UNSTRIPPED_MODULES=
if [ -z "${DO_NOT_STRIP_MODULES}" ] && [ $(echo "${UNSTRIPPED_MODULES}" | tr -d '\n') = "*.ko" ]; then
  if [ -n "${COMPRESS_UNSTRIPPED_MODULES}" ] && [ ! -f "${UNSTRIPPED_DIR}" ]; then
    tar -xzf ${DIST_DIR}/${UNSTRIPPED_MODULES_ARCHIVE} -C $(dirname ${UNSTRIPPED_DIR})
    DELETE_UNSTRIPPED_MODULES=1
  fi
  ABI_LINUX_TREE=${UNSTRIPPED_DIR}
  ABI_VMLINUX_PATH="--vmlinux ${DIST_DIR}/vmlinux"
fi

# create abi dump
COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out/${BRANCH}})
id=${ABI_OUT_TAG:-$(git -C $KERNEL_DIR describe --dirty --always)}
abi_out_file=abi-${id}.xml
full_abi_out_file=abi-full-${id}.xml
${ROOT_DIR}/build/abi/dump_abi                \
    --linux-tree ${ABI_LINUX_TREE}            \
    ${ABI_VMLINUX_PATH}                       \
    --out-file ${DIST_DIR}/${full_abi_out_file}
if [ "$KMI_SYMBOL_LIST_FLAG" ]; then
  ${ROOT_DIR}/build/abi/filter_abi               \
      --in-file ${DIST_DIR}/${full_abi_out_file} \
      --out-file ${DIST_DIR}/${abi_out_file}     \
      $KMI_SYMBOL_LIST_FLAG
else
  cp ${DIST_DIR}/${full_abi_out_file} ${DIST_DIR}/${abi_out_file}
fi

effective_kernel_dir=$(readlink -f ${ROOT_DIR}/${KERNEL_DIR})
for f in "$abi_out_file" "$full_abi_out_file"; do
  # sanitize the abi.xml by removing any occurrences of the kernel path
  # and also do that with any left over paths sneaking in
  # (e.g. from the prebuilts)
  sed -i -e "s#${effective_kernel_dir}/##g"   \
         -e "s#${ROOT_DIR}/${KERNEL_DIR}/##g" \
         -e "s#${ROOT_DIR}/##g" "$DIST_DIR/$f"
  # Append debug information to abi file
  echo "
<!--
     libabigail: $(abidw --version)
-->" >> ${DIST_DIR}/$f
done

ln -sf ${abi_out_file} ${DIST_DIR}/abi.xml
ln -sf ${full_abi_out_file} ${DIST_DIR}/abi-full.xml
echo "========================================================"
echo " ABI dump has been created at ${DIST_DIR}/${abi_out_file}"
echo " Full ABI dump has been created at ${DIST_DIR}/${full_abi_out_file}"

rc=0
if [ -n "$ABI_DEFINITION" ]; then
    if [ $DIFF -eq 1 ]; then
        echo "========================================================"
        echo " Comparing ABI against expected definition ($ABI_DEFINITION)"
        set +e
        ${ROOT_DIR}/build/abi/diff_abi --abi-tool libabigail                  \
                                       --baseline $KERNEL_DIR/$ABI_DEFINITION \
                                       --new      ${DIST_DIR}/${abi_out_file} \
                                       --report   ${DIST_DIR}/abi.report      \
                                       $KMI_SYMBOL_LIST_FLAG
        rc=$?
        set -e
    fi
    if [ $UPDATE -eq 1 ] ; then
        echo "========================================================"
        echo " Updating expected ABI definition ($ABI_DEFINITION)"
        cp -v ${DIST_DIR}/${abi_out_file} $KERNEL_DIR/$ABI_DEFINITION
    fi
fi

[ -n "${DELETE_UNSTRIPPED_MODULES}" ] && rm -rf ${UNSTRIPPED_DIR}

if [ -n "${KMI_ENFORCED}" ]; then
  exit $rc
else
  exit 0
fi

