#!/usr/bin/env python3
#
# Copyright (C) 2019-2022 The Android Open Source Project
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

import concurrent.futures
import os
import re
import subprocess
import tempfile

from contextlib import nullcontext
from typing import List


def _collapse_abidiff_impacted_interfaces(text):
    """Removes impacted interfaces details, leaving just the summary count."""
    return re.sub(
        r"^( *)([^ ]* impacted interfaces?):\n(?:^\1 .*\n)*",
        r"\1\2\n",
        text,
        flags=re.MULTILINE)


def _collapse_abidiff_offset_changes(text):
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

    for line in text.splitlines(keepends=True):
        match = regex.search(line)
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


def _collapse_stgdiff_offset_changes(text: str) -> str:
    """Replaces "offset changed" lines with a one-line summary."""
    regex1 = re.compile(r"^( *)member ('.*') changed$")
    regex2 = re.compile(r"^( *)offset changed from (\d+) to (\d+)$")
    regex3 = re.compile(r"^( *)")
    items = []
    indent = ""
    offset = ""
    new_text = []

    def emit_pending() -> None:
        if not items:
            return
        count = len(items)
        if count == 1:
            only = items[0]
            lines = [
                "{}member {} changed\n".format(indent, only),
                "{}  offset changed by {}\n".format(indent, offset)
            ]
        else:
            first = items[0]
            last = items[-1]
            lines = [
                "{}{} members ({} .. {}) changed\n".format(indent, count, first, last),
                "{}  offsets changed by {}\n".format(indent, offset)
            ]
        del items[:]
        new_text.extend(lines)

    lines = text.splitlines(keepends=True)
    index = 0
    while index < len(lines):
        line = lines[index]
        # Match over 3 lines to detect indentation changes.
        if index + 2 < len(lines):
            match1 = regex1.search(line)
            match2 = regex2.search(lines[index + 1])
            match3 = regex3.search(lines[index + 2])
            if match1 and match2 and match3:
                indent1, item = match1.group(1, 2)
                indent2, before, after = match2.group(1, 2, 3)
                indent3 = match3.group(1)
                if len(indent1) + 2 == len(indent2) and len(indent1) >= len(indent3):
                    new_indent = indent1
                    new_offset = int(after) - int(before)
                    if new_indent != indent or new_offset != offset:
                        emit_pending()
                        indent = new_indent
                        offset = new_offset
                    items.append(item)
                    # Consume 2 lines.
                    index += 2
                    continue
        emit_pending()
        new_text.append(line)
        index += 1

    emit_pending()
    return "".join(new_text)


def _collapse_abidiff_CRC_changes(text, limit):
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

    lines = text.splitlines(keepends=True)
    index = 0
    while index < len(lines):
        line = lines[index]
        if section_regex.search(line):
            emit_pending()
        if (index + 2 < len(lines) and change_regex.search(line) and
            crc_regex.search(lines[index+1]) and blank_regex.search(lines[index+2])):
                pending.append((line, lines[index+1]))
                index += 3
                continue
        new_lines.append(line)
        index += 1

    emit_pending()
    return "".join(new_lines)


def _collapse_stgdiff_CRC_changes(text: str, limit: int) -> str:
    """Preserves some CRC-only changes and summarises the rest.

    A CRC-only change is one like the following (indented and with a trailing
    blank line).

    symbol 'ufshcd_bkops_ctrl' changed
        CRC changed from 0x34dac87f to 0xc7d9df6f

    Up to the first 'limit' changes will be emitted at the end of the section. Any
    remaining ones will be summarised with a line like the following.

    ... 17 omitted; 27 symbols have only CRC changes

    Args:
        text: The report text.
        limit: The maximum, integral number of CRC-only changes per diff section.

    Returns:
        Updated report text.
    """
    section_regex = re.compile(r"^[^ \n]")
    symbol_regex = re.compile(r"^symbol ")
    symbol_changed_regex = re.compile(r"^symbol '[^']*' changed$")
    crc_regex = re.compile(r"^  CRC changed from [^ ]* to [^ ]*$")
    blank_regex = re.compile(r"^$")
    pending = []
    new_lines = []

    def emit_pending() -> None:
        if not pending:
            return
        for (symbol_details, crc_details) in pending[0:limit]:
            new_lines.extend([symbol_details, crc_details, "\n"])
        count = len(pending)
        if count > limit:
            new_lines.append(
                "... {} omitted; {} symbols have only CRC changes\n\n".format(
                    count - limit, count))
        del pending[:]

    lines = text.splitlines(keepends=True)
    index = 0
    while index < len(lines):
        line = lines[index]
        if section_regex.search(line) and not symbol_regex.search(line):
            emit_pending()
        elif (symbol_changed_regex.search(line) and index + 2 < len(lines) and
              crc_regex.search(lines[index + 1]) and
              blank_regex.search(lines[index + 2])):
            pending.append((line, lines[index + 1]))
            index += 3
            continue
        new_lines.append(line)
        index += 1

    emit_pending()
    return "".join(new_lines)


