#!/usr/bin/env python
"""This script is used to download components for miext and product
  --android-version number-of-android-version
      android verison of current build. e.g. 13
  --miui-version number-of-miui-version
      miui version of current build. e.g. 14.0
  --device-name name-of-sku
      the name of sku. e.g. cupid_pre
  --target target-name
      partition name. e.g. miext | product
  --target-dir path-to-download
      the directory of target
  --target-url url
      the url to download target files. Can be empty.
      If this field is not set, the url will be set with {android-version}/{miui-version}/{deivce-name}/{target}
  --branch branch-name
      name of branch. dev | stable
  --sign-keys-dir key-path
      the directory of keys used to sign apk. If not set 'android_app' will not be signed
"""
import argparse
from concurrent import futures
import shutil
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import logging
import multiprocessing
import os
import re
import subprocess
import tempfile
import time
import traceback
import sys
import threading
from urllib import response
import zipfile
import common
import urllib
from urllib import request
from threading import Event
import ssl
import glob

TARGET_PRODCUT = "product"
TARGET_MI_EXT = "miext"
BASE_URL = "http://eng.comm.miui.srv/xms/api/open/v2/component/query/latest"

SPECIAL_CERT_STRINGS = ("PRESIGNED", "EXTERNAL")

logger = logging.getLogger(__name__)
OPTIONS = common.OPTIONS

# Always turn on verbose logging.
OPTIONS.verbose = True

OPTIONS.device_name = None
OPTIONS.target = TARGET_MI_EXT
OPTIONS.android_version = 13
OPTIONS.miui_version = 14.0
OPTIONS.branch = 'stable'
OPTIONS.target_dir = None
OPTIONS.target_url = None
OPTIONS.sign_keys_dir = None
OPTIONS.json_content = None

OPTIONS.key_map = None
OPTIONS.build_properties = None
OPTIONS.max_retried_times = 3
OPTIONS.resource_set_download_dir = None

cert_context = ssl.create_default_context()
cert_context.check_hostname = False
cert_context.verify_mode = ssl.CERT_NONE

class Options:
    def __init__(self,
                 certificate: str = "",
                 platform_apis: bool = False,
                 privileged: bool = False,
                 system_bundled: bool = False,
                 abi: str = "",
                 sysconfig: bool = False,
                 permissions: bool = False,
                 audio: bool = False,
                 removable: bool = False,
                 opcust: bool = False,
                 bootanimation: bool = False,
                 other_bootanimation: bool = False,
                 ringtones: bool = False,
                 wallpaper: bool = False,
                 carrier: str = "",
                 install_path: str = "",
                 sub_dir: str = "",
                 default_permissions=False,
                 device_features=False,
                 device_spec: object = None,
                 license_url: str = None,
                 custom_install_path: str = "",
                 ):
        self.certificate = certificate
        self.platform_apis = platform_apis
        self.privileged = privileged
        self.system_bundled = system_bundled
        self.abi = abi
        self.sysconfig = sysconfig
        self.permissions = permissions
        self.audio = audio
        self.removable = removable
        self.opcust = opcust
        self.bootanimation = bootanimation
        self.other_bootanimation = other_bootanimation
        self.wallpapter = wallpaper
        self.ringtones = ringtones
        self.carrier = carrier
        self.install_path = install_path
        self.sub_dir = sub_dir
        self.default_permissions = default_permissions
        self.device_features = device_features
        self.device_spec = device_spec
        self.license_url = license_url
        self.custom_install_path = custom_install_path


