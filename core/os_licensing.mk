ifeq ($(TARGET_BUILD_APPS),)

.PHONY: systemlicense
systemlicense: $(call corresponding-license-metadata, $(SYSTEM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(SYSTEM_NOTICE_DEPS))

SYSTEM_NOTICE_DEPS += $(UNMOUNTED_NOTICE_DEPS)

ifneq ($(PRODUCT_NOTICE_SPLIT),true)
$(eval $(call html-notice-rule,$(target_notice_file_html_gz),"System image",$(system_notice_file_message),$(SYSTEM_NOTICE_DEPS),$(SYSTEM_NOTICE_DEPS)))

$(installed_notice_html_or_xml_gz): $(target_notice_file_html_gz)
	$(copy-file-to-target)
else
$(eval $(call xml-notice-rule,$(target_notice_file_xml_gz),"System image",$(system_notice_file_message),$(SYSTEM_NOTICE_DEPS),$(SYSTEM_NOTICE_DEPS)))

$(eval $(call text-notice-rule,$(target_notice_file_txt),"System image",$(system_notice_file_message),$(SYSTEM_NOTICE_DEPS),$(SYSTEM_NOTICE_DEPS)))

$(installed_notice_html_or_xml_gz): $(target_notice_file_xml_gz)
	$(copy-file-to-target)
endif

$(call declare-0p-target,$(target_notice_file_xml_gz))
$(call declare-0p-target,$(installed_notice_html_or_xml_gz))
endif

.PHONY: vendorlicense
vendorlicense: $(call corresponding-license-metadata, $(VENDOR_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(VENDOR_NOTICE_DEPS))

VENDOR_NOTICE_DEPS += $(UNMOUNTED_NOTICE_DEPS)

$(eval $(call text-notice-rule,$(target_vendor_notice_file_txt),"Vendor image", \
         "Notices for files contained in all filesystem images except system/system_ext/product/odm/vendor_dlkm/odm_dlkm in this directory:", \
         $(VENDOR_NOTICE_DEPS),$(VENDOR_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_vendor_notice_file_xml_gz),"Vendor image", \
         "Notices for files contained in all filesystem images except system/system_ext/product/odm/vendor_dlkm/odm_dlkm in this directory:", \
         $(VENDOR_NOTICE_DEPS),$(VENDOR_NOTICE_DEPS)))

$(installed_vendor_notice_xml_gz): $(target_vendor_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_vendor_notice_file_xml_gz))
$(call declare-0p-target,$(installed_vendor_notice_xml_gz))
endif

.PHONY: odmlicense
odmlicense: $(call corresponding-license-metadata, $(ODM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(ODM_NOTICE_DEPS))
$(eval $(call text-notice-rule,$(target_odm_notice_file_txt),"ODM filesystem image", \
         "Notices for files contained in the odm filesystem image in this directory:", \
         $(ODM_NOTICE_DEPS),$(ODM_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_odm_notice_file_xml_gz),"ODM filesystem image", \
         "Notices for files contained in the odm filesystem image in this directory:", \
         $(ODM_NOTICE_DEPS),$(ODM_NOTICE_DEPS)))

$(installed_odm_notice_xml_gz): $(target_odm_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_odm_notice_file_xml_gz))
$(call declare-0p-target,$(installed_odm_notice_xml_gz))
endif

.PHONY: oemlicense
oemlicense: $(call corresponding-license-metadata, $(OEM_NOTICE_DEPS)) reportmissinglicenses

.PHONY: productlicense
productlicense: $(call corresponding-license-metadata, $(PRODUCT_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(PRODUCT_NOTICE_DEPS))
$(eval $(call text-notice-rule,$(target_product_notice_file_txt),"Product image", \
         "Notices for files contained in the product filesystem image in this directory:", \
         $(PRODUCT_NOTICE_DEPS),$(PRODUCT_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_product_notice_file_xml_gz),"Product image", \
         "Notices for files contained in the product filesystem image in this directory:", \
         $(PRODUCT_NOTICE_DEPS),$(PRODUCT_NOTICE_DEPS)))

$(installed_product_notice_xml_gz): $(target_product_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_product_notice_file_xml_gz))
$(call declare-0p-target,$(installed_product_notice_xml_gz))
endif

.PHONY: systemextlicense
systemextlicense: $(call corresponding-license-metadata, $(SYSTEM_EXT_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(SYSTEM_EXT_NOTICE_DEPS))
$(eval $(call text-notice-rule,$(target_system_ext_notice_file_txt),"System_ext image", \
         "Notices for files contained in the system_ext filesystem image in this directory:", \
         $(SYSTEM_EXT_NOTICE_DEPS),$(SYSTEM_EXT_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_system_ext_notice_file_xml_gz),"System_ext image", \
         "Notices for files contained in the system_ext filesystem image in this directory:", \
         $(SYSTEM_EXT_NOTICE_DEPS),$(SYSTEM_EXT_NOTICE_DEPS)))

$(installed_system_ext_notice_xml_gz): $(target_system_ext_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_system_ext_notice_file_xml_gz))
$(call declare-0p-target,$(installed_system_ext_notice_xml_gz))
endif

.PHONY: vendor_dlkmlicense
vendor_dlkmlicense: $(call corresponding-license-metadata, $(VENDOR_DLKM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(VENDOR_DLKM_NOTICE_DEPS))
$(eval $(call text-notice-rule,$(target_vendor_dlkm_notice_file_txt),"Vendor_dlkm image", \
         "Notices for files contained in the vendor_dlkm filesystem image in this directory:", \
         $(VENDOR_DLKM_NOTICE_DEPS),$(VENDOR_DLKM_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_vendor_dlkm_notice_file_xml_gz),"Vendor_dlkm image", \
         "Notices for files contained in the vendor_dlkm filesystem image in this directory:", \
         $(VENDOR_DLKM_NOTICE_DEPS),$(VENDOR_DLKM_NOTICE_DEPS)))

$(installed_vendor_dlkm_notice_xml_gz): $(target_vendor_dlkm_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_vendor_dlkm_notice_file_xml_gz))
$(call declare-0p-target,$(installed_vendor_dlkm_notice_xml_gz))
endif

.PHONY: odm_dlkmlicense
odm_dlkmlicense: $(call corresponding-license-metadata, $(ODM_DLKM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(ODM_DLKM_NOTICE_DEPS))
$(eval $(call text-notice-rule,$(target_odm_dlkm_notice_file_txt),"ODM_dlkm filesystem image", \
         "Notices for files contained in the odm_dlkm filesystem image in this directory:", \
         $(ODM_DLKM_NOTICE_DEPS),$(ODM_DLKM_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_odm_dlkm_notice_file_xml_gz),"ODM_dlkm filesystem image", \
         "Notices for files contained in the odm_dlkm filesystem image in this directory:", \
         $(ODM_DLKM_NOTICE_DEPS),$(ODM_DLKM_NOTICE_DEPS)))

$(installed_odm_dlkm_notice_xml_gz): $(target_odm_dlkm_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_odm_dlkm_notice_file_xml_gz))
$(call declare-0p-target,$(installed_odm_dlkm_notice_xml_gz))
endif

.PHONY: system_dlkmlicense
system_dlkmlicense: $(call corresponding-license-metadata, $(SYSTEM_DLKM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(SYSTEM_DLKM_NOTICE_DEPS))
$(eval $(call text-notice-rule,$(target_system_dlkm_notice_file_txt),"System_dlkm filesystem image", \
         "Notices for files contained in the system_dlkm filesystem image in this directory:", \
         $(SYSTEM_DLKM_NOTICE_DEPS),$(SYSTEM_DLKM_NOTICE_DEPS)))

$(eval $(call xml-notice-rule,$(target_system_dlkm_notice_file_xml_gz),"System_dlkm filesystem image", \
         "Notices for files contained in the system_dlkm filesystem image in this directory:", \
         $(SYSTEM_DLKM_NOTICE_DEPS),$(SYSTEM_DLKM_NOTICE_DEPS)))

$(installed_system_dlkm_notice_xml_gz): $(target_system_dlkm_notice_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_system_dlkm_notice_file_xml_gz))
$(call declare-0p-target,$(installed_sysetm_dlkm_notice_xml_gz))
endif

# set the value of gpl_notice_file_message as "XMI_CUSTOM_UNQ_GPL_NOTOICE",
# which would be checked as special case in the build/tools/compliance/cmd/htmlnotice/htmlnotice.go
gpl_notice_file_message := "XMI_CUSTOM_UNQ_GPL_NOTOICE"
.PHONY: systemlicense_gpl
systemlicense_gpl: $(call corresponding-license-metadata, $(SYSTEM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(SYSTEM_NOTICE_DEPS))

SYSTEM_NOTICE_DEPS += $(UNMOUNTED_NOTICE_DEPS)
target_notice_gpl_file_html_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_GPL.html.gz
installed_notice_gpl_html_or_xml_gz := $(TARGET_OUT)/etc/NOTICE_GPL.html.gz

ifneq ($(PRODUCT_NOTICE_SPLIT),true)
$(eval $(call html-notice-rule,$(target_notice_gpl_file_html_gz),"System image",$(gpl_notice_file_message),$(SYSTEM_NOTICE_DEPS),$(SYSTEM_NOTICE_DEPS)))

$(installed_notice_gpl_html_or_xml_gz): $(target_notice_gpl_file_html_gz)
	$(copy-file-to-target)

else
$(eval $(call html-notice-rule,$(target_notice_gpl_file_html_gz),"System image",$(gpl_notice_file_message),$(SYSTEM_NOTICE_DEPS),$(SYSTEM_NOTICE_DEPS)))

$(installed_notice_gpl_html_or_xml_gz): $(target_notice_gpl_file_html_gz)
	$(copy-file-to-target)
endif

$(call declare-0p-target,$(target_notice_gpl_file_html_gz))
$(call declare-0p-target,$(installed_notice_gpl_html_or_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_notice_gpl_html_or_xml_gz)

endif

.PHONY: vendorlicense_gpl
vendorlicense_gpl: $(call corresponding-license-metadata, $(VENDOR_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(VENDOR_NOTICE_DEPS))

VENDOR_NOTICE_DEPS += $(UNMOUNTED_NOTICE_DEPS)

target_vendor_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_VENDOR_GPL.html.gz
installed_vendor_notice_gpl_xml_gz := $(TARGET_OUT_VENDOR)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_vendor_notice_gpl_file_xml_gz),"Vendor image", \
         $(gpl_notice_file_message), \
         $(VENDOR_NOTICE_DEPS),$(VENDOR_NOTICE_DEPS)))

$(installed_vendor_notice_gpl_xml_gz): $(target_vendor_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_vendor_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_vendor_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_vendor_notice_gpl_xml_gz)
endif

.PHONY: odmlicense_gpl
odmlicense_gpl: $(call corresponding-license-metadata, $(ODM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(ODM_NOTICE_DEPS))

target_odm_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_ODM_GPL.html.gz
installed_odm_notice_gpl_xml_gz := $(TARGET_OUT_ODM)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_odm_notice_gpl_file_xml_gz),"ODM filesystem image", \
         $(gpl_notice_file_message), \
         $(ODM_NOTICE_DEPS),$(ODM_NOTICE_DEPS)))

