#!/bin/bash

# Copyright (C) 2022 The Android Open Source Project
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

set -e

ABI=0
CONFIG=0
ARGS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --abi)
            ABI=1
            shift
            ;;
        --config)
            CONFIG=1
            shift
            ;;
        -*|--*|*)
            ARGS="$ARGS $1"
            shift
            ;;
    esac
done

# For printing results
BAZEL=$(which bazel >/dev/null && echo "bazel" || echo "tools/bazel")

ROOT_DIR=$($(dirname $(dirname $(readlink -m "$0")))/gettop.sh)
REAL_BAZEL=$(which bazel || echo "${ROOT_DIR}/tools/bazel")

source "${ROOT_DIR}/build/build_utils.sh"
source "${ROOT_DIR}/build/_setup_env.sh"

function determine_targets_internal() (
    result_var=$1
    cd $ROOT_DIR

    if [[ ! -f $BUILD_CONFIG ]]; then
        echo "ERROR: BUILD_CONFIG ($BUILD_CONFIG) does not exist." >&2
        exit 1
    fi

    # Determine the package that contains the build config by going up and
    # looking for BUILD / BUILD.bazel files.
    rel_build_config=$(realpath "$(readlink -e $BUILD_CONFIG)" --relative-to $ROOT_DIR)
    package_path=$(
        cur_path=$(dirname "$rel_build_config")
        while [[ $cur_path != "." ]] && [[ ! -f $cur_path/BUILD.bazel ]] && [[ ! -f $cur_path/BUILD ]]; do
            cur_path=$(dirname $cur_path)
        done
        echo $cur_path
    )
    if [[ $package_path == "." ]]; then
        cat >&2 <<EOF
WARNING: Unable to determine package of build.config. Please migrate to Bazel.
See
    https://android.googlesource.com/kernel/build/+/refs/heads/main/kleaf/README.md
EOF
        exit 1
    fi
    build_config_base=${rel_build_config#$package_path/}

    package="//$package_path"
    build_config_label="$package:$build_config_base"

    script="
        let pkg_targets = siblings($build_config_label) in
        let dists = filter(\"_dist\$\", \$pkg_targets) except kind(alias, \$pkg_targets) in
        let kernel_builds = kind(_kernel_build, \$pkg_targets) in
        let kernel_configs = kind(kernel_config, \$pkg_targets) in

        let build_config_rdeps = attr(build_config, \"^$build_config_label\$\", \$pkg_targets) in
        let kernel_builds_on_build_config = \$kernel_builds intersect allpaths(\$kernel_builds, \$build_config_rdeps) except filter(\"_interceptor\$\", \$pkg_targets) in

        let dists_on_kernel_builds = \$dists intersect allpaths(\$dists, \$kernel_builds_on_build_config) in

        let abi_targets = kind(filegroup, filter(\"_abi\$\", \$pkg_targets)) except filter(\"_interceptor_abi\$\", \$pkg_targets) in
        let dists_with_abi_dep = \$dists_on_kernel_builds intersect allpaths(\$dists_on_kernel_builds, \$abi_targets) in
        let dists_without_abi_dep = \$dists_on_kernel_builds except \$dists_with_abi_dep in

        let kythe = kind(kernel_kythe, \$pkg_targets) in
        let dists_with_kythe_dep = \$dists_on_kernel_builds intersect allpaths(\$dists_on_kernel_builds, \$kythe) in
        let dists_without_kythe_dep = \$dists_on_kernel_builds except \$dists_with_kythe_dep in

        let dists_with_abi_without_kythe = \$dists_with_abi_dep intersect \$dists_without_kythe_dep in
        let dists_without_abi_without_kythe = \$dists_without_abi_dep intersect \$dists_without_kythe_dep in
        let abi_targets_on_build_config = \$abi_targets intersect allpaths(\$abi_targets, \$build_config_rdeps) in

        let kernel_configs_on_build_config = \$kernel_configs intersect allpaths(\$kernel_configs, \$build_config_rdeps) in
        let kernel_configs_with_abi = filter(\"_with_vmlinux_config\$\", \$kernel_configs_on_build_config) in
        let kernel_configs_interceptor = filter(\"_interceptor_config\$\", \$kernel_configs_on_build_config) in
        let kernel_configs_without_abi = \$kernel_configs_on_build_config
                  except \$kernel_configs_with_abi
                  except \$kernel_configs_interceptor in

        $result_var
"

    $REAL_BAZEL version > /dev/null # prints start up message to stderr
    $REAL_BAZEL query --ui_event_filters=-info,-debug --noshow_progress "$script"
) # determine_targets_internal

function determine_targets() {
    targets=$(determine_targets_internal "$@")
    if [[ $? != 0 ]]; then
        echo "WARNING: Unable to determine the target corresponding to the build config." >&2
        exit 1
    fi
    if [[ -z "$targets" ]]; then
        echo "WARNING: No matching targets depend on the given build config." >&2
        exit 1
    fi
    echo "$targets"
}

flags=""

if [[ -n "$LTO" ]]; then
    flags="$flags --lto=$LTO"
fi

# Attempt to determine the relative path from DIST_DIR to CWD. If unable to do so,
# fallback to the value of DIST_DIR.
my_dist_dir_code=0
my_dist_dir=$(realpath $DIST_DIR  --relative-to .) || my_dist_dir_code=$?
if [[ $my_dist_dir_code != 0 ]]; then
    my_dist_dir=$DIST_DIR
fi

if [[ "$ABI" == "1" ]]; then
    if [[ "$UPDATE" == "1" ]] || [[ "$UPDATE_SYMBOL_LIST" == "1" ]] || [[ "$DIFF" == 0 ]]; then
        abi_targets=$(determine_targets "\$abi_targets_on_build_config")
    fi

    if [[ "$UPDATE" == "1" ]] && [[ "$DIFF" == "1" ]]; then
        for target in $abi_targets; do
            echo "$BAZEL run" $flags "${target}_update_symbol_list &&
        $BAZEL build" $flags "$target &&
        $BAZEL run" $flags "${target}_update"
        done
    elif [[ "$UPDATE" == "1" ]] && [[ "$DIFF" == "0" ]]; then
        for target in $abi_targets; do
            echo "$BAZEL run" $flags "${target}_update_symbol_list &&
        $BAZEL run" $flags "${target}_update"
        done
    elif [[ "$UPDATE_SYMBOL_LIST" == "1" ]]; then
        for target in $abi_targets; do
            echo "$BAZEL run" $flags "${target}_update_symbol_list"
        done
    elif [[ "$DIFF" == "0" ]]; then
        echo "$BAZEL build" $flags $(for target in $abi_targets; do echo ${target}_dump; done)
    else
        dist_targets=$(determine_targets "\$dists_with_abi_without_kythe")
        for target in $dist_targets; do
            echo "$BAZEL run" $flags "$target -- --dist_dir=$my_dist_dir"
        done
    fi
elif [[ "$CONFIG" == "1" ]]; then
    config_targets=$(determine_targets "\$kernel_configs_without_abi")
    for target in $config_targets; do
        echo "$BAZEL run" $flags "$target -- $ARGS"
    done
else
    dist_targets=$(determine_targets "\$dists_without_abi_without_kythe")
    for target in $dist_targets; do
        echo "$BAZEL run" $flags "$target -- --dist_dir=$my_dist_dir"
    done
fi