class Component:
    def __init__(self,
                 name: str = "",
                 module: str = "",
                 type: str = "",
                 url: str = "",
                 hash: str = "",
                 partition: str = "",
                 options: Options = Options()):
        self.name = os.path.splitext(name)[0]
        self.file_name = name
        self.url = url
        self.type = type
        self.module = module
        self.partition = partition
        self.options = options
        self.install_path = self.__get_install_path()
        self.hash = hash
        self.retried_times = 0

    def __str__(self) -> str:
        return self.file_name

    def __android_app_dir(self) -> str:
        file_name_stem = f'split-{self.name}' if self.type == 'app_bundle' else self.name
        if self.options.removable:
            if self.options.opcust:
                dir = "opcust/data-app/%s" % file_name_stem
            else:
                dir = "data-app/%s" % file_name_stem
        else:
            if self.options.privileged:
                dir = "priv-app/%s" % file_name_stem
            else:
                dir = "app/%s" % file_name_stem
        return dir

    def __app_config_dir(self) -> str:
        return "opcust/regionlist/" if self.options.opcust else ""

    def __cc_library_dir(self) -> str:
        return "lib64" if str(self.options.abi) == "64" else "lib/"

    def __resource_dir(self) -> str:
        if self.options.opcust and self.options.carrier:
            if self.options.bootanimation:
                dir = "opcust/%s/theme/operator/boots/" % self.options.carrier
            elif self.options.other_bootanimation:
                dir = "opcust/%s/theme/operator/other_boots/" % self.options.carrier
            elif self.options.wallpapter:
                dir = "opcust/%s/wallpaper/" % self.options.carrier
            elif self.options.ringtones:
                dir = "opcust/%s/audio/ringtones/" % self.options.carrier
        else:
            if self.options.audio:
                dir = "media/audio/"
            elif self.options.wallpapter:
                dir = "media/wallpaper/"
            else:
                dir = "media/"
        return dir

    def __prebuilt_etc_dir(self) -> str:
        if self.options.sysconfig:
            return "etc/sysconfig/"
        if self.options.permissions:
            return "etc/permissions/"
        if self.options.default_permissions:
            return "etc/default-permissions"
        if self.options.device_features:
            return "etc/device_features"
        return ""

    # derive from https://xiaomi.f.mioffice.cn/docs/dock4JRJz7nRFTZDwusfzjdYUEe#BvZpwj
    def __get_install_path(self):
        install_path = self.options.custom_install_path
        if install_path is not None and len(install_path) > 0:
            return install_path
        base_dir = "system" if self.options.system_bundled else "product"
        dir = ""
        if self.type in {"android_app", "app_bundle"}:
            dir = self.__android_app_dir()

        if self.type == "app_config":
            dir = self.__app_config_dir()

        if self.type == "java_library":
            dir = "framework/"

        if self.type == "runtime_resource_overlay":
            dir = "overlay/"

        if self.type == "cc_binary":
            dir = "bin/"

        if self.type == "cc_library":
            dir = self.__cc_library_dir()

        if self.type == "resource":
            dir = self.__resource_dir()

        if self.type == "prebuilt_etc":
            dir = self.__prebuilt_etc_dir()

        if self.type == "app_properties":
            dir = "etc/"

        if self.type == "gms_ime_data":
            dir = "usr/share/ime/google/d3_lms"

        if self.type == "init_rc":
            sub_dir = self.options.sub_dir
            if sub_dir is None:
                return "etc/init"
            return os.path.join("etc/init", sub_dir)

        if self.type == "resource_set":
            return OPTIONS.resource_set_download_dir

        if self.type == "root":
            return "root/xbin"

        return "%s/%s" % (base_dir, dir)

def run_cmd(command, is_abort=True):
    logger.info(command)
    res = subprocess.Popen(command, shell=True, env=os.environ)
    out, err = res.communicate()
    if res.returncode != 0:
        logger.warning("command \"{}\" returned {}: {}".format(command, res.returncode, err))
        if is_abort:
            raise Exception(f"Execute command {command} failed: output = {out}, error = {err}")

def download_impl(download_file:str, url: str, event: Event):
    with request.urlopen(url, context=cert_context) as response:
        with open(download_file, 'wb') as f:
            buffer_size = 1024 * 10
            while True:
                data = response.read(buffer_size)
                if not data or event.is_set():
                    break
                f.write(data)
   