$(installed_odm_notice_gpl_xml_gz): $(target_odm_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_odm_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_odm_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_odm_notice_gpl_xml_gz)
endif

# .PHONY: oemlicense_gpl
# oemlicense_gpl: $(call corresponding-license-metadata, $(OEM_NOTICE_DEPS)) reportmissinglicenses

.PHONY: productlicense_gpl
productlicense_gpl: $(call corresponding-license-metadata, $(PRODUCT_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(PRODUCT_NOTICE_DEPS))
target_product_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_PRODUCT_GPL.html.gz
installed_product_notice_gpl_xml_gz := $(TARGET_OUT_PRODUCT)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_product_notice_gpl_file_xml_gz),"Product image", \
         $(gpl_notice_file_message), \
         $(PRODUCT_NOTICE_DEPS),$(PRODUCT_NOTICE_DEPS)))

$(installed_product_notice_gpl_xml_gz): $(target_product_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_product_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_product_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_product_notice_gpl_xml_gz)
endif

.PHONY: systemextlicense_gpl
systemextlicense_gpl: $(call corresponding-license-metadata, $(SYSTEM_EXT_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(SYSTEM_EXT_NOTICE_DEPS))

target_system_ext_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_SYSTEM_EXT_GPL.html.gz
installed_system_ext_notice_gpl_xml_gz := $(TARGET_OUT_SYSTEM_EXT)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_system_ext_notice_gpl_file_xml_gz),"System_ext image", \
         $(gpl_notice_file_message), \
         $(SYSTEM_EXT_NOTICE_DEPS),$(SYSTEM_EXT_NOTICE_DEPS)))

