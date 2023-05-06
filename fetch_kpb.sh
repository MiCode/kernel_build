#!/bin/sh

# Copyright (c) 2019, The Linux Foundation. All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#    * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
#    * Neither the name of The Linux Foundation nor the names of its
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
#
# ---------------------------------------------------------------------
# Usage:
#   sh fetch_kpb.sh -v 4.19 -f /home/user1/prebuilts
#
# Script to get the Kernel prebuilts from filer space.

get_kernel_sha() {
    local ker_prj=$1

    SHA=$(repo forall $ker_prj -c "git rev-parse HEAD")
    echo $SHA
}

usage() {
   echo "Usage:"
   echo "   sh $0 -v 4.19 -f /home/user1/prebuilts"
   exit 1
}

validate_parameters() {
   if [ -z "$KERNEL_VERSION" ]; then
        echo "Please provide Kernel Version (4.19,4.14, etc)"
        usage
   fi
   if [ -z "$PREBUILTS_PATH" ]; then
        echo "Please provide path to the prebuilts (/home/user1/)"
        usage
   fi

}

TEMP=$(getopt -o v:f:h --long kernel-version:,filer:,help -n $(basename "$0") -- "$@")
eval set -- "$TEMP"
while true ; do
    case "$1" in
        -v|--kernel-version) KERNEL_VERSION="$2" ;
            shift 2;;
        -f|--filer) PREBUILTS_PATH="$2" ;
            shift 2;;
        -h|--help) usage;;
        --) shift ;
            break ;;
        *) echo "invalid parameters!! $1" ;
            usage;;
   esac
done

validate_parameters

PREBUILT_FOLDER="ship_prebuilt"
KERNEL_PROJECT_PREFIX="kernel/msm"
echo "Kernel: ${KERNEL_PROJECT_PREFIX}-$KERNEL_VERSION"
echo "Prebuilts Path: $PREBUILTS_PATH"

ls kernel | grep -q msm
if [ $? -ne 0 ]; then
     echo "Execute the script from the root of the workspace"
     exit 1
fi

if [ ! -e "$PREBUILTS_PATH" ]; then
     echo "Prebuilts path doesn't exist"
     exit 1
fi

echo "Fetching kernel top commit id"
SHA="$(get_kernel_sha ${KERNEL_PROJECT_PREFIX}-$KERNEL_VERSION)"
if [ -z "$SHA" ]; then
     echo "Unable to read SHA for ${KERNEL_PROJECT_PREFIX}-$KERNEL_VERSION"
     exit 1
fi

if [ -e "kernel/${PREBUILT_FOLDER}/kernel_sha1.txt" ]; then
      PB_SHA=$(cat kernel/${PREBUILT_FOLDER}/kernel_sha1.txt)
      if [ "$SHA" == "$PB_SHA" ]; then
           echo "Prebuilts for the existing kernel repo already exists in the workspace"
           exit 0
      else
           echo "Existing workspace has outdated kernel prebuilts, removing them."
	   rm -rf kernel/${PREBUILT_FOLDER}
      fi
fi

if [ -e "${PREBUILTS_PATH}/$SHA" ]; then
     echo "Copying prebuilts is inprogress..."
     if [ -e "${PREBUILTS_PATH}/$SHA/${PREBUILT_FOLDER}.tar.gz" ]; then
           rsync -al ${PREBUILTS_PATH}/$SHA/${PREBUILT_FOLDER}.tar.gz ./
           tar xzfm ${PREBUILT_FOLDER}.tar.gz
           rm -rf ${PREBUILT_FOLDER}.tar.gz
     else
           rsync -al ${PREBUILTS_PATH}/$SHA/${PREBUILT_FOLDER} kernel/
     fi
else
     echo "Prebuilts are not available for Kernel:$SHA"
fi
