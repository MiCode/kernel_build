#!/bin/bash
# $1 BUILD_REGION
# $2 DEVICE_NAME
# mi ogki only for cn&V+ device

echo
echo "  preparing kernel tree for Mi OGKI build! "
set -x
if [ -d ./common-ogki -a -d ./kernel-6.6 ]; then
  echo "  current tree supported mi ogki build!  "
  if [ "$1" == "cn" ] && { [ "$2" == "rodin" ] || [ "$2" == "dali" ] || [ "$2" == "turner" ]; }; then
      echo "  current device supported mi ogki build! "
      echo "  current path:$(pwd)"
      cd kernel
      rm -rf ./kernel-6.6
      ln -sf ../common-ogki kernel-6.6
      export REAL_KERNEL_DIR_NAME="common-ogki"
  else
      echo "  current device is not supported mi ogki! "
      export REAL_KERNEL_DIR_NAME="kernel-6.6"
  fi
else
    echo "  The Mi OGKI is not supported! "
fi
set +x