def download(component: Component, event: Event):
    print(f'download target_dir: {common.OPTIONS.target_dir}')
    install_path = os.path.join(
        common.OPTIONS.target_dir, component.install_path)
    print(f'download install path: {install_path}')
    print(f'download filename: {component.file_name}')
    if not os.path.exists(install_path):
        os.makedirs(name=install_path, exist_ok=True)

    download_file = os.path.join(install_path, component.file_name)
    download_impl(download_file,component.url,event)
    if component.options.license_url is not None:
        license_file = os.path.join(install_path, component.file_name+".LICENSE")
        download_impl(license_file,component.options.license_url,event)


def get_min_sdk_version(apk_name):
    try:
        version = common.GetMinSdkVersion(apk_name)
    except BaseException:
        # If fail to get MinSdkVersion from AndroidManifest.xml,
        # then return 33 stands for Androit T's sdkVersion
        version = 33
    return version


def sign_apks(component: Component, event: Event):
    if OPTIONS.sign_keys_dir == None:
        logger.info("sign_key_dir is not set skip sign apks")
        return
    certificate = component.options.certificate
    key = OPTIONS.key_map.get(certificate)
    if certificate in SPECIAL_CERT_STRINGS or key is None:
        return

    install_path = os.path.join(OPTIONS.target_dir, component.install_path)
    unsigned_file_names = filter(lambda f: f.endswith('.apk'), os.listdir(install_path))
    for unsigned_file_name in unsigned_file_names:
        unsigned_file = os.path.join(install_path, unsigned_file_name)
        signed_file = os.path.join(install_path, "signed_" + unsigned_file_name)
        logger.info("    signing: %s (%s)" % (unsigned_file, key))
        common.SignFile(unsigned_file, signed_file, key, password=None,
                    min_api_level=get_min_sdk_version(unsigned_file))
        shutil.move(signed_file, unsigned_file)

def sign_apk(component: Component, event: Event):
    if OPTIONS.sign_keys_dir == None:
        logger.info("sign_key_dir is not set skip sign apk")
        return
    certificate = component.options.certificate
    key = OPTIONS.key_map.get(certificate)
    logger.info("sign_apk: %s (%s)" % (certificate, key))
    if certificate in SPECIAL_CERT_STRINGS or key is None:
        return

    unsigned_file = os.path.join(OPTIONS.target_dir, component.install_path, component.file_name)
    signed_file = os.path.join(OPTIONS.target_dir, component.install_path, "signed_" + component.file_name)

    logger.info("    signing: %s (%s)" % (unsigned_file, key))
    common.SignFile(unsigned_file, signed_file, key, password=None,min_api_level=get_min_sdk_version(unsigned_file))
    shutil.move(signed_file, unsigned_file)


def run_cmd_with_output(cmd):
    return os.popen(cmd).readlines()


def uncompress_embedded_jni_libs(apk_path:str):
    logging.info(f"uncompress_embedded_jni_libs apk install path is {apk_path}")
    check_uncompare_so = run_cmd_with_output(f"zipinfo {apk_path} 'lib/*.so' 2>/dev/null | grep -v ' stor ' 2>/dev/null")
    if len(check_uncompare_so) > 0:
        cmd = ['zip2zip', '-i', apk_path, '-o', f"{apk_path}.tmp",'-0','lib/**/*.so']
        uncompress_result = common.RunAndCheckOutput(cmd)
        run_cmd_with_output(f"mv -f {apk_path}.tmp {apk_path}")
        logging.info(f"execute uncompress_embedded_jni_libs result: {uncompress_result}")
        return True
    else:
        logging.info(f"not need execute uncompress_embedded_jni_libs")
    return False



