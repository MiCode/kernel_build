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
import re

import common

logger = logging.getLogger(__name__)
common.OPTIONS.verbose = True
bundletool = ''

WHITE_LIST = {
    "pissarro",
    "courbet",
    "agate",
    "chopin",
    "ares",
    "pissarropro",
    "star",
    "venus",
    "fuxi",
    "mondrian",
    "psyche",
    "munch",
    "thyme",
    "renoir",
    "cupid",
    "taoyao",
    "ingres",
    "matisse",
    "xaga",
    "munch",
    "zeus",
    "nuwa",
    "venus",
}

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

PANGU_REMAKE_SUCCESS_FLAG = ".pangu_userdata_remake_success.lock"


class Options:
    def __init__(self,
                 certificate: str = "",
                 install_path: str = "",
                 device_spec: object = None):
        self.certificate = certificate
        self.install_path = install_path
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
        self.name = name
        self.file_name = name + type.type_to_ext()
        self.url = url
        self.type = type
        self.partition = partition
        self.options = options
        self.install_path = options.install_path + "/" + (f'split-{name}' if type == PackageType.APP_BUNDLE else name)
        self.hash = hash

    def __str__(self) -> str:
        return self.name


def download(component: Component, event: Event, userdata_download_dir):
    install_path = os.path.join(userdata_download_dir, component.install_path)
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


def check_hash(component: Component, event: Event, userdata_download_dir):
    if not component.hash:
        logger.info("component's(%s) hash is empty, skip check hash" %
                    component.file_name)
        return
    download_file = os.path.join(
        userdata_download_dir, component.install_path, component.file_name)
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
    logger.info(f"apk files under {output_dir}:")
    dir_name = os.path.basename(output_dir)
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

    run_cmd(f'java -jar {bundletool} extract-apks --apks={apks_path} --output-dir={output_dir} --device-spec={device_spec_path}')

    change_extacted_apk_name(output_dir)

def extract_apks_task(component: Component, event: Event, download_dir):
    if component.type != PackageType.APP_BUNDLE:
        logger.info(f'extract_apks: component type isn\'t "app_bundle", skip')
        return
    if not bundletool:
        raise Exception(f'Couldn\'t found bundletool in otatools.zip')

    install_path = os.path.join(download_dir, component.install_path)
    apks_path = os.path.join(install_path, component.file_name)
    device_spec_path = os.path.join(download_dir, component.install_path, f'{component.name}.json')
    with open (device_spec_path, 'w') as f:
        f.write(json.dumps(component.options.device_spec))

    extract_apks(apks_path=apks_path, output_dir=install_path, device_spec_path=device_spec_path)

    os.remove(apks_path)
    os.remove(device_spec_path)


def validate_and_append_apkcerts(raw_apkcerts_file, new_apkcerts_files):
    logger.info(
        f"validate_and_append_apkcerts: raw_apkcerts_file = {raw_apkcerts_file}, new_apkcerts_files = {new_apkcerts_files}")
    raw_name_set = set()
    with open(raw_apkcerts_file, 'r') as file:
        contents = file.read()
        lines = contents.split('\n')
        start = 'name="'
        end = '" certificate='
        for line in lines:
            name = line[(line.find(start) + len(start)):line.rfind(end)]
            if name:
                raw_name_set.add(name)

    for certs in new_apkcerts_files:
        with open(certs, 'r') as file:
            contents = file.read()
            lines = contents.split('\n')
            start = 'name="'
            end = '" certificate='
            for line in lines:
                name = line[line.find(start) + len(start):line.rfind(end)]
                if name in raw_name_set:
                    raise Exception(f"validate apkcerts.txt failed， duplicate name [{name}] {certs}")
                if name:
                    raw_name_set.add(name)

    with open(raw_apkcerts_file, 'a+') as outfile:
        for certs in new_apkcerts_files:
            with open(certs) as infile:
                contents = infile.read()
                logger.info(
                    f"Following content from {certs} will be appended into {raw_apkcerts_file}:\n{contents}\n\n")
                infile.seek(0)
                outfile.write(infile.read())


