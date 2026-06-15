#!/bin/bash
set -e
device=vince            # the sign_key belongs to E7,so the $device must be "vince"
real_device=pine     # $real_device is the real sub_project
date_string=$(date +%F)
cur_time_string=$(date +%S)
random=$RANDOM
SIGN_ROOT_DIR=`pwd`
#source $SIGN_ROOT_DIR/build/make/hq_tools/sakura/verify_shell/vpn_api.sh
#xiaomi_vpn_trigger
#check_vpn_state

origin_file_name="vbmeta.img"
sign_origin_file_name="${cur_time_string}${random}_${origin_file_name}"
RSA_PRIVATE_KEY=$SIGN_ROOT_DIR/build/make/hq_tools/pine/rsa_private_key.pem
base64_signaure=$(echo -n "$date_string$random" | openssl dgst -sha1 -sign $RSA_PRIVATE_KEY | base64)
signed_file_name="signed_VBMETA_${device}_${sign_origin_file_name}"
curl -F "device=$device" -F "data=@$3" -F "file_name=$sign_origin_file_name" -F "signature=$base64_signaure" -F "random=$random"  ${STR_SIGN_SERVER_PROXY}sign.pt.miui.com/api/sign_vbmeta_image.php
echo "Vbmeta.img Successful submission"
sleep 150
echo "150s sleep is finished"
#curl -O sign.pt.miui.com/download/$signed_file_name
wget  ${STR_SIGN_SERVER_PROXY}sign.pt.miui.com/download/$signed_file_name
echo "Vbmeta.img Successful download"
cp $signed_file_name  $3
echo $3
rm $signed_file_name
#stop_vpn