def uncompress_dex(apk_path:str):
    logging.info(f"uncompress_dex apk install path is {apk_path}")
    check_uncompare_dex = run_cmd_with_output(f"zipinfo {apk_path} 'classes*.dex' 2>/dev/null | grep -v ' stor ' 2>/dev/null")
    if len(check_uncompare_dex) > 0:
        cmd = ['zip2zip', '-i', apk_path, '-o', f"{apk_path}.tmp",'-0','classes*.dex']
        uncompress_result = common.RunAndCheckOutput(cmd)
        run_cmd_with_output(f"mv -f {apk_path}.tmp {apk_path}")
        logging.info(f"execute uncompress_dex result: {uncompress_result}")
        return True
    else:
        logging.info(f"not need execute uncompress_dex")
    return False

def align_package(apk_path):
    logging.info(f"align_package apk install path is {apk_path}")
    check_zipalgin_result = os.system(f"zipalign -c -p 4 {apk_path} 2>/dev/null")
    if check_zipalgin_result != 0:
        run_cmd_with_output(f"mv {apk_path} {apk_path}.unaligned")
        cmd = ['zipalign', '-f', '-p', '4', f"{apk_path}.unaligned",f"{apk_path}.aligned"]
        zipalign_result = common.RunAndCheckOutput(cmd)
        run_cmd_with_output(f"mv {apk_path}.aligned {apk_path}")
        run_cmd_with_output(f"rm -f {apk_path}.unaligned")
        logging.info(f"execute zipalign_result result: {zipalign_result}")
        return True
    else:
        logging.info(f"not need execute align_package")
    return False


def process_apk(component: Component,event:Event):
    certificate = component.options.certificate
    apk_path = os.path.join(OPTIONS.target_dir, component.install_path, component.file_name)
    key = OPTIONS.key_map.get(certificate)
    if certificate in SPECIAL_CERT_STRINGS or key is None:
        logger.info(f"certificate is {certificate}, skip process apk")
        return
    uncompress_jni_result = uncompress_embedded_jni_libs(apk_path)
    uncompress_dex_result = uncompress_dex(apk_path)
    align_package_result = align_package(apk_path)
    logger.info("process apk  uncompress_jni: %s ,uncompress_dex: %s, align_package: %s" % (uncompress_jni_result, uncompress_dex_result,align_package_result))


def check_hash(component: Component, event: Event):
    if component.hash is None:
        logger.info("component's(%s) hash is empty, skip check hash" %
                    component.file_name)
        return
    download_file = os.path.join(
        OPTIONS.target_dir, component.install_path, component.file_name)
    if not os.path.exists(download_file):
        raise BaseException("File %s is not existed" % component.file_name)
    sha1 = hashlib.sha1()
    with open(download_file, 'rb') as file:
        while True:
            data = file.read(1024)
            if not data or event.is_set():
                break
            sha1.update(data)
    actual_sha1sum = sha1.hexdigest()
    if actual_sha1sum != component.hash:
        raise BaseException("File %s is corrupted" % component.file_name)
    logger.info("check hash of file {}({}MB) success.".format(
        download_file, int(os.stat(download_file).st_size / (1024 * 1024))))

def change_extacted_apk_name(output_dir):
    apk_files = os.listdir(f"{output_dir}")
    logger.info(f"apk files under {output_dir}:")
    dir_name = os.path.basename(output_dir)
    print(f'change_extacted_apk_name out_dir: {output_dir}, dir_name: {dir_name}')
    for apk_file in apk_files:
        if apk_file.startswith("base"):
            dst_file = apk_file.replace('base', f'{dir_name}')
            logger.info(f'move from: {output_dir}/{apk_file}')
            logger.info(f'move to: {output_dir}/{dst_file}')
            shutil.move(f'{output_dir}/{apk_file}', f'{output_dir}/{dst_file}')