def write_apkcerts(components_list: list, apkcerts_file_path, userdata_download_dir):
    logger.info(f"write_apkcerts: apkcerts_file_path is f{apkcerts_file_path}")

    def get_certificate_info(component):
        raw_certificate = component.options.certificate
        certificate_section = 'PRESIGNED' if raw_certificate == "PRESIGNED" else f'build/make/target/product/security/{raw_certificate}.x509.pem'
        private_key = '' if raw_certificate == "PRESIGNED" else f'build/make/target/product/security/{raw_certificate}.pk8'
        return certificate_section, private_key

    def deal_apk(component, infile):
        file_name = component.file_name
        certificate_section, private_key = get_certificate_info(component)
        new_line = f'name="{file_name}" certificate="{certificate_section}" private_key="{private_key}" partition="{component.partition}"\n'
        infile.write(new_line)

    def deal_apks(component, infile):
        certificate_section, private_key = get_certificate_info(component)
        install_path = os.path.join(userdata_download_dir, component.install_path)
        apk_list = list(filter(lambda f: f.endswith('.apk'), os.listdir(install_path)))
        for apk in apk_list:
            new_line = f'name="{apk}" certificate="{certificate_section}" private_key="{private_key}" partition="{component.partition}"\n'
            infile.write(new_line)
    with open(apkcerts_file_path, 'w+') as infile:
        for i, component in enumerate(components_list):
            match(component.type):
                case PackageType.XMS_APP:
                    deal_apk(component, infile)
                case PackageType.APP_BUNDLE:
                    deal_apks(component, infile)


def parse_components(content: str):
    json_data = json.loads(content)
    partitions = json_data['partitions']
    res = []
    components_list = list()
    for partition in partitions:
        partition_name = partition.get('name')
        if partition_name != 'data':
            continue
        components = partition.get('components')
        if components is None:
            return res
        for component_data in components:
            if 'options' not in component_data:
                logger.info("component data [{}] does not contains options key, ignore".format(component_data))
                continue
            options_data = component_data['options']
            options = Options(certificate=options_data.get('certificate'),
                              install_path=options_data.get('installPath'),
                              device_spec=options_data.get('device_spec', None))
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


