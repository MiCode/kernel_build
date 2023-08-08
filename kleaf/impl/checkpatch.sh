#!/bin/bash -e

# Copyright (C) 2023 The Android Open Source Project
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

# Bazel equivalent of checkpatch[_presubmit].sh that is used for
# checkpatch() macro.

# Wrapper around checkpatch.pl to gather necessary information from the
# dist dir. Notably, this includes the git_sha1 and whether to suppress
# the check for post-submit.

# Parse flags.
BUILD_NUMBER=""
CHECKPATCH_ARGS=(--show-types)
GIT_SHA1=""
CHECKPATCH_PL_PATH=""
IGNORELIST_FILE=""
DIST_DIR=""
DIR=""
GIT="git"
while [[ $# -gt 0 ]]; do
  next="$1"
  case ${next} in
  --bid)
    BUILD_NUMBER="$2"
    shift
    ;;
  --dist_dir)
    DIST_DIR="$2"
    shift
    ;;
  --git_sha1)
    GIT_SHA1="$2"
    shift
    ;;
  --ignored_checks)
    IGNORELIST_FILE="$2"
    shift
    ;;
  --checkpatch_pl)
    CHECKPATCH_PL_PATH="$2"
    shift
    ;;
  --dir)
    DIR="$2"
    shift
    ;;
  --git)
    GIT="$2"
    shift
    ;;
  --help)
    echo "Checks whether given build is for presubmit. If so, extract git_sha1"
    echo "from repo.prop and invoke checkpatch.sh."
    echo ""
    echo "Usage: $0 "
    echo "  --dir <dir>"
    echo "      directory to run checkpatch"
    echo "      If relative, it is interpreted against Bazel workspace root."
    echo "  [--bid <BUILD_NUMBER>]"
    echo "      Build ID. If specified, it is used to skip the check on"
    echo "      post-submit."
    echo "  [--dist_dir <DIST_DIR>]"
    echo "      Distribution directory. If specified. it is used to find"
    echo "      applied.prop and store checkpatch.log."
    echo "      If relative, it is interpreted as a relative path to the Bazel "
    echo "      workspace root."
    echo "  [--git_sha1 <GIT_SHA1>]"
    echo "      Git SHA1 to check patch on. Default is HEAD if applied.prop is"
    echo "      not provided, otherwise default is value from applied.prop."
    echo "  [--ignored_checks <checkpatch_ignorelist>]"
    echo "      List of ignored checks. See checkpatch() rule for defaults."
    echo "      If relative, it is interpreted against Bazel workspace root."
    echo
    echo "Flags set by Kleaf and not allowed in command line:"
    echo "  --checkpatch_pl </path/to/checkpatch.pl>"
    echo "      Absolute path to checkpatch.pl."
    echo "  [--git </path/to/git>]"
    echo "      Absolute path to Git binary, if it should not be found in PATH"
    exit 0
    ;;
  *)
    CHECKPATCH_ARGS+=("$1")
    ;;
  esac
  shift
done

