import argparse
import logging
import os
import pathlib
import shutil
import ssl
import subprocess
import sys
import time
import traceback
import urllib.request
from concurrent.futures import ThreadPoolExecutor, wait
from datetime import timedelta

import common
import merge_compatibility_checks
import merge_utils

logger = logging.getLogger(__name__)
logging.basicConfig(format='%(asctime)s - %(filename)s - %(levelname)-8s %(threadName)-10s: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S', level=logging.INFO)

# Disable HTTPS SSL globally
try:
    _create_unverified_https_context = ssl._create_unverified_context
except AttributeError:
    # Legacy Python that doesn't verify HTTPS certificates by default
    pass
else:
    # Handle target environment that doesn't support HTTPS verification
    ssl._create_default_https_context = _create_unverified_https_context

OPTIONS = common.OPTIONS


def run_cmd(command, cwd=None, is_abort=True):
    logger.info(command)
    res = subprocess.Popen(command, shell=True, env=os.environ, cwd=cwd, executable='/bin/bash')
    out, err = res.communicate()
    if res.returncode != 0:
        logger.warning("command \"{}\" returned {}: {}".format(command, res.returncode, err))
        if is_abort:
            raise Exception("Execute command {} failed: output = {}, error = {}".format(command, out, err))


class Performance(object):

    def __init__(self) -> None:
        super().__init__()
        self.get_target_files_start = 0
        self.get_target_files_end = 0
        self.check_compatibility_start = 0
        self.check_compatibility_end = 0

    def show(self):
        logger.info("************************ pangu_compatibility_checks cost ****************************")
        logger.info(
            "total cost {}".format(timedelta(seconds=int(self.check_compatibility_end - self.get_target_files_start))))
        logger.info(
            "get target fiels cost {}".format(
                timedelta(seconds=int(self.get_target_files_end - self.get_target_files_start))))
        logger.info(
            "check compatibility cost {}".format(
                timedelta(seconds=int(self.check_compatibility_end - self.check_compatibility_start))))


def check_compatibility_wrapper(base_target_files, soc_name, mtk_release_tools):
    if not base_target_files or not os.path.exists(base_target_files):
        logger.warning("Could not check compatibility: invalid base target files {}".format(base_target_files))
        return

    if soc_name == "qcom":
        framework_item_list = os.path.join(base_target_files, "SYSTEM", "merge_config_system_item_list")
        vendor_item_list = os.path.join(base_target_files, "SYSTEM", "merge_config_other_item_list")
        if not os.path.exists(framework_item_list) or not os.path.exists(vendor_item_list):
            raise Exception("Failed to check compatibility: both merge_config_system_item_list {} and "
                            "merge_config_other_item_list {} must be exist".format(framework_item_list,
                                                                                   vendor_item_list))

        OPTIONS.framework_partition_set = merge_utils.ItemListToPartitionSet(
            common.LoadListFromFile(framework_item_list))
        OPTIONS.vendor_partition_set = merge_utils.ItemListToPartitionSet(common.LoadListFromFile(vendor_item_list))
    elif soc_name == "mtk":
        if not mtk_release_tools:
            raise Exception("Failed to check compatibility: mtk_release_tools can not be None")

        system_item_list = os.path.join(mtk_release_tools, "system_item_list.txt")
        other_item_list = os.path.join(mtk_release_tools, "other_item_list.txt")
        if not os.path.exists(system_item_list) or not os.path.exists(other_item_list):
            raise Exception("Failed to check compatibility: both system_item_list {} and "
                            "other_item_list {} must be exist".format(system_item_list, other_item_list))

        OPTIONS.framework_partition_set = merge_utils.ItemListToPartitionSet(common.LoadListFromFile(system_item_list))
        OPTIONS.vendor_partition_set = merge_utils.ItemListToPartitionSet(common.LoadListFromFile(other_item_list))
    else:
        raise Exception("unknown cpu model value {}".format(soc_name))

    partition_map = common.PartitionMapFromTargetFiles(base_target_files)
    compatibility_errors = merge_compatibility_checks.CheckCompatibility(
        target_files_dir=base_target_files,
        partition_map=partition_map)
    if compatibility_errors:
        logger.error("incompatibilities Found in the merged target files package: ")
        for error in compatibility_errors:
            logger.error(error)
        return False
    else:
        logger.info("No incompatibilities Found in the merged target files package.")
        return True


def replace_partition_dir(base_dir, origin_dir_name, new_dir):
    origin = os.path.join(base_dir, origin_dir_name)
    bak_dir = os.path.join(base_dir, origin_dir_name + "_ORIGIN")
    os.rename(origin, bak_dir)
    os.symlink(new_dir, origin)


def sizeof_fmt(num, suffix="B"):
    for unit in ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"]:
        if abs(num) < 1024.0:
            return "{num:3.1f}{unit}{suffix}".format(num=num, unit=unit, suffix=suffix)
        num /= 1024.0
    return "{num:.1f}Yi{suffix}".format(num=num, suffix=suffix)


def download(address, name):
    start = time.time()
    site = urllib.request.urlopen(address)
    logger.info("remote file size is {}".format(sizeof_fmt(int(site.info().get('content-length')))))
    path, header = urllib.request.urlretrieve(address, name)
    logger.info("download {} cost {}s".format(name, timedelta(seconds=int(time.time() - start))))
    return path


