#!/usr/bin/env python
"""This script merges two partial target files packages.

Usage: pangu_merge_target_files [args]

  --first-target-files first-target-files-zip-archive
      The input target files package. This is a zip
      archive.

  --second-target-files second-target-files-zip-archive
      The input target files package. This is a zip
      archive.

  --output-target-files output-target-files-package
      If provided, the output merged target files package. Also a zip archive.

  --dexpreopt-config-1 dexpreopt-config-1-zip-archive
      The first input dexpreopt file. This is a zip
      archive.

  --dexpreopt-config-2 dexpreopt-config-2-zip-archive
      The first input dexpreopt file. This is a zip
      archive.

  --output-dexpreopt-config output-dexpreopt-config
      If provided, the output merged dexpreopt file. Also a zip archive.

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
OPTIONS.target_files_1 = None
OPTIONS.target_files_2 = None
OPTIONS.output_target_files = None

OPTIONS.dexpreopt_config_1 = None
OPTIONS.dexpreopt_config_2 = None
OPTIONS.output_dexpreopt_config = None

OPTIONS.keep_tmp = False

OPTIONS.framework_misc_info_keys = []
OPTIONS.allow_duplicate_apkapex_keys = True
OPTIONS.framework_partition_set = set(['system', 'product', 'system_ext', 'system_other', 'root', 'system_dlkm','vendor', 'odm', 'oem', 'boot', 'vendor_boot', 'recovery',
    'prebuilt_images', 'radio', 'data', 'vendor_dlkm', 'odm_dlkm'])
OPTIONS.vendor_partition_set = set(['system', 'product', 'system_ext', 'system_other', 'root', 'system_dlkm','vendor', 'odm', 'oem', 'boot', 'vendor_boot', 'recovery',
    'prebuilt_images', 'radio', 'data', 'vendor_dlkm', 'odm_dlkm'])

def PanguMergeMiscInfo(framework_meta_dir, vendor_meta_dir, merged_meta_dir):
  """Merges META/misc_info.txt.

  The output contains a combination of key=value pairs from both inputs.
  Most pairs are taken from the vendor input, while some are taken from
  the framework input.
  """

  OPTIONS.framework_misc_info = common.LoadDictionaryFromFile(
      os.path.join(framework_meta_dir, 'misc_info.txt'))
  OPTIONS.vendor_misc_info = common.LoadDictionaryFromFile(
      os.path.join(vendor_meta_dir, 'misc_info.txt'))

  # Merged misc info is a combination of vendor misc info plus certain values
  # from the framework misc info.

  merged_dict = OPTIONS.vendor_misc_info

  for key in OPTIONS.framework_misc_info:
      if key not in merged_dict:
        merged_dict[key] = OPTIONS.framework_misc_info[key]

  if 'no_boot' in merged_dict: del merged_dict['no_boot']
  if 'no_recovery' in merged_dict: del merged_dict['no_recovery']

  # for key in OPTIONS.framework_misc_info_keys:
  #   if key in OPTIONS.framework_misc_info:
  #     merged_dict[key] = OPTIONS.framework_misc_info[key]

  # If AVB is enabled then ensure that we build vbmeta.img.
  # Partial builds with AVB enabled may set PRODUCT_BUILD_VBMETA_IMAGE=false to
  # skip building an incomplete vbmeta.img.
  if merged_dict.get('avb_enable') == 'true':
    merged_dict['avb_building_vbmeta_image'] = 'true'

  return merged_dict

def PanguMergeMetaFiles(temp_dir, merged_dir):
  """Merges various files in META/*."""

  framework_meta_dir = os.path.join(temp_dir, '1', 'META')
  merge_utils.ExtractItems(
      input_zip=OPTIONS.target_files_1,
      output_dir=os.path.dirname(framework_meta_dir),
      extract_item_list=('META/*',))

  vendor_meta_dir = os.path.join(temp_dir, '2', 'META')
  merge_utils.ExtractItems(
      input_zip=OPTIONS.target_files_2,
      output_dir=os.path.dirname(vendor_meta_dir),
      extract_item_list=('META/*',))
  
  merged_meta_dir = os.path.join(merged_dir, 'META')

  # Merge META/misc_info.txt into OPTIONS.merged_misc_info,
  # but do not write it yet. The following functions may further
  # modify this dict.
  OPTIONS.merged_misc_info = PanguMergeMiscInfo(
      framework_meta_dir=framework_meta_dir,
      vendor_meta_dir=vendor_meta_dir,
      merged_meta_dir=merged_meta_dir)

  # CopyNamedFileContexts(
  #     framework_meta_dir=framework_meta_dir,
  #     vendor_meta_dir=vendor_meta_dir,
  #     merged_meta_dir=merged_meta_dir)

  if OPTIONS.merged_misc_info.get('use_dynamic_partitions') == 'true':
    merge_meta.MergeDynamicPartitionsInfo(
        framework_meta_dir=framework_meta_dir,
        vendor_meta_dir=vendor_meta_dir,
        merged_meta_dir=merged_meta_dir)

  if OPTIONS.merged_misc_info.get('ab_update') == 'true':
    merge_meta.MergeAbPartitions(
        framework_meta_dir=framework_meta_dir,
        vendor_meta_dir=vendor_meta_dir,
        merged_meta_dir=merged_meta_dir)
    # UpdateCareMapImageSizeProps(images_dir=os.path.join(merged_dir, 'IMAGES'))

  for file_name in ('apkcerts.txt', 'apexkeys.txt'):
     merge_meta.MergePackageKeys(
         framework_meta_dir=framework_meta_dir,
         vendor_meta_dir=vendor_meta_dir,
         merged_meta_dir=merged_meta_dir,
         file_name=file_name)

  # Write the now-finalized OPTIONS.merged_misc_info.
  merge_utils.WriteSortedData(
      data=OPTIONS.merged_misc_info,
      path=os.path.join(merged_meta_dir, 'misc_info.txt'))

  bcf_data1 = bcf_data2 = ""
  
  with open(framework_meta_dir + '/boot_filesystem_config.txt') as fp:
      bcf_data1 = fp.read()
    
  with open(vendor_meta_dir + '/boot_filesystem_config.txt') as fp:
      bcf_data2 = fp.read()

  bcf_data1 += bcf_data2
    
  with open (merged_meta_dir + '/boot_filesystem_config.txt', 'w') as fp:
      fp.write(bcf_data1)


def pangu_create_merged_package(temp_dir, file_1, file_2):
  """Merges two target files packages into one target files structure.

  Returns:
    Path to merged package under temp directory.
  """
  # Extract "as is" items from the input framework and vendor partial target
  # files packages directly into the output temporary directory, since these items
  # do not need special case processing.

  output_target_files_temp_dir = os.path.join(temp_dir, 'output')
  if not os.path.exists(output_target_files_temp_dir):
    os.makedirs(output_target_files_temp_dir)

  merge_utils.ExtractItems(
        input_zip=file_1,
        output_dir=output_target_files_temp_dir,
        extract_item_list=["merge_target-files_copy.list"])

  filelist = common.LoadListFromFile(output_target_files_temp_dir+"/merge_target-files_copy.list")

  merge_utils.ExtractItems(
        input_zip=file_1,
        output_dir=output_target_files_temp_dir,
        extract_item_list=filelist)

  merge_utils.ExtractItems(
        input_zip=file_2,
        output_dir=output_target_files_temp_dir,
        extract_item_list=["merge_target-files_copy.list"])

  filelist = common.LoadListFromFile(output_target_files_temp_dir+"/merge_target-files_copy.list")

  merge_utils.ExtractItems(
        input_zip=file_2,
        output_dir=output_target_files_temp_dir,
        extract_item_list=filelist)

  os.remove(output_target_files_temp_dir+"/merge_target-files_copy.list")

  PanguMergeMetaFiles(
      temp_dir=output_target_files_temp_dir, merged_dir=output_target_files_temp_dir)

  shutil.rmtree(output_target_files_temp_dir+"/1")
  shutil.rmtree(output_target_files_temp_dir+"/2")

  return output_target_files_temp_dir

def pangu_create_dexpreopt_config(temp_dir, file_1, file_2):
  """Merges two target files packages into one target files structure.

  Returns:
    Path to merged package under temp directory.
  """
  # Extract "as is" items from the input framework and vendor partial target
  # files packages directly into the output temporary directory, since these items
  # do not need special case processing.

  output_target_files_temp_dir = os.path.join(temp_dir, 'output')
  if not os.path.exists(output_target_files_temp_dir):
    os.makedirs(output_target_files_temp_dir)

  common.UnzipToDir(file_1, output_target_files_temp_dir)
  common.UnzipToDir(file_2, output_target_files_temp_dir)

  return output_target_files_temp_dir

def create_target_files_archive(output_zip, source_dir, temp_dir):
  """Creates a target_files zip archive from the input source dir.

  Args:
    output_zip: The name of the zip archive target files package.
    source_dir: The target directory contains package to be archived.
    temp_dir: Path to temporary directory for any intermediate files.
  """
  output_target_files_list = os.path.join(temp_dir, 'output.list')
  output_target_files_meta_dir = os.path.join(source_dir, 'META')

  def files_from_path(target_path, extra_args=None):
    """Gets files under the given path and return a sorted list."""
    find_command = ['find', target_path] + (extra_args or [])
    find_process = common.Run(
        find_command, stdout=subprocess.PIPE, verbose=False)
    return common.RunAndCheckOutput(['sort'],
                                    stdin=find_process.stdout,
                                    verbose=False)

  # META content appears first in the zip. This is done by the
  # standard build system for optimized extraction of those files,
  # so we do the same step for merged target_files.zips here too.
  meta_content = files_from_path(output_target_files_meta_dir)
  other_content = files_from_path(
      source_dir,
      ['-path', output_target_files_meta_dir, '-prune', '-o', '-print'])

  with open(output_target_files_list, 'w') as f:
    f.write(meta_content)
    f.write(other_content)

  command = [
      'soong_zip',
      '-d',
      '-o',
      os.path.abspath(output_zip),
      '-C',
      source_dir,
      '-r',
      output_target_files_list,
  ]

  logger.info('creating %s', output_zip)
  common.RunAndCheckOutput(command, verbose=True)
  logger.info('finished creating %s', output_zip)

def pangu_merge_target_files(temp_dir, file_1, file_2, output_file):
  """Merges two target files packages together.

  This function uses framework and vendor target files packages as input,
  performs various file extractions, special case processing, and finally
  creates a merged zip archive as output.

  Args:
    temp_dir: The name of a directory we use when we extract items from the
      input target files packages, and also a scratch directory that we use for
      temporary files.
  """

  logger.info('starting: merge target-file %s and target-file %s into output %s',
              file_1, file_2,
              output_file)

  output_target_files_temp_dir = pangu_create_merged_package(temp_dir,file_1, file_2)

  create_target_files_archive(output_file,
                              output_target_files_temp_dir, temp_dir)


def pangu_merge_dexpreopt_config(temp_dir, file_1, file_2, output_file):
  """Merges two target files packages together.

  This function uses framework and vendor target files packages as input,
  performs various file extractions, special case processing, and finally
  creates a merged zip archive as output.

  Args:
    temp_dir: The name of a directory we use when we extract items from the
      input target files packages, and also a scratch directory that we use for
      temporary files.
  """

  logger.info('starting: merge target-file %s and target-file %s into output %s',
              file_1, file_2,
              output_file)

  output_target_files_temp_dir = pangu_create_dexpreopt_config(temp_dir,file_1, file_2)

  create_target_files_archive(output_file,
                              output_target_files_temp_dir, temp_dir)

def main():
  """The main function.

  Process command line arguments, then call merge_target_files to
  perform the heavy lifting.
  """

  common.InitLogging()

  def option_handler(o, a):
    if o == '--first-target-files':
      OPTIONS.target_files_1 = a
    elif o == '--second-target-files':
      OPTIONS.target_files_2 = a
    elif o == '--output-target-files':
      OPTIONS.output_target_files = a

    elif o == '--dexpreopt-config-1':
      OPTIONS.dexpreopt_config_1 = a
    elif o == '--dexpreopt-config-2':
      OPTIONS.dexpreopt_config_2 = a
    elif o == '--output-dexpreopt-config':
      OPTIONS.output_dexpreopt_config = a

    elif o == '--keep-tmp':
      OPTIONS.keep_tmp = True
    else:
      return False
    return True

  args = common.ParseOptions(
      sys.argv[1:],
      __doc__,
      extra_long_opts=[
          'first-target-files=',
          'second-target-files=',
          'output-target-files=',
          'dexpreopt-config-1=',
          'dexpreopt-config-2=',
          'output-dexpreopt-config=',
          'keep-tmp',
      ],
      extra_option_handler=option_handler)

  if (OPTIONS.target_files_1 is not None and
      OPTIONS.target_files_2 is not None and
      OPTIONS.output_target_files is not None):
    logger.info('merging target files')
    temp_dir = common.MakeTempDir(prefix='pangu_merge_target_files_')
    try:
      pangu_merge_target_files(temp_dir, OPTIONS.target_files_1, OPTIONS.target_files_2, OPTIONS.output_target_files)
    finally:
      if OPTIONS.keep_tmp:
        logger.info('Keeping temp_dir %s', temp_dir)
      else:
        common.Cleanup()

  elif (OPTIONS.dexpreopt_config_1 is not None and
    OPTIONS.dexpreopt_config_2 is not None and
    OPTIONS.output_dexpreopt_config is not None):
      logger.info('merging dexpreopt_config')
      temp_dir = common.MakeTempDir(prefix='pangu_merge_dexpreopt_config_')
      try:
        pangu_merge_dexpreopt_config(temp_dir, OPTIONS.dexpreopt_config_1, OPTIONS.dexpreopt_config_2, OPTIONS.output_dexpreopt_config)
      finally:
        if OPTIONS.keep_tmp:
          logger.info('Keeping temp_dir %s', temp_dir)
        else:
          common.Cleanup()

  else:
      common.Usage(__doc__)
      sys.exit(1)

if __name__ == '__main__':
  main()
