#!/usr/bin/env python
"""This script used to download and generate MI_EXT partition.

Usage: mi_ext_partition_tools [args]

  --target-files-zip target-files-zip
      target_files_zip to generate.

  ----mi-addon-misc-info mi-addon-misc-info-file
        The file stored mi addon misc info.

  --build-phrase
        build phrase:download or build

  --output-dir
        directory to indicate where script runs.

  --device-name name-of-sku
      the name of sku. e.g. cupid_pre

  --pkg-url url
      the url to download target files. Can be empty.

  --sign-keys-dir key-path
      the directory of keys used to sign apk. If not set 'android_app' will not be signed

"""
import logging
import logging.config
import os
import shutil
import subprocess
import sys
import shutil
import common
import zipfile

logger = logging.getLogger(__name__)
OPTIONS = common.OPTIONS

# Always turn on verbose logging.
OPTIONS.verbose = True
OPTIONS.target_files_zip = None
OPTIONS.mi_addon_misc_info = None
OPTIONS.output_dir = None
OPTIONS.build_phrase = None
OPTIONS.device_name = None
OPTIONS.sign_key_dir = None
OPTIONS.sku_files_url = None
OPTIONS.enable_userroot_prune = False
OPTIONS.userroot_prune_zip = None
OPTIONS.userroot_prune_url = None

def run_cmd(command, is_abort=False):
    logger.info(command)
    res = subprocess.Popen(command, shell=True, env=os.environ)
    out, err = res.communicate()
    if res.returncode != 0:
        logger.warning("command \"{}\" returned {}: {}".format(command, res.returncode, err))
        if is_abort:
            raise Exception(f"Execute command {command} failed: output = {out}, error = {err}")

def unzip_file_to(entry, extract_path):
  f = zipfile.ZipFile(OPTIONS.userroot_prune_zip)
  if entry in f.namelist():
    if not os.path.exists(extract_path):
      os.makedirs(extract_path)
    run_cmd(f'unzip -j -q -o {OPTIONS.userroot_prune_zip} {entry} -d {extract_path}')
  f.close()

def generate_mi_ext_target_files_zip(output_dir, device_name, sign_key_dir, sku_files_url, target_files_zip):
    target_file_out_dir = os.path.dirname(target_files_zip)
    if not os.path.exists(target_file_out_dir):
        run_cmd(f"mkdir -p {target_file_out_dir}")
    run_cmd(f"mkdir -p {output_dir}/template/MI_EXT")
    arguments = ""
    if (sku_files_url is not None) and sku_files_url != 'None' and sku_files_url.upper() != 'NULL':
        arguments = arguments + f" --target-url '{sku_files_url}'"
    run_cmd(f"pangu_download_sku_files {arguments} --device-name {device_name} --target-dir {output_dir}/template/MI_EXT --sign-keys-dir {sign_key_dir}", True)

    # userroot addon begin
    if OPTIONS.enable_userroot_prune:
      if OPTIONS.userroot_prune_url:
        run_cmd(f"pangu_download_sku_files --target-url {OPTIONS.userroot_prune_url} --device-name {device_name} --target-dir {output_dir}/template/MI_EXT --sign-keys-dir {sign_key_dir}", True)
      if OPTIONS.userroot_prune_zip and zipfile.is_zipfile(OPTIONS.userroot_prune_zip):
        unzip_file_to('META/userdebug_plat_sepolicy.cil', f'{output_dir}/template/MI_EXT/root')
        unzip_file_to('META/remount', f'{output_dir}/template/MI_EXT/root/bin')
    # userroot addon end
    run_cmd(f"cd {output_dir}/template && zip -r {target_files_zip} ./MI_EXT && cd -")

#return output_dir + "/mi_ext_target_files.zip"

def generate_mi_ext_image(output_dir, mi_addon_misc_info):
    # parse info from
    mi_addon_misc_dict = common.LoadDictionaryFromFile(mi_addon_misc_info)
    mi_ext_target_files_zip = mi_addon_misc_dict.get("mi_ext_target_files_zip")
    mi_ext_parent_dir = os.path.join(output_dir, "template")
    if not os.path.exists(mi_ext_parent_dir):
        os.makedirs(mi_ext_parent_dir)
    run_cmd(f"unzip {mi_ext_target_files_zip} -d {mi_ext_parent_dir}")
    run_cmd(f"pangu_update_mi_ext_meta --meta-dir {output_dir}/META --template-dir {output_dir}/template --image-name product  --image-size 1048576 --disable-sparse", True)
    run_cmd(f"cp {output_dir}/META/framework_file_contexts.bin {output_dir}/template/file_contexts.bin")
    run_cmd(f"cd {output_dir}/template && build_image ./MI_EXT ./product.txt ./product.img ./MI_EXT && touch ./mi_ext.map && sed -i --expression 's@^/product@/mi_ext@g' mi_ext.map && cd -", True)
    run_cmd(f"cp {output_dir}/template/product.img {output_dir}/PREBUILT_IMAGES/mi_ext.img")
    run_cmd(f"cp {output_dir}/template/mi_ext.map {output_dir}/PREBUILT_IMAGES/mi_ext.map")
    run_cmd(f"rm -r {output_dir}/template")


def main():
  """The main function.
  Process command line arguments, then call merge_target_files to
  perform the heavy lifting.
  """

  common.InitLogging()
  def option_handler(o, a):
    if o == '--target-files-zip':
      OPTIONS.target_files_zip = a
    elif o == '--mi-addon-misc-info':
      OPTIONS.mi_addon_misc_info = a
    elif o == '--build-phrase':
      OPTIONS.build_phrase = a
    elif o == '--output-dir':
      OPTIONS.output_dir = a
    elif o == '--device-name':
      OPTIONS.device_name = a
    elif o == '--sign-keys-dir':
      OPTIONS.sign_key_dir = a
    elif o == '--pkg-url':
      OPTIONS.sku_files_url = a
    elif o == '--enable-userroot-prune':
      OPTIONS.enable_userroot_prune = a
    elif o == '--debug-plat-sepolicy-cil-zip':
      OPTIONS.userroot_prune_zip = a
    elif o == '--userroot-prune-url':
      OPTIONS.userroot_prune_url = a
    else:
      return False
    return True

  args = common.ParseOptions(
      sys.argv[1:],
      __doc__,
      extra_long_opts=[
          'target-files-zip=',
          'mi-addon-misc-info=',
          'build-phrase=',
          'output-dir=',
          'device-name=',
          'sign-keys-dir=',
          'pkg-url=',
          'enable-userroot-prune=',
          'debug-plat-sepolicy-cil-zip=',
          'userroot-prune-url=',
      ],
      extra_option_handler=option_handler)

  if OPTIONS.build_phrase == 'download':
    generate_mi_ext_target_files_zip(OPTIONS.output_dir, OPTIONS.device_name, OPTIONS.sign_key_dir, OPTIONS.sku_files_url, OPTIONS.target_files_zip)
  elif OPTIONS.build_phrase == 'build':
    generate_mi_ext_image(OPTIONS.output_dir, OPTIONS.mi_addon_misc_info)

if __name__ == '__main__':
  main()

