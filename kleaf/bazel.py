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


def main(root_dir, bazel_args, env):
    env = env.copy()

    bazel_path = "{root_dir}/prebuilts/bazel/linux-x86_64/bazel".format(root_dir=root_dir)
    bazel_jdk_path = "{root_dir}/prebuilts/jdk/jdk11/linux-x86".format(root_dir=root_dir)
    bazelrc_name = "build/kernel/kleaf/common.bazelrc"

    absolute_out_dir = "{root_dir}/out".format(root_dir=root_dir)

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--use_prebuilt_gki")
    parser.add_argument("--experimental_strip_sandbox_path",
                        action='store_true')
    parser.add_argument("--make_jobs", type=int, default=None)
    known_args, bazel_args = parser.parse_known_args(bazel_args)
    if known_args.use_prebuilt_gki:
        # Insert before positional arguments
        try:
            idx = bazel_args.index("--")
        except ValueError:
            idx = len(bazel_args)
        bazel_args.insert(idx, "--//common:use_prebuilt_gki")
        env["KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"] = "gki_prebuilts=" + known_args.use_prebuilt_gki
    if known_args.make_jobs is not None:
        env["KLEAF_MAKE_JOBS"] = str(known_args.make_jobs)

    command_args = [
        bazel_path,
        "--server_javabase={}".format(bazel_jdk_path),
        "--output_user_root={}/bazel/output_user_root".format(absolute_out_dir),
        "--host_jvm_args=-Djava.io.tmpdir={}/bazel/javatmp".format(
            absolute_out_dir),
        "--bazelrc={root_dir}/{bazelrc_name}".format(
            root_dir=root_dir,
            bazelrc_name=bazelrc_name)
    ]
    command_args += bazel_args

    if known_args.experimental_strip_sandbox_path:
        import asyncio
        import re
        filter_regex=re.compile(absolute_out_dir+"/\S+?/sandbox/.*?/__main__/")
        asyncio.run(run(command_args, env, filter_regex))
    else:
        os.execve(path=bazel_path, argv=command_args, env=env)


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
    main(root_dir=sys.argv[1], bazel_args=sys.argv[2:], env=os.environ)
