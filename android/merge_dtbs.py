#! /usr/bin/env python3

# Copyright (c) 2020, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
#     * Neither the name of The Linux Foundation nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT
# ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import os
import sys
import subprocess
from shutil import copy

"""
This function uses fdtget to get the specified property from a compiled devicetree file.
"""
def fdt_get_prop(filename, node, prop, prop_type):
	returned_output = subprocess.check_output(["fdtget", "-t", prop_type, filename, node, prop])
	return returned_output.decode("utf-8").strip()

"""
This function goes through the specified folder and caches the compiled dt filename based on the
msm-id and board-id for use later.
"""
def parse_dt_files(dt_folder):
	dt_dictionary = dict()
	for root, dirs, files in os.walk(dt_folder):
		for filename in files:
			if os.path.splitext(filename)[1] not in ['.dtb', '.dtbo']:
				continue
			filepath = os.path.join(root, filename)
			msm_id = fdt_get_prop(filepath, '/', "qcom,msm-id", 'x')
			board_id = fdt_get_prop(filepath, '/', "qcom,board-id", 'x')
			key = "{},{}".format(msm_id, board_id)
			if key in dt_dictionary:
				dt_dictionary[key].append(filepath)
			else:
				dt_dictionary[key] = [filepath]

	return dt_dictionary

"""
This function uses the cached msm-id and board-id for each dt file to figure out the dts to merge
together. This is done using the pre-compiled ufdt_apply_overlay and fdtoverlaymerge for stitching
the dts.
"""
def merge_dts(base, techpack, output_folder):
	print("Merging dts:")
	for key in base:
		# each dt file in base dt folder will have a unique msm_id and board_id combo
		filename = os.path.basename(base[key][0])
		techpack_files = techpack.get(key, [])
		file_out = os.path.join(output_folder, filename)
		if len(techpack_files) == 0:
			copy(base[key][0], file_out)
			continue

		if filename.split(".")[-1] == "dtb":
			cmd = ["ufdt_apply_overlay"]
			cmd.extend(base[key])
			cmd.extend(techpack_files)
			cmd.append(file_out)
		else:
			cmd = ["fdtoverlaymerge", "-i"]
			cmd.extend(base[key])
			cmd.extend(techpack_files)
			cmd.extend(["-o", file_out])
		print(' '.join(cmd))
		# returns output as byte string
		returned_output = subprocess.check_output(cmd)
	unmatched = techpack.keys() - base.keys()
	if len(unmatched) > 0:
		print('WARNING! Unmatched techpack DTBs!')
		for key in unmatched:
			for file in techpack.get(key, []):
				print(file)

def main():
	if len(sys.argv) != 4:
		print("Usage: {} <base dtb folder> <techpack dtb folder> <output folder>"
		      .format(sys.argv[0]))
		sys.exit(1)

	base_dt_dict = parse_dt_files(sys.argv[1])
	techpack_dt_dict = parse_dt_files(sys.argv[2])
	merge_dts(base_dt_dict, techpack_dt_dict, sys.argv[3])

if __name__ == "__main__":
	main()
