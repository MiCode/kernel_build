#!/bin/bash

# default values as below:
export ANDROID_SET_JAVA_HOME=true
export HQ_BUILD_ARM_LICENSE=false
export BUILD_SIGN_FOR_SECBOOT=false
export HQ_USE_CUST_KEY=false
export HQ_PRODUCT_ID=
export HQ_BUILD_MODE=remake
export HQ_AVB_KEY=true
export ALLOW_MISSING_DEPENDENCIES=true
HQ_EFUSE_ENABLE=false


BUILD_VARIANT=userdebug
BUILD_OBJECT=all
BUILD_TGT_FILES_PKG=false
CCACHE=true

ROOT_DIR=`pwd`
LOG_DIR=$ROOT_DIR/log
SYMBOLS=symbols
NON_HLOS_DIR=non-hlos
VER_DIR_NAME=all_images
SPARSE_VER_DIR_NAME=all_sparse_images
CPUS=`grep processor /proc/cpuinfo | wc -l`
QCOM_PARAM_CFG=qcom_param.cfg

DEBUG=false
if [ "$DEBUG" = "true" ]; then
    MAKE_PRINT='-n'
else
    MAKE_PRINT=
fi


function usage(){
cat << EOF
Usage: ./mk.sh PROJECT [-m MODE] [-o OBJECT] [-v VARIANT] [-hs]
  PROJECT is a must, which should be a project name or a sub-project name.
  Example:
      short: ./mk sdm660_64 -m remake -o all -v userdebug
      long: ./mk sdm660_64 --mode=new --object=hlos --variant=user

      With default values, ./mk sdm660_64
      equals to ./mk sdm660_64 -m remake -o all -v userdebug

      when --mode=[mm mmm mma mmma]
      ./mk sdm660_64 --mode=mm --object=packages/apps/Calculator

Optional arguments:
  -h, --help            show this help message and exit
  -s, --sign            sign images for secure-boot
  -p, --proxy           use a proxy server to sign.
  -e, --efuse           enable efuse in version with specified sec.dat
  -c, --cust-key        use custom key to sign boot.img & system.img
  -l, --license         when OBJECT is [all non-hlos], it will make sure to compile
                        qualcomm BOOT and RPM.
  -t, --tgt_files       after compiling hlos, it will make target-files-package.
                        only valid when --object=hlos
  -b, --bp-sync         compile bp synchronized with ap
  -i, --ci-build        ci_build
  -o, --object=OBJECT
                        object option, default is "all". 
                        The following objects are supported until now:
                        all            includes all objects
                        hlos           aosp and qcom proprietary
                        non-hlos       includes ADSP,MPSS,TZ, 
                                       if sign flag is set, also includes BOOT and RPM
                        update-api     make update-api
                        tgt-files      make target-files-package
                        aboot          make lk
                        *image         compile ap images, including [boot system userdata recovery vendor]
                        qcom-*         qualcomm component,including [boot rpm modem adsp tz]
                        <path>         directory path of modules, compatible with absolute path and relative path
                                       valid only when --mode=[mm mmm mma mmma]
  -v, --variant=VIRIANT
                        which defines TARGET_BUILD_VARIANT
                        should be "user" or "userdebug", default is "userdebug"
  -m, --mode=MODE
                        build mode, default is "remake"
                        new            clean and make
                        remake         make
                        clean          clean the generated object files, like *.o,
                                       valid only when --object=[all,hlos,non-hlos,qcom-{component}]
                        nodeps         builds hlos images ignoring dependencies
                                       valid only when --object=[bootimage systemimage userdataimage recoveryimage]
                        mm             builds all of the modules in the directory <path>, but not their dependencies
                        mmm            builds all of the modules in the supplied directory <path>, but not their dependencies
                        mma            builds all of the modules in the directory <path>, and their dependencies
                        mmma           builds all of the modules in the supplied directory <path>, and their dependencies
EOF
}

function check_gcc_version(){
    local required_version='4.8'
    local gcc_version_str=`gcc --version 2>&1 | grep '^gcc .*[ "]4\.[0-9][\. "$$]'`
    local gcc_version=$(expr "$gcc_version_str" : '.*\(4\.[0-9]\)\.[0-9].*')
    echo -e "Your gcc version is: $gcc_version_str"
    if [ "$gcc_version" != "$required_version" ]
    then
        echo "You are attempting to build with the incorrect version of gcc."
        echo "The required version is: $required_version."
        echo "Please update gcc version with vendor/qcom/non-hlos/hq_build/install_gcc4-8-1.sh"
        exit 1
    fi
}

function show_java_version(){
    echo "==============SHOW JAVA VERSION============="
    java -version
    javac -version
    echo "==============SHOW JAVA VERSION============="
}

function check_build_variant()
{
    if [[ "$BUILD_VARIANT" != "user" && "$BUILD_VARIANT" != "userdebug" ]]
    then
        echo "***** Unsupported BUILD_VARIANT=$BUILD_VARIANT *****"
        exit 1
    fi
}

function check_build_mode()
{
    local supported_mode=(new remake clean mm mmm mma mmma nodeps)
    for obj in "${supported_mode[@]}"
    do
        if [ "$obj" = "$HQ_BUILD_MODE" ]; then
            return 0
        fi
    done

    echo "***** Unsupported HQ_BUILD_MODE=${HQ_BUILD_MODE} *****"
    exit 1
}

function check_security()
{
    if [[ $HQ_EFUSE_ENABLE = "true" && $BUILD_SIGN_FOR_SECBOOT = "false" ]]
    then
        echo "Error: HQ_EFUSE_ENABLE=$HQ_EFUSE_ENABLE BUILD_SIGN_FOR_SECBOOT=$BUILD_SIGN_FOR_SECBOOT"
        exit 1
    fi
}

