# Copyright (C) 2023 The Android Open Source Project
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

"""Runs necessary checkpatch targets for a build on ci.android.com.

usage:

tools/bazel run //build/kernel/static_analysis:checkpatch_presubmit -- \\
    --dist_dir <DIST_DIR> \\
    [<other flags to checkpatch>] \\
"""

import argparse
import logging
import os
import pathlib
import shlex
import subprocess
import sys
from typing import Any

_LOG_LEVEL = logging.INFO
# _LOG_LEVEL = logging.DEBUG

_BAZEL = pathlib.Path("tools/bazel")
_SILENT_ARGS = [
    "--ui_event_filters=-info",
    "--noshow_progress",
]


def load_arguments() -> dict[str, Any]:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument(
        "--dist_dir",
        type=_resolve_against_workspace_root,
        required=True,
        help="DIST_DIR. If relative, resolve against workspace root.",
    )
    return parser.parse_known_args()


def _resolve_against_workspace_root(value: str) -> pathlib.Path:
    path = pathlib.Path(value)
    if path.is_absolute():
        return path
    return pathlib.Path(os.environ["BUILD_WORKSPACE_DIRECTORY"]) / path


def _log_command(args):
    quoted = [shlex.quote(str(arg)) for arg in args]
    logging.debug("Running command line: %s", " ".join(quoted))


def _find_checkpatch_targets(path: pathlib.Path) -> list[str]:
    args = [_BAZEL, "query"]
    args += _SILENT_ARGS
    args.append(f'kind("^checkpatch rule$", //{path}:all)')
    _log_command(args)
    lines = subprocess.check_output(
        args,
        text=True,
        cwd=_resolve_against_workspace_root("."),
    ).splitlines()
    return [line.strip() for line in lines if line.strip()]


def _run_checkpatch(
    target: str,
    dist_dir: pathlib.Path,
    checkpatch_args: list[str],
) -> int:
    args = [_BAZEL, "run", "--show_result=0"]
    args += _SILENT_ARGS
    args += [target, "--"]
    args += checkpatch_args
    args += ["--dist_dir", dist_dir]
    _log_command(args)
    return subprocess.run(
        args,
        text=True,
        cwd=_resolve_against_workspace_root("."),
    ).returncode


def main(
        checkpatch_args: list[str],
        dist_dir: pathlib.Path,
) -> int:
    applied_prop = dist_dir / "applied.prop"
    paths: list[pathlib.Path] = []
    with open(applied_prop) as applied_prop_file:
        for line in applied_prop_file:
            line = line.strip()
            if not line:
                continue
            path, _ = line.split(maxsplit=2)
            paths.append(pathlib.Path(path))

    targets: list[str] = []
    for path in paths:
        path_targets = _find_checkpatch_targets(path)
        if not path_targets:
            logging.info(
                "Skipping %s because no checkpatch() target is found.", path)
            continue
        targets += path_targets

    return_codes = []
    for target in targets:
        return_codes.append(_run_checkpatch(
            target=target,
            dist_dir=dist_dir,
            checkpatch_args=checkpatch_args,
        ))

    success = sum(return_codes) == 0
    return 0 if success else 1


if __name__ == "__main__":
    logging.basicConfig(level=_LOG_LEVEL,
                        format="%(levelname)s: %(message)s")
    known, checkpatch_args = load_arguments()
    sys.exit(main(checkpatch_args=checkpatch_args, **vars(known)))