def extract_apks(apks_path, output_dir, device_spec_path):
    if not os.path.exists(device_spec_path):
        raise Exception(f'device spec file {device_spec_path} not exists')
    if not os.path.exists(output_dir):
        os.makedirs(name=output_dir, exist_ok=True)

    run_cmd(f'java -jar {OPTIONS.bundletool} extract-apks --apks={apks_path} --output-dir={output_dir} --device-spec={device_spec_path}')

    change_extacted_apk_name(output_dir)

def extract_apks_task(component: Component, event: Event):
    if component.type != 'app_bundle':
        logger.info(f'extract_apks: component type isn\'t "app_bundle", skip')
        return

    if not OPTIONS.bundletool:
        raise Exception(f'Couldn\'t found bundletool in otatools.zip')

    install_path = os.path.join(OPTIONS.target_dir, component.install_path)
    apks_path = os.path.join(install_path, component.file_name)
    device_spec_path = os.path.join(OPTIONS.target_dir, component.install_path, f'{component.name}.json')
    with open (device_spec_path, 'w') as f:
        f.write(json.dumps(component.options.device_spec))

    extract_apks(apks_path=apks_path, output_dir=install_path, device_spec_path=device_spec_path)

    os.remove(apks_path)
    os.remove(device_spec_path)

def extract_resource_set(resrouce_set_dir):
    filelist = {}
    for file in os.listdir(resrouce_set_dir):
        target_file = os.path.join(resrouce_set_dir, file)
        if zipfile.is_zipfile(target_file):
            with zipfile.ZipFile(target_file) as zip_file :
                for name in zip_file.namelist():
                    if name in filelist:
                        logger.error(f"{name} in {zip_file.filename} is alread exists in {filelist.get(name)}")
                        sys.exit(1)
                    else:
                        zip_file.extract(name, OPTIONS.target_dir)
                        file_info = zip_file.getinfo(name)
                        if not file_info.is_dir():
                            filelist[name] = zip_file.filename



def add_properties():
    if not OPTIONS.build_properties:
        return
    install_path = ""
    if OPTIONS.target == TARGET_MI_EXT:
        install_path = "etc/"
    install_path = os.path.join(OPTIONS.target_dir, install_path)

    if not os.path.exists(install_path):
        os.mkdir(install_path)
    prop_file = os.path.join(install_path, "build.prop")
    with open(prop_file, 'a') as f:
        for key, value in OPTIONS.build_properties.items():
            f.write("%s=%s\n" % (key, value))

def find_bundletool(selfPath):
    parent = re.findall(r'(.+)/bin.+', selfPath)
    bundetools = glob.glob(f'{parent[0]}/releasetools/bundletool/bundletool*.jar')
    if bundetools:
        return bundetools[0]
    return None

def parse_components(content: str):
    json_data = json.loads(content)
    partitions = json_data.get('partitions')
    res = []
    for partition in partitions:
        partition_name = partition.get('name')
        if "mi_ext" != partition_name:
            logger.info(f"skip partition {partition_name}")
            continue
        components = partition.get('components')
        OPTIONS.build_properties = partition.get('build_properties')
        if components is None:
            return res
        for component_data in components:
            options_data = component_data.get('options')
            options = Options(certificate=options_data.get('certificate'),
                              platform_apis=options_data.get('platform_apis'),
                              privileged=options_data.get('privileged'),
                              system_bundled=options_data.get( 'system_bundled'),
                              abi=options_data.get('abi'),
                              sysconfig=options_data.get('sysconfig'),
                              permissions=options_data.get('permissions'),
                              audio=options_data.get('audio'),
                              opcust=options_data.get('opcust'),
                              removable=options_data.get('removable'),
                              bootanimation=options_data.get('bootanimation'),
                              other_bootanimation=options_data.get( 'other_bootanimation'),
                              wallpaper=options_data.get('wallpaper'),
                              ringtones=options_data.get('ringtones'),
                              carrier=options_data.get('carrier'),
                              install_path=options_data.get('installPath'),
                              default_permissions=options_data.get("default_permissions"),
                              device_features=options_data.get("device_features"),
                              sub_dir=options_data.get("sub_dir"),
                              device_spec=options_data.get("device_spec"),
                              license_url=options_data.get("license_url"),
                              custom_install_path=options_data.get("custom_install_path")) if options_data else Options()
            component = Component(
                name=component_data.get('name'),
                module=component_data.get('module'),
                type=component_data.get('type'),
                url=component_data.get('url'),
                hash=component_data.get('hash'),
                options=options,
                partition=partition_name)
            tasks = __tasks(component)
            res.append((component, tasks))
    return res