# check project path
# before checking, HQ_PRODUCT_ID is like a6000;
#
# in case of enable_project_id=true,
# HQ_PRODUCT_ID will be changed from a6000 to TARGET_DEVICE, like hq_msm8917_64,
# and a6000 is assigned to HQ_PROJECT_ID as exported;
#
# in case of enable_project_id=false,
# just check if HQ_PRODUCT_ID does exist in device/*/*
function check_project_path()
{
    local enable_project_id=$1
    echo "$enable_project_id"

    echo "check_project_path: HQ_PRODUCT_ID=$HQ_PRODUCT_ID enable_project_id=$enable_project_id"
    cd $ROOT_DIR
    if [ x$enable_project_id = x"true" ]; then
        if [ x$PROJECT_PATH = x"" ]; then
            echo "Error: PROJECT_PATH=$PROJECT_PATH"
            exit 1
        fi

        if [ ! -d $ROOT_DIR/$PROJECT_PATH ]; then
            echo "Error: $ROOT_DIR/$PROJECT_PATH doesnot exist"
            exit 1
        fi

        prj_paths=`find ./$PROJECT_PATH -maxdepth 3 -name $1`
        for path in $prj_paths
        do
            echo "path is $path"
            HQ_PRODUCT_ID=`echo "$path" | cut -d "/" -f 3`
            export HQ_VENDOR=`echo "$path" | cut -d "/" -f 4`
            export HQ_PROJECT_ID=`echo "$path" | cut -d "/" -f 5`
            echo "HQ_VENDOR=$HQ_VENDOR HQ_PROJECT_ID=$HQ_PROJECT_ID"
        done

        if [ x$HQ_PRODUCT_ID = x"" ]; then
            echo "Error: No matched project name!"
            exit 1
        fi
    else
        cd $ROOT_DIR
        prj_path=`find ./device/*/ -maxdepth 3 -name $HQ_PRODUCT_ID`
        echo "$prj_path"
        if [ x"$prj_path" = x"" ]; then
            echo "Error: ***** No matched project name! *****"
            exit 1
        fi
    fi
    echo "check_project_path:in the end, HQ_PRODUCT_ID=$HQ_PRODUCT_ID"
}

# init version dirs.
# $ROOT_DIR & $OUT_TARGET_DIR are assumed to be defined
function init_version_dirs()
{
    if [ x$flash_scr_dir != x"" ]; then
        FLASH_SCRIPTS_DIR=$ROOT_DIR/$flash_scr_dir
    fi

    if [ x$version_dir != x"" ]; then
        VER_DIR_NAME=$version_dir
        SPARSE_VER_DIR_NAME=${version_dir}_sparse
    fi

    if [ x$image_dir != x"" ]; then
        IMGS_DIR_NAME=$image_dir
    fi

    VERSION_DIR=$OUT_TARGET_DIR/$VER_DIR_NAME
    SPARSE_VERSION_DIR=$OUT_TARGET_DIR/$SPARSE_VER_DIR_NAME

    if [ x$IMGS_DIR_NAME != x"" ]; then
        VER_IMAGES_DIR=$VERSION_DIR/$IMGS_DIR_NAME
    else
        VER_IMAGES_DIR=$VERSION_DIR
    fi

    VERSION_FILE=$OUT_TARGET_DIR/$VER_DIR_NAME.zip
    SPARSE_VERSION_FILE=$OUT_TARGET_DIR/$SPARSE_VER_DIR_NAME.zip

    echo "VERSION_DIR=$VERSION_DIR SPARSE_VERSION_DIR=$SPARSE_VERSION_DIR VER_IMAGES_DIR=$VER_IMAGES_DIR"
    echo "VERSION_FILE=$VERSION_FILE SPARSE_VERSION_FILE=$SPARSE_VERSION_FILE"
}

# init variables
function init_variables()
{    
    check_project_path $enable_project_id
    OUT_TARGET_DIR=$ROOT_DIR/out/target/product/$HQ_PRODUCT_ID
    SYMBOLS_DIR=$OUT_TARGET_DIR/symbols
    PRODUCT_TARGET_DIR=$ROOT_DIR/out/target/product/$HQ_PRODUCT_ID
    ALL_IMAGES_DIR=$PRODUCT_TARGET_DIR/$VER_DIR_NAME
    IMAGES_DIR=$ALL_IMAGES_DIR/images
    IMAGES_FILE=$PRODUCT_TARGET_DIR/$VER_DIR_NAME.zip
    SPARSE_IMAGES_DIR=$PRODUCT_TARGET_DIR/$SPARSE_VER_DIR_NAME
    SPARSE_IMAGES_FILE=$PRODUCT_TARGET_DIR/$SPARSE_VER_DIR_NAME.zip
    init_version_dirs
}

function make_nonhlos_component()
{
    sleep 3
    local component=$1
    cd ${ROOT_DIR}/vendor/qcom/${NON_HLOS_DIR}/hq_build
    ./build_$component.sh $HQ_PRODUCT_ID $HQ_BUILD_MODE no_sparse_cfg
    if [ $? -gt 0 ]; then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi
}

function make_nonhlos()
{
    cd ${ROOT_DIR}/vendor/qcom/${NON_HLOS_DIR}/hq_build
    echo "${ROOT_DIR}/vendor/qcom/${NON_HLOS_DIR}/hq_build"
    ./build_non_hlos.sh $HQ_PRODUCT_ID $HQ_BUILD_MODE $HQ_BUILD_ARM_LICENSE no_parse_cfg
    if [ $? -gt 0 ]; then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi
}

function copy_nonhlos_component()
{
    local component=$1
    local dest_dir=$2
    cd ${ROOT_DIR}/vendor/qcom/${NON_HLOS_DIR}
    if [ ! -e copy-all-img.sh ]; then
        cp -f hq_build/copy-all-img.sh copy-all-img.sh
        chmod 777 copy-all-img.sh
    fi

    if [ ! -e $dest_dir ]; then
        mkdir -p $dest_dir
    fi
    echo "./copy-all-img.sh $QCOM_PLATFORM $component $dest_dir"
    ./copy-all-img.sh $QCOM_PLATFORM $component $dest_dir

}

function copy_prebuilt_images()
{
    local dest_dir=$1
    echo "[copy_prebuilt_images] dest_dir=$1"
    echo "PREBUILT_IMGS_DIR=$PREBUILT_IMGS_DIR"
    if [ x$PREBUILT_IMGS_DIR = x"" ]; then
        return 0
    fi

    if [ -e $PREBUILT_IMGS_DIR ]; then
        echo "cp -f $PREBUILT_IMGS_DIR/* $dest_dir"
        cp -f $PREBUILT_IMGS_DIR/* $dest_dir
    fi
}

# copy sec.dat to dest_dir
function copy_efuse_if_needed()
{
    local dest_dir=$1
    if [ x$HQ_EFUSE_ENABLE = x"true" ]; then
        echo "cp -f $PREBUILT_IMGS_DIR/efuse/* $dest_dir"
        cp -f $PREBUILT_IMGS_DIR/efuse/* $dest_dir
    fi
}

function copy_nonhlos_component_elf()
{
    local component=$1
    local dest_dir=$2
    cd $ROOT_DIR/vendor/qcom/$NON_HLOS_DIR
    echo "cd $ROOT_DIR/vendor/qcom/$NON_HLOS_DIR"
    if [ ! -e copy-all-elf.sh ]; then
        echo "================copy-all-elf.sh not exists!==============="
        cp -f hq_build/copy-all-elf.sh copy-all-elf.sh
        echo "cp -f hq_build/copy-all-elf.sh copy-all-elf.sh"
        chmod 777 copy-all-elf.sh
    fi
    echo "============build copy-all-elf.sh begin!=============="
    ./copy-all-elf.sh $QCOM_PLATFORM $component $dest_dir

}

function copy_lk_symbol()
{
    local dest_dir=$1
    #cp -f ${OUT_TARGET_DIR}/obj/EMMC_BOOTLOADER_OBJ/build-msm*/lk $dest_dir
}

