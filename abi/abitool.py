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

import logging
import re
import subprocess
import tempfile

log = logging.getLogger(__name__)


def _collapse_impacted_interfaces(text):
  """Removes impacted interfaces details, leaving just the summary count."""
  return re.sub(
      r"^( *)([^ ]* impacted interfaces?):\n(?:^\1 .*\n)*",
      r"\1\2\n",
      text,
      flags=re.MULTILINE)


def _collapse_offset_changes(text):
  """Replaces "offset changed" lines with a one-line summary."""
  regex = re.compile(
      r"^( *)('.*') offset changed from .* to .* \(in bits\) (\(by .* bits\))$")
  items = []
  indent = ""
  offset = ""
  new_text = []

  def emit_pending():
    if not items:
      return
    count = len(items)
    if count == 1:
      only = items[0]
      line = "{}{} offset changed {}\n".format(indent, only, offset)
    else:
      first = items[0]
      last = items[-1]
      line = "{}{} ({} .. {}) offsets changed {}\n".format(
          indent, count, first, last, offset)
    del items[:]
    new_text.append(line)

  for line in text.splitlines(True):
    match = regex.match(line)
    if match:
      (new_indent, item, new_offset) = match.group(1, 2, 3)
      if new_indent != indent or new_offset != offset:
        emit_pending()
        indent = new_indent
        offset = new_offset
      items.append(item)
    else:
      emit_pending()
      new_text.append(line)

  emit_pending()
  return "".join(new_text)


# TODO(b/157510812#comment15): Drop when libabigail fixed.
def _eliminate_spurious_blank_lines(text):
    return re.sub(
        r"^\n(^    CRC.*changed from [^ ]* to [^ ]*$)",
        r"\1",
        text,
        flags=re.MULTILINE)


def _collapse_CRC_changes(text, limit):
    """Preserves some CRC-only changes and summarises the rest.

    A CRC-only change is one like the following (indented and with a
    trailing blank line).

    [C] 'function void* blah(type*)' at core.c:666:1 has some sub-type changes:
       CRC value (modversions) changed from 0xf0f8820e to 0xe817181d

    Up to the first 'limit' changes will be emitted at the end of the
    enclosing diff section. Any remaining ones will be summarised with
    a line like the following.

    ... 17 omitted; 27 symbols have only CRC changes

    Args:
      text: The report text.
      limit: The maximum, integral number of CRC-only changes per diff section.

    Returns:
      Updated report text.
    """
    section_regex = re.compile(r"^[^ \n]")
    change_regex = re.compile(r"^  \[C\] .*:$")
    crc_regex = re.compile(r"^    CRC.*changed from [^ ]* to [^ ]*$")
    blank_regex = re.compile(r"^$")
    pending = []
    new_lines = []

    def emit_pending():
        if not pending:
            return
        for (symbol_details, crc_details) in pending[0:limit]:
            new_lines.extend([symbol_details, crc_details, "\n"])
        count = len(pending)
        if count > limit:
            new_lines.append("  ... {} omitted; {} symbols have only CRC changes\n\n"
                             .format(count - limit, count))
        pending.clear()

    lines = text.splitlines(True)
    index = 0
    while index < len(lines):
        line = lines[index]
        if section_regex.match(line):
            emit_pending()
        if (index + 2 < len(lines) and change_regex.match(line) and
            crc_regex.match(lines[index+1]) and blank_regex.match(lines[index+2])):
                pending.append((line, lines[index+1]))
                index += 3
                continue
        new_lines.append(line)
        index += 1

    emit_pending()
    return "".join(new_lines)


class AbiTool(object):
    """ Base class for different kinds of abi analysis tools"""
    def dump_kernel_abi(self, linux_tree, dump_path, symbol_list,
                        vmlinux_path=None, tidy=False):
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
    def dump_kernel_abi(self, linux_tree, dump_path, symbol_list,
                        vmlinux_path=None, tidy=False):
        with tempfile.NamedTemporaryFile() as temp_file:
            temp_path = temp_file.name

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
                            temp_path]

            if vmlinux_path is not None:
                dump_abi_cmd.extend(['--vmlinux', vmlinux_path])

            if symbol_list is not None:
                dump_abi_cmd.extend(['--kmi-whitelist', symbol_list])

            subprocess.check_call(dump_abi_cmd)

            if tidy:
              process_abi_command = ['abitidy',
                                     '--all',
                                     '--no-report-untyped',
                                     '--input', temp_path,
                                     '--output', dump_path]
            else:
              process_abi_command = ['cp', '--', temp_path, dump_path]

            subprocess.check_call(process_abi_command)

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

        rc = 0

        with open(diff_report, 'w') as out:
            try:
                subprocess.check_call(diff_abi_cmd, stdout=out, stderr=out)
            except subprocess.CalledProcessError as e:
                if e.returncode & (ABIDIFF_ERROR | ABIDIFF_USAGE_ERROR):
                    raise
                rc = e.returncode  # actual abi change

        if short_report is not None:
            with open(diff_report) as full_report:
                with open(short_report, 'w') as out:
                    text = full_report.read()
                    text = _collapse_impacted_interfaces(text)
                    text = _collapse_offset_changes(text)
                    text = _eliminate_spurious_blank_lines(text)
                    text = _collapse_CRC_changes(text, 3)
                    out.write(text)

        return rc

def get_abi_tool(abi_tool = "libabigail"):
    if abi_tool == 'libabigail':
        log.info('using libabigail for abi analysis')
        return Libabigail()

    raise ValueError("not a valid abi_tool: %s" % abi_tool)
