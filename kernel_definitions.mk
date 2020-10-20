# Android Kernel compilation/common definitions
ifeq ($(TARGET_BUILD_VARIANT),user)
     KERNEL_DEFCONFIG := vendor/$(TARGET_BOARD_PLATFORM)-perf_defconfig
endif

ifeq ($(KERNEL_DEFCONFIG),)
     KERNEL_DEFCONFIG := vendor/$(TARGET_PRODUCT)_defconfig
endif

TARGET_KERNEL := msm-$(TARGET_KERNEL_VERSION)
ifeq ($(TARGET_KERNEL_SOURCE),)
     TARGET_KERNEL_SOURCE := kernel/$(TARGET_KERNEL)
endif

DTC := $(HOST_OUT_EXECUTABLES)/dtc$(HOST_EXECUTABLE_SUFFIX)
UFDT_APPLY_OVERLAY := $(HOST_OUT_EXECUTABLES)/ufdt_apply_overlay$(HOST_EXECUTABLE_SUFFIX)

SOURCE_ROOT := $(shell pwd)

TARGET_KERNEL_MAKE_ENV := DTC_EXT=$(SOURCE_ROOT)/$(DTC)
TARGET_KERNEL_MAKE_ENV += DTC_OVERLAY_TEST_EXT=$(SOURCE_ROOT)/$(UFDT_APPLY_OVERLAY)
ifeq ($(BOARD_KERNEL_SEPARATED_DTBO), true)
TARGET_KERNEL_MAKE_ENV += CONFIG_BUILD_ARM64_DT_OVERLAY=y
endif
TARGET_KERNEL_MAKE_ENV += HOSTCC=$(SOURCE_ROOT)/$(SOONG_LLVM_PREBUILTS_PATH)/clang
TARGET_KERNEL_MAKE_ENV += HOSTAR=$(SOURCE_ROOT)/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/bin/x86_64-linux-ar
TARGET_KERNEL_MAKE_ENV += HOSTLD=$(SOURCE_ROOT)/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/bin/x86_64-linux-ld
TARGET_KERNEL_MAKE_CFLAGS = "-I$(SOURCE_ROOT)/$(TARGET_KERNEL_SOURCE)/include/uapi -I/usr/include -I/usr/include/x86_64-linux-gnu -L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
TARGET_KERNEL_MAKE_LDFLAGS = "-L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"

KERNEL_LLVM_BIN := $(lastword $(sort $(wildcard $(SOURCE_ROOT)/$(LLVM_PREBUILTS_BASE)/$(BUILD_OS)-x86/clang-4*)))/bin/clang

KERNEL_TARGET := $(strip $(INSTALLED_KERNEL_TARGET))
ifeq ($(KERNEL_TARGET),)
INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
endif

ifneq ($(TARGET_KERNEL_APPEND_DTB), true)
$(info Using DTB Image)
INSTALLED_DTBIMAGE_TARGET := $(PRODUCT_OUT)/dtb.img
endif

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := arm
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

ifeq ($(shell echo $(KERNEL_DEFCONFIG) | grep vendor),)
KERNEL_DEFCONFIG := vendor/$(KERNEL_DEFCONFIG)
endif

# Force 32-bit binder IPC for 64bit kernel with 32bit userspace
ifeq ($(KERNEL_ARCH),arm64)
ifeq ($(TARGET_ARCH),arm)
KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
endif
endif

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
ifeq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
KERNEL_CROSS_COMPILE := arm-eabi-
else
KERNEL_CROSS_COMPILE := $(TARGET_KERNEL_CROSS_COMPILE_PREFIX)
endif

ifeq ($(TARGET_PREBUILT_KERNEL),)

KERNEL_GCC_NOANDROID_CHK := $(shell (echo "int main() {return 0;}" | $(KERNEL_CROSS_COMPILE)gcc -E -mno-android - > /dev/null 2>&1 ; echo $$?))

real_cc :=
ifeq ($(KERNEL_LLVM_SUPPORT),true)
  ifeq ($(KERNEL_SD_LLVM_SUPPORT), true)  #Using sd-llvm compiler
    ifeq ($(shell echo $(SDCLANG_PATH) | head -c 1),/)
       KERNEL_LLVM_BIN := $(SDCLANG_PATH)/clang
    else
       KERNEL_LLVM_BIN := $(shell pwd)/$(SDCLANG_PATH)/clang
    endif
    $(warning "Using sdllvm" $(KERNEL_LLVM_BIN))
  else
    KERNEL_LLVM_BIN := $(shell pwd)/$(CLANG) #Using aosp-llvm compiler
    $(warning "Using aosp-llvm" $(KERNEL_LLVM_BIN))
  endif
  ifeq ($(KERNEL_ARCH), arm64)
      real_cc := REAL_CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=aarch64-linux-gnu-
  else
      real_cc := REAL_CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=arm-linux-gnueabihf
  endif
else
ifeq ($(strip $(KERNEL_GCC_NOANDROID_CHK)),0)
KERNEL_CFLAGS := KCFLAGS=-mno-android
endif
endif

BUILD_ROOT_LOC := ../../..
KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/kernel/$(TARGET_KERNEL)
KERNEL_SYMLINK := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
KERNEL_USR := $(KERNEL_SYMLINK)/usr

