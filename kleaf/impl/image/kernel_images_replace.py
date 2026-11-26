# Copyright (C) 2024 The Android Open Source Project
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

"""Print deprecation message for kernel_images() rule."""

import argparse
import sys


def main(replace: list[tuple[str, str]], ban: list[str]):
    for line in sys.stdin:
        if line.startswith("#"):
            continue
        if any(banned_keyword in line for banned_keyword in ban):
            continue

        for replace_from, replace_to in replace:
            line = line.replace(replace_from, replace_to)

        print(line, end="")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replace", nargs=2, action="append")
    parser.add_argument("--ban", action="append")
    args = parser.parse_args()
    main(**vars(args))
