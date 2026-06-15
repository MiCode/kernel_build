#!/bin/bash

#./build_qssi12 qssi -v userdebug -m new $*
# 判断编译是否报错，若报错停止编译
#if [ ${PIPESTATUS[0]} -gt 0 ]
#    then
#        echo "for more information, please check $LOG_FILE_PATH"
#        exit 1
#    fi
./mk moonstone -v userdebug -m new -l  -o vendor $*