# resolve_path <path>
#   resolves relative path against BUILD_WORKSPACE_DIRECTORY
function resolve_path() {
  local path="$1"
  if [[ "${path}" == /* ]]; then
    echo "${path}"
  else
    echo "${BUILD_WORKSPACE_DIRECTORY}/${path}"
  fi
}

# Skip checkpatch for postsubmit (b/35390488).
if [[ -n "${BUILD_NUMBER}" ]]; then
  return_code=0
  echo "${BUILD_NUMBER}" | grep -qE "^P[0-9]+" || return_code=$?
  if [[ "${return_code}" != 0 ]]; then
    echo "Did not identify a presubmit build. Exiting."
    exit 0
  fi
fi

if [[ -z ${DIR} ]]; then
  echo "ERROR: --dir is required" >&2
  exit 1
fi
ABS_DIR=$(resolve_path "${DIR}")

if [[ -z ${CHECKPATCH_PL_PATH} ]]; then
  echo "ERROR: --checkpatch_pl is required" >&2
  exit 1
fi

CHECKPATCH_TMP=$(mktemp -d /tmp/.tmp.checkpatch.XXXXXX)
trap "rm -rf ${CHECKPATCH_TMP}" EXIT

if [[ -n ${DIST_DIR} ]]; then
  DIST_DIR=$(resolve_path "${DIST_DIR}")

  applied_prop_path=${DIST_DIR}/applied.prop
  if [[ -f ${applied_prop_path} ]]; then
    if [[ -n ${GIT_SHA1} ]]; then
      echo "WARNING: applied.prop is found under --dist_dir, and --git_sha1 is specified."
      echo "    Using --git_sha1 instead." >&2
    else
      GIT_SHA1=$(sed -nE "s:^${DIR} .*([0-9a-f]{40}).*:\\1:p" "${applied_prop_path}")

      if [[ -z ${GIT_SHA1} ]]; then
        # There's applied.prop file (we are on build bots), but no changes
        # detected in the given directory. Just exit quietly.
        echo "INFO: No changes applied to ${DIR}"
        exit 0
      fi
    fi
  fi
fi

if [[ -z ${GIT_SHA1} ]]; then
  GIT_SHA1="HEAD"
fi

if [ $("${GIT}" -C "${ABS_DIR}" show --no-patch --format="%p" ${GIT_SHA1} | wc -w) -gt 1 ] ; then
  echo "INFO: Merge commit detected for "${DIR}". Skipping this check."
  exit 0
fi

SUBJECT=$("${GIT}" -C "${ABS_DIR}" show --no-patch --format="%s" ${GIT_SHA1})
if [[ "$SUBJECT" =~ ^UPSTREAM|^BACKPORT|^FROMGIT ]]; then
  echo "Not linting upstream patches for "${DIR}". Skipping this check."
  exit 0
fi

# Now run checkpatch.pl on DIR: GIT_SHA1
# Below is the equivalent of build/kernel/static_analysis/checkpatch.sh

PATCH_DIR=${CHECKPATCH_TMP}/checkpatch/patches

# Update ignorelist.
if [[ -n "${IGNORELIST_FILE}" ]]; then
  IGNORELIST_FILE=$(resolve_path "${IGNORELIST_FILE}")
  if [[ -f "${IGNORELIST_FILE}" ]]; then
    IGNORED_ERRORS=$(grep -v '^#' ${IGNORELIST_FILE} | paste -s -d,)
    if [[ -n "${IGNORED_ERRORS}" ]]; then
      CHECKPATCH_ARGS+=(--ignore)
      CHECKPATCH_ARGS+=("${IGNORED_ERRORS}")
    fi
  else
    echo "ERROR: --ignored_checks is not a file: ${IGNORELIST_FILE}" >&2
    exit 1
  fi
fi

echo "========================================================"
echo " Running static analysis on ${DIR} (${GIT_SHA1}) ..."
echo "========================================================"

pushd ${ABS_DIR} > /dev/null

"${GIT}" format-patch --quiet -o "${PATCH_DIR}" "${GIT_SHA1}^1..${GIT_SHA1}" -- \
  ':!android/abi*' ':!BUILD.bazel'
PATCH_FILE="${PATCH_DIR}/*.patch"

if ! $(stat -t ${PATCH_FILE} >/dev/null 2>&1); then
  echo "Patch empty (probably due to suppressions). Skipping analysis."
  popd > /dev/null
  exit 0
fi

CLEANUP_CHECKPATCH_RESULTS=0
if [[ -n ${DIST_DIR} ]]; then
  RESULTS_PATH=${DIST_DIR}/checkpatch.log
  RESULTS_PATH_PRETTY=$(basename "${RESULTS_PATH}")
else
  RESULTS_PATH=$(mktemp -p "${CHECKPATCH_TMP}" checkpatch.log.XXXXXX)
  RESULTS_PATH_PRETTY="${RESULTS_PATH}"
  CLEANUP_CHECKPATCH_RESULTS=1
fi

# Delay exit on non-zero checkpatch.pl return code so we can finish logging.

# Note, it's tricky to ignore this exit code completely and instead return only
# based on the log values. For example, if the log is not empty, but contains
# no ERRORS, how do we reliabliy distinguish WARNINGS that were not ignored (or
# other conditions we want to ignore), from legitimate errors running the
# script itself (e.g. bad flags)? checkpatch.pl will return 1 in both cases.
# For now, include all known warnings in the ignorelist, and forward this code
# unconditionally.

set +e
"${CHECKPATCH_PL_PATH}" ${CHECKPATCH_ARGS[*]} $PATCH_FILE > "${RESULTS_PATH}"
CHECKPATCH_RC=$?
set -e

# Summarize errors in the build log (full copy included in dist dir).
if [[ $CHECKPATCH_RC -ne 0 ]]; then
  echo "Errors were reported from checkpatch.pl." >&2
  echo "" >&2
  echo "Summary:" >&2
  echo "" >&2
  { grep -r -h -E -A1 "^(ERROR|WARNING):" "${RESULTS_PATH}" 1>&2; } || true
  echo "" >&2
  echo "See ${RESULTS_PATH_PRETTY} for complete output." >&2
  CLEANUP_CHECKPATCH_RESULTS=0
fi

if [[ ${CLEANUP_CHECKPATCH_RESULTS} == 1 ]]; then
  rm -f ${RESULTS_PATH}
fi

echo "========================================================"
echo "Finished running static analysis on ${DIR}."
echo "========================================================"
popd > /dev/null
exit ${CHECKPATCH_RC}
