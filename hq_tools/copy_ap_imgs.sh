#!/bin/bash

# this script should run in AP_ROOT_DIR
HQ_PRODUCT_ID=$1
DEST_DIR=$2
OBJ=$3
ROOT_DIR=$4

if [[ x$HQ_PRODUCT_ID = x"" || x$DEST_DIR = x"" ]]; then
    echo "Error: HQ_PRODUCT_ID=$HQ_PRODUCT_ID DEST_DIR=$DEST_DIR!"
    exit 1
fi

echo "HQ_PRODUCT_ID=$HQ_PRODUCT_ID, DEST_DIR=$DEST_DIR, OBJ=$OBJ, ROOT_DIR=$ROOT_DIR"

if [ ! -e $DEST_DIR ]; then
    mkdir -p $DEST_DIR
fi

# belows are needed to copy for ap
cd out/target/product/$HQ_PRODUCT_ID
if [ -e abl.elf ]; then
    cp -f abl.elf $DEST_DIR/abl.elf
fi

# BSP.System - 2022.6.3
#add cust.img
if [ -e cust.img ]; then
    cp -f cust.img $DEST_DIR/cust.img
fi

# BSP.System - 2022.6.3 - Add rescue.img
if [ -e rescue.img ]; then
    cp -f rescue.img $DEST_DIR/rescue.img
fi

# BSP.System - 2022.6.13 - Add opcust.img
if [ -e opcust.img ]; then
    cp -f opcust.img $DEST_DIR/opcust.img
fi

# BSP.System - 2022.6.13 - Add opconfig.img
if [ -e opconfig.img ]; then
    cp -f opconfig.img $DEST_DIR/opconfig.img
fi

#cp -f *.mbn $DEST_DIR
if [ x$OBJ != x"lk" ]; then
    cp -f *.img $DEST_DIR
fi

#cp super produce .img
cd $ROOT_DIR/out/target/product/$HQ_PRODUCT_ID
pwd
cp -f *.img $DEST_DIR
echo "copying ap images is done!"

