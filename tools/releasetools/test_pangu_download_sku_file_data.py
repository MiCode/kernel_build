NO_COMPONENTS = """ {
    "partitions": [
        {
            "name": "mi_ext"
        }
    ]
}
"""

EMPTY_COMPONENTS = """
{
    "partitions": [
        {
            "components":[],
            "name": "mi_ext"
        }
    ]
}
"""

EMPTY_BUILD_PROP = """
{
    "partitions": [
        {
            "components":[],
            "build_properties": {
                
            },
            "name": "mi_ext"
        }
    ]
}
"""

TEST_BUILD_PROP = """
{
    "partitions": [
        {
            "components":[],
            "build_properties": {
                "test_prop":"test"
            },
            "name": "mi_ext"
        }
    ]
}
"""

NO_OPTIONS = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "app-debug.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/3cd7801f-fc05-4fd2-8fb9-b88cee77c397.apk",
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

EMPTY_OPTIONS = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "app-debug.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/3cd7801f-fc05-4fd2-8fb9-b88cee77c397.apk",
                    "module": "mx_telcel",
                    "options": {

                    }
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

"""
android_app:
    product/app 
    product/priv-app                                        privileged:true 
    product/data-app                                        removable:true
    product/opcust/data-app                                 opcust:true, removable:true

java_library:
    product/framework

runtime_resource_overlay:
    product/overlay

cc_library:
    product/lib/                                            abi:32
    product/lib64/                                          abi:64

prebuilt_etc:
    product/etc/sysconfig                                   sysconfig:true
    product/etc/permissions                                 permissions:true
    product/etc/device_features                             device_features:true

resource:
    product/media/audio                                     audio:true
    product/opcust/${carrier}/theme/operator/boots/         opcust:true,bootanimation:true,carrier: ${carrier}
    product/opcust/${carrier}/theme/operator/other_boots/*  opcust:true,other_bootanimation:true,carrier: ${carrier}
    product/opcust/${carrier}/wallpaper/*                   opcust:true,wallpaper:true,carrier: ${carrier}
    product/opcust/${carrier}/audio/ringtones/*             opcust:true,ringtones:true,carrier: ${carrier}
"""
PRODUCT_COMPONENTS = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "messenger.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/8b030776-d660-44e4-bae7-edffced1c141.apk",
                    "options": {
                        
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "messenger.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/8b030776-d660-44e4-bae7-edffced1c141.apk",
                    "options": {
                        "privileged":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "messenger.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/8b030776-d660-44e4-bae7-edffced1c141.apk",
                    "options": {
                        "removable":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "messenger.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/8b030776-d660-44e4-bae7-edffced1c141.apk",
                    "options": {
                        "opcust":true, 
                        "removable":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "com.xiaomi.nfc.jar",
                    "type": "java_library",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/com.xiaomi.nfc.jar",
                    "options": {
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "SettingsProviderCustResOverlay.apk",
                    "type": "runtime_resource_overlay",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/ea3a90b0-8753-4fdb-8452-e6e8ee36110a.apk",
                    "options": {},
                    "module": "MI_ext_cupid_mx_telcel"
                },
                {
                    "name": "libbase.so",
                    "type": "cc_library",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/libbase.so",
                    "options": {
                        "abi":"32"
                    },
                    "module": "MI_ext_cupid_mx_telcel"
                },
                {
                    "name": "libbase.so",
                    "type": "cc_library",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/libbase.so",
                    "options": {
                        "abi":"64"
                    },
                    "module": "MI_ext_cupid_mx_telcel"
                },
                {
                    "name": "facebook-hiddenapi-package-whitelist.xml",
                    "type": "prebuilt_etc",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/libbase.so",
                    "options": {
                        "sysconfig":true
                    },
                    "module": "MI_ext_cupid_mx_telcel"
                }, 
                {
                    "name": "privapp-permissions-softbank.xml",
                    "type": "prebuilt_etc",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/libbase.so",
                    "options": {
                        "permissions": true
                    },
                    "module": "MI_ext_cupid_mx_telcel"
                },
                {
                    "name": "device_feature.txt",
                    "type": "prebuilt_etc",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/bc913ad3-db93-4003-ba0f-37f0a3780719.txt",
                    "options": {
                        "device_features": true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "shutdownaudio.mp3",
                    "type": "resource",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/e250ec7e-f45c-4b39-b321-d85fa75c4f23.mp3",
                    "options": {
                        "carrier": "mx_telcel",
                        "opcust": true,
                        "bootanimation": true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "shutdownaudio.mp3",
                    "type": "resource",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/e250ec7e-f45c-4b39-b321-d85fa75c4f23.mp3",
                    "options": {
                        "carrier": "mx_telcel",
                        "opcust": true,
                        "other_bootanimation": true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "shutdownaudio.mp3",
                    "type": "resource",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/e250ec7e-f45c-4b39-b321-d85fa75c4f23.mp3",
                    "options": {
                        "audio":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "2.jpg",
                    "type": "resource",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/9ca7b093-6ce2-4c49-a20b-906d97263b6c.jpg",
                    "options": {
                        "carrier": "mx_telcel",
                        "wallpaper": true,
                        "opcust": true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "Telcel Ríe.mp3",
                    "type": "resource",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/e9077004-3f2e-4647-a01c-4e105f87e588.mp3",
                    "options": {
                        "carrier": "mx_telcel",
                        "opcust": true,
                        "ringtones": true
                    },
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

"""
    system/app                  system_bundled:true
    system/priv-app             system_bundled:true privilieged:true
    system/etc/sysconfig        system_bundled:true sysconfig:true
    system/etc/permissions      system_bundled:true permissions:true
"""
SYSTEM_COMPONENTS = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "messenger.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/8b030776-d660-44e4-bae7-edffced1c141.apk",
                    "options": {
                        "system_bundled":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "messenger.apk",
                    "type": "android_app",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/8b030776-d660-44e4-bae7-edffced1c141.apk",
                    "options": {
                        "privileged":true,
                        "system_bundled":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "facebook-hiddenapi-package-whitelist.xml",
                    "type": "prebuilt_etc",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/a263eb03-6fb8-41d2-b127-b2e530d76f62.xml",
                    "options": {
                        "sysconfig":true,
                        "system_bundled":true
                    },
                    "module": "mx_telcel"
                },
                {
                    "name": "privapp-permissions-softbank.xml",
                    "type": "prebuilt_etc",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/959083ee-473a-4012-acc5-3efbea393578.xml",
                    "options": {
                        "system_bundled": true,
                        "permissions": true
                    },
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

INIT_RC = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "init.rc",
                    "type": "init_rc",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/56b21112-4b7b-469f-98f7-0479f0935cf9.rc",
                    "options": {},
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

BAD_HASH = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "init.rc",
                    "type": "init_rc",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/56b21112-4b7b-469f-98f7-0479f0935cf9.rc",
                    "options": {},
                    "module": "mx_telcel",
                    "hash": "123"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

GMS_IME_DATA = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "mozc.data",
                    "type": "gms_ime_data",
                    "url": "http://staging-cnbj2-fds.api.xiaomi.net/config-center/56b21112-4b7b-469f-98f7-0479f0935cf9.rc",
                    "options": {},
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

RESOUCE_SET_DATA = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "product.zip",
                    "type": "resource_set",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/product.zip",
                    "options": {},
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

RESOUCE_SET_DATA_DUPLICATED = """
{
    "partitions": [
        {
            "components":[
                {
                    "name": "product.zip",
                    "type": "resource_set",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/product.zip",
                    "options": {},
                    "module": "mx_telcel"
                },
                {
                    "name": "product1.zip",
                    "type": "resource_set",
                    "url": "https://cnbj2m-fds.api.xiaomi.net/images/product.zip",
                    "options": {},
                    "module": "mx_telcel"
                }
            ],
            "name": "mi_ext"
        }
    ]
}
"""