__type_to_tasks = {
    "android_app": [process_apk, sign_apk],
    "runtime_resource_overlay": [sign_apk],
    "app_bundle": [extract_apks_task, sign_apks],
}


def __tasks(component: Component):
    result = [download, check_hash]
    tasks_for_type = __type_to_tasks.get(component.type)
    if tasks_for_type is not None:
        result.extend(tasks_for_type)
    return result


def execute(components):
    if not components:
        logging.info("Download exit. No work to do")
        return
    default_max_worker = multiprocessing.cpu_count() * 2
    max_workers = min(default_max_worker, len(components))
    event = threading.Event()
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures_list = [executor.submit(__run, component, event)
                    for component in components]
        for future in futures_list:
            try:
                executed_component = future.result()
            except BaseException as exception:
                composed_component = exception.args[0]
                component = composed_component[0]
                reason = exception.args[1]
                if component.retried_times < OPTIONS.max_retried_times:
                    logging.info("retry download %s for %s, tried %s times" % (component.name,
                                                                          reason,
                                                                          component.retried_times))
                    component.retried_times += 1
                    retried_future = executor.submit(__run, composed_component, event)
                    futures_list.append(retried_future)
                else:
                    event.set()
                    logging.error("Abort download:%s" %  reason)
                    executor.shutdown()
                    sys.exit(1)
    logging.info("Download finished")


def delay(seconds=1):
    time.sleep(seconds)


def need_delay(component: Component):
    return component.retried_times > 0


def __run(composed_component, event):
    component = composed_component[0]
    if need_delay(component):
        delay(seconds=component.retried_times)
    tasks = composed_component[1]
    for task in tasks:
        try:
            task(component, event)
        except BaseException as exception:
            # traceback.print_exc()
            raise BaseException(composed_component, exception.args)
    return component


def query_json_content():
    if OPTIONS.target_url:
        url = OPTIONS.target_url
    else:
        url =url_for_json_content ()

    if not url:
            logger.info("Nothing to download.")
            return None
    try:
        logger.info("download sku files from %s " % url)
        response = request.urlopen(url, context=cert_context)
        json_content = response.read().decode('utf-8')
        return json_content
    except BaseException as arg:
        logger.error('Fail to open %s. exit program...' % url)
        sys.exit(1)


def url_for_json_content():
    json_url = '{base_url}?'\
        'componentType={component}&'\
        'modDevice={modDevice}&'\
        'miui={miui_version}&'\
        'androidVersion={android_version}&'\
        'branch={branch}'.format(
            base_url=BASE_URL,
            component=OPTIONS.target,
            modDevice=OPTIONS.device_name,
            miui_version=OPTIONS.miui_version,
            android_version=OPTIONS.android_version,
            branch=OPTIONS.branch)
    return request.urlopen(json_url, context=cert_context).read().decode()


def build_key_map():
    sign_key_dir = OPTIONS.sign_keys_dir
    if sign_key_dir is None:
        return
    OPTIONS.key_map = {
        "devkey":   sign_key_dir + "/releasekey",
        "testkey":  sign_key_dir + "/releasekey",
        "default":  sign_key_dir + "/releasekey",
        "media":    sign_key_dir + "/media",
        "shared":   sign_key_dir + "/shared",
        "platform": sign_key_dir + "/platform",
        "sdk_sandbox":  sign_key_dir + "/sdk_sandbox",
        "bluetooth":  sign_key_dir + "/bluetooth",
        "networkstack": sign_key_dir + "/networkstack",
    }

