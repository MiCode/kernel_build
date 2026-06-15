#!/bin/bash

XIAOMI_SIGN_FILE="sign_images.py"
echo "sign_xiaomi.sh: ROOT_DIR=$ROOT_DIR, XIAOMI_SIGN_FILE=$XIAOMI_SIGN_FILE, OUT_TARGET_DIR=$OUT_TARGET_DIR, LOG_DIR=$LOG_DIR"

# add xiaomi VPN trigger by chenyanting 170504 start
function check_vpn_state()
{
    ret=`ifconfig | grep tun > /dev/null 2>&1`
    return $ret
}

function start_vpn()
{
    echo "go to start vpn flow"
    echo 'start' > ~/.vpn.conf
}

function stop_vpn()
{
    echo "go to stop vpn flow"
    echo 'stop' > ~/.vpn.conf
}

function wait_for_connected()
{
    ret=-1
    until [[ $ret -eq 0 ]]
    do
        check_vpn_state
        ret=$?
        sleep 3
    done
}

function xiaomi_vpn_trigger()
{
    export -f start_vpn stop_vpn check_vpn_state wait_for_connected
    start_vpn
    timeout 900 bash -c wait_for_connected
    check_vpn_state
    if [ $? -gt 0 ]
    then
        echo "SCM Warning: Please check VPN connection"
        exit 1
    fi
}

# add xiaomi VPN trigger by chenyanting 170504 end

function copy_secimagelog_to_symbols()
{
    cp -f ${OUT_TARGET_DIR}/sign_ap_images.log $LOG_DIR
    cp -f ${OUT_TARGET_DIR}/sign_bp_images.log $LOG_DIR
}

function sign_ap_code_py()
{
#    echo "hq-r-moonstone-dev  rain  test"
#    echo "===================================== START TO SIGN AP IMAGES ======================================"
#    cd ${ROOT_DIR}/vendor/xiaomi/securebootsigner/Qualcomm/common/
#    echo `pwd`
#    python ${XIAOMI_SIGN_FILE} -p ${HQ_PRODUCT_ID} -f ${OUT_TARGET_DIR}/abl.elf -s abl_v1 2>&1 |tee ${OUT_TARGET_DIR}/sign_ap_images.log
#    tail -n 10 ${OUT_TARGET_DIR}/sign_ap_images.log | grep "signed successfully"
#    if [[ $? -eq 0 ]];then
#        echo "--------------------File abl.elf is signed successfully------------------"
#    else
#        echo "-----SCM Warning: File abl.elf is signed unsuccessfully------------------"
#        exit 1
#    fi
#    cd -
#    echo "===================================== SIGN AP IMAGES COMPLETE ======================================"
}

function sign_bp_code_py()
{
    echo "===================================== START TO SIGN BP IMAGES ======================================"
    cd ${ROOT_DIR}/vendor/qcom/non-hlos/
    echo `pwd`
    python ./../../xiaomi/securebootsigner/Qualcomm/common/${XIAOMI_SIGN_FILE} -p ${HQ_PRODUCT_ID} --all 2>&1 | tee ${OUT_TARGET_DIR}/sign_bp_images.log
    tail -n 10 ${OUT_TARGET_DIR}/sign_bp_images.log | grep "signed successfully"
    if [[ $? -eq 0 ]];then
        echo "--------------------sign BP image files successfully------------------"
    else
        echo "-----SCM Warning: sign BP image files unsuccessfully------------------"
        exit 1
    fi
    cd -
    echo "===================================== SIGN IMAGES BP COMPLETE ======================================"
}

################################################
# Project must implement this function.
# Each project will implemente with different method.
# @param$1: whether sign?
# @param$2: sign which moudule? value:hlos/non-hlos/others.
################################################
function sign_if_needed()
{
    echo "###If sign ?:$1, Sign moudule: $2 (NULL indicate sign hlos and non-hlos)"
    #echo "ROOT_DIR=$ROOT_DIR, XIAOMI_SIGN_FILE=$XIAOMI_SIGN_FILE, OUT_TARGET_DIR=$OUT_TARGET_DIR, LOG_DIR=$LOG_DIR"
    if [ "$1" == "true" ]
    then
        # 1. call xiaomi vpn connection
        #check_vpn_state
        #xiaomi_vpn_trigger

        # 2. sign images and copy log files
        #sign_code_py
        if [ "$2" == "hlos" ]; then
            sign_ap_code_py
        elif [ "$2" == "non-hlos" ]; then
            sign_bp_code_py
        else
            sign_ap_code_py
            sign_bp_code_py
        fi

        # copy to sign log to $LOG_DIR.
        copy_secimagelog_to_symbols

        # 3. close xiaomi vpn connection
        #stop_vpn
    #    echo "sign images not available yet"
    fi
}
