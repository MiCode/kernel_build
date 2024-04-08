#!/usr/bin/env python
#
# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.
#
"""Generates dexopt files for vendor apps, from a merged target_files.

Expects items in OPTIONS prepared by merge_target_files.py.
"""

import glob
import json
import logging
import os
import shutil
import subprocess

import common
import merge_utils

logger = logging.getLogger(__name__)
OPTIONS = common.OPTIONS
PARTITIONS = ['product']
PARTITIONS_CONFIG_DIC = {}


def MergeDexopt(temp_dir, output_target_files_dir):
  """If needed, generates dexopt files for vendor apps.

  Args:
    temp_dir: Location containing an 'output' directory where target files have
      been extracted, e.g. <temp_dir>/output/SYSTEM, <temp_dir>/output/IMAGES,
      etc.
    output_target_files_dir: The name of a directory that will be used to create
      the output target files package after all the special cases are processed.
  """
  # Load vendor and framework META/misc_info.txt.
  #    if (OPTIONS.vendor_misc_info.get('building_with_vsdk') != 'true' or
  #      OPTIONS.framework_dexpreopt_tools is None or
  #      OPTIONS.framework_dexpreopt_config is None or
  #      OPTIONS.vendor_dexpreopt_config is None):
  if (OPTIONS.framework_dexpreopt_tools is None or
      OPTIONS.framework_dexpreopt_config is None or
      OPTIONS.vendor_dexpreopt_config is None):
    return  

  logger.info('applying dexpreopt')
  
  # The directory structure to apply dexpreopt is:
  #
  # <temp_dir>/
  #     framework_meta/
  #         META/
  #     vendor_meta/
  #         META/
  #     output/
  #         SYSTEM/
  #         VENDOR/
  #         IMAGES/
  #         <other items extracted from system and vendor target files>
  #     tools/
  #         <contents of dexpreopt_tools.zip>
  #     system_config/
  #         <contents of system dexpreopt_config.zip>
  #     vendor_config/
  #         <contents of vendor dexpreopt_config.zip>
  #     system -> output/SYSTEM
  #     vendor -> output/VENDOR
  #     apex -> output/SYSTEM/apex (only for flattened APEX builds)
  #     apex/ (extracted updatable APEX)
  #         <apex 1>/
  #             ...
  #         <apex 2>/
  #             ...
  #         ...
  #     out/dex2oat_result/vendor/
  #         <app>
  #             oat/arm64/
  #                 package.vdex
  #                 package.odex
  #         <priv-app>
  #             oat/arm64/
  #                 package.vdex
  #                 package.odex
  dexpreopt_tools_files_temp_dir = os.path.join(temp_dir, 'tools')
  dexpreopt_framework_config_files_temp_dir = os.path.join(
    temp_dir, 'system_config')
  dexpreopt_vendor_config_files_temp_dir = os.path.join(temp_dir,
                                                        'vendor_config')
  PARTITIONS_CONFIG_DIC['system_ext'] = dexpreopt_framework_config_files_temp_dir
  PARTITIONS_CONFIG_DIC['product'] = dexpreopt_framework_config_files_temp_dir
  PARTITIONS_CONFIG_DIC['vendor'] = dexpreopt_vendor_config_files_temp_dir
  PARTITIONS_CONFIG_DIC['odm'] = dexpreopt_vendor_config_files_temp_dir
  
  merge_utils.ExtractItems(
    input_zip=OPTIONS.framework_dexpreopt_tools,
    output_dir=dexpreopt_tools_files_temp_dir,
    extract_item_list=('*',))
  merge_utils.ExtractItems(
    input_zip=OPTIONS.framework_dexpreopt_config,
    output_dir=dexpreopt_framework_config_files_temp_dir,
    extract_item_list=('*',))
  merge_utils.ExtractItems(
      input_zip=OPTIONS.vendor_dexpreopt_config,
      output_dir=dexpreopt_vendor_config_files_temp_dir,
      extract_item_list=('*',))

  os.symlink(
      os.path.join(output_target_files_dir, 'SYSTEM'),
      os.path.join(temp_dir, 'system'))  
  os.symlink(
    os.path.join(output_target_files_dir, 'SYSTEM_EXT'),
    os.path.join(temp_dir, 'system_ext'))
  for partition in PARTITIONS:
    os.symlink(
      os.path.join(output_target_files_dir, str.upper(partition)),
      os.path.join(temp_dir, partition))
  
  # The directory structure for flatteded APEXes is:
  #
  # SYSTEM
  #     apex
  #         <APEX name, e.g., com.android.wifi>
  #             apex_manifest.pb
  #             apex_pubkey
  #             etc/
  #             javalib/
  #             lib/
  #             lib64/
  #             priv-app/
  #
  # The directory structure for updatable APEXes is:
  #
  # SYSTEM
  #     apex
  #         com.android.adbd.apex
  #         com.android.appsearch.apex
  #         com.android.art.apex
  #         ...
  apex_root = os.path.join(output_target_files_dir, 'SYSTEM', 'apex')
  
  # Check for flattended versus updatable APEX.
  if OPTIONS.framework_misc_info.get('target_flatten_apex') == 'false':
    # Extract APEX.
    logging.info('extracting APEX')
    
    apex_extract_root_dir = os.path.join(temp_dir, 'apex')
    os.makedirs(apex_extract_root_dir)
    
    for apex in (glob.glob(os.path.join(apex_root, '*.apex')) +
                 glob.glob(os.path.join(apex_root, '*.capex'))):
      logging.info('  apex: %s', apex)
      # deapexer is in the same directory as the merge_target_files binary extracted
      # from otatools.zip.
      apex_json_info = subprocess.check_output(['deapexer', 'info', apex])
      logging.info('    info: %s', apex_json_info)
      apex_info = json.loads(apex_json_info)
      apex_name = apex_info['name']
      logging.info('    name: %s', apex_name)
      
      apex_extract_dir = os.path.join(apex_extract_root_dir, apex_name)
      os.makedirs(apex_extract_dir)
      
      # deapexer uses debugfs_static, which is part of otatools.zip.
      command = [
        'deapexer',
        '--debugfs_path',
        'debugfs_static',
        'extract',
        apex,
        apex_extract_dir,
      ]
      logging.info('    running %s', command)
      subprocess.check_call(command)
  else:
    # Flattened APEXes don't need to be extracted since they have the necessary
    # directory structure.
    os.symlink(os.path.join(apex_root), os.path.join(temp_dir, 'apex'))
  
  # TODO(b/220167405): remove BootImageProfiles field until these files are included.
  dexpreopt_framework_config = os.path.join(dexpreopt_framework_config_files_temp_dir, 'dexpreopt.config')
  with open(dexpreopt_framework_config, 'r') as f:
    framework_config_data = json.load(f)
  framework_config_data["BootImageProfiles"] = []
  with open(dexpreopt_framework_config, 'w') as f:
    json.dump(framework_config_data, f)
  
  # Modify system config to point to the tools that have been extracted.
  # Absolute or .. paths are not allowed  by the dexpreopt_gen tool in
  # dexpreopt_soong.config.
  dexpreopt_framework_soon_config = os.path.join(
    dexpreopt_framework_config_files_temp_dir, 'dexpreopt_soong.config')
  with open(dexpreopt_framework_soon_config, 'w') as f:
    dexpreopt_soong_config = {
      'Profman': 'tools/profman',
      'Dex2oat': 'tools/dex2oatd',
      'Aapt': 'tools/aapt2',
      'SoongZip': 'tools/soong_zip',
      'Zip2zip': 'tools/zip2zip',
      'ManifestCheck': 'tools/manifest_check',
      'ConstructContext': 'tools/construct_context',
    }
    json.dump(dexpreopt_soong_config, f)
  
  for partition in PARTITIONS:
    dexpreopt(partition,
              temp_dir,
              output_target_files_dir,
              dexpreopt_framework_config_files_temp_dir,
              dexpreopt_tools_files_temp_dir)
  

