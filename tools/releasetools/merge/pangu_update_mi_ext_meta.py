#!/usr/bin/env python
"""This script add MI_EXT partition info to meta files.

Usage: pange_update_meta [args]

  --meta-dir meta-directory
      The meta directory path.

  --template-dir template-directory
        The template directory path.

  --image-name image-name
        The image name.

  --image-size image-size
        The image size.

  --fs-type fs-type
        The file system type.

  --disable-sparse disable-sparse
        Disable generate sparse image.

  --enable_userdata_img_with_data
        create userdata.img with real data from the target files.

  --keep-tmp
      Keep tempoary files for debugging purposes.

"""
import logging
import logging.config
import os
import shutil
import subprocess
import sys
import merge_utils
import logging
import logging.config
import os
import shutil
import subprocess
import sys
import zipfile
import merge_meta
from hashlib import sha1, sha256
import common

logger = logging.getLogger(__name__)
OPTIONS = common.OPTIONS

# Always turn on verbose logging.
OPTIONS.verbose = True
OPTIONS.meta_dir = None
OPTIONS.template_dir = None
OPTIONS.image_name = "product"
OPTIONS.fs_type = "erofs"
OPTIONS.keep_tmp = False
OPTIONS.disable_sparse = False
OPTIONS.image_size = "4171481088"
OPTIONS.framework_misc_info_keys = []
OPTIONS.enable_userdata_img_with_data = False


image_info = """product_fs_type=erofs
product_selinux_fc=file_contexts.bin
building_product_image=true
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
erofs_default_compressor=lz4hc,9
ext4_share_dup_blocks=true
avb_avbtool=avbtool
block_list=mi_ext.map
root_dir=out/target/product/missi/root
use_dynamic_partition_size=true
skip_fsck=true"""

def mod_ab_partition(meta_dir):
    flag = os.path.exists(meta_dir+"/ab_partitions.txt")
    if flag:
        with open(meta_dir+"/ab_partitions.txt", "r+") as f:
            content = f.read()

            if "mi_ext" not in content:
                f.write("mi_ext")


def update_meta_files_for_userdata(meta_dir):
    misc_info = common.LoadDictionaryFromFile(
                  os.path.join(meta_dir, 'misc_info.txt'))
    if OPTIONS.enable_userdata_img_with_data is True:
        # misc_info['userdata_img_with_data'] = "true"
        misc_info['userdata_selinux_fc'] = "framework_file_contexts.bin"
    merge_utils.WriteSortedData(data=misc_info,path=os.path.join(meta_dir, 'misc_info.txt'))


def mod_misc_info(meta_dir):
    misc_info = common.LoadDictionaryFromFile(
                  os.path.join(meta_dir, 'misc_info.txt'))

    if misc_info.get('product_fs_type') is not None:
        OPTIONS.fs_type = misc_info['product_fs_type']
        logger.info('fs_type  = %s',OPTIONS.fs_type)
    else:
        logger.info('product_fs_type is none!')

    if OPTIONS.fs_type is None:
        OPTIONS.fs_type = "erofs"
        print("use default fs_type erofs")

    if misc_info.get('dynamic_partition_list') is not None:
        if "mi_ext" not in misc_info['dynamic_partition_list']:
            misc_info['dynamic_partition_list'] = misc_info['dynamic_partition_list'] + " mi_ext"

    super_partition_name=misc_info.get("super_partition_groups")
    if misc_info.get(f'super_{super_partition_name}_partition_list') is not None:
        if "mi_ext" not in misc_info[f'super_{super_partition_name}_partition_list']:
            misc_info[f'super_{super_partition_name}_partition_list'] = misc_info[f'super_{super_partition_name}_partition_list'] + " mi_ext"

    if misc_info.get('avb_product_add_hashtree_footer_args') is not None:
        if misc_info.get('avb_mi_ext_add_hashtree_footer_args') is None:
            mi_ext_args = misc_info['avb_product_add_hashtree_footer_args']
            mi_ext_args = mi_ext_args.replace(".product.",".mi_ext.")
            mi_ext_args = mi_ext_args.replace("miproduct","mi_ext")
            mi_ext_args+=" --partition_name mi_ext"
            misc_info['avb_mi_ext_add_hashtree_footer_args']=mi_ext_args
            misc_info['avb_mi_ext_hashtree_enable'] = "true"

    if OPTIONS.disable_sparse is True:
      misc_info['mi_ext_disable_sparse'] = "true"

    misc_info['mi_ext_fs_type'] = f"{OPTIONS.fs_type}"
    misc_info['mi_ext_selinux_fc'] = "framework_file_contexts.bin"
    misc_info['has_mi_ext'] = "true"

    misc_info['mi_ext_image_size'] = f"{OPTIONS.image_size}"

    merge_utils.WriteSortedData(data=misc_info,path=os.path.join(meta_dir, 'misc_info.txt'))

