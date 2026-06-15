#!/bin/bash

function use_cust_key()
{
    echo "use_cust_key: CUST_KEY_DIR=$ROOT_DIR/$CUST_KEY_DIR"
    if [ -e $ROOT_DIR/$CUST_KEY_DIR ]; then
        echo "dm-verity enable"
        cp $ROOT_DIR/$CUST_KEY_DIR/oem_keystore.h $ROOT_DIR/bootable/bootloader/lk/platform/msm_shared/include/
        cp $ROOT_DIR/$CUST_KEY_DIR/build_verity_metadata.py $ROOT_DIR/system/extras/verity/
        cp $ROOT_DIR/$CUST_KEY_DIR/verity.pk8 $ROOT_DIR/build/target/product/security/
        cp $ROOT_DIR/$CUST_KEY_DIR/verity.x509.pem $ROOT_DIR/build/target/product/security/
        cp $ROOT_DIR/$CUST_KEY_DIR/verity_key $ROOT_DIR/build/target/product/security/
#        cp $ROOT_DIR/$PREBUILT_IMGS_DIR/efuse/sec.dat $ROOT_DIR/$PREBUILT_IMGS_DIR
    fi
}
