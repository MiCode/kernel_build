#!/bin/bash

#./build_qssi12 qssi -v user -m new $*
# 判断编译是否报错，若报错停止编译
#if [ ${PIPESTATUS[0]} -gt 0 ]
#    then
#        echo "for more information, please check $LOG_FILE_PATH"
#        exit 1
#    fi
./mk sunstone -v user -m new -l  -o vendor $*