KERNEL_CONFIG := $(KERNEL_OUT)/.config

ifeq ($(KERNEL_DEFCONFIG)$(wildcard $(KERNEL_CONFIG)),)
$(error Kernel configuration not defined, cannot build kernel)
else

TARGET_USES_UNCOMPRESSED_KERNEL := $(shell grep "CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y" $(TARGET_KERNEL_SOURCE)/arch/arm64/configs/$(KERNEL_DEFCONFIG))

ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),)
ifeq ($(KERNEL_ARCH),arm64)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image.gz
else
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/zImage
endif
else
$(info Using uncompressed kernel)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image
endif

ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
$(info Using appended DTB)
TARGET_PREBUILT_INT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)-dtb
endif

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_MODULES_INSTALL ?= system
KERNEL_MODULES_OUT ?= $(PRODUCT_OUT)/$(KERNEL_MODULES_INSTALL)/lib/modules

TARGET_PREBUILT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)

endif
endif

# Add RTIC DTB to dtb.img if RTIC MPGen is enabled.
# Note: unfortunately we can't define RTIC DTS + DTB rule here as the
# following variable/ tools (needed for DTS generation)
# are missing - DTB_OBJS, OBJDUMP, KCONFIG_CONFIG, CC, DTC_FLAGS (the only available is DTC).
# The existing RTIC kernel integration in scripts/link-vmlinux.sh generates RTIC MP DTS
# that will be compiled with optional rule below.
# To be safe, we check for MPGen enable.
ifdef RTIC_MPGEN
RTIC_DTB := $(KERNEL_SYMLINK)/rtic_mp.dtb
endif

MAKE_PATH := $(SOURCE_ROOT)/prebuilts/build-tools/linux-x86/bin/
# Android Kernel make rules

$(KERNEL_HEADERS_INSTALL): $(KERNEL_OUT) $(DTC) $(UFDT_APPLY_OVERLAY)
	KERNEL_DIR=$(TARGET_KERNEL_SOURCE) \
	DEFCONFIG=$(KERNEL_DEFCONFIG) \
	OUT_DIR=$(KERNEL_OUT) \
	MAKE_PATH=$(MAKE_PATH)\
	ARCH=$(KERNEL_ARCH) \
	CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) \
	KERNEL_MODULES_OUT=$(KERNEL_MODULES_OUT) \
	KERNEL_HEADERS_INSTALL=$(KERNEL_HEADERS_INSTALL) \
	HEADERS_INSTALL=1 \
	TARGET_PREBUILT_INT_KERNEL=$(TARGET_PREBUILT_INT_KERNEL) \
	TARGET_INCLUDES=$(TARGET_KERNEL_MAKE_CFLAGS) \
	TARGET_LINCLUDES=$(TARGET_KERNEL_MAKE_LDFLAGS) \
	device/qcom/kernelscripts/buildkernel.sh \
	$(real_cc) \
	$(TARGET_KERNEL_MAKE_ENV)

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)

$(KERNEL_USR): $(KERNEL_HEADERS_INSTALL)
	rm -rf $(KERNEL_SYMLINK)
	ln -s kernel/$(TARGET_KERNEL) $(KERNEL_SYMLINK)

$(TARGET_PREBUILT_KERNEL): $(KERNEL_OUT) $(DTC) $(KERNEL_USR)
	KERNEL_DIR=$(TARGET_KERNEL_SOURCE) \
	DEFCONFIG=$(KERNEL_DEFCONFIG) \
	OUT_DIR=$(KERNEL_OUT) \
	MAKE_PATH=$(MAKE_PATH) \
	ARCH=$(KERNEL_ARCH) \
	CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) \
	KERNEL_MODULES_OUT=$(KERNEL_MODULES_OUT) \
	KERNEL_HEADERS_INSTALL=$(KERNEL_HEADERS_INSTALL) \
	TARGET_PREBUILT_INT_KERNEL=$(TARGET_PREBUILT_INT_KERNEL) \
	TARGET_INCLUDES=$(TARGET_KERNEL_MAKE_CFLAGS) \
	TARGET_LINCLUDES=$(TARGET_KERNEL_MAKE_LDFLAGS) \
	device/qcom/kernelscripts/buildkernel.sh \
	$(real_cc) \
	$(TARGET_KERNEL_MAKE_ENV)

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_KERNEL) | $(ACP)
	$(transform-prebuilt-to-target)

# RTIC DTS to DTB (if MPGen enabled;
# and make sure we don't break the build if rtic_mp.dts missing)
$(RTIC_DTB): $(INSTALLED_KERNEL_TARGET)
	stat $(KERNEL_SYMLINK)/rtic_mp.dts 2>/dev/null >&2 && \
	$(DTC) -O dtb -o $(RTIC_DTB) -b 1 $(DTC_FLAGS) $(KERNEL_SYMLINK)/rtic_mp.dts || \
	touch $(RTIC_DTB)

# Creating a dtb.img once the kernel is compiled if TARGET_KERNEL_APPEND_DTB is set to be false
$(INSTALLED_DTBIMAGE_TARGET): $(INSTALLED_KERNEL_TARGET) $(RTIC_DTB)
	cat $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts/vendor/qcom/*.dtb $(RTIC_DTB) > $@