def _remove_matching_lines(regexes: List[str], text: str) -> str:
    """Removes consecutive lines matching consecutive regexes."""
    if not regexes:
        return text
    num_regexes = len(regexes)
    lines = text.splitlines(keepends=True)
    num_lines = len(lines)
    new_lines = []
    index = 0
    while index < num_lines:
        match = True
        for offset in range(0, num_regexes):
            i = index + offset
            if i == num_lines or not re.search(regexes[offset], lines[i]):
                match = False
                break
        if match:
            index += num_regexes
        else:
            new_lines.append(lines[index])
            index += 1
    return "".join(new_lines)


def dump_kernel_abi(linux_tree, dump_path, symbol_list, vmlinux_path=None):
    with tempfile.NamedTemporaryFile() as temp_file:
        temp_path = temp_file.name

        dump_abi_cmd = [
            "abidw",
            # omit various sources of indeterministic abidw output
            "--no-corpus-path",
            "--no-comp-dir-path",
            # use (more) stable type ids
            "--type-id-style", "hash",
            # the path containing vmlinux and *.ko
            "--linux-tree", linux_tree,
            "--out-file", temp_path
        ]

        if vmlinux_path is not None:
            dump_abi_cmd.extend(["--vmlinux", vmlinux_path])

        if symbol_list is not None:
            dump_abi_cmd.extend(["--kmi-whitelist", symbol_list])

        subprocess.check_call(dump_abi_cmd)

        tidy_abi_command = ["abitidy",
                            "--all",
                            "--no-report-untyped",
                            "--input", temp_path,
                            "--output", dump_path]

        subprocess.check_call(tidy_abi_command)

class AbiTool(object):
    """Base class for different kinds of abi analysis tools"""
    def diff_abi(self, old_dump, new_dump, diff_report, short_report,
                 symbol_list, full_report):
        raise NotImplementedError()


ABIDIFF_ERROR                   = (1<<0)
ABIDIFF_USAGE_ERROR             = (1<<1)
ABIDIFF_ABI_CHANGE              = (1<<2)
ABIDIFF_ABI_INCOMPATIBLE_CHANGE = (1<<3)


def _run_abidiff(old_dump, new_dump, diff_report, symbol_list, full_report):
    diff_abi_cmd = ["abidiff", old_dump, new_dump]

    if not full_report:
        diff_abi_cmd.extend([
            "--leaf-changes-only",
            "--impacted-interfaces",
        ])

    if symbol_list is not None:
        diff_abi_cmd.extend(["--kmi-whitelist", symbol_list])

    abi_changed = False

    with open(diff_report, "w") as out:
        try:
            subprocess.check_call(diff_abi_cmd, stdout=out, stderr=out)
        except subprocess.CalledProcessError as e:
            if e.returncode & (ABIDIFF_ERROR | ABIDIFF_USAGE_ERROR):
                raise
            abi_changed = True  # actual abi change

    return abi_changed


def _shorten_abidiff(diff_report, short_report):
    with open(diff_report) as input:
        text = input.read()
        text = _collapse_abidiff_impacted_interfaces(text)
        text = _collapse_abidiff_offset_changes(text)
        text = _collapse_abidiff_CRC_changes(text, 3)
        with open(short_report, "w") as output:
            output.write(text)


STGDIFF_ERROR      = (1<<0)
STGDIFF_ABI_CHANGE = (1<<1)
STGDIFF_FORMATS    = ["plain", "flat", "small", "viz"]


def _run_stgdiff(old_dump, new_dump, basename, symbol_list=None):
    dumps = [old_dump, new_dump]

    # if a symbol list has been specified, we need some scratch space
    if symbol_list:
        context = tempfile.TemporaryDirectory()
    else:
        context = nullcontext()

    with context as temp:
        # if a symbol list has been specified, filter both input files
        if symbol_list:
            for ix in [0, 1]:
                raw = dumps[ix]
                cooked = os.path.join(temp, f"dump{ix}")
                subprocess.check_call(
                    ["abitidy", "-S", symbol_list, "-i", raw, "-o", cooked])
                dumps[ix] = cooked

        command = ["stgdiff", "--abi", dumps[0], dumps[1]]
        for f in STGDIFF_FORMATS:
            command.extend(["--format", f, "--output", f"{basename}.{f}"])

        abi_changed = False

        with open(f"{basename}.errors", "w") as out:
            try:
                subprocess.check_call(command, stdout=out, stderr=out)
            except subprocess.CalledProcessError as e:
                if e.returncode & STGDIFF_ERROR:
                    raise
                abi_changed = True

        return abi_changed


