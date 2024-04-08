#!/usr/bin/env python3
import argparse
import hashlib
import json
import logging
import multiprocessing
import os
import shutil
import subprocess
import sys
import threading
import traceback
from concurrent import futures
from concurrent.futures import ThreadPoolExecutor
from threading import Event
from urllib import request
from enum import Enum
import glob
import filecmp

import common

logger = logging.getLogger(__name__)
common.OPTIONS.verbose = True
top_dir = ''

class PackageType(Enum):
    XMS_APP = 'xms_app'
    APP_BUNDLE = 'app_bundle'

    def fromType(type):
        return PackageType.__members__.get(type.upper(), None)

    def type_to_ext(self):
        ext = ''
        match(self.value):
            case 'xms_app':
                ext = '.apk'
            case 'app_bundle':
                ext = '.apks'
        return ext

class Options:
    def __init__(self,
                 certificate: str = "",
                 install_path: str = "",
                 removable: bool = False,
                 privileged: bool = False,
                 device_spec: object = None):
        self.certificate = certificate
        self.install_path = install_path
        self.removable = removable
        self.privileged = privileged
        self.device_spec = device_spec


class Component:
    def __init__(self,
                 name: str = "",
                 type: str = None,
                 url: str = None,
                 hash: str = None,
                 partition: str = None,
                 options: Options = None):
        type = PackageType.fromType(type)
        self.name = os.path.splitext(name)[0]
        self.file_name = name
        self.url = url
        self.type = type
        self.partition = partition
        self.options = options
        self.install_path = self.__android_app_dir()
        self.hash = hash

    def __android_app_dir(self) -> str:
        file_name_stem = f'split-{self.name}' if self.type == PackageType.APP_BUNDLE else self.name
        if self.options.removable:
            dir = "data-app/%s" % file_name_stem
        else:
            if self.options.privileged:
                dir = "priv-app/%s" % file_name_stem
            else:
                dir = "app/%s" % file_name_stem
        return dir

    def __str__(self) -> str:
        return self.name


def download(component: Component, event: Event, download_dir):
    install_path = os.path.join(download_dir, component.install_path)
    if not os.path.exists(install_path):
        os.makedirs(name=install_path, exist_ok=True)

    download_file = os.path.join(install_path, component.file_name)
    with request.urlopen(component.url) as response:
        with open(download_file, 'wb') as f:
            buffer_size = 1024 * 10
            while True:
                data = response.read(buffer_size)
                if not data or event.is_set():
                    break
                f.write(data)


def check_hash(component: Component, event: Event, download_dir):
    if not component.hash:
        logger.info("component's(%s) hash is empty, skip check hash" %
                    component.file_name)
        return
    download_file = os.path.join(download_dir, component.install_path, component.file_name)
    if not os.path.exists(download_file):
        raise Exception("File %s is not existed" % component.file_name)
    sha1 = hashlib.sha1()
    with open(download_file, 'rb') as file:
        while True:
            data = file.read(1024)
            if not data or event.is_set():
                break
            sha1.update(data)
    actual_sha1sum = sha1.hexdigest()
    if actual_sha1sum != component.hash:
        raise Exception("File %s is corrupted" % component.file_name)
    logger.info("check hash of file {}({}MB) success.".format(
        download_file, int(os.stat(download_file).st_size / (1024 * 1024))))

def change_extacted_apk_name(output_dir):
    apk_files = os.listdir(f"{output_dir}")
    dir_name = os.path.basename(output_dir)
    for apk_file in apk_files:
        if apk_file.startswith("base"):
            dst_file = apk_file.replace('base', f'{dir_name}')
            logger.info(f'move from: {output_dir}/{apk_file}')
            logger.info(f'move to: {output_dir}/{dst_file}')
            shutil.move(f'{output_dir}/{apk_file}', f'{output_dir}/{dst_file}')

def extract_apks(apks_path, output_dir, device_spec_path):
    bundletool_dir = os.path.join(top_dir,'prebuilts/bundletool')
    bundletool = glob.glob(f'{bundletool_dir}/bundletool*.jar')
    if not bundletool :
        raise Exception(f'Couldn\'t found bundletool in {bundletool_dir}')
    bundletool = bundletool[0]

    if not os.path.exists(device_spec_path):
        raise Exception(f'device spec file {device_spec_path} not exists')
    if not os.path.exists(output_dir):
        os.makedirs(name=output_dir, exist_ok=True)

    run_cmd(f'java -jar {bundletool} extract-apks --apks={apks_path} --output-dir={output_dir} --device-spec={device_spec_path}')
    change_extacted_apk_name(output_dir)

