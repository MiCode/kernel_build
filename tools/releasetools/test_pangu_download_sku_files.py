import shutil
import tempfile
import os
import unittest
import zipfile
import common
import test_pangu_download_sku_file_data
import pangu_download_sku_files


class PanguDownloadTest(unittest.TestCase):
    def setUp(self) -> None:
        self.target_dir = tempfile.mkdtemp()
        print("target dir is " + self.target_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.target_dir)
        common.Cleanup()
        pass

    def __run(self, json_content):
        args = [
            "--target-dir",
            self.target_dir,
            "--json-content",
            json_content
        ]
        pangu_download_sku_files.main(args)

    def assert_init_dir(self):
        product_dir = os.path.join(self.target_dir, "product")
        self.assertTrue(os.path.exists(product_dir))
        self.assertEqual(os.listdir(product_dir), [])

        system_app_dir = os.path.join(self.target_dir, "system", "app")
        self.assertTrue(os.path.exists(system_app_dir))
        self.assertEqual(os.listdir(system_app_dir), [])

        system_priv_app_dir = os.path.join(
            self.target_dir, "system", "priv-app")
        self.assertTrue(os.path.exists(system_priv_app_dir))
        self.assertEqual(os.listdir(system_priv_app_dir), [])

        system_framework_dir = os.path.join(
            self.target_dir, "system", "framework")
        self.assertTrue(os.path.exists(system_framework_dir))
        self.assertEqual(os.listdir(system_framework_dir), [])

        system_sys_config_dir = os.path.join(
            self.target_dir, "system", "etc", "sysconfig")
        self.assertTrue(os.path.exists(system_sys_config_dir))
        self.assertEqual(os.listdir(system_sys_config_dir), [])

        system_permissions_dir = os.path.join(
            self.target_dir, "system", "etc", "permissions")
        self.assertTrue(os.path.exists(system_permissions_dir))
        self.assertEqual(os.listdir(system_permissions_dir), [])


    def test_download_with_no_components_no_build_prop(self):
        self.__run(test_pangu_download_sku_file_data.NO_COMPONENTS)
        self.assert_init_dir()


    def test_download_with_empty_components(self):
        self.__run(test_pangu_download_sku_file_data.EMPTY_COMPONENTS)
        self.assert_init_dir()


    def test_download_with_empty_build_prop(self):
        self.__run(test_pangu_download_sku_file_data.EMPTY_BUILD_PROP)
        etc_dir = os.path.join(self.target_dir, "etc")
        self.__assert_not_exist(etc_dir)


    def test_download_with_build_prop(self):
        self.__run(test_pangu_download_sku_file_data.TEST_BUILD_PROP)
        etc_file = os.path.join(self.target_dir, "etc", "build.prop")
        self.__assert_exist(etc_file)

        with open(etc_file) as file:
            actual = file.read()
        expected = "test_prop=test\n"
        self.assertEqual(actual, expected)


    def test_download_component_with_no_option(self):
        self.__run(test_pangu_download_sku_file_data.NO_OPTIONS)
        android_app = os.path.join( self.target_dir, "product", "app", "app-debug", "app-debug.apk")
        self.__assert_exist(android_app)


    def test_download_component_with_empty_option(self):
        self.test_download_component_with_no_option()

    
    def __assert_exist(self, file):
        self.assertTrue(os.path.exists(file))

    def __assert_not_exist(self, file):
        self.assertFalse(os.path.exists(file))


    def test_download_product_components(self):
        self.__run(test_pangu_download_sku_file_data.PRODUCT_COMPONENTS)
        app = os.path.join(self.target_dir, "product", "app", "messenger", "messenger.apk")
        self.__assert_exist(app)

        priv_app = os.path.join(self.target_dir, "product", "priv-app", "messenger", "messenger.apk")
        self.__assert_exist(priv_app)

        data_app = os.path.join(self.target_dir, "product", "data-app", "messenger", "messenger.apk")
        self.__assert_exist(data_app)

        opcust_data_app = os.path.join(self.target_dir, "product", "opcust", "data-app", "messenger", "messenger.apk")
        self.__assert_exist(opcust_data_app)

        java_library = os.path.join(self.target_dir, "product", "framework")
        self.__assert_exist(java_library)

        overlay_app = os.path.join(self.target_dir, "product", "overlay", "SettingsProviderCustResOverlay.apk")
        self.__assert_exist(overlay_app)

        lib_32 = os.path.join(self.target_dir, "product", "lib", "libbase.so")
        self.__assert_exist(lib_32)

        lib_64 = os.path.join(self.target_dir, "product", "lib64", "libbase.so")
        self.__assert_exist(lib_64)

        sysconfig = os.path.join(self.target_dir, "product", "etc", "sysconfig", "facebook-hiddenapi-package-whitelist.xml")
        self.__assert_exist(sysconfig)

        permissions = os.path.join(self.target_dir, "product", "etc", "permissions", "privapp-permissions-softbank.xml")
        self.__assert_exist(permissions)

        device_feature = os.path.join(self.target_dir, "product", "etc", "device_features", "device_feature.txt")
        self.__assert_exist(device_feature)

        bootanimation = os.path.join(self.target_dir, "product", "opcust", "mx_telcel", "theme", "operator", "boots", "shutdownaudio.mp3")
        self.__assert_exist(bootanimation)

        other_bootanimation = os.path.join(self.target_dir, "product", "opcust", "mx_telcel", "theme", "operator", "other_boots", "shutdownaudio.mp3")
        self.__assert_exist(other_bootanimation)

        wallpaper = os.path.join(self.target_dir, "product", "opcust", "mx_telcel", "wallpaper", "2.jpg")
        self.__assert_exist(wallpaper)

        ringtone = os.path.join(self.target_dir, "product", "opcust", "mx_telcel", "audio", "ringtones", "Telcel Ríe.mp3")
        self.__assert_exist(ringtone)


    def test_download_system_components(self):
        self.__run(test_pangu_download_sku_file_data.SYSTEM_COMPONENTS)
        app = os.path.join(self.target_dir, "system", "app", "messenger", "messenger.apk")
        self.__assert_exist(app)

        priv_app = os.path.join(self.target_dir, "system", "priv-app", "messenger", "messenger.apk")
        self.__assert_exist(priv_app)

        sysconfig = os.path.join(self.target_dir, "system", "etc", "sysconfig", "facebook-hiddenapi-package-whitelist.xml")
        self.__assert_exist(sysconfig)

        permissions = os.path.join(self.target_dir, "system", "etc","permissions", "privapp-permissions-softbank.xml")
        self.__assert_exist(permissions)


    def test_download_init_rc(self):
        self.__run(test_pangu_download_sku_file_data.INIT_RC) 
        init_rc = os.path.join(self.target_dir, "etc", "init", "init.rc")
        self.__assert_exist(init_rc)

    def test_download_gms_ime_data(self):
        self.__run(test_pangu_download_sku_file_data.GMS_IME_DATA)
        gms_ime_data = os.path.join(self.target_dir, "product", "usr/share/ime/google/d3_lms/", "mozc.data")
        self.__assert_exist(gms_ime_data)


    @unittest.expectedFailure
    def test_retry_download(self):
        self.__run(test_pangu_download_sku_file_data.BAD_HASH)

    def test_download_resource_set(self):
        self.__run(test_pangu_download_sku_file_data.RESOUCE_SET_DATA)
        resource_set_dir = pangu_download_sku_files.OPTIONS.resource_set_download_dir
        for file in os.listdir(resource_set_dir):
            target_file = os.path.join(resource_set_dir, file)
            zip_file = zipfile.ZipFile(target_file)
            namelist = zip_file.namelist();
            for name in namelist:
                self.__assert_exist(os.path.join(self.target_dir, name))


    @unittest.expectedFailure
    def test_download_resource_set_duplicate(self):
        self.__run(test_pangu_download_sku_file_data.RESOUCE_SET_DATA_DUPLICATED)


if __name__ == '__main__':
    unittest.main()