def dexpreopt(partition,
              temp_dir,
              output_target_files_dir,
              dexpreopt_framework_config_files_temp_dir,
              dexpreopt_tools_files_temp_dir):
  # Open filesystem_config to append the items generated by dexopt.
  system_config_file = open(os.path.join(temp_dir, 'output', 'META', '%s_filesystem_config.txt' % partition), 'a')
  
  # Dexpreopt apps in location
  dexpreopt_config_suffix = '_dexpreopt.config'
  for config in glob.glob(
      os.path.join(PARTITIONS_CONFIG_DIC[partition],
                   '*' + dexpreopt_config_suffix)):
    app = os.path.basename(config)[:-len(dexpreopt_config_suffix)]
    logging.info('dexpreopt config: %s %s' % (config, app))
    
    apk_dir = 'app'
    apk_path = os.path.join(temp_dir, partition, apk_dir, app, app + '.apk')
    if not os.path.exists(apk_path):
      apk_dir = 'priv-app'
      apk_path = os.path.join(temp_dir, partition, apk_dir, app, app + '.apk')
      if not os.path.exists(apk_path):
        apk_dir = 'framework'
        apk_path = os.path.join(temp_dir, partition, apk_dir, app + '.jar')
        if not os.path.exists(apk_path):
          logging.warning('skipping dexpreopt for %s, no apk found in %s/app '
                          'or %s/priv-app, no jar found in %s/framework', app, partition, partition, partition)
          continue
    
    script_dir = os.path.join(temp_dir, "scripts")
    if not os.path.exists(script_dir):
      os.mkdir(script_dir)
    script_name = os.path.join(script_dir, app + 'dexpreopt_app.sh')
    command = [
      os.path.join(dexpreopt_tools_files_temp_dir, 'dexpreopt_gen'),
      '-global',
      os.path.join(dexpreopt_framework_config_files_temp_dir,
                   'dexpreopt.config'),
      '-global_soong',
      os.path.join(dexpreopt_framework_config_files_temp_dir,
                   'dexpreopt_soong.config'),
      '-module',
      config,
      '-dexpreopt_script',
      script_name,
      '-out_dir',
      'out',
      '-base_path',
      '.',
      '--uses_target_files',
    ]
    # Run the command from temp_dir so all tool paths are its descendants.
    logging.info('running %s', command)
    subprocess.check_call(command, cwd=temp_dir)
    
    # Call the generated script.
    command = ['sh', script_name, apk_path]
    logging.info('running %s', command)
    subprocess.check_call(command, cwd=temp_dir)

    # Output files are in:
    #
    # <temp_dir>/out/dex2oat_result/vendor/priv-app/<app>/oat/arm64/package.vdex
    # <temp_dir>/out/dex2oat_result/vendor/priv-app/<app>/oat/arm64/package.odex
    # <temp_dir>/out/dex2oat_result/vendor/app/<app>/oat/arm64/package.vdex
    # <temp_dir>/out/dex2oat_result/vendor/app/<app>/oat/arm64/package.odex
    #
    # Copy the files to their destination. The structure of system_other is:
    #
    # system_other/
    #     system-other-odex-marker
    #     system/
    #         app/
    #             <app>/oat/arm64/
    #                 <app>.odex
    #                 <app>.vdex
    #             ...
    #         priv-app/
    #             <app>/oat/arm64/
    #                 <app>.odex
    #                 <app>.vdex
    #             ...

    # TODO(b/188179859): Support for other architectures.
    dex_img = str.upper(partition)
    if apk_path.endswith(".apk"):
      arch = 'arm64'
      dex_destination = os.path.join(temp_dir, 'output', dex_img, apk_dir, app, 'oat', arch)
      if not os.path.exists(dex_destination):
        os.makedirs(dex_destination)
      
      dex2oat_path = os.path.join(temp_dir, 'out', 'dex2oat_result', partition, apk_dir, app, 'oat', arch)
      shutil.copy(
        os.path.join(dex2oat_path, 'package.vdex'),
        os.path.join(dex_destination, app + '.vdex'))
      shutil.copy(
        os.path.join(dex2oat_path, 'package.odex'),
        os.path.join(dex_destination, app + '.odex'))
      app_prefix = partition + '/' + apk_dir + '/' + app + '/oat'
      selabel = 'selabel=u:object_r:system_file:s0 capabilities=0x0'
      system_config_file.writelines([
        app_prefix + ' 0 2000 755 ' + selabel + '\n',
        app_prefix + '/' + arch + ' 0 2000 755 ' + selabel + '\n',
        app_prefix + '/' + arch + '/' + app + '.odex 0 0 644 ' +
        selabel + '\n',
        app_prefix + '/' + arch + '/' + app + '.vdex 0 0 644 ' +
        selabel + '\n',
      ])
    else:
      archs = ['arm64', 'arm']
      app_prefix = partition + '/' + apk_dir + '/oat'
      selabel = 'selabel=u:object_r:system_file:s0 capabilities=0x0'
      system_config_file.write(app_prefix + ' 0 2000 755 ' + selabel + '\n')
      for arch in archs:
        system_config_file.write(app_prefix + '/' + arch + ' 0 2000 755 ' + selabel + '\n')
        dex_destination = os.path.join(temp_dir, 'output', dex_img, apk_dir, 'oat', arch)
        if not os.path.exists(dex_destination):
          os.makedirs(dex_destination)
        
        dex2oat_path = os.path.join(temp_dir, 'out', 'dex2oat_result', partition, apk_dir, 'oat', arch)
        shutil.copy(
          os.path.join(dex2oat_path, 'javalib.vdex'),
          os.path.join(dex_destination, app + '.vdex'))
        shutil.copy(
          os.path.join(dex2oat_path, 'javalib.odex'),
          os.path.join(dex_destination, app + '.odex'))
        system_config_file.writelines([
          app_prefix + '/' + arch + '/' + app + '.odex 0 0 644 ' +
          selabel + '\n',
          app_prefix + '/' + arch + '/' + app + '.vdex 0 0 644 ' +
          selabel + '\n',
        ])
  
  system_config_file.close()
  # Delete vendor.img so that it will be regenerated.
  img = os.path.join(output_target_files_dir, 'IMAGES', partition + '.img')
  if os.path.exists(img):
    logging.info('Deleting %s', img)
    os.remove(img)