$(installed_system_ext_notice_gpl_xml_gz): $(target_system_ext_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_system_ext_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_system_ext_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_system_ext_notice_gpl_xml_gz)
endif

.PHONY: vendor_dlkmlicense_gpl
vendor_dlkmlicense_gpl: $(call corresponding-license-metadata, $(VENDOR_DLKM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(VENDOR_DLKM_NOTICE_DEPS))
target_vendor_dlkm_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_VENDOR_DLKM_GPL.html.gz
installed_vendor_dlkm_notice_gpl_xml_gz := $(TARGET_OUT_VENDOR_DLKM)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_vendor_dlkm_notice_gpl_file_xml_gz),"Vendor_dlkm image", \
         $(gpl_notice_file_message), \
         $(VENDOR_DLKM_NOTICE_DEPS),$(VENDOR_DLKM_NOTICE_DEPS)))

$(installed_vendor_dlkm_notice_gpl_xml_gz): $(target_vendor_dlkm_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_vendor_dlkm_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_vendor_dlkm_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_vendor_dlkm_notice_gpl_xml_gz)
endif

.PHONY: odm_dlkmlicense_gpl
odm_dlkmlicense_gpl: $(call corresponding-license-metadata, $(ODM_DLKM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(ODM_DLKM_NOTICE_DEPS))

target_odm_dlkm_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_ODM_DLKM_GPL.html.gz
installed_odm_dlkm_notice_gpl_xml_gz := $(TARGET_OUT_ODM_DLKM)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_odm_dlkm_notice_gpl_file_xml_gz),"ODM_dlkm filesystem image", \
         $(gpl_notice_file_message), \
         $(ODM_DLMK_NOTICE_DEPS),$(ODM_DLMK_NOTICE_DEPS)))

