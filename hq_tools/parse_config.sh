#!/bin/bash

QCOM_PARAM_CFG=qcom_param.cfg

function parse_config()
{
    local root_dir=$1
    local product_id=$2

    qcom_cfg_file=$root_dir/build/make/hq_tools/$product_id/$QCOM_PARAM_CFG
    if [ ! -e $qcom_cfg_file ]; then
        echo "Error: $qcom_cfg_file doesnot exist!"
        exit 1
    fi

    export QCOM_PLATFORM=`awk -F '=' '/^platform/{print $2}' $qcom_cfg_file`
    export MSM_DEVICE_DIR=`awk -F '=' '/^qcom_dir/{print $2}' $qcom_cfg_file`
    export NON_HLOS_DIR=`awk -F '=' '/^nonhlos_dir/{print $2}' $qcom_cfg_file`
    export HQ_RFCARD_MODE=`awk -F '=' '/^rfcard_mode/{print $2}' $qcom_cfg_file`
    CUST_KEY_DIR=`awk -F '=' '/^cust_key_dir/{print $2}' $qcom_cfg_file`

    if [[ x$QCOM_PLATFORM = x"" || x$MSM_DEVICE_DIR = x"" || x$NON_HLOS_DIR = x"" || x$HQ_RFCARD_MODE = x"" ]]
    then
        echo "Error: QCOM_PLATFORM=$QCOM_PLATFORM MSM_DEVICE_DIR=$MSM_DEVICE_DIR \
              NON_HLOS_DIR=$NON_HLOS_DIR HQ_RFCARD_MODE=$HQ_RFCARD_MODE"
        exit 1
    fi

    prebuilt_imgs_dir=`awk -F '=' '/^prebuilt_images_dir/{print $2}' $qcom_cfg_file`
    if [ x$prebuilt_imgs_dir != x"" ]; then
        PREBUILT_IMGS_DIR=$root_dir/$prebuilt_imgs_dir
    fi

    partition_file=`awk -F '=' '/^partition_file/{print $2}' $qcom_cfg_file`
    if [ x$partition_file != x"" ]; then
        PARTITION_FILE=$root_dir/$partition_file
    fi

    SRC_OVERLAY_ENABLE=`awk -F '=' '/^src_overlay_enable/{print $2}' $qcom_cfg_file`
    SRC_OVERLAY_IN_CASE=`awk -F '=' '/^src_overlay_in_case/{print $2}' $qcom_cfg_file`

   # src_overlay_dir=`awk -F '=' '/^src_overlay_dir/{print $2}' $qcom_cfg_file`
   #if [ x$src_overlay_dir != x"" ]; then
   #     SRC_OVERLAY_DIR=$root_dir/$src_overlay_dir
    #fi

    src_overlay_common_dir=`awk -F '=' '/^src_overlay_common_dir/{print $2}' $qcom_cfg_file`
    if [ x$src_overlay_common_dir != x"" ]; then
        SRC_OVERLAY_COMMON_DIR=$root_dir/$src_overlay_common_dir
    fi

    src_overlay_qcom_dir=`awk -F '=' '/^src_overlay_qcom_dir/{print $2}' $qcom_cfg_file`
    if [ x$src_overlay_qcom_dir != x"" ]; then
        SRC_OVERLAY_QCOM_DIR=$root_dir/$src_overlay_qcom_dir
    fi

    src_overlay_product_dir=`awk -F '=' '/^src_overlay_product_dir/{print $2}' $qcom_cfg_file`
    if [ x$src_overlay_product_dir != x"" ]; then
        SRC_OVERLAY_PRODUCT_DIR=$root_dir/$src_overlay_product_dir
    fi

    # the following cannot be put before the others,
    # because HQ_PRODUCT_ID may be changed, in case of enable_project_id=true
    enable_project_id=`awk -F '=' '/^enable_project_id/{print $2}' $qcom_cfg_file`
    PROJECT_PATH=`awk -F '=' '/^project_path/{print $2}' $qcom_cfg_file`


    # Qualcomm component
    export QCT_MPSS_NAME=`awk -F '=' '/^QCT_MPSS_NAME/{print $2}' $qcom_cfg_file`
    export QCT_ADSP_NAME=`awk -F '=' '/^QCT_ADSP_NAME/{print $2}' $qcom_cfg_file`
    export QCT_CDSP_NAME=`awk -F '=' '/^QCT_CDSP_NAME/{print $2}' $qcom_cfg_file`
    export QCT_BOOT_NAME=`awk -F '=' '/^QCT_BOOT_NAME/{print $2}' $qcom_cfg_file`
    export QCT_TZ_NAME=`awk -F '=' '/^QCT_TZ_NAME/{print $2}' $qcom_cfg_file`
    export QCT_VIDEO_NAME=`awk -F '=' '/^QCT_VIDEO_NAME/{print $2}' $qcom_cfg_file`
    export QCT_WCNSS_NAME=`awk -F '=' '/^QCT_WCNSS_NAME/{print $2}' $qcom_cfg_file`
    export QCT_CPE_NAME=`awk -F '=' '/^QCT_CPE_NAME/{print $2}' $qcom_cfg_file`
    export LA_UM_NAME=`awk -F '=' '/^LA_UM_NAME/{print $2}' $qcom_cfg_file`
    export QCT_AOP_NAME=`awk -F '=' '/^QCT_AOP_NAME/{print $2}' $qcom_cfg_file`
    export QCT_Agatti_NAME=`awk -F '=' '/^QCT_Agatti_NAME/{print $2}' $qcom_cfg_file`
    export QCT_BTFM_CHE_NAME=`awk -F '=' '/^QCT_BTFM_CHE_NAME/{print $2}' $qcom_cfg_file`
    export QCT_BTFM_CMC_NAME=`awk -F '=' '/^QCT_BTFM_CMC_NAME/{print $2}' $qcom_cfg_file`
    export QCT_RPM_NAME=`awk -F '=' '/^QCT_RPM_NAME/{print $2}' $qcom_cfg_file`
    export QCT_WLAN_NAME=`awk -F '=' '/^QCT_WLAN_NAME/{print $2}' $qcom_cfg_file`
    export QCT_TZ_APPS_NAME=`awk -F '=' '/^QCT_TZ_APPS_NAME/{print $2}' $qcom_cfg_file`


    if [[ x$QCT_MPSS_NAME = x"" || x$QCT_ADSP_NAME = x"" || x$QCT_CDSP_NAME = x"" || x$QCT_BOOT_NAME = x"" || \
          x$LA_UM_NAME = x"" ]]; then
        echo "Error: qcom components dir is not set!"
        exit 1
    fi

    flash_scr_dir=`awk -F '=' '/^flash_scripts_dir/{print $2}' $qcom_cfg_file`
    version_dir=`awk -F '=' '/^version_dir/{print $2}' $qcom_cfg_file`
    image_dir=`awk -F '=' '/^image_dir_in_version/{print $2}' $qcom_cfg_file`

    root_scripts_dir=`awk -F '=' '/^root_scripts_dir/{print $2}' $qcom_cfg_file`
    if [ x$root_scripts_dir != x"" ]; then
        ROOT_SCRIPTS_DIR=$ROOT_DIR/$root_scripts_dir
    fi

    contents_file=`awk -F '=' '/^contents/{print $2}' $qcom_cfg_file`
    if [[ x$BUILD_SIGN_FOR_SECBOOT = x"true" && x$HQ_BUILD_SIGN_PROXY = x"true" ]]; then
        export STR_SIGN_SERVER_PROXY=`awk -F '=' '/^sign_server_proxy/{print $2}' $qcom_cfg_file`
        export STR_SIGN_PROXY_USER=`awk -F 'sign_proxy_user=' '/^sign_proxy_user/{print $2}' $qcom_cfg_file`
        export STR_SIGN_PROXY_PASSWORD=`awk -F 'sign_proxy_password=' '/^sign_proxy_password/{print $2}' $qcom_cfg_file`
    fi

    echo "STR_SIGN_SERVER_PROXY=${STR_SIGN_SERVER_PROXY}"
    echo "STR_SIGN_PROXY_USER=${STR_SIGN_PROXY_USER}"
    echo "STR_SIGN_PROXY_PASSWORD=${STR_SIGN_PROXY_PASSWORD}"


    echo "parse config end"    
}

