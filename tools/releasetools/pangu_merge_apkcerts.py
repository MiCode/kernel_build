#!/usr/bin/env python3
import argparse
import logging
import os
import shutil

import common

logger = logging.getLogger(__name__)
common.OPTIONS.verbose = True


def validate_and_append_apkcerts(origin_apkcerts_file, addon_apkcerts_files, output_apkcerts_file):
    logger.info(
        f"validate_and_append_apkcerts: raw_apkcerts_file = {origin_apkcerts_file}, new_apkcerts_files = {addon_apkcerts_files}")
    if not addon_apkcerts_files:
        logger.info(f"validate_and_append_apkcerts: new_apkcerts_files is empty, skip")
        return
    raw_name_map = set()
    with open(origin_apkcerts_file, 'r') as file:
        contents = file.read()
        lines = contents.split('\n')
        start = 'name="'
        end = '" certificate='
        for line in lines:
            name = line[(line.find(start) + len(start)):line.rfind(end)]
            if name:
                raw_name_map.add(name)

    with open(addon_apkcerts_files, 'r') as file:
        contents = file.read()
        lines = contents.split('\n')
        start = 'name="'
        end = '" certificate='
        for line in lines:
            name = line[line.find(start) + len(start):line.rfind(end)]
            if name in raw_name_map:
                raise Exception(f"validate apkcerts.txt failed， duplicate name [{name}] {certs}")
            if name:
                raw_name_map.add(name)

    shutil.copyfile(origin_apkcerts_file, output_apkcerts_file)
    with open(output_apkcerts_file, 'a+') as outfile:
        with open (addon_apkcerts_files) as infile:
            contents = infile.read()
            logger.info(f"write addon apkcerts: {contents}")
            outfile.write(contents)


def cmd_merge_apkcerts(args):
    logger.info(f"merge-apkcerts args.addon-apkcerts = {args.addon_apkcerts}, args.origin-apkcerts = {args.origin_apkcerts}, args.output-apkcerts = {args.output_apkcerts}")
    addon_apkcerts = args.addon_apkcerts
    origin_apkcerts = args.origin_apkcerts
    output_apkcerts = args.output_apkcerts

    if addon_apkcerts and os.path.exists(addon_apkcerts):
        validate_and_append_apkcerts(origin_apkcerts, addon_apkcerts, output_apkcerts)
    else:
        shutil.copyfile(origin_apkcerts, output_apkcerts)


def main():
    common.InitLogging()

    parser = argparse.ArgumentParser(description='download product APKs、merge Apkcerts')

    parser.add_argument('--addon-apkcerts', nargs='?', type=str)
    parser.add_argument('--origin-apkcerts', nargs='?', type=str, required=True)
    parser.add_argument('--output-apkcerts', nargs='?', type=str, required=True)

    args = parser.parse_args()
    cmd_merge_apkcerts(args)


if __name__ == '__main__':
    main()