def download_and_extract_files(url, zip_file_name, tmp_dir, unzip_pattern=None):
    logger.info("start to download {} into local {} from {}".format(zip_file_name, tmp_dir, url))
    zip_files_path = os.path.join(tmp_dir, zip_file_name + ".zip")
    download(url, zip_files_path)
    logger.info("start to unzip file {}".format(zip_files_path))
    start_unzip_time = time.time()
    common.UnzipToDir(zip_files_path, os.path.join(tmp_dir, zip_file_name), unzip_pattern)
    logger.info("unzip file {} cost {}s".format(zip_files_path, timedelta(seconds=int(time.time() - start_unzip_time))))
    return os.path.join(tmp_dir, zip_file_name)


def get_target_files(output_dir, image_names, base_target_files, system_target_files,
                     product_target_files,
                     odm_target_files):
    is_check_system = "system" in image_names
    is_check_system_ext = "system_ext" in image_names
    is_check_product = "product" in image_names

    if not system_target_files and (is_check_system or is_check_system_ext):
        raise Exception("system-target-file must be specified if image name contain system or system_ext")

    if not product_target_files and is_check_product:
        raise Exception("product-target-file must be specified if image name contain product")

    if not os.path.exists(output_dir):
        raise Exception("Failed to get target files: output directory {} not exist".format(output_dir))
    tmp_dir = os.path.join(output_dir, "tmp")
    if os.path.exists(tmp_dir):
        logger.warning("tmp directory {} exist, clean it first.".format(tmp_dir))
        shutil.rmtree(tmp_dir)
    pathlib.Path(tmp_dir).mkdir(exist_ok=False)

    futures = []
    with ThreadPoolExecutor(max_workers=5) as executor:
        base_target_file_pattern = ["BOOT/*", "META/*", "OTA/*", "PRODUCT/*", "RECOVERY/*", "SYSTEM/*", "SYSTEM_DLKM/*",
                                    "VENDOR/*",
                                    "VENDOR_DLKM/*", "DATA/*", "INIT_BOOT/*", "ODM/*", "PREBUILT_IMAGES/*", "RADIO/*",
                                    "ROOT/*", "SYSTEM_EXT/*", "VENDOR_BOOT/*"]
        futures.append(executor.submit(download_and_extract_files, base_target_files, "base_target_files",
                                       tmp_dir, base_target_file_pattern))

        if is_check_system or is_check_system_ext:
            system_extract_pattern = []
            if is_check_system:
                system_extract_pattern.append("SYSTEM/*")
            if is_check_system_ext:
                system_extract_pattern.append("SYSTEM_EXT/*")
            futures.append(executor.submit(download_and_extract_files, system_target_files, "system_target_files",
                                           tmp_dir, system_extract_pattern))
        if is_check_product:
            futures.append(executor.submit(download_and_extract_files, product_target_files, "product_target_files",
                                           tmp_dir, ["PRODUCT/*"]))

    base_target_files = os.path.join(tmp_dir, "base_target_files")

    logger.info("futures = " + str(futures))
    has_exception_in_thread = False
    for i, future in enumerate(futures):
        try:
            future.result()
        except Exception as e:
            traceback.print_exc()
            has_exception_in_thread = True
            logger.error("Thread num{} occurs exception {}".format(i, e))

    if has_exception_in_thread:
        raise Exception("Can not continue because some exception throw by the threads, please check above error log.")
    wait(futures)
    if is_check_system:
        replace_partition_dir(base_target_files, "SYSTEM",
                              os.path.join(tmp_dir, "system_target_files", "SYSTEM"))
    if is_check_system_ext:
        replace_partition_dir(base_target_files, "SYSTEM_EXT",
                              os.path.join(tmp_dir, "system_target_files", "SYSTEM_EXT"))

    if is_check_product:
        replace_partition_dir(base_target_files, "PRODUCT",
                              os.path.join(tmp_dir, "product_target_files", "PRODUCT"))

    return base_target_files


def _main():
    parser = argparse.ArgumentParser(description='check compatibility between single images and full target file.')
    parser.add_argument('--base-target-files', required=True)
    parser.add_argument('--image-names', nargs='*', required=True, choices=['system', 'system_ext', 'product'])
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--soc-name', required=True, choices=['qcom', 'mtk'])
    parser.add_argument('--system-target-files')
    parser.add_argument('--product-target-files')
    parser.add_argument('--odm-target-files')
    parser.add_argument('--vendor-target-files')
    parser.add_argument('--mtk-releasetools')

    args = parser.parse_args()

    performance = Performance()

    performance.get_target_files_start = time.time()
    base_target_files = get_target_files(args.output_dir, args.image_names,
                                         args.base_target_files,
                                         args.system_target_files,
                                         args.product_target_files,
                                         args.odm_target_files)
    performance.get_target_files_end = time.time()

    performance.check_compatibility_start = time.time()
    if not check_compatibility_wrapper(base_target_files, args.soc_name, args.mtk_releasetools):
        sys.exit(1)
    performance.check_compatibility_end = time.time()
    performance.show()


if __name__ == '__main__':
    _main()