def prepare_dirs():
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/lib64"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/lib"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/overlay"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/app"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/priv-app"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/bin"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/usr"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/framework"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/media"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/opcust"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/data-app"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/etc/sysconfig"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/etc/permissions"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/etc/precust_theme"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/etc/security"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "product/etc/preferred-apps"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "system/app"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "system/priv-app"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "system/framework"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "system/etc/sysconfig"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "system/etc/permissions"), exist_ok=True)
    os.makedirs(os.path.join(OPTIONS.target_dir, "system_ext/etc/permissions"), exist_ok=True)

def json_content():
    if OPTIONS.json_content:
        return OPTIONS.json_content
    else:
        return query_json_content()

def generator_sub_meta_lic(built_file:str,license_path:str,license_url:str=None):
    meta_lic_file = built_file + '.meta_lic'
    license_file = license_path
    if license_url is not None:
        license_file = built_file+".LICENSE"
    with open(meta_lic_file, 'w',encoding='utf-8') as f:
        f.write("package_name:  \"Android\"\n")
        f.write("module_types:  \"raw\"\n")
        f.write("module_classes:  \"unknown\"\n")
        f.write("license_kinds:  \"SPDX-license-identifier-Apache-2.0\"\n")
        f.write("license_conditions:  \"notice\"\n")
        f.write(f"license_texts:  \"{license_file}\"\n")
        f.write("is_container:  false\n")
        f.write(f"built:  \"{built_file}\"")
        return meta_lic_file

def find_license(selfPath):
    parent = re.findall(r'(.+)/bin.+', selfPath)
    license = glob.glob(f'{parent[0]}/releasetools/LICENSE')
    if license:
        return license[0]
    return None

def generator_img_meta_lic(meta_lic_file_list,license_path):
    img_meta_lic = os.path.join(OPTIONS.target_dir,"mi_ext.img.meta_lic")
    from_path = OPTIONS.target_dir
    logger.info("from_path: %s " % from_path)
    with open(img_meta_lic, 'w',encoding='utf-8') as f:
        f.write("package_name:  \"Android\"\n")
        f.write("module_types:  \"raw\"\n")
        f.write("module_classes:  \"unknown\"\n")
        f.write("license_kinds:  \"SPDX-license-identifier-Apache-2.0\"\n")
        f.write("license_conditions:  \"notice\"\n")
        f.write(f"license_texts:  \"{license_path}\"\n")
        f.write("is_container:  true\n")
        f.write(f"built:  \"mi_ext.img\"\n")
        f.write("install_map:  {\n")
        f.write(f"  from_path:  \"{from_path}/\"\n")
        f.write("  container_path:  \"/\"\n")
        f.write("}\n")
        for meta_lic_file in meta_lic_file_list:
            download_file = meta_lic_file.replace(".meta_lic","")
            f.write(f"sources:  \"{download_file}\"\n")
            f.write("deps:  {\n")
            f.write(f"  file:  \"{meta_lic_file}\"\n")
            f.write("}\n")
    return img_meta_lic