def extract_apks_task(component: Component, event: Event, download_dir):
    if component.type != PackageType.APP_BUNDLE:
        logger.info(f'extract_apks: component type isn\'t "app_bundle", skip')
        return

    install_path = os.path.join(download_dir, component.install_path)
    apks_path = os.path.join(install_path, component.file_name)
    device_spec_path = os.path.join(download_dir, component.install_path, f'{component.name}.json')
    with open (device_spec_path, 'w') as f:
        f.write(json.dumps(component.options.device_spec))

    extract_apks(apks_path=apks_path, output_dir=install_path, device_spec_path=device_spec_path)

    os.remove(apks_path)
    os.remove(device_spec_path)

def write_apkcerts(components_list: list, apkcerts_file_path, product_dir):
    logger.info(f"write_apkcerts: apkcerts_file_path is f{apkcerts_file_path}")

    def get_certificate_info(component):
        raw_certificate = component.options.certificate
        certificate_section = 'PRESIGNED' if raw_certificate == "PRESIGNED" else f'build/make/target/product/security/{raw_certificate}.x509.pem'
        private_key = '' if raw_certificate == "PRESIGNED" else f'build/make/target/product/security/{raw_certificate}.pk8'
        return certificate_section, private_key

    def deal_apk(component, infile, download_dir):
        file_name = component.file_name
        certificate_section, private_key = get_certificate_info(component)
        new_line = f'name="{file_name}" certificate="{certificate_section}" private_key="{private_key}" partition="{component.partition}"\n'
        infile.write(new_line)

    def deal_apks(component, infile, download_dir):
        certificate_section, private_key = get_certificate_info(component)
        install_path = os.path.join(download_dir, component.install_path)
        apk_list = list(filter(lambda f: f.endswith('.apk'), os.listdir(install_path)))
        for apk in apk_list:
            new_line = f'name="{apk}" certificate="{certificate_section}" private_key="{private_key}" partition="{component.partition}"\n'
            infile.write(new_line)


    with open(apkcerts_file_path, 'w+') as infile:
        for i, component in enumerate(components_list):
            match(component.type):
                case PackageType.XMS_APP:
                    deal_apk(component, infile, product_dir)
                case PackageType.APP_BUNDLE:
                    deal_apks(component, infile, product_dir)


def parse_components(content: str):
    json_data = json.loads(content)
    partitions = json_data['partitions']
    res = []
    components_list = list()
    for partition in partitions:
        partition_name = partition.get('name')
        if partition_name != 'product':
            continue
        components = partition.get('components')
        if components is None:
            return res
        for component_data in components:
            if 'options' not in component_data:
                logger.info("component data [{}] does not contains options key, ignore".format(component_data))
                continue
            if component_data.get('type') != PackageType.APP_BUNDLE.value:
                logger.info("component data [{}] type is not app_bundle, skip".format(component_data))
                continue
            options_data = component_data['options']

            options = Options(certificate=options_data.get('certificate'),
                              install_path=options_data.get('installPath'),
                              removable=options_data.get('removable'),
                              privileged=options_data.get('privileged'),
                              device_spec=options_data.get('device_spec', None))
            logger.info("options.device_spec: %s" %(options.device_spec))

            component = Component(
                name=component_data.get('name'),
                type=component_data.get('type'),
                url=component_data.get('url'),
                hash=component_data.get('hash'),
                options=options,
                partition=partition_name)
            components_list.append(component)
            tasks = __tasks(component)
            res.append((component, tasks))

    return res, components_list


def __tasks(component: Component):
    result = [download, check_hash, extract_apks_task]
    return result


def execute(components, product_dir):
    if len(components) == 0:
        logging.info("Download exit. No work to do")
        return
    default_max_worker = multiprocessing.cpu_count() * 2
    max_workers = min(default_max_worker, len(components))
    event = threading.Event()
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures_list = [executor.submit(__run, component, event, product_dir)
                        for component in components]
        for future in futures.as_completed(futures_list):
            try:
                executed_component = future.result()
            except BaseException as exception:
                event.set()
                reason = exception.args
                logging.error("Abort download:%s" % reason)
                executor.shutdown()
                sys.exit(1)
    logging.info("Download finished")


def __run(composed_component, event, thread_param):
    component = composed_component[0]
    tasks = composed_component[1]
    for task in tasks:
        try:
            task(component, event, thread_param)
        except BaseException as exception:
            traceback.print_exc()
            raise Exception("Download %s failed " % component.file_name)
    return component