def mod_dynamic_partitions_info(meta_dir):
    misc_info = common.LoadDictionaryFromFile(
                  os.path.join(meta_dir, 'dynamic_partitions_info.txt'))

    if misc_info.get('dynamic_partition_list') is not None:
        if "mi_ext" not in misc_info['dynamic_partition_list']:
            misc_info['dynamic_partition_list'] = misc_info['dynamic_partition_list'] + " mi_ext"

    super_partition_name=misc_info.get("super_partition_groups")
    if misc_info.get(f'super_{super_partition_name}_partition_list') is not None:
        if "mi_ext" not in misc_info[f'super_{super_partition_name}_partition_list']:
            misc_info[f'super_{super_partition_name}_partition_list'] = misc_info[f'super_{super_partition_name}_partition_list'] + " mi_ext"

    merge_utils.WriteSortedData(data=misc_info,path=os.path.join(meta_dir, 'dynamic_partitions_info.txt'))

def pangu_update_meta_files(temp_dir, meta_dir):

    logger.info('starting: update meta dir %s',meta_dir)

    mod_ab_partition(meta_dir)
    mod_misc_info(meta_dir)
    mod_dynamic_partitions_info(meta_dir)

def pangu_update_template_files(temp_dir, template_dir, meta_dir):

    logger.info('starting: update template dir %s',template_dir)

    lines = image_info
    filepath = template_dir+ f"/{OPTIONS.image_name}.txt"
    with open(filepath, "w") as ff:
        for line in lines:
            ff.write(line)
    template_misc_info = common.LoadDictionaryFromFile(
                  os.path.join(template_dir, f"{OPTIONS.image_name}.txt"))
    template_misc_info[f'{OPTIONS.image_name}_fs_type'] = f"{OPTIONS.fs_type}"
    if OPTIONS.disable_sparse is False:
      template_misc_info['extfs_sparse_flag'] = "-s"
      template_misc_info['erofs_sparse_flag'] = "-s"
      template_misc_info['squashfs_sparse_flag'] = "-s"
      template_misc_info['f2fs_sparse_flag'] = "-S"

    merge_utils.WriteSortedData(data=template_misc_info,path=os.path.join(template_dir, f"{OPTIONS.image_name}.txt"))


def main():
  """The main function.
  Process command line arguments, then call merge_target_files to
  perform the heavy lifting.
  """

  common.InitLogging()

  def option_handler(o, a):
    if o == '--meta-dir':
      OPTIONS.meta_dir = a
    elif o == '--template-dir':
      OPTIONS.template_dir = a
    elif o == '--image-name':
      OPTIONS.image_name = a
    elif o == '--image-size':
      OPTIONS.image_size = a
    elif o == '--fs-type':
      OPTIONS.fs_type = a
    elif o == '--keep-tmp':
      OPTIONS.keep_tmp = True
    elif o == '--disable-sparse':
      OPTIONS.disable_sparse = True
    elif o == '--enable_userdata_img_with_data':
      print("enable userdata_img_with_data")
      OPTIONS.enable_userdata_img_with_data = True
    else:
      return False
    return True

  args = common.ParseOptions(
      sys.argv[1:],
      __doc__,
      extra_long_opts=[
          'meta-dir=',
          'template-dir=',
          'image-name=',
          'image-size=',
          'fs-type=',
          'disable-sparse',
          'enable_userdata_img_with_data',
          'keep-tmp',
      ],
      extra_option_handler=option_handler)

  if (OPTIONS.meta_dir is not None and OPTIONS.template_dir is not None and OPTIONS.image_name is not None and OPTIONS.image_size is not None):
    logger.info('updating meta files')
    temp_dir = common.MakeTempDir(prefix='pangu_meta_files_')
    try:
      pangu_update_meta_files(temp_dir, OPTIONS.meta_dir)
      pangu_update_template_files(temp_dir, OPTIONS.template_dir, OPTIONS.meta_dir)
    finally:
      if OPTIONS.keep_tmp:
        logger.info('Keeping temp_dir %s', temp_dir)
      else:
        common.Cleanup()
  elif (OPTIONS.meta_dir is not None and OPTIONS.enable_userdata_img_with_data is not None):
    logger.info('update userdata_img_with_data value.')
    try:
        update_meta_files_for_userdata(OPTIONS.meta_dir)
    finally:
        common.Cleanup()
  else:
      common.Usage(__doc__)
      sys.exit(1)

if __name__ == '__main__':
  main()

