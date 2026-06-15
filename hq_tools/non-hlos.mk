# The makefile is used to compile qcom components synchronized with AP

# $(1) source_file_list
define check_built_target
$(foreach f,$(1), \
if [[ ! -e $(f) ]]; then echo "build $(f) failed!!"; exit 1; fi;)
endef


NON_HLOS_PATH := vendor/qcom/$(NON_HLOS_DIR)
include build/make/hq_tools/$(HQ_PRODUCT_ID)/non-hlos_target.mk

QCT_MPSS_BUILD_CMD := cd $(NON_HLOS_PATH)/hq_build && ./build_modem.sh $(HQ_PRODUCT_ID) $(HQ_BUILD_MODE) no_parse_cfg
QCT_ADSP_BUILD_CMD := cd $(NON_HLOS_PATH)/hq_build && ./build_adsp.sh $(HQ_PRODUCT_ID) $(HQ_BUILD_MODE) no_parse_cfg
QCT_CDSP_BUILD_CMD := cd $(NON_HLOS_PATH)/hq_build && ./build_cdsp.sh $(HQ_PRODUCT_ID) $(HQ_BUILD_MODE) no_parse_cfg
QCT_BOOT_BUILD_CMD := cd $(NON_HLOS_PATH)/hq_build && ./build_boot.sh $(HQ_PRODUCT_ID) $(HQ_BUILD_MODE) no_parse_cfg
QCT_RPM_BUILD_CMD := cd $(NON_HLOS_PATH)/hq_build && ./build_rpm.sh $(HQ_PRODUCT_ID) $(HQ_BUILD_MODE) no_parse_cfg
QCT_TZ_BUILD_CMD := cd $(NON_HLOS_PATH)/hq_build && ./build_tz.sh $(HQ_PRODUCT_ID) $(HQ_BUILD_MODE) no_parse_cfg


none-hlos_intermediates := $(call intermediates-dir-for,PACKAGING,none-hlos)

# boot
BUILT_BOOT_IMAGE_TARGET := $(none-hlos_intermediates)/$(QCT_BOOT_NAME)
$(BUILT_BOOT_IMAGE_TARGET):
	$(call pretty,"Building bootloader")
	$(hide) $(QCT_BOOT_BUILD_CMD)
	$(call check_built_target,$(QCT_BOOT_BUILT_TARGET))
	$(hide) touch $@

# tz
BUILT_TZ_IMAGE_TARGET := $(none-hlos_intermediates)/$(QCT_TZ_NAME)
$(BUILT_TZ_IMAGE_TARGET):
	$(call pretty,"Building tz")
	$(hide) $(QCT_TZ_BUILD_CMD)
	$(call check_built_target,$(QCT_TZ_BUILT_TARGET))
	$(hide) touch $@

# rpm
BUILT_RPM_IMAGE_TARGET := $(none-hlos_intermediates)/$(QCT_RPM_NAME)
$(BUILT_RPM_IMAGE_TARGET):
	$(call pretty,"Building rpm")
	$(warning "non-hlos in rpm : $(BUILT_RADIO_IMAGE_TARGET)")
	$(hide) $(QCT_RPM_BUILD_CMD)
	$(call check_built_target,$(QCT_RPM_BUILT_TARGET))
	$(hide) touch $@

# adsp
BUILT_ADSP_IMAGE_TARGET := $(none-hlos_intermediates)/$(QCT_ADSP_NAME)
$(BUILT_ADSP_IMAGE_TARGET):
	$(call pretty,"Building adsp")
	$(hide) $(QCT_ADSP_BUILD_CMD)
	$(call check_built_target,$(QCT_ADSP_BUILT_TARGET))
	$(hide) touch $@

# cdsp
BUILT_CDSP_IMAGE_TARGET := $(none-hlos_intermediates)/$(QCT_CDSP_NAME)
$(BUILT_CDSP_IMAGE_TARGET):
	$(call pretty,"Building cdsp")
	$(hide) $(QCT_CDSP_BUILD_CMD)
	$(call check_built_target,$(QCT_CDSP_BUILT_TARGET))
	$(hide) touch $@

# mpss
BUILT_MPSS_IMAGE_TARGET := $(none-hlos_intermediates)/$(QCT_MPSS_NAME)
$(BUILT_MPSS_IMAGE_TARGET):
	$(call pretty,"Building mpss")
	$(hide) $(QCT_MPSS_BUILD_CMD)
	$(call check_built_target,$(QCT_MPSS_BUILT_TARGET))
	$(hide) touch $@

BUILT_RADIO_IMAGE_TARGET := $(BUILT_MPSS_IMAGE_TARGET)
BUILT_RADIO_IMAGE_TARGET += $(BUILT_ADSP_IMAGE_TARGET)
BUILT_RADIO_IMAGE_TARGET += $(BUILT_TZ_IMAGE_TARGET)
BUILT_RADIO_IMAGE_TARGET += $(BUILT_CDSP_IMAGE_TARGET)
ifeq ($(HQ_BUILD_ARM_LICENSE),true)
BUILT_RADIO_IMAGE_TARGET += $(BUILT_BOOT_IMAGE_TARGET)
BUILT_RADIO_IMAGE_TARGET += $(BUILT_RPM_IMAGE_TARGET)
endif

$(shell rm -rf $(BUILT_RADIO_IMAGE_TARGET))
$(warning "non-hlos BUILT_RADIO_IMAGE_TARGET=$(BUILT_RADIO_IMAGE_TARGET)")

#droid: meta-build
droid: $(BUILT_RADIO_IMAGE_TARGET)