def execute(components, userdata_download_dir):
    if len(components) == 0:
        logging.info("Download exit. No work to do")
        return
    default_max_worker = multiprocessing.cpu_count() * 2
    max_workers = min(default_max_worker, len(components))
    event = threading.Event()
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures_list = [executor.submit(__run, component, event, userdata_download_dir)
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
    res = subprocess.Popen(command, shell=True, env=os.environ)
    out, err = res.communicate()
    if res.returncode != 0:
        logger.warning("command \"{}\" returned {}: {}".format(command, res.returncode, err))
        if is_abort:
            raise Exception(f"Execute command {command} failed: output = {out}, error = {err}")


def is_command_exist(name):
    """Check whether `name` is on PATH and marked as executable."""
    return shutil.which(name) is not None


def del_dir_if_exist(*dirs):
    for dir in dirs:
        if os.path.exists(dir) and os.path.isdir(dir):
            logger.info(f"dir {dir} exist and delete it.")
            shutil.rmtree(dir)


def del_file_if_exist(file):
    if os.path.exists(file):
        os.remove(file)
    else:
        logger.info(f"cannot find the file [{file}]")


def download_apks_from_server(apk_info_url, userdata_download_dir, apkcerts):
    if not apk_info_url:
        logger.warning("apk_info_url is None, ignore download apks from server.")
        return
    json_content = query_json_content(apk_info_url)
    if not json_content:
        raise Exception(f"An exception occurred while downloading json resources from CDP_COMP_PRODUCT_PKG_URL"
                        f"{apk_info_url}, " f"please try again or check corgi environment variable "
                        f"CDP_COMP_PRODUCT_PKG_URL.")
    tasks, components_list = parse_components(json_content)
    execute(tasks, userdata_download_dir)
    write_apkcerts(components_list, apkcerts, userdata_download_dir)


def download_third_apks(userdata_download_dir, device_name, build_profile, build_region,
                        build_android_codebase, apkcerts):
    userdata_app_download_name = "userdata_app_download"
    if not is_command_exist(userdata_app_download_name):
        logger.warning(f"{userdata_app_download_name} not exist, ignore")
        return

    logger.info(f"{userdata_app_download_name} exist, prepare to call it.")
    run_cmd(
        f"{userdata_app_download_name} {device_name} {build_profile} {build_region} false {build_region} \"\" {build_android_codebase} {userdata_download_dir} {apkcerts}")


def download_apks(output_dir, apk_info_url, device_name, build_profile, build_region, build_android_codebase):
    userdata_download_dir = os.path.join(output_dir, "pangu_userdata_download_dir")
    del_dir_if_exist(userdata_download_dir)
    run_cmd(f"mkdir -p {userdata_download_dir}")
    new_apkcerts_dir = f"{output_dir}/pangu_new_apkcerts_dir"
    del_dir_if_exist(new_apkcerts_dir)
    run_cmd(f"mkdir -p {new_apkcerts_dir}")

    download_apkcerts = f"{new_apkcerts_dir}/download_apkcerts.txt"
    download_apks_from_server(apk_info_url, userdata_download_dir, download_apkcerts)

    apkcerts_third = f"{new_apkcerts_dir}/apkcerts_third.txt"
    download_third_apks(userdata_download_dir, device_name, build_profile, build_region, build_android_codebase,
                        apkcerts_third)

    logger.info("download apks finished, data dir size is:")
    run_cmd(f"du -sh {userdata_download_dir}", is_abort=False)
    return new_apkcerts_dir, userdata_download_dir


def WriteSortedData(data, path):
    """Writes the sorted contents of either a list or dict to file.

    This function sorts the contents of the list or dict and then writes the
    resulting sorted contents to a file specified by path.

    Args:
      data: The list or dict to sort and write.
      path: Path to the file to write the sorted values to. The file at path will
        be overridden if it exists.
    """
    with open(path, 'w') as output:
        for entry in sorted(data):
            out_str = '{}={}\n'.format(entry, data[entry]) if isinstance(
                data, dict) else '{}\n'.format(entry)
            output.write(out_str)


def update_miscinfo_txt(meta_dir):
    misc_info = common.LoadDictionaryFromFile(
        os.path.join(meta_dir, 'misc_info.txt'))
    logger.info(
        f"update_miscinfo_txt: origin userdata_img_with_data value is: [{misc_info.get('userdata_img_with_data')}]")
    logger.info(f"update_miscinfo_txt: origin userdata_selinux_fc value is: [{misc_info.get('userdata_selinux_fc')}]")
    misc_info['userdata_img_with_data'] = "true"
    misc_info['userdata_selinux_fc'] = "framework_file_contexts.bin"
    WriteSortedData(data=misc_info, path=os.path.join(meta_dir, 'misc_info.txt'))


def make_userdata_img(output_dir, target_files, userdata_download_dir, new_apkcerts_dir, userdata_image):
    logger.info(f"make_userdata_img: output_dir = {output_dir}, target_files = {target_files}, userdata_download_dir = "
                f"{userdata_download_dir}, new_apkcerts_dir = {new_apkcerts_dir}, userdata_download_dir = {userdata_image}")
    run_cmd(f"ls -hl {userdata_download_dir}", is_abort=False)
    run_cmd(f"du -sh {userdata_download_dir}", is_abort=False)
    if os.path.exists(userdata_download_dir) and os.listdir(userdata_download_dir):
        run_cmd(f"ls -hl {target_files}", is_abort=False)
        run_cmd(f"rm -rf {output_dir}/target_files")
        run_cmd(f"unzip {target_files} -d {output_dir}/target_files")
        raw_apk_certs = os.path.join(output_dir, "target_files", "META", "apkcerts.txt")
        new_apkcerts_files = list()
        for file in os.listdir(new_apkcerts_dir):
            new_apkcerts_files.append(os.path.join(new_apkcerts_dir, file))
        validate_and_append_apkcerts(raw_apk_certs, new_apkcerts_files)
        update_miscinfo_txt(f"{output_dir}/target_files/META")
        run_cmd(f"ls -hl {userdata_image}")
        run_cmd(f"rm {userdata_image}")
        run_cmd(f"cp -a {userdata_download_dir}/. {output_dir}/target_files/DATA/")
        run_cmd(f"add_img_to_target_files -v -a {output_dir}/target_files/")
        logger.info("after add_img_to_target_files, userdata.img size is:")
        run_cmd(f"ls -hl {userdata_image}")
        logger.info("remaking userdata image successfully, ")
    else:
        logger.info(f"ignore making userdata image because {userdata_download_dir} is empty")


def make_target_files(output_dir, target_files, userdata_image):
    logger.info(
        f"make_target_files: output_dir = {output_dir}, target_files = {target_files}, userdata_image = {userdata_image}")
    if os.path.exists(userdata_image):
        run_cmd(f"rm {target_files}")
        run_cmd(f"find {output_dir}/target_files | sort >{output_dir}/target_files.list")
        run_cmd(f"cat {output_dir}/target_files.list")
        run_cmd(f"soong_zip -d -o {target_files} -C {output_dir}/target_files -r {output_dir}/target_files.list")
        run_cmd(f"rm -rf {output_dir}/target_files")
        run_cmd(f"ls -hl {target_files}")
        logger.info("remaking target file successfully.")
        # create an empty file to notify CI that userdata image has been remaking successfully.
        try:
            open(f"{output_dir}/{PANGU_REMAKE_SUCCESS_FLAG}", 'w+')
        except OSError as e:
            raise Exception(
                f"Could not create FLAG file[{PANGU_REMAKE_SUCCESS_FLAG}] to notify CI that ussrdata image has been "
                f"created successfully, error is [{e}]")
    else:
        logger.info(f"ignore making target files because userdata image {userdata_image} is not exist")

def find_bundletool(selfPath):
    logger.info(f'find_bundletool selfPath: {selfPath}')
    parent = re.findall(r'(.+)/bin.+', selfPath)
    logger.info(f'find_bundletool selfPath: {selfPath}')
    bundetools = glob.glob(f'{parent[0]}/releasetools/bundletool/bundletool*.jar')
    if bundetools:
        return bundetools[0]
    return None

def main():
    common.InitLogging()
    parser = argparse.ArgumentParser(description='download apk resources and make userdata image')
    parser.add_argument('--output-dir', nargs='?', type=str, required=True)
    parser.add_argument('--target-files', nargs='?', type=str, required=True)
    parser.add_argument('--device-name', nargs='?', type=str)
    parser.add_argument('--build-profile', nargs='?', type=str)
    parser.add_argument('--build-region', nargs='?', type=str)
    parser.add_argument('--build-android-codebase', nargs='?', type=str)
    parser.add_argument('--apk-info-url', nargs='?', type=str)
    args = parser.parse_args()

    logger.info(f"args.output_dir = {args.output_dir}, args.target_files = {args.target_files}, "
                f"args.device_name = {args.device_name}, args.build_profile = {args.build_profile}, "
                f"args.build_region = {args.build_region}, args.build_android_codebase = {args.build_android_codebase},"
                f" args.apk_info_url = {args.apk_info_url}")

    output_dir = args.output_dir
    apk_info_url = args.apk_info_url
    device_name = args.device_name
    build_profile = args.build_profile
    build_region = args.build_region
    build_android_codebase = args.build_android_codebase

    global bundletool
    bundletool = find_bundletool(os.path.dirname(__file__))

    if not os.path.exists(output_dir):
        raise Exception(f"output_dir {output_dir} not exist，please check your input argument --output-dir")

    del_file_if_exist(f"{output_dir}/{PANGU_REMAKE_SUCCESS_FLAG}")

    new_apkcerts_dir, userdata_download_dir = download_apks(output_dir, apk_info_url, device_name, build_profile,
                                                            build_region, build_android_codebase)

    target_files = args.target_files
    if not os.path.exists(target_files):
        raise Exception(f"target_files [{target_files}] not exist ，please check your input argument --target-files")
    userdata_image = f"{output_dir}/target_files/IMAGES/userdata.img"
    make_userdata_img(output_dir, target_files, userdata_download_dir, new_apkcerts_dir, userdata_image)
    make_target_files(output_dir, target_files, userdata_image)


if __name__ == '__main__':
    main()
