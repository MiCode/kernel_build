# Copyright (C) 2022 The Android Open Source Project
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

import argparse
import os
import sys
from typing import Tuple, Optional

_BAZEL_REL_PATH = "prebuilts/bazel/linux-x86_64/bazel"
_BAZEL_JDK_REL_PATH = "prebuilts/jdk/jdk11/linux-x86"
_BAZEL_RC_NAME = "build/kernel/kleaf/common.bazelrc"


def _partition(lst: list[str], index: Optional[int]) \
        -> Tuple[list[str], Optional[str], list[str]]:
    """Returns the triple split by index.

    That is, return a tuple:
    (everything before index, the element at index, everything after index)

    If index is None, return (the list, None, empty list)
    """
    if index is None:
        return lst[:], None, []
    return lst[:index], lst[index], lst[index + 1:]


class BazelWrapper(object):
    def __init__(self, root_dir: str, bazel_args: list[str], env):
        """Splits arguments to the bazel binary based on the functionality.

        bazel [startup_options] command         [command_args] --               [target_patterns]
                                 ^- command_idx                ^- dash_dash_idx

        See https://bazel.build/reference/command-line-reference

        Args:
            root_dir: root of repository
            bazel_args: The list of arguments the user provides through command line
            env: existing environment
        """

        self.root_dir = root_dir
        self.env = env.copy()

        self.bazel_path = f"{self.root_dir}/{_BAZEL_REL_PATH}"
        self.absolute_out_dir = f"{self.root_dir}/out"

        command_idx = None
        for idx, arg in enumerate(bazel_args):
            if not arg.startswith("-"):
                command_idx = idx
                break

        self.startup_options, self.command, remaining_args = _partition(bazel_args,
                                                                        command_idx)

        # Split command_args into `command_args -- target_patterns`
        dash_dash_idx = None
        try:
            dash_dash_idx = remaining_args.index("--")
        except ValueError:
            # If -- is not found, put everything in command_args. These arguments
            # are not provided to the Bazel executable target.
            pass

        self.command_args, self.dash_dash, self.target_patterns = _partition(remaining_args,
                                                                             dash_dash_idx)

        self._parse_command_args()

    def _parse_command_args(self):
        """Parses the given list of command_args.

        After calling this function, the following attributes are set:
        - known_args: A namespace holding options known by this Bazel wrapper script
        - transformed_command_args: The transformed list of command_args to replace
          existing command_args to be fed to the Bazel binary
        - env: A dictionary containing the new environment variables for the subprocess.
        """

        # Arguments known by this bazel wrapper.
        parser = argparse.ArgumentParser(add_help=False)
        parser.add_argument("--use_prebuilt_gki")
        parser.add_argument("--experimental_strip_sandbox_path",
                            action='store_true')
        parser.add_argument("--make_jobs", type=int, default=None)

        # known_args: List of arguments known by this bazel wrapper. These
        #   are stripped from the final bazel invocation.
        # remaining_command_args: the rest of the arguments
        # Skip startup options (before command) and target_patterns (after --)
        self.known_args, self.transformed_command_args = parser.parse_known_args(self.command_args)

        if self.known_args.use_prebuilt_gki:
            self.transformed_command_args.append("--//common:use_prebuilt_gki")
            self.env[
                "KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"] = f"gki_prebuilts={self.known_args.use_prebuilt_gki}"

        if self.known_args.make_jobs is not None:
            self.env["KLEAF_MAKE_JOBS"] = str(self.known_args.make_jobs)

    def _build_final_args(self) -> list[str]:
        """Builds the final arguments for the subprocess."""
        # final_args:
        # bazel [startup_options] [additional_startup_options] command [transformed_command_args] -- [target_patterns]

        bazel_jdk_path = f"{self.root_dir}/{_BAZEL_JDK_REL_PATH}"
        final_args = [self.bazel_path] + self.startup_options + [
            f"--server_javabase={bazel_jdk_path}",
            f"--output_user_root={self.absolute_out_dir}/bazel/output_user_root",
            f"--host_jvm_args=-Djava.io.tmpdir={self.absolute_out_dir}/bazel/javatmp",
            f"--bazelrc={self.root_dir}/{_BAZEL_RC_NAME}",
        ]
        if self.command is not None:
            final_args.append(self.command)
        final_args += self.transformed_command_args
        if self.dash_dash is not None:
            final_args.append(self.dash_dash)
        final_args += self.target_patterns

        return final_args

    def run(self):
        final_args = self._build_final_args()
        if self.known_args.experimental_strip_sandbox_path:
            import asyncio
            import re
            filter_regex = re.compile(self.absolute_out_dir + r"/\S+?/sandbox/.*?/__main__/")
            asyncio.run(run(final_args, self.env, filter_regex))
        else:
            os.execve(path=self.bazel_path, argv=final_args, env=self.env)


async def output_filter(input_stream, output_stream, filter_regex):
    import re
    while not input_stream.at_eof():
        output = await input_stream.readline()
        output = re.sub(filter_regex, "", output.decode())
        output_stream.buffer.write(output.encode())
        output_stream.flush()


async def run(command, env, filter_regex):
    import asyncio
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
    )

    await asyncio.gather(
        output_filter(process.stderr, sys.stderr, filter_regex),
        output_filter(process.stdout, sys.stdout, filter_regex),
    )
    await process.wait()


if __name__ == "__main__":
    BazelWrapper(root_dir=sys.argv[1], bazel_args=sys.argv[2:], env=os.environ).run()