$(installed_odm_dlkm_notice_gpl_xml_gz): $(target_odm_dlkm_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_odm_dlkm_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_odm_dlkm_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_odm_dlkm_notice_gpl_xml_gz)
endif

.PHONY: system_dlkmlicense_gpl
system_dlkmlicense_gpl: $(call corresponding-license-metadata, $(SYSTEM_DLKM_NOTICE_DEPS)) reportmissinglicenses

ifneq (,$(SYSTEM_DLKM_NOTICE_DEPS))

target_system_dlkm_notice_gpl_file_xml_gz := $(TARGET_OUT_INTERMEDIATES)/NOTICE_SYSTEM_DLKM_GPL.html.gz
installed_system_dlkm_notice_gpl_xml_gz := $(TARGET_OUT_SYSTEM_DLKM)/etc/NOTICE_GPL.html.gz

$(eval $(call html-notice-rule,$(target_system_dlkm_notice_gpl_file_xml_gz),"System_dlkm filesystem image", \
         $(gpl_notice_file_message), \
         $(SYSTEM_DLMK_NOTICE_DEPS),$(SYSTEM_DLMK_NOTICE_DEPS)))

$(installed_system_dlkm_notice_gpl_xml_gz): $(target_system_dlkm_notice_gpl_file_xml_gz)
	$(copy-file-to-target)

$(call declare-0p-target,$(target_system_dlkm_notice_gpl_file_xml_gz))
$(call declare-0p-target,$(installed_system_dlkm_notice_gpl_xml_gz))
ALL_DEFAULT_INSTALLED_MODULES += $(installed_system_dlkm_notice_gpl_xml_gz)
endif

endif # not TARGET_BUILD_APPS
