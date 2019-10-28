#!/vendor/bin/sh

# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2019, The Linux Foundation. All rights reserved.
#

MODULES_PATH="/vendor/lib/modules"
MODPROBE="/vendor/bin/modprobe"

MODULES=`${MODPROBE} -d ${MODULES_PATH} -l`

${MODPROBE} -a -b -d ${MODULES_PATH} ${MODULES} > /dev/null 2>&1