def query_json_content(apk_info_url):
    try:
        if apk_info_url is None or len(apk_info_url) == 0:
            raise Exception(f"download apk resources from CDP_COMP_PRODUCT_PKG_URL{apk_info_url} failed, "
                            f"please try again or check corgi environment variable CDP_COMP_PRODUCT_PKG_URL.")
        logger.info("download apk resource from %s " % apk_info_url)
        response = request.urlopen(apk_info_url)
        json_content = response.read().decode('utf-8')
        return json_content
    except ValueError as arg:
        traceback.print_exc()
        raise Exception(f"An exception occurred while downloading apk resources from CDP_COMP_PRODUCT_PKG_URL"
                        f"{apk_info_url}, " f"please try again or check corgi environment variable "
                        f"CDP_COMP_PRODUCT_PKG_URL.")


def run_cmd(command, is_abort=True):
    logger.info(command)
    with subprocess.Popen(command, shell=True, env=os.environ) as res:
        out, err = res.communicate()
        if res.returncode != 0:
            logger.warning("command \"{}\" returned {}: {}".format(command, res.returncode, err))
            if is_abort:
                raise Exception(f"Execute command {command} failed: output = {out}, error = {err}")


def del_dir_if_exist(*dirs):
    for dir in dirs:
        if os.path.exists(dir) and os.path.isdir(dir):
            logger.info(f"dir {dir} exist and delete it.")
            shutil.rmtree(dir)


def prepare_for_download(apk_info_url):
    if not apk_info_url:
        logger.warning("apk_info_url is None, ignore download apks from server.")
        return

    json_content = query_json_content(apk_info_url)
    if not json_content:
        raise Exception(f"An exception occurred while downloading json resources from CDP_COMP_PRODUCT_PKG_URL"
                        f"{apk_info_url}, " f"please try again or check corgi environment variable "
                        f"CDP_COMP_PRODUCT_PKG_URL.")
    tasks, components_list = parse_components(json_content)

    return tasks, components_list

def download_apks_from_server(product_dir, apkcerts, tasks, components_list):
    execute(tasks, product_dir)
    write_apkcerts(components_list, apkcerts, product_dir)


def download_apks(tasks, components_list, product_dir, download_apkcerts):
    download_apks_from_server(product_dir, download_apkcerts, tasks, components_list)

    logger.info("download apks finished, data dir size is:")
    run_cmd(f"du -sh {product_dir}", is_abort=False)


def cmd_download(args):
    print('cmd_download')
    logger.info(f"download args.output-dir = {args.output_dir}, args.addon-apkcerts = {args.addon_apkcerts}, args.apk_info_url = {args.apk_info_url}")
    global top_dir
    top_dir = args.top_dir
    output_dir = args.output_dir
    addon_apkcerts = args.addon_apkcerts
    apk_info_url = args.apk_info_url
    if not apk_info_url:
        apk_info_url = os.environ.get('CDP_COMP_PRODUCT_PKG_URL', '')

    if not apk_info_url:
        logger.info("apk_info_url not set, don\'t download APKs")
        return

    if not os.path.exists(top_dir):
        raise Exception(f"top-dir {top_dir} not exist，please check your input argument --top-dir")
    if not os.path.exists(output_dir):
        raise Exception(f"output-dir {output_dir} not exist，please check your input argument --output-dir")
    if not addon_apkcerts:
        raise Exception(f"addon-apkcerts {output_dir} not exist，please check your input argument --addon-apkcerts")

    tmp_apkcerts_dir = f'{output_dir}/tmp_apkcerts'
    product_dir = f'{output_dir}/product'
    if os.path.exists(tmp_apkcerts_dir):
        shutil.rmtree(tmp_apkcerts_dir)
    os.makedirs(tmp_apkcerts_dir)

    tasks, components_list = prepare_for_download(apk_info_url)

    download_apkcerts = f"{tmp_apkcerts_dir}/download_apkcerts.txt"

    download_apks(tasks, components_list, product_dir, download_apkcerts)

    if not os.path.exists(addon_apkcerts) or not filecmp(addon_apkcerts, download_apkcerts):
        logger.info(f'copy {download_apkcerts} to {addon_apkcerts}')
        shutil.copyfile(download_apkcerts, addon_apkcerts)

    del_dir_if_exist(tmp_apkcerts_dir)


def main():
    common.InitLogging()

    parser = argparse.ArgumentParser(description='download APKs')

    parser.add_argument('--top-dir', nargs='?', type=str, required=True)
    parser.add_argument('--output-dir', nargs='?', type=str, required=True)
    parser.add_argument('--addon-apkcerts', nargs='?', type=str, required=True)
    parser.add_argument('--apk-info-url', nargs='?', type=str)

    args = parser.parse_args()
    cmd_download(args)

if __name__ == '__main__':
    main()