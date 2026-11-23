#SPDX-License-Identifier: GPL-2.0-only
#Copyright (c) 2025 Qualcomm Innovation Center, Inc. All rights reserved.

#!/bin/bash

function check_return_value () {
    retVal=$1
    command=$2
    if [ $retVal -ne 0 ]; then
        echo "FAILED: $command"
        exit $retVal
    fi
}

function command () {
    command=$@
    echo "Command: \"$command\""
    time $command
    retVal=$?
    check_return_value $retVal "$command"
}