def _shorten_stgdiff(changed, diff_report, short_report):
    with open(diff_report) as input:
        text = input.read()
        # TODO(b/214966642): Remove once ABI XML type definitions are more stable.
        text = _remove_matching_lines([
            r"^type '.*' changed$",
            r"^  was (fully defined|only declared), is now (fully defined|only declared)$",
            r"^$",
        ], text)
        # TODO(b/221022839): Remove once ABI XML symbol definitions are more stable.
        text = _remove_matching_lines([
            r"^symbol changed from '.*' to '.*'$",
            r"^  type '.*' was (added|removed)$",
            r"^$",
        ], text)
        if not text:
            changed = False
        text = _collapse_stgdiff_offset_changes(text)
        text = _collapse_stgdiff_CRC_changes(text, 3)
        with open(short_report, "w") as output:
            output.write(text)
        return changed


class Libabigail(AbiTool):
    """Concrete AbiTool implementation for libabigail"""
    def diff_abi(self, old_dump, new_dump, diff_report, short_report,
                 symbol_list, full_report):
        abi_changed = _run_abidiff(
            old_dump, new_dump, diff_report, symbol_list, full_report)
        if short_report is not None:
            _shorten_abidiff(diff_report, short_report)
        return abi_changed


class Stg(AbiTool):
    """" Concrete AbiTool implementation for STG """
    def diff_abi(self, old_dump, new_dump, diff_report, short_report=None,
                 symbol_list=None, full_report=None):
        # shoehorn the interface
        basename = diff_report
        abi_changed = _run_stgdiff(old_dump, new_dump, basename, symbol_list)
        small_report = f"{basename}.small"
        abi_changed = _reinterpret_stgdiff(abi_changed, small_report)
        if short_report is not None:
            _shorten_stgdiff(small_report, short_report)
        return abi_changed


def _line_count(path):
    with open(path) as input:
        count = sum(1 for _ in input)
        return count


class Delegated(AbiTool):
    """" Concrete AbiTool implementation"""
    def diff_abi(self, old_dump, new_dump, diff_report, short_report=None,
                 symbol_list=None, full_report=None):
        # shoehorn the interface
        basename = diff_report
        abg_leaf = basename + ".leaf"
        abg_full = basename + ".full"
        stg_basename = basename + ".stg"
        stg_small = stg_basename + ".small"
        links = {
            basename: abg_leaf,
            basename + ".short": abg_leaf + ".short",
        }

        abidiff_leaf_changed = None
        abidiff_full_changed = None
        stgdiff_changed = None
        with concurrent.futures.ThreadPoolExecutor() as executor:
            # fork
            abidiff_leaf = executor.submit(
                _run_abidiff, old_dump, new_dump, abg_leaf, symbol_list, False)
            abidiff_full = executor.submit(
                _run_abidiff, old_dump, new_dump, abg_full, symbol_list, True)
            stgdiff = executor.submit(
                _run_stgdiff, old_dump, new_dump, stg_basename, symbol_list)
            # join
            abidiff_leaf_changed = abidiff_leaf.result()
            abidiff_full_changed = abidiff_full.result()
            stgdiff_changed = stgdiff.result()

        # post-process
        for report in [abg_leaf, abg_full]:
           _shorten_abidiff(report, report + ".short")
        stgdiff_changed = _shorten_stgdiff(stgdiff_changed, stg_small,
                                           stg_small + ".short")

        print("ABI diff reports have been created")
        paths = [abg_leaf, abg_full,
                 *(f"{stg_basename}.{format}" for format in STGDIFF_FORMATS),
                 *(f"{path}.short" for path in [abg_leaf, abg_full, stg_small])]
        for path in paths:
            count = _line_count(path)
            print(f" {path} [{count} lines]")
        for link, target in links.items():
            try:
                os.unlink(link)
            except FileNotFoundError:
                pass
            os.link(target, link)

        changed = []
        if abidiff_leaf_changed:
            changed.append(("abidiff (leaf changes)", abg_leaf))
        if stgdiff_changed:
            changed.append(("stgdiff", stg_small))
        if changed:
            print()
            print("ABI DIFFERENCES HAVE BEEN DETECTED!")
            for which, _ in changed:
                print(f" by {which}")
            print()
            with open(changed[0][1] + ".short") as input:
                print(input.read(), end="")
            return True
        return False


def get_abi_tool(abi_tool = "libabigail"):
    if abi_tool == "libabigail":
        return Libabigail()
    if abi_tool == "STG":
        return Stg()
    if abi_tool == "delegated":
        return Delegated()

    raise ValueError("not a valid abi_tool: %s" % abi_tool)
