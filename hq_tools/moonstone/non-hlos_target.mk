# the defined target files are used to check if qcom components are compiled successfully

# mpss
QCT_MPSS_BUILT_TARGET := $(NON_HLOS_PATH)/$(QCT_MPSS_NAME)/modem_proc/build/ms/bin/mannar.gen.prod/qdsp6sw.mbn
QCT_MPSS_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_MPSS_NAME)/modem_proc/build/ms/bin/mannar.gen.prod/efs2.bin
QCT_MPSS_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_MPSS_NAME)/modem_proc/build/ms/bin/mannar.gen.prod/efs1.bin
QCT_MPSS_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_MPSS_NAME)/modem_proc/build/ms/bin/mannar.gen.prod/efs3.bin
QCT_MPSS_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_MPSS_NAME)/modem_proc/build/ms/bin/mannar.gen.prod/qdsp6m.qdb
 

# adsp
QCT_ADSP_BUILT_TARGET := $(NON_HLOS_PATH)/$(QCT_ADSP_NAME)/adsp_proc/build/ms/bin/mannar.adsp.prod2/adsp2.mbn

# rpm
QCT_RPM_BUILT_TARGET := $(NON_HLOS_PATH)/$(QCT_RPM_NAME)/rpm_proc/build/ms/bin/mannar/sdm_ddr4/rpm.mbn

# boot
QCT_BOOT_BUILT_TARGET := $(NON_HLOS_PATH)/$(QCT_BOOT_NAME)/boot_images/QcomPkg/SocPkg/MannarPkg/Library/XBL_SEC/xbl_sec.mbn
QCT_BOOT_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_BOOT_NAME)/boot_images/QcomPkg/SocPkg/MannarPkg/Bin/LAA/RELEASE/xbl.elf

# cdsp
QCT_CDSP_BUILT_TARGET := $(NON_HLOS_PATH)/$(QCT_CDSP_NAME)/cdsp_proc/build/ms/bin/mannar.cdsp.prod/cdsp.mbn

# tz
QCT_TZ_BUILT_TARGET := $(NON_HLOS_PATH)/$(QCT_TZ_NAME)/trustzone_images/build/ms/bin/HACAANAA/tz.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_NAME)/trustzone_images/build/ms/bin/HACAANAA/hyp.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_NAME)/trustzone_images/build/ms/bin/HACAANAA/devcfg.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_NAME)/trustzone_images/build/ms/bin/HACAANAA/smplap32.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_NAME)/trustzone_images/build/ms/bin/HACAANAA/smplap64.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/featenabler.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/smplap64.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/storsec.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/km41.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/uefi_sec.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/widevine.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/securemm.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/soter64.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/hdcpsrm.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/rtic.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/rtic_tst.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/loadalgota64.mbn
QCT_TZ_BUILT_TARGET += $(NON_HLOS_PATH)/$(QCT_TZ_APPS_NAME)/qtee_tas/build/ms/bin/HACAANAA/haventkn.mbn

