#!/usr/bin/env python
import sys

HWASAN_MODULE_PATHS = {
    'stability_asan':
        [
            "bionic/libc",
            "frameworks/native/libs/binder"
        ],
    'audio_asan':
        [
            "bionic/libc",
            "vendor/qcom/opensource/agm/service",
            "vendor/qcom/opensource/agm/ipc/HwBinders/agm_ipc_client",
            "vendor/qcom/opensource/agm/ipc/HwBinders/agm_ipc_service",
            "vendor/qcom/opensource/pal",
            "vendor/qcom/proprietary/args/gsl",
            "vendor/qcom/opensource/audio-hal/st-hal",
            "vendor/qcom/opensource/audio-hal/primary-hal/hal"
        ]
    }

if __name__ == '__main__':
    if len(sys.argv) != 2:
        exit()
    module_name = sys.argv[1]
    if HWASAN_MODULE_PATHS.get(module_name):
        print(' '.join(HWASAN_MODULE_PATHS[module_name]))