function copy_vmlinux()
{
    local dest_dir=$1
    cp -f ${OUT_TARGET_DIR}/obj/KERNEL_OBJ/vmlinux $dest_dir
    echo "cp -f ${OUT_TARGET_DIR}/obj/KERNEL_OBJ/vmlinux $dest_dir"
}

function copy_secimagelog()
{
    local dest_dir=$1
    cp -f ${OUT_TARGET_DIR}/secimage.log $dest_dir
    cp -f ${OUT_TARGET_DIR}/secimage_hq.log $dest_dir
}

function copy_sparse_image()
{
    local dest_dir=$1

    # copy ap sparsed images and delete the Redundant
    cd $ROOT_DIR/vendor/qcom/$NON_HLOS_DIR
    if [ ! -e copy_sparse_imgs.sh ]; then
        echo "cp -f hq_build/copy_sparse_imgs.sh copy_sparse_imgs.sh"
        cp -f hq_build/copy_sparse_imgs.sh copy_sparse_imgs.sh
    fi

    echo "./copy_sparse_imgs.sh $HQ_PRODUCT_ID $dest_dir"
    ./copy_sparse_imgs.sh $dest_dir
}

function backup_symbols()
{
    echo "===========backup symbols begin!============"
    copy_lk_symbol $SYMBOLS_DIR
    copy_vmlinux $SYMBOLS_DIR
    copy_nonhlos_component_elf all $SYMBOLS_DIR
    local symbols_zip=$OUT_TARGET_DIR/${SYMBOLS}.zip
    echo "$symbols_zip"
    if [ -e $symbols_zip ]; then
        rm -f $symbols_zip
        echo "rm -f $symbols_zip"
    fi

    cd $SYMBOLS_DIR
    echo "cd $SYMBOLS_DIR"
    echo "${SYMBOLS}: pack ..."
    zip -r ../${SYMBOLS}.zip ./* >>/dev/null
    echo "${SYMBOLS}.zip is done."
    # if [ -e $symbols_zip ]; then
    #     cd $PRODUCT_TARGET_DIR
    #     if [ -e $symbols_zip ]; then
    #         rm -f ${SYMBOLS}.zip
    #         echo "rm -rf ${SYMBOLS}.zip"
    #     fi
    #     cp -r $symbols_zip $PRODUCT_TARGET_DIR
    #     echo "cp -r $symbols_zip $PRODUCT_TARGET_DIR"
    # fi
    echo "===========backup symbols end!============"
}

function overlay_contents_if_needed()
{
    if [[ x$contents_file != x"" ]]; then
        local src_contents=$ROOT_DIR/$contents_file
        echo "src_contents=$src_contents"
        if [ ! -e $src_contents ]; then
            echo "Error: $src_contents does not exist!"
            exit 1
        fi
        local des_contents=$ROOT_DIR/vendor/qcom/$NON_HLOS_DIR/$MSM_DEVICE_DIR/contents.xml
        cp -f $src_contents $des_contents
        echo "cp -f $src_contents $des_contents"
    fi
}

function filter_out_readme()
{
    if [[ $1 =~ ^\./[Rr][Ee][Aa][Dd][Mm][Ee].* ]]
    then
        return 1
    fi
    return 0
}

function copy_src_files()
{
    #copy_src_files_old
    copy_src_files_common
    copy_src_files_qcom
    copy_src_files_product
}

function copy_src_files_old()
{
    echo "copy src files ..."
    echo "src_dir: $SRC_OVERLAY_DIR des_dir: $ROOT_DIR"
    if [ ! -e $SRC_OVERLAY_DIR ]; then
        echo "Error: $SRC_OVERLAY_DIR doesnot exist!"
        exit 1
    fi

    cd $SRC_OVERLAY_DIR
    local file_path_list=`find . -name "*"`
    for file_path in $file_path_list
    do
        filter_out_readme $file_path
        if [ $? -gt 0 ]; then continue; fi

        if [ -f $file_path ]; then
            local strip_file_path=${file_path:2}
            local src=$SRC_OVERLAY_DIR/$strip_file_path
            local des=$ROOT_DIR/$strip_file_path
            echo "cp -af $src $des"
            cp -af $src $des
        fi
    done

    if [ $? -gt 0 ]
    then
        echo "Failed to copy src files!"
        exit 1
    fi
}

function copy_src_files_common()
{
    echo "copy src files ..."
    echo "src_dir: $SRC_OVERLAY_COMMON_DIR des_dir: $ROOT_DIR"
    if [ ! -e $SRC_OVERLAY_COMMON_DIR ]; then
        echo "Error: $SRC_OVERLAY_COMMON_DIR doesnot exist!"
        exit 1
    fi

    cd $SRC_OVERLAY_COMMON_DIR
    local file_path_list=`find . -name "*"`
    for file_path in $file_path_list
    do
        filter_out_readme $file_path
        if [ $? -gt 0 ]; then continue; fi

        if [ -f $file_path ]; then
            local strip_file_path=${file_path:2}
            local src=$SRC_OVERLAY_COMMON_DIR/$strip_file_path
            local des=$ROOT_DIR/$strip_file_path
            echo "cp -af $src $des"
            cp -af $src $des
        fi
    done

    if [ $? -gt 0 ]
    then
        echo "Failed to copy src files!"
        exit 1
    fi
}

function copy_src_files_qcom()
{
    echo "copy src files ..."
    echo "src_dir: $SRC_OVERLAY_QCOM_DIR des_dir: $ROOT_DIR"
    if [ ! -e $SRC_OVERLAY_QCOM_DIR ]; then
        echo "Error: $SRC_OVERLAY_QCOM_DIR doesnot exist!"
        exit 1
    fi

    cd $SRC_OVERLAY_QCOM_DIR
    local file_path_list=`find . -name "*"`
    for file_path in $file_path_list
    do
        filter_out_readme $file_path
        if [ $? -gt 0 ]; then continue; fi

        if [ -f $file_path ]; then
            local strip_file_path=${file_path:2}
            local src=$SRC_OVERLAY_QCOM_DIR/$strip_file_path
            local des=$ROOT_DIR/$strip_file_path
            echo "cp -af $src $des"
            cp -af $src $des
        fi
    done

    if [ $? -gt 0 ]
    then
        echo "Failed to copy src files!"
        exit 1
    fi
}

function copy_src_files_product()
{
    echo "copy src files ..."
    echo "src_dir: $SRC_OVERLAY_PRODUCT_DIR des_dir: $ROOT_DIR"
    if [ ! -e $SRC_OVERLAY_PRODUCT_DIR ]; then
        echo "Error: $SRC_OVERLAY_PRODUCT_DIR doesnot exist!"
        exit 1
    fi

    cd $SRC_OVERLAY_PRODUCT_DIR
    local file_path_list=`find . -name "*"`
    for file_path in $file_path_list
    do
        filter_out_readme $file_path
        if [ $? -gt 0 ]; then continue; fi

        if [ -f $file_path ]; then
            local strip_file_path=${file_path:2}
            local src=$SRC_OVERLAY_PRODUCT_DIR/$strip_file_path
            local des=$ROOT_DIR/$strip_file_path
            echo "cp -af $src $des"
            cp -af $src $des
        fi
    done

    if [ $? -gt 0 ]
    then
        echo "Failed to copy src files!"
        exit 1
    fi
}

function copy_src_files_if_needed()
{
    echo "SRC_OVERLAY_ENABLE=$SRC_OVERLAY_ENABLE SRC_OVERLAY_IN_CASE=$SRC_OVERLAY_IN_CASE"
    if [ x$SRC_OVERLAY_ENABLE = x"true" ]; then
        if [[ x$SRC_OVERLAY_IN_CASE == x"factory" && x$FACTORY_VERSION_MODE == x"true" ]] || \
           [[ x$SRC_OVERLAY_IN_CASE == x"normal" && x$FACTORY_VERSION_MODE == x"" ]] || \
           [[ x$SRC_OVERLAY_IN_CASE == x"both" ]]; then
            echo "don't need to copy files"
            #copy_src_files
        fi
    fi

    if [ x$PARTITION_FILE != x"" ]; then
        echo "$PARTITION_FILE"
        echo "cp -f $PARTITION_FILE $ROOT_DIR/vendor/qcom/$NON_HLOS_DIR/$MSM_DEVICE_DIR/common/config/partition.xml"
        cp -f $PARTITION_FILE $ROOT_DIR/vendor/qcom/$NON_HLOS_DIR/$MSM_DEVICE_DIR/common/config/partition.xml
    fi
}

# BSP.memory - 2022.5.27 - copy MI FFU file
function copy_mi_ffu()
{
	local dest_dir=$1
	cd $ROOT_DIR
	echo "dest_dir=$dest_dir"
	echo "cp -f -r ./device/xiaomi/$HQ_PRODUCT_ID/MI_FFU $dest_dir"
	cp -f -r ./device/xiaomi/$HQ_PRODUCT_ID/MI_FFU $dest_dir
}
# end edit

function build_nonhlos_component()
{
    local component=$(expr "$1" : '^qcom-\(.*\)')
    make_nonhlos_component $component

    if [ "$HQ_BUILD_MODE" != "clean" ]; then
        generate_device_bins nonhlos
        copy_nonhlos_component $component $PREBUILT_IMGS_DIR
        copy_nonhlos_component $component $VER_IMAGES_DIR
        copy_nonhlos_component_elf $component $SYMBOLS_DIR
    fi
}

# usage: generate_device_bins <mode>
# mode:
#        nonhlos  (generates NON_HLOS.bin alone)
#        hlos     (generates sparse images if rawprogram0.xml exists)
#        all      (generates NON-HLOS.bin and sparse images)
function generate_device_bins()
{
    local mode=$1
    overlay_contents_if_needed
    cd ${ROOT_DIR}/vendor/qcom/${NON_HLOS_DIR}/
    echo "generate_device_bins"
    cp -f hq_build/split_sparse.sh split_sparse.sh
    cp -f hq_build/build_ln.sh build_ln.sh
    cp -f hq_build/rm_ln.sh rm_ln.sh
    chmod 777 split_sparse.sh build_ln.sh rm_ln.sh
    ./split_sparse.sh $HQ_PRODUCT_ID $mode no_parse_cfg
}

function make_update_api()
{
    cd $ROOT_DIR
    make -j${CPUS} update-api $MAKE_PRINT
    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi
}

function make_target_files_package()
{
    cd $ROOT_DIR
    echo "make -j${CPUS} target-files-package $MAKE_PRINT"
    make -j${CPUS} target-files-package $MAKE_PRINT
    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi
}

# function make_qssi()
# {
#     if [ "$BUILD_SIGN_FOR_SECBOOT" = "true" ]; then
#         # 1. call xiaomi vpn connection
#         echo "sign qssi ,enable xiaomi vpn"
#         check_vpn_state
#         #xiaomi_vpn_trigger
#     fi

#     case $HQ_BUILD_MODE in
#         new)
#             echo "======command: build.sh -j${CPUS} dist=========="
#             make clean -j${CPUS} $MAKE_PRINT
#             echo "========make clean done!===="
#             bash build.sh dist -j${CPUS} --qssi_only
#             echo "========build done!======="
#              ;;
#         remake)
#             bash build.sh dist -j${CPUS} --qssi_only
#         ;;
#         clean) make clean -j${CPUS} $MAKE_PRINT ;;
#     esac
#     if [ ${PIPESTATUS[0]} -gt 0 ]
#     then
#         echo "for more information, please check $LOG_FILE_PATH"
#         exit 1
#     fi

#     if [ "$BUILD_SIGN_FOR_SECBOOT" = "true" ]; then
#         echo "sign qssi end ,disable xiaomi vpn"
#         #stop_vpn
#         #sleep 120
#     fi
# }

function make_hlos()
{
    # follow release note, remove this templetly by panghongbo begin 
    # make_update_api
    # echo "after make_update_api"
    # follow release note, remove this templetly by panghongbo end


    if [ "$BUILD_SIGN_FOR_SECBOOT" = "true" ]; then
        # 1. call xiaomi vpn connection
        echo "sign hlos ,enable xiaomi vpn"
        check_vpn_state
        #xiaomi_vpn_trigger
    fi


    case $HQ_BUILD_MODE in
        new) 
            # if [ "$BUILD_VARIANT" = "user" ];then
            #     echo "============build user!======"
            #     echo "======command: build.sh -j${CPUS} dist KERNEL_DEFCONFIG=vendor/$HQ_PRODUCT_ID-qgki_defconfig "
            #     make clean -j${CPUS} $MAKE_PRINT
            #     bash build.sh dist -j${CPUS} KERNEL_DEFCONFIG=vendor/$HQ_PRODUCT_ID-qgki_defconfig
            # elif [ "$BUILD_VARIANT" = "userdebug" ];then
            #     echo "============build userdebug!======"
            #     echo "======command: build.sh -j${CPUS} dist "
            #     make clean -j${CPUS} $MAKE_PRINT
            #     bash build.sh dist -j${CPUS} --target_only
            # fi
            echo "==========build hlos!======="
            echo "======command: build.sh -j${CPUS} dist=========="
            make clean -j${CPUS} $MAKE_PRINT
            echo "========make clean done!===="
            make -j${CPUS} target-files-package
             ;;
        remake) 
            # if [ "$BUILD_VARIANT" = "user" ];then
            #     echo "============build user!======"
            #     echo "======command: build.sh -j${CPUS} dist KERNEL_DEFCONFIG=vendor/$HQ_PRODUCT_ID-qgki_defconfig "
            #     bash build.sh dist -j${CPUS} KERNEL_DEFCONFIG=vendor/$HQ_PRODUCT_ID-qgki_defconfig --target_only
            
            # elif [ "$BUILD_VARIANT" = "userdebug" ];then
            #     echo "============build userdebug!======"
            #     echo "======command: build.sh -j${CPUS} dist "
            #     bash build.sh dist -j${CPUS} --target_only
            # fi
            make -j${CPUS} target-files-package
        ;;
        clean) make clean -j${CPUS} $MAKE_PRINT ;;
    esac
    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi

    if [ "$BUILD_SIGN_FOR_SECBOOT" = "true" ]; then
        echo "sign hlos end ,disable xiaomi vpn"
        #stop_vpn
        #sleep 120
    fi
}

function build_ninja()
{
    cd $ROOT_DIR
    make -j${CPUS} prepare_ninja $MAKE_PRINT

    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi
}

function copy_hlos_component()
{
    local obj=$1
    local dest_dir=$2
    cd $ROOT_DIR
    ./build/make/hq_tools/copy_ap_imgs.sh $HQ_PRODUCT_ID $dest_dir $obj $ROOT_DIR
}

#make root package
function make_root()
{
    cd $ROOT_DIR
    if [-d "./out/target/product/$HQ_PRODUCT_ID/root"]; then
        rm -rf ./out/target/product/$HQ_PRODUCT_ID/root
    fi
    if [-d "./out/target/product/$HQ_PRODUCT_ID/recovery"]; then
        rm -rf ./out/target/product/$HQ_PRODUCT_ID/recovery
    fi

    choosecombo release $HQ_PRODUCT_ID eng
    make recoveryimage -j`expr $CPUS \* 2` 2>&1 | tee $HQ_PRODUCT_ID-recoveryimage.log
    if [ ! -f "./out/target/product/$HQ_PRODUCT_ID/recovery.img" ]; then
        make bootimage -j`expr $CPUS \* 2` 2>&1 | tee $HQ_PRODUCT_ID-bootimage.log
    fi
    if [${PIPESTATUS[0]} -ne 0]; then
        echo "build: make root image error!"
        exit 1
    fi

    if [-d "./out/target/product/$HQ_PRODUCT_ID/root_img"]; then
        rm -rf ./out/target/product/$HQ_PRODUCT_ID/root_img
    fi

    mkdir ./out/target/product/$HQ_PRODUCT_ID/root_img
    mv ./out/target/product/$HQ_PRODUCT_ID/boot.img ./out/target/product/$HQ_PRODUCT_ID/root_img
    if [ -f "./out/target/product/$HQ_PRODUCT_ID/recovery.img" ]; then
        mv ./out/target/product/$HQ_PRODUCT_ID/recovery.img ./out/target/product/$HQ_PRODUCT_ID/root_img
    fi
    
    mv -f ./out/target/product/$HQ_PRODUCT_ID/ramdisk.img ./out/target/product/$HQ_PRODUCT_ID/root_img
    mv -f ./out/target/product/$HQ_PRODUCT_ID/kernel ./out/target/product/$HQ_PRODUCT_ID/root_img
    mv -f ./out/target/product/$HQ_PRODUCT_ID/obj/KERNEL_OBJ/vmlinux ./out/target/product/$HQ_PRODUCT_ID/root_img
    mv -f ./out/target/product/$HQ_PRODUCT_ID/root ./out/target/product/$HQ_PRODUCT_ID/root_img
    mv -f ./out/target/product/$HQ_PRODUCT_ID/recovery ./out/target/product/$HQ_PRODUCT_ID/root_img
}

function switch_build_variant()
{
    choosecombo release $HQ_PRODUCT_ID $BUILD_VARIANT
}

function build_hlos()
{
    #if [ x$BUILD_VARIANT = x"user" ]; then
    #    make_root
    #    switch_build_variant
    #fi

    make_hlos

    if [ "$HQ_BUILD_MODE" != "clean" ]; then
        sign_if_needed $BUILD_SIGN_FOR_SECBOOT $BUILD_OBJECT
        copy_hlos_component all $VER_IMAGES_DIR
        copy_lk_symbol $SYMBOLS_DIR
        copy_vmlinux $SYMBOLS_DIR
    fi

    if [ "$BUILD_TGT_FILES_PKG" = "true" ]; then
        make_target_files_package
    fi
    
    echo "build hlos is done."
}

function build_non_hlos()
{
    make_nonhlos
    if [ "$HQ_BUILD_MODE" != "clean" ]; then
        sign_if_needed $BUILD_SIGN_FOR_SECBOOT $BUILD_OBJECT
        generate_device_bins nonhlos
        copy_nonhlos_component all $PREBUILT_IMGS_DIR
        copy_nonhlos_component all $VER_IMAGES_DIR
        copy_efuse_if_needed $VER_IMAGES_DIR
        copy_nonhlos_component_elf all $SYMBOLS_DIR
    fi
    echo "build non-hlos is done."
}

function build_aboot()
{
    cd $ROOT_DIR
    make aboot -j${CPUS} $MAKE_PRINT
    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi

    if [ "$HQ_BUILD_MODE" != "clean" ]; then
        copy_hlos_component lk $VER_IMAGES_DIR
        copy_lk_symbol $SYMBOLS_DIR
    fi
}

# $1=*image 
# normally [bootimage systemimage dataimage recoveryimage]
function build_hlos_image()
{
    local obj=$1
    local partition=$(expr "$obj" : '\(.*\)image$')
    if [ "$HQ_BUILD_MODE" = "nodeps" ]; then
        obj=${obj}-nodeps
    fi

    cd $ROOT_DIR
    echo "build_hlos_image: obj=$obj partition=$partition"
    make $obj -j${CPUS} $MAKE_PRINT
    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi

    if [ "$HQ_BUILD_MODE" != "clean" ]; then
        cp -f ${OUT_TARGET_DIR}/${partition}.img $VER_IMAGES_DIR
        if [ "$partition" = "boot" ]; then
            copy_vmlinux $SYMBOLS_DIR
        fi
    fi
}

# mkdir all_images and generate all_images.zip
function zip_all_images()
{
    echo "=============== START TO GENERATE DOWNLOAD PACKAGE(UNSPARSED) ================"
    # delete old
    echo "zip_all_images: delete old folder and zip if exists"
    echo "$ALL_IMAGES_DIR"

    echo "============ START TO CLEAN ALL_IAMGES FLODER AND ZIP FILE ============="
    if [ -e $ALL_IMAGES_DIR ]; then
        echo "${ALL_IMAGES_DIR} exists"
        rm -rf $ALL_IMAGES_DIR
        echo "rm -rf $ALL_IMAGES_DIR"
    fi

    if [ -e $IMAGES_FILE ]; then
        echo "${IMAGES_FILE} exists"
        rm -f $IMAGES_FILE
        echo "rm -f $IMAGES_FILE"
    fi

    # mkdir new
    echo "zip_all_images: copy all images(non-hlos and hlos images)"
    mkdir -p $IMAGES_DIR
    echo "${IMAGES_DIR}"

    if [ $? -gt 0 ]
    then
        echo "Error: fail to create dir $IMAGES_DIR."
        exit 1
    fi

    # copy prebuilt images
    copy_prebuilt_images $IMAGES_DIR

    # copy hlos image
    copy_hlos_component all $IMAGES_DIR

    # copy non-hlos
    copy_nonhlos_component all $IMAGES_DIR

    # copy efuse if need
    copy_efuse_if_needed $IMAGES_DIR

    # copy MI_FFU
    copy_mi_ffu $IMAGES_DIR

    # flash_scripts
    if [ -e $FLASH_SCRIPTS_DIR ]; then
        echo "copying flash scripts ..."
        cp $FLASH_SCRIPTS_DIR/* $ALL_IMAGES_DIR
    fi

    #cust_all_images
    #cust_all_images $VERSION_DIR

    # 4-gen crc list
    echo "gen crc list......"
    cd $ALL_IMAGES_DIR
    python flash_gen_crc_list.py
    #rm -f flash_gen_crc_list.py
    rm -f flash_gen_resparsecount

    # pack
    echo "$ALL_IMAGES_DIR: pack ..."
    cd $ALL_IMAGES_DIR
    zip -r ../$VER_DIR_NAME.zip ./* >>/dev/null
    echo "$VER_DIR_NAME.zip is done."
    echo "zip_all_images done."
}



# mkdir all_sparse_images and generate all_sparse_images.zip
function zip_all_sparse_images()
{
    echo "================ START TO GENERATE DOWNLOAD PACKAGE(SPARSED) ================="
    # delete old
    echo "all_sparse_images: delete old folder and zip if exists"
    if [ -e $SPARSE_IMAGES_DIR ]; then
        rm -rf $SPARSE_IMAGES_DIR
    fi

    if [ -e $SPARSE_IMAGES_FILE ]; then
        rm -f $SPARSE_IMAGES_FILE
    fi

    # mkdir new
    echo "all_sparse_images: copy all images(non-hlos, hlos and sparse images)"
    mkdir -p $SPARSE_IMAGES_DIR
    if [ $? -gt 0 ]
    then
        echo "Error: fail to create dir $SPARSE_IMAGES_DIR."
        exit 1
    fi

    # copy prebuilt images
    copy_prebuilt_images $SPARSE_IMAGES_DIR

    # copy hlos image
    copy_hlos_component all $SPARSE_IMAGES_DIR

    # copy non-hlos
    copy_nonhlos_component all $SPARSE_IMAGES_DIR

    # copy efuse if need
    copy_efuse_if_needed $SPARSE_IMAGES_DIR

    # copy sparse images
    copy_sparse_image $SPARSE_IMAGES_DIR

    # cust for all_sparse_image
    #cust_all_sparse_images $SPARSE_VERSION_DIR
    
    # md5 will be used by XI AN tools
    echo "MD5 checksum ..."
    echo "$ROOT_DIR/build/make/hq_tools/Md5Data.py $SPARSE_IMAGES_DIR"
    python $ROOT_DIR/build/make/hq_tools/Md5Data.py $SPARSE_IMAGES_DIR

    # pack
    cd $SPARSE_IMAGES_DIR
    echo "$SPARSE_IMAGES_DIR: pack ..."
    zip -r ../$SPARSE_VER_DIR_NAME.zip ./* >>/dev/null
    echo "$SPARSE_VER_DIR_NAME.zip is done."
}

function build_vendor()
{
    echo "==========build make_hlos begin!========="
    build_hlos
    echo "==========build make_hlos end!========="
    if [[ x$HQ_COMPILE_BP_SYNC != x"true" ]]; then
        echo "==========build make_nonhlos begin!========="
        build_non_hlos
        echo "==========build make_nonhlos end!========="
    fi
#    sign_if_needed $BUILD_SIGN_FOR_SECBOOT $BUILD_OBJECT

    ####### miui merge script #####
    localname=`whoami`

#    ls $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/obj/PACKAGING/target_files_intermediates

#    generate_device_bins vendor
#    if [ $? -gt 0 ]
#    then
#        echo "Error: fail to generate_device_bins."
#        exit 1
#    fi


    if [ "$BUILD_TGT_FILES_PKG" = "true" ]; then
        echo "==========build make_target_files_package begin!========="
        make_target_files_package
        echo "==========build make_target_files_package end!========="
    fi

    #add hq ci-build
    if [ "$HQ_CI_BUILD" = "true" ];then
        echo "***** CI build do not copy all images *****"

    else
        backup_symbols
        zip_all_images
        zip_all_sparse_images
    fi

    echo "==========build vendor end!========="
}

function build_all()
{
    echo "==========build make_hlos begin!========="
    make_hlos
    echo "==========build make_hlos end!========="
    if [[ x$HQ_COMPILE_BP_SYNC != x"true" ]]; then
        echo "==========build make_nonhlos begin!========="
        make_nonhlos
        echo "==========build make_nonhlos end!========="
    fi
    sign_if_needed $BUILD_SIGN_FOR_SECBOOT $BUILD_OBJECT
    
    ####### miui merge script ##### 
    localname=`whoami`
    
    ls $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/obj/PACKAGING/target_files_intermediates

#    unzip -o -d $ROOT_DIR/QSSI12/out/target/product/qssi/otatools $ROOT_DIR/QSSI12/out/target/product/qssi/otatools.zip
    #  (本地不清除out编译的话，只需要运行一次这个命令就好)

#    $ROOT_DIR/QSSI12/out/target/product/qssi/otatools/bin/merge_target_files \
#        --path $ROOT_DIR/QSSI12/out/target/product/qssi/otatools \
#        --framework-target-files $ROOT_DIR/QSSI12/out/target/product/qssi/obj/PACKAGING/target_files_intermediates/qssi-target_files-eng.$localname.zip \
#        --vendor-target-files $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/obj/PACKAGING/target_files_intermediates/$HQ_PRODUCT_ID-target_files-eng.$localname.zip \
#        --output-target-files $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/$HQ_PRODUCT_ID-merged-target_files.zip \
#        --framework-misc-info-keys $ROOT_DIR/QSSI12/device/qcom/qssi/ota_merge_configs/dynamic_partition/ab/merge_config_system_misc_info_keys \
#        --framework-item-list $ROOT_DIR/QSSI12/device/qcom/qssi/ota_merge_configs/dynamic_partition/ab/merge_config_system_item_list \
#        --vendor-item-list  $ROOT_DIR/QSSI12/device/qcom/qssi/ota_merge_configs/dynamic_partition/ab/merge_config_other_item_list \
#        --allow-duplicate-apkapex-keys

#    unzip -o -d $ROOT_DIR/QSSI12/out/target/product/qssi/merged_folder $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/$HQ_PRODUCT_ID-merged-target_files.zip

#    $ROOT_DIR/QSSI12/out/target/product/qssi/otatools/releasetools/build_super_image.py $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/$HQ_PRODUCT_ID-merged-target_files.zip $ROOT_DIR/QSSI12/out/target/product/qssi/merged_folder/super.img
    
#    rm -rf $ROOT_DIR/QSSI12/out/target/product/qssi/merged_folder/IMAGES/userdata.img

#    cp -f $ROOT_DIR/QSSI12/out/target/product/qssi/merged_folder/IMAGES/* $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/

#    cp -f $ROOT_DIR/QSSI12/out/target/product/qssi/merged_folder/super.img $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/
    
#    echo "Rainbow's superscript success"
    ####### miui merge script #####

    # python $ROOT_DIR/vendor/qcom/opensource/core-utils/build/build_image_standalone.py --image super --qssi_build_path $ROOT_DIR/QSSI12 --target_build_path $ROOT_DIR --merged_build_path $ROOT_DIR --target_lunch moonstone --skip_qiifa --output_ota 2>&1 |tee $ROOT_DIR/log/build_image_standalone_log.txt

    #判断是否生成super.img,没有生成img,则退出编译
#    if [ ! -e $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID/super.img ]; then
#          echo "error:can't find super.img,please check log!"
#          exit 1
#    fi

    generate_device_bins all
    if [ $? -gt 0 ]
    then
        echo "Error: fail to generate_device_bins."
        exit 1
    fi


    if [ "$BUILD_TGT_FILES_PKG" = "true" ]; then
        echo "==========build make_target_files_package begin!========="
        make_target_files_package
        echo "==========build make_target_files_package end!========="
    fi

    

    #add hq ci-build
    if [ "$HQ_CI_BUILD" = "true" ];then
        echo "***** CI build do not copy all images *****"

    else
        backup_symbols
        zip_all_images
        zip_all_sparse_images
    fi
}

function setup_ccache()
{
    if [[ x$CI_CCACHE_PATH != x"" && -d $CI_CCACHE_PATH ]]; then
        export CCACHE_DIR=$CI_CCACHE_PATH/.ccache/$HQ_PRODUCT_ID
    else
        export CCACHE_DIR=../.ccache/$HQ_PRODUCT_ID
    fi

    export USE_CCACHE=1
    echo "CCACHE_DIR=$CCACHE_DIR USE_CCACHE=$USE_CCACHE"
    if [ ! -e $CCACHE_DIR ]; then
        mkdir -p $CCACHE_DIR
    fi
}

function delete_ccache()
{
    prebuilts/misc/linux-x86/ccache/ccache -C
    rm -rf $CCACHE_DIR
}

function create_ccache()
{
    echo -e "\nINFO: Setting CCACHE with 50 GB\n"
    delete_ccache
    setup_ccache
    prebuilts/misc/linux-x86/ccache/ccache -M 50G
}

# Parse Parameters
function parse_params()
{
    TEMP=`getopt -o lescftbhpiv:o:m: --long license,efuse,sign,cust-key,factory,tgt-files,bp-sync,help,proxy,ci-build,variant:,object:,mode: -n '* ERROR' -- "$@"`
    if [ $? != 0 ] ; then echo error "$0 exited with doing nothing." >&2 ; exit 1 ; fi

    # Note the quotes around $TEMP: they are essential!  
    eval set -- "$TEMP"

    # set option values  
    while true; do
        if [ "$1" = "" ]; then break; fi
        case "$1" in
            -h | --help) usage; exit 1 ;;
            -l | --license) HQ_BUILD_ARM_LICENSE=true; shift ;;
            -e | --efuse) HQ_EFUSE_ENABLE=true; shift ;;
            -s | --sign) BUILD_SIGN_FOR_SECBOOT=true; shift ;;
            -p | --proxy) export HQ_BUILD_SIGN_PROXY=true; shift ;;
            -c | --cust-key) HQ_USE_CUST_KEY=true; shift ;;
            -f | --factory) export FACTORY_VERSION_MODE=true; export FACTORY_BUILD=1; shift ;;
            -t | --tgt-files) BUILD_TGT_FILES_PKG=true; shift ;;
            -b | --bp-sync) export HQ_COMPILE_BP_SYNC=true; shift ;;
            -v | --variant) BUILD_VARIANT=$2; shift 2 ;;
            -o | --object) BUILD_OBJECT=$2; shift 2 ;;
            -m | --mode) HQ_BUILD_MODE=$2; shift 2 ;;
            -i | --ci-build) export HQ_CI_BUILD=true; shift ;;
            --) HQ_PRODUCT_ID=$2; shift 2 ;;
            *) echo error "Invalid option! use [$0 -h] to view the help info." ; exit 1 ;;
         esac
    done
}

# check env
function check_env()
{
    #check_gcc_version   //Don't check gcc version.The newest gcc version has been updated to 7.**
    check_build_mode
    check_build_variant
    check_security
}

# Show Build Info
function show_build_info()
{
    show_java_version
    echo "================================================="
    echo "HQ_PRODUCT_ID=$HQ_PRODUCT_ID"
    echo "HQ_EFUSE_ENABLE=$HQ_EFUSE_ENABLE"
    echo "BUILD_SIGN_FOR_SECBOOT=$BUILD_SIGN_FOR_SECBOOT"
    echo "HQ_BUILD_SIGN_PROXY=$HQ_BUILD_SIGN_PROXY"
    echo "HQ_BUILD_ARM_LICENSE=$HQ_BUILD_ARM_LICENSE"
    echo "HQ_RFCARD_MODE=$HQ_RFCARD_MODE"
    echo "BUILD_VARIANT=$BUILD_VARIANT"
    echo "BUILD_OBJECT=$BUILD_OBJECT"
    echo "HQ_BUILD_MODE=$HQ_BUILD_MODE"
    echo "BUILD_TGT_FILES_PKG=$BUILD_TGT_FILES_PKG"
    echo "MSM_DEVICE_DIR=$MSM_DEVICE_DIR"
    echo "QCOM_PLATFORM=$QCOM_PLATFORM"
    echo "OUT_TARGET_DIR=$OUT_TARGET_DIR"
    echo "HQ_CI_BUILD=$HQ_CI_BUILD"
    echo "================================================="
}

# load functions
function load_functions()
{
    source $ROOT_DIR/build/make/hq_tools/parse_config.sh
    source $ROOT_DIR/build/make/hq_tools/$HQ_PRODUCT_ID/sign_images.sh
    source $ROOT_DIR/build/make/hq_tools/$HQ_PRODUCT_ID/use_cust_key.sh
    source $ROOT_DIR/build/make/hq_tools/$HQ_PRODUCT_ID/package_version.sh
}

function use_cust_key_if_needed()
{
    if [ $HQ_USE_CUST_KEY = "true" ]; then
        use_cust_key
    fi
}

# init ccache
function init_ccache()
{
    if [ "$CCACHE" = "true" ]; then
        setup_ccache
        if [ $HQ_BUILD_MODE = "clean" ]; then
            create_ccache
        fi
    fi
}

# lunch project
function lunch_project()
{
    cd $ROOT_DIR
    echo "{$ROOT_DIR}"
    echo "===============source before lunch=========="
    source build/envsetup.sh
    echo "===============source end==============="
    lunch ${HQ_PRODUCT_ID}-${BUILD_VARIANT}
    # echo "===============lunch end================"
    if [ $? -gt 0 ]; then
        exit 1
    fi
}

# init log file
function init_logfile()
{
    local obj=$1
    if [[ ! -e $LOG_DIR ]]; then
        mkdir -p $LOG_DIR
    fi

    if [ x$obj = x"all" ]; then
        obj=build_all
    fi

    dt_str=$(date +"[%Y-%m-%d]_[%H-%M-%S]")
    LOG_FILE=${obj}_${dt_str}.log
    LOG_FILE_PATH=$LOG_DIR/$LOG_FILE
}

# handle build mode. if handled, exit 0
function handle_build_mode()
{
    init_logfile $HQ_BUILD_MODE
    case $HQ_BUILD_MODE in
        mm | mma)
            if [[ "$BUILD_OBJECT" =~ "$ROOT_DIR" ]]; then
                mm_dir=$BUILD_OBJECT
            else
                mm_dir=$ROOT_DIR/$BUILD_OBJECT
            fi

            if [ -d $mm_dir ]; then
                cd $mm_dir
                $HQ_BUILD_MODE 2>&1 | tee $LOG_FILE_PATH
                echo "log saved in $LOG_FILE_PATH"
                exit 0
            else
                echo "******Invalid BUILD_OBJECT=$BUILD_OBJECT"
                exit 1
            fi
            ;;
        mmm | mmma)
            if [[ "$BUILD_OBJECT" =~ "$ROOT_DIR" ]]; then
                mmm_dir=$BUILD_OBJECT
            else
                mmm_dir=$ROOT_DIR/$BUILD_OBJECT
            fi

            if [ -d $mmm_dir ]; then
                $HQ_BUILD_MODE $mmm_dir 2>&1 | tee $LOG_FILE_PATH
                echo "log saved in $LOG_FILE_PATH"
                exit 0
            else
                echo "******Invalid BUILD_OBJECT=$BUILD_OBJECT"
                exit 1
            fi 
            ;;
        nodeps)
            init_logfile $BUILD_OBJECT-$HQ_BUILD_MODE
            case $BUILD_OBJECT in
                bootimage | systemimage | userdataimage | recoveryimage)
                    build_hlos_image $BUILD_OBJECT 2>&1 | tee $LOG_FILE_PATH
                    exit 0 ;;
                *)
                    echo "***** Unsupported BUILD_OBJECT=${BUILD_OBJECT} *****"
                    echo "Only bootimage, systemimage, userdataimage and recoveryimage are allowed when --mode=nodeps"
                    exit 1 ;;
            esac
            ;;
        clean)
            case $BUILD_OBJECT in
                all | hlos | non-hlos | qcom-*) ;;
                *) echo "***** NO supported .PHONY *****"; exit 1 ;;
            esac
            ;;
    esac
}

# handle build object
function handle_build_object()
{
    init_logfile $BUILD_OBJECT
    case $BUILD_OBJECT in
        all)           build_all 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]};;
        vendor)        build_vendor 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        update-api)    make_update_api 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        hlos)          build_hlos  2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        non-hlos)      build_non_hlos 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        aboot)         build_aboot 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        tgt-files)     make_target_files_package 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        *image)        build_hlos_image $BUILD_OBJECT 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        qcom-*)        build_nonhlos_component $BUILD_OBJECT 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        build_ninja)   build_ninja 2>&1 | tee $LOG_FILE_PATH ; exit_code=${PIPESTATUS[0]} ;;
        *)             echo "***** Unsupported BUILD_OBJECT=${BUILD_OBJECT} *****"; exit 1 ;;
    esac
}

# do main
function do_main()
{
    parse_params $@
    check_env
    load_functions
    parse_config $ROOT_DIR $HQ_PRODUCT_ID
    init_variables
    show_build_info
    init_ccache
    copy_src_files_if_needed
    copy_mi_ffu
    use_cust_key_if_needed
    lunch_project
    handle_build_mode
    handle_build_object
    if [ "${exit_code}" != "0" ]; then
        exit 1
    fi
}

# start
do_main $@



