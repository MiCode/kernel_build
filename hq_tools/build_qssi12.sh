ROOT_DIR=`pwd`
LOG_DIR=$ROOT_DIR/log
BUILD_VARIANT=userdebug

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

function check_build_variant()
{
    if [[ "$BUILD_VARIANT" != "user" && "$BUILD_VARIANT" != "userdebug" ]]
    then
        echo "***** Unsupported BUILD_VARIANT=$BUILD_VARIANT *****"
        exit 1
    fi
}

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
            -f | --factory) export FACTORY_VERSION_MODE=true; shift ;;
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

# init log file
function init_logfile()
{
    if [[ ! -e $LOG_DIR ]]; then
        echo "not exists log file"
        mkdir -p $LOG_DIR
    fi

    dt_str=$(date +"[%Y-%m-%d]_[%H-%M-%S]")
    LOG_FILE=build_qssi12_log_${dt_str}.log
    LOG_FILE_PATH=$LOG_DIR/$LOG_FILE
}

# do main
function do_main()
{
    parse_params $@
    init_logfile
    echo "============build QSSI12 begin!=========="
    cd $ROOT_DIR/QSSI12
    source build/envsetup.sh
    lunch qssi-${BUILD_VARIANT}
    make -j${CPUS} target-files-package
    if [ ${PIPESTATUS[0]} -gt 0 ]
    then
        echo "for more information, please check $LOG_FILE_PATH"
        exit 1
    fi
}

# start
do_main $@

