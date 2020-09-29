#!/usr/bin/env python3
#
# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import re
import subprocess
import logging

log = logging.getLogger(__name__)

class AbiTool(object):
    """ Base class for different kinds of abi analysis tools"""
    def dump_kernel_abi(self, linux_tree, dump_path, symbol_list):
        raise NotImplementedError()

    def diff_abi(self, old_dump, new_dump, diff_report, short_report, symbol_list):
        raise NotImplementedError()

    def name(self):
        raise NotImplementedError()

ABIDIFF_ERROR                   = (1<<0)
ABIDIFF_USAGE_ERROR             = (1<<1)
ABIDIFF_ABI_CHANGE              = (1<<2)
ABIDIFF_ABI_INCOMPATIBLE_CHANGE = (1<<3)

class Libabigail(AbiTool):
    """" Concrete AbiTool implementation for libabigail """
    def dump_kernel_abi(self, linux_tree, dump_path, symbol_list):
        dump_abi_cmd = ['abidw',
                        # omit various sources of indeterministic abidw output
                        '--no-corpus-path',
                        '--no-comp-dir-path',
                        # use (more) stable type ids
                        '--type-id-style',
                        'hash',
                        # the path containing vmlinux and *.ko
                        '--linux-tree',
                        linux_tree,
                        '--out-file',
                        dump_path]

        if symbol_list is not None:
            dump_abi_cmd.extend(['--kmi-whitelist', symbol_list])

        subprocess.check_call(dump_abi_cmd)

    def diff_abi(self, old_dump, new_dump, diff_report, short_report,
                 symbol_list, full_report):
        log.info('libabigail diffing: {} and {} at {}'.format(old_dump,
                                                                new_dump,
                                                                diff_report))
        diff_abi_cmd = ['abidiff',
                        '--flag-indirect',
                        old_dump,
                        new_dump]

        if not full_report:
            diff_abi_cmd.extend([
                '--leaf-changes-only',
                '--impacted-interfaces',
            ])

        if symbol_list is not None:
            diff_abi_cmd.extend(['--kmi-whitelist', symbol_list])

        abi_changed = False

        with open(diff_report, 'w') as out:
            try:
                subprocess.check_call(diff_abi_cmd, stdout=out, stderr=out)
            except subprocess.CalledProcessError as e:
                if e.returncode & (ABIDIFF_ERROR | ABIDIFF_USAGE_ERROR):
                    raise
                abi_changed = True  # actual abi change

        if short_report is not None:
            with open(diff_report) as full_report:
                with open(short_report, 'w') as out:
                    out.write(re.sub(
                        r"^( *)([^ ]* impacted interfaces?):\n(?:^\1 .*\n)*",
                        r"\1\2\n",
                        full_report.read(),
                        flags=re.MULTILINE))

        return abi_changed

def get_abi_tool(abi_tool = "libabigail"):
    if abi_tool == 'libabigail':
        log.info('using libabigail for abi analysis')
        return Libabigail()

    raise ValueError("not a valid abi_tool: %s" % abi_tool)
