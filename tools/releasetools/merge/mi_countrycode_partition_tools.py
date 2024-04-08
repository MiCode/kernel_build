#!/usr/bin/env python3

"""
This script generate countrycode.img

Usage: mi_build_countrycode_image [args]

  --countrycode-info-url countrycode_info_url
      The url for countrycode info

  --output-dir output_dir
      The output dir for countrycode.img

  --build-phrase
      build phrase:download or build

  --target-files-zip target-files-zip
      target_files_zip to generate

  --mi-addon-misc-info mi-addon-misc-info-file
      The file stored mi addon misc info.
"""
      
import common
import os
import logging
import sys
import argparse
import json
import merge_utils
import subprocess
import shutil
from urllib import request
from urllib import response
import zipfile

logger = logging.getLogger(__name__)
common.OPTIONS.verbose = True
OPTIONS = common.OPTIONS
MAX_BUILD_REGION_LEN = 31

def query_json_content(countrycode_info_url):
    try:
        logger.info("download countrycode_info_url from %s " % countrycode_info_url)
        response = request.urlopen(countrycode_info_url)
        json_content = response.read().decode('utf-8')
        return json_content
    except ValueError as arg:
        traceback.print_exc()
        raise Exception(f"An exception occurred while downloading countrycode_info_url from {countrycode_info_url}.")

def parse_components(content: str):
    json_data = json.loads(content)
    partitions = json_data['partitions']
    file_url = None

    for partition in partitions:
        partition_name = partition.get('name')
        if partition_name != 'countrycode':
            continue
        components = partition.get('components')
        if components is not None:
            for component_data in components:
                if component_data.get('type') != 'country_code_region_file':
                    logger.info("component data [{}] type is not country_code_region_file , skip".format(component_data))
                    continue
                if component_data.get('url') is not None:
                    file_url = component_data.get('url')

    return file_url

def prepare_for_download(countrycode_info_url):
    if countrycode_info_url is None or len(countrycode_info_url) == 0 or countrycode_info_url.upper() == 'NULL':
        logger.warning("countrycode_info_url is None, ignore download countrycode info from server.")
        return

    json_content = query_json_content(countrycode_info_url)
    if json_content is None or len(json_content) == 0 or json_content.upper() == 'NULL':
        logger.warning(f"json_content is none, while downloading json resources from {countrycode_info_url}.")
        return

    file_url = parse_components(json_content)
    return file_url

def generate_countrycode_image(output_dir, mi_addon_misc_info):
    mi_addon_misc_dict = common.LoadDictionaryFromFile(mi_addon_misc_info)
    countrycode_target_files_zip = mi_addon_misc_dict.get("countrycode_target_files_zip")
    if countrycode_target_files_zip is None or len(countrycode_target_files_zip) == 0 or countrycode_target_files_zip.upper() == 'NULL':
        logger.warning("The path of countrycode_target_files_zip is NONE")
        return

    temp_dir = common.MakeTempDir()
    merge_utils.ExtractItems(
        input_zip=countrycode_target_files_zip,
        output_dir=temp_dir,
        extract_item_list=('*',))

    misc_info = common.LoadDictionaryFromFile(os.path.join(output_dir, "META", "misc_info.txt"))
    countrycode_misc_info = common.LoadDictionaryFromFile(os.path.join(temp_dir, "countrycode_misc_info.txt"))
    misc_info.update(countrycode_misc_info)
    merge_utils.WriteSortedData(data=misc_info,path=os.path.join(output_dir, "META", "misc_info.txt"))

    if countrycode_misc_info.get("has_countrycode") == "true":
        countrycode_dest_path = os.path.join(output_dir, "PREBUILT_IMAGES", "countrycode.img")
    else:
        countrycode_dest_path = os.path.join(output_dir, "IMAGES", "countrycode.img")
    shutil.copyfile(os.path.join(temp_dir, "countrycode.img"), countrycode_dest_path)
    logger.info(f"generate_countrycode_image to {countrycode_dest_path}")

    #add to ab_partitions.txt for OTA
    #TODO: this may change by json config
    dest_ab_partitions_path = os.path.join(output_dir, 'META', 'ab_partitions.txt')
    with open(dest_ab_partitions_path) as f:
        base_ab_partitions = f.read().splitlines()
    if "countrycode" not in base_ab_partitions:
        base_ab_partitions.append("countrycode")
        merge_utils.WriteSortedData(
          data=set(base_ab_partitions),
          path=os.path.join(dest_ab_partitions_path))

