#!/usr/bin/env python
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024, Qualcomm Innovation Center, Inc. All rights reserved.

import sys

config_file_path = sys.argv[1]
kbuild_file_path = sys.argv[2]
config_dict = {}

# Read the config file and form a dict
with open(config_file_path, 'r') as file:
    for line in file:
        line = line.strip()
        if 'is not set' in line:
            key = line.split()[1]
            config_dict[key] = "n"
        elif '=' in line:
            key, value = line.split('=', 1)
            config_dict[str(key)] = str(value.strip('"'))

# Read the device-tree Kbuild file
with open(kbuild_file_path, 'r') as file:
    kbuild_code = file.read()

# Replace placeholders with values from the config dictionary
for key, value in config_dict.items():
    placeholder = "$({})".format(key)
    kbuild_code = kbuild_code.replace(placeholder, str(value))

# Output the modified Kbuild into Kbuild_modified
output_file_path = 'Kbuild'
with open(output_file_path, 'w') as file:
    file.write(kbuild_code)

