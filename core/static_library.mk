$(call record-module-type,STATIC_LIBRARY)
ifdef LOCAL_IS_HOST_MODULE
  $(call pretty-error,BUILD_STATIC_LIBRARY is incompatible with LOCAL_IS_HOST_MODULE. Use BUILD_HOST_STATIC_LIBRARY instead)
endif
my_prefix := TARGET_
include $(BUILD_SYSTEM)/multilib.mk

ifndef my_module_multilib
# libraries default to building for both architecturess
my_module_multilib := both
endif

ifneq ($(FORCE_SDCLANG_OFF),true)
ifeq ($(LOCAL_SDCLANG),true)
include $(SDCLANG_FLAG_DEFS)
endif
endif

LOCAL_2ND_ARCH_VAR_PREFIX :=
include $(BUILD_SYSTEM)/module_arch_supported.mk

ifeq ($(my_module_arch_supported),true)
include $(BUILD_SYSTEM)/static_library_internal.mk
endif

ifdef TARGET_2ND_ARCH

LOCAL_2ND_ARCH_VAR_PREFIX := $(TARGET_2ND_ARCH_VAR_PREFIX)
include $(BUILD_SYSTEM)/module_arch_supported.mk

ifeq ($(my_module_arch_supported),true)
# Build for TARGET_2ND_ARCH
LOCAL_BUILT_MODULE :=
LOCAL_INSTALLED_MODULE :=
LOCAL_INTERMEDIATE_TARGETS :=

include $(BUILD_SYSTEM)/static_library_internal.mk

endif

LOCAL_2ND_ARCH_VAR_PREFIX :=

endif # TARGET_2ND_ARCH

ifneq ($(FORCE_SDCLANG_OFF),true)
ifeq ($(LOCAL_SDCLANG),true)
ifeq ($(LOCAL_SDCLANG_LTO),true)
include $(SDCLANG_LTO_DEFS)
endif
endif
endif

my_module_arch_supported :=
LOCAL_SRC_FILES :=
LOCAL_STATIC_LIBRARIES :=
LOCAL_WHOLE_STATIC_LIBRARIES :=
LOCAL_EXPORT_C_INCLUDES :=
LOCAL_CFLAGS :=
LOCAL_ABI_CHECKER :=
LOCAL_C_INCLUDES :=


###########################################################
## Copy headers to the install tree
###########################################################
ifdef LOCAL_COPY_HEADERS
$(call pretty-warning,LOCAL_COPY_HEADERS is deprecated. See $(CHANGES_URL)#copy_headers)
include $(BUILD_SYSTEM)/copy_headers.mk
endif