def generate_countrycode_target_files_zip(target_files_zip, countrycode_info_url):
    if os.path.exists(target_files_zip):
        os.remove(target_files_zip)

    file_url = prepare_for_download(countrycode_info_url)
    if file_url is None or len(file_url) == 0 or file_url.upper() == 'NULL':
        logger.warning(f"file_url is none, while get countrycode's url from {countrycode_info_url}.")
        return
    temp_dir = common.MakeTempDir()
    target_file_out_dir = os.path.dirname(target_files_zip)
    if not os.path.exists(target_file_out_dir):
        os.makedirs(target_file_out_dir)

    response = request.urlopen(file_url)
    #TODO: will add more info like paretion size in file_url
    build_region = response.read().decode('utf-8').rstrip('\x00').rstrip('\n')

    if len(build_region) == 0:
        raise Exception(f"build_region is empty.")

    if len(build_region) > MAX_BUILD_REGION_LEN:
        raise Exception(f"build_region is too long: {build_region}.")

    countrycode_img_path = os.path.join(temp_dir, "countrycode.img")
    if os.path.exists(countrycode_img_path):
        os.remove(countrycode_img_path)
    with open(countrycode_img_path, "wb") as f:
        f.write(bytes(build_region,encoding="utf-8"))
        f.seek(MAX_BUILD_REGION_LEN, 0)
        f.write(b'\x00')

    countrycode_misc_info = {}
    countrycode_misc_info['has_countrycode'] = "true"
    countrycode_misc_info['countrycode_size'] = 0x100000
    countrycode_misc_info_path = os.path.join(temp_dir, "countrycode_misc_info.txt")
    merge_utils.WriteSortedData(data=countrycode_misc_info,path=countrycode_misc_info_path)

    output_zip = zipfile.ZipFile(target_files_zip, 'w', allowZip64=True)
    common.ZipWrite(output_zip, countrycode_img_path, arcname="countrycode.img")
    common.ZipWrite(output_zip, countrycode_misc_info_path, arcname="countrycode_misc_info.txt")
    common.ZipClose(output_zip)
    logger.info(f"generate_countrycode_target_files_zip successfully, build_region: {build_region}")

def main():
    common.InitLogging()

    def option_handler(o, a):
        if o == '--countrycode-info-url':
            OPTIONS.countrycode_info_url = a
        elif o == '--output-dir':
            OPTIONS.output_dir = a
        elif o == '--build-phrase':
            OPTIONS.build_phrase = a
        elif o == '--target-files-zip':
            OPTIONS.target_files_zip = a
        elif o == '--mi-addon-misc-info':
          OPTIONS.mi_addon_misc_info = a
        else:
          return False
        return True

    args = common.ParseOptions(
        sys.argv[1:],
        __doc__,
        extra_long_opts=[
            'countrycode-info-url=',
            'output-dir=',
            'build-phrase=',
            'target-files-zip=',
            'mi-addon-misc-info=',
        ],
        extra_option_handler=option_handler)

    if OPTIONS.build_phrase == 'download':
        generate_countrycode_target_files_zip(OPTIONS.target_files_zip, OPTIONS.countrycode_info_url)
    elif OPTIONS.build_phrase == 'build':
        generate_countrycode_image(OPTIONS.output_dir, OPTIONS.mi_addon_misc_info)

if __name__ == "__main__":
    main()