def generator_notice_xml_gz(components):
    if not components:
        return
    meta_lic_file_list = []
    license_path = find_license(os.path.dirname(os.path.realpath(__file__)))
    logger.info("found LICENSE path: %s " % license_path)
    if license_path is None:
        raise Exception(f'Couldn\'t found LICENSE in otatools.zip')
    target_link_dir = os.path.join(OPTIONS.target_dir,'mi_ext')
    if not os.path.exists(target_link_dir):
        os.symlink(OPTIONS.target_dir, target_link_dir)
    for component in components:
        cpt = component[0]
        if isinstance(cpt, Component) and cpt.type != "resource_set":
            download_file = os.path.join(target_link_dir, cpt.install_path, cpt.file_name)
            meta_lic_file = generator_sub_meta_lic(download_file,license_path,cpt.options.license_url)
            if meta_lic_file is not None:
                meta_lic_file_list.append(meta_lic_file)
        else:
            logging.info(f"not component type: {type(cpt)}")
    build_prop_file = os.path.join(target_link_dir, 'etc/build.prop')
    if(os.path.exists(build_prop_file)):
        meta_lic_file_list.append(generator_sub_meta_lic(build_prop_file,license_path))
    if len(meta_lic_file_list)>0:
        img_meta_lic = generator_img_meta_lic(meta_lic_file_list,license_path)
        out_path = os.path.join(OPTIONS.target_dir,"etc/NOTICE.xml.gz")
        out_dir = os.path.dirname(out_path)
        if not os.path.exists(out_dir):
            os.makedirs(out_dir)
        run_cmd(f"xmlnotice -o {out_path} -product=\"MI EXT image\" -title=\"Notices for files contained in the MI EXT filesystem image in this directory:\" -strip_prefix=mi_ext.img {img_meta_lic}")
        os.remove(img_meta_lic)
        for meta_lic_file in meta_lic_file_list:
            os.remove(meta_lic_file)
            license_file = meta_lic_file.replace('.meta_lic','.LICENSE')
            if os.path.exists(license_file):
                os.remove(license_file)
    else:
        logging.info(f"meta_lic_file_list len = 0")

    if(os.path.islink(target_link_dir)):
        os.remove(target_link_dir)

def main(argv):
    common.InitLogging()

    def option_handler(o, a):
        if o == '--android-version':
            OPTIONS.android_version = a
        elif o == '--miui-version':
            OPTIONS.miui_version = a
        elif o == '--device-name':
            OPTIONS.device_name = a
        elif o == '--target':
            OPTIONS.target = a
        elif o == '--branch':
            OPTIONS.branch = a
        elif o == '--target-dir':
            OPTIONS.target_dir = a
        elif o == '--target-url':
            OPTIONS.target_url = a
        elif o == '--sign-keys-dir':
            OPTIONS.sign_keys_dir = a
        elif o == '--json-content':
            OPTIONS.json_content = a
        else:
            return False
        return True
    args = common.ParseOptions(
        argv,
        __doc__,
        extra_long_opts=[
            'android-version=',
            'miui-version=',
            'device-name=',
            'target=',
            'branch=',
            'target-dir=',
            'target-url=',
            'sign-keys-dir=',
            'json-content=',
        ],
        extra_option_handler=option_handler)

    if (OPTIONS.target_dir is not None) and (not os.path.exists(OPTIONS.target_dir)):
        logger.error("target-dir: %s is not exists" % OPTIONS.target_dir)
        return

    if (OPTIONS.sign_keys_dir is not None) and (not os.path.exists(OPTIONS.sign_keys_dir)):
        logger.error("sign-keys-dir: %s is not exists" % OPTIONS.sign_keys_dir)
        return

    OPTIONS.bundletool = find_bundletool(os.path.dirname(__file__))
    # OPTIONS.bundletool = '/home/mi/workspace/aosp/nuwa/m2-nuwa-ssi/prebuilts/bundletool/bundletool-all-20210812.jar'
    OPTIONS.resource_set_download_dir = common.MakeTempDir()
    prepare_dirs()
    build_key_map()
    components_json = json_content()
    if components_json:
        try:
            components = parse_components(components_json)
        except BaseException as exception:
            logger.error("json content is invalid.%s"%exception)
            sys.exit(1)
        execute(components)
        add_properties()
        extract_resource_set(OPTIONS.resource_set_download_dir)
        generator_notice_xml_gz(components)


if __name__ == '__main__':
    try:
        argv = sys.argv[1:]
        main(argv)
    finally:
        common.Cleanup()

