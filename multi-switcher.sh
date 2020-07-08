#!/bin/bash
#
# Copyright (C) 2020 The Android Open Source Project
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

BASE=$(readlink -f $(dirname $0)/..)

BRANCH=$1

pushd $BASE > /dev/null

  if [[ ! ( -d common-${BRANCH} || -d common${BRANCH} ) || ${BRANCH} == "" ]]; then
    echo "usage: $0 <branch>"
    echo
    echo "Branches available: "
    ls -d common-* | sed 's/common-/\t/g'
    ls -d common1?-* | sed 's/common/\t/g'
    exit 1
  fi

  echo "Switching to $BRANCH"

  if [[ ${BRANCH} == "11-5.4" ]]; then
    alt_name="5.4-stable"
  fi

  if [[ ${BRANCH} == "12-5.4" ]]; then
    alt_name="5.4"
  fi

  for dir in common cuttlefish-modules goldfish-modules; do
    if [ -L ${dir} ]; then
      rm ${dir}
    fi

    for candidate in ${dir}-${BRANCH} ${dir}-${alt_name} ${dir}${BRANCH}; do
      if [ -d ${candidate} ]; then
          ln -vs ${candidate} ${dir}
      fi
    done
  done

popd > /dev/null
