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
import pathlib
import shlex
import shutil
import sys
import textwrap
from typing import Tuple, Optional

from kleaf_help import KleafHelpPrinter, FLAGS_BAZEL_RC

_BAZEL_REL_PATH = "prebuilts/kernel-build-tools/bazel/linux-x86_64/bazel"

# Sync with the following files:
#   kleaf/impl/kernel_build.bzl
_QUERY_TARGETS_ARG = 'kind("kernel_build rule", //... except attr("tags", \
    "manual", //...) except //.source_date_epoch_dir/... except //out/...)'

# Sync with the following files:
#   kleaf/impl/abi/abi_update.bzl
#   kleaf/impl/abi/kernel_abi.bzl
_QUERY_ABI_TARGETS_ARG = 'kind("(update_source_file|abi_update) rule", //... except attr("tags", \
    "manual", //...) except //.source_date_epoch_dir/... except //out/...)'

_REPO_BOUNDARY_FILES = ("MODULE.bazel", "REPO.bazel", "WORKSPACE.bazel", "WORKSPACE")

def _require_absolute_path(p: str | pathlib.Path) -> pathlib.Path:
    p = pathlib.Path(p)
    if not p.is_absolute():
        raise argparse.ArgumentTypeError("need to specify an absolute path")
    return p


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


class BazelWrapper(KleafHelpPrinter):
    def __init__(self, kleaf_repo_dir: pathlib.Path, bazel_args: list[str], env):
        """Splits arguments to the bazel binary based on the functionality.

        bazel [startup_options] command         [command_args] --               [target_patterns]
                                 ^- command_idx                ^- dash_dash_idx

        See https://bazel.build/reference/command-line-reference

        Args:
            kleaf_repo_dir: root of Kleaf repository.
            bazel_args: The list of arguments the user provides through command line
            env: existing environment
        """

        # Path to repository that contains Kleaf tooling.
        self.kleaf_repo_dir = kleaf_repo_dir
        self.env = env.copy()

        self.bazel_path = self.kleaf_repo_dir / _BAZEL_REL_PATH

        self.workspace_dir = self._get_workspace_dir()

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

        self._parse_startup_options()
        self._parse_command_args()
        self._rebuild_kleaf_help_args()

    @classmethod
    def _get_workspace_dir(cls):
        """Returns Root of the top level workspace (named "@")

        where WORKSPACE is located. This is not necessarily equal to
        kleaf_repo_dir, especially when Kleaf tooling is in a submodule.
        """

        # See Bazel's implementation at:
        # https://github.com/bazelbuild/bazel/blob/master/src/main/cpp/workspace_layout.cc

        possible_workspace = pathlib.Path.cwd()
        while possible_workspace.parent != possible_workspace: # is not root directory
            if cls._is_workspace(possible_workspace):
                return possible_workspace
            possible_workspace = possible_workspace.parent

        sys.stderr.write(textwrap.dedent("""\
            ERROR: Unable to determine root of repository. See
                https://bazel.build/external/overview#repository
            """))
        sys.exit(1)

    @staticmethod
    def _is_workspace(possible_workspace: pathlib.Path):
        for boundary_file in _REPO_BOUNDARY_FILES:
            if (possible_workspace / boundary_file).is_file():
                return True
        return False


    def add_startup_option_to_parser(self, parser):
        group = parser.add_argument_group(
            title="Startup options - Wrapper flags",
            description="Startup options known by the Kleaf Bazel wrapper.",)
        group.add_argument(
            "--output_root",
            metavar="PATH",
            type=_require_absolute_path,
            default=_require_absolute_path(self.workspace_dir / "out"),
            help="Absolute path to output directory",
        )
        group.add_argument(
            "--output_user_root",
            metavar="PATH",
            type=_require_absolute_path,
            help="Passthrough flag to bazel if specified",
        )
        group.add_argument(
            "-h", "--help", action="store_true",
            help="show this help message and exit"
        )

    def _parse_startup_options(self):
        """Parses the given list of startup_options.

        After calling this function, the following attributes are set:
        - absolute_user_root: A path holding bazel build output location
        - transformed_startup_options: The transformed list of startup_options to replace
          existing startup_options to be fed to the Bazel binary
        """

        parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
        self.add_startup_option_to_parser(parser)

        self.known_startup_options, user_startup_options = parser.parse_known_args(
            self.startup_options)

        self.absolute_out_dir = self.known_startup_options.output_root
        self.absolute_user_root = self.known_startup_options.output_user_root or \
            self.absolute_out_dir / "bazel/output_user_root"

        if self.known_startup_options.help:
            self.transformed_startup_options = [
                "--help"
            ]

        if not self.known_startup_options.help:
            javatmp = self.absolute_out_dir / "bazel/javatmp"
            self.transformed_startup_options = [
                f"--host_jvm_args=-Djava.io.tmpdir={javatmp}",
            ]

        self.transformed_startup_options += user_startup_options

        if not self.known_startup_options.help:
            self.transformed_startup_options.append(
                f"--output_user_root={self.absolute_user_root}")

    def add_command_args_to_parser(self, parser):
        absolute_cache_dir = self.absolute_out_dir / "cache"
        group = parser.add_argument_group(
            title="Args - Bazel wrapper flags",
            description="Args known by the Kleaf Bazel wrapper.")

        # Arguments known by this bazel wrapper.
        group.add_argument(
            "--use_prebuilt_gki",
            metavar="BUILD_NUMBER",
            help="Use prebuilt GKI downloaded from ci.android.com or a custom download location.")
        group.add_argument(
            "--experimental_strip_sandbox_path",
            action="store_true",
            help=textwrap.dedent("""\
                Deprecated; use --strip_execroot.
                Strip sandbox path from output.
                """))
        group.add_argument(
            "--strip_execroot", action="store_true",
            help="Strip execroot from output.")
        group.add_argument(
            "--make_jobs", metavar="JOBS", type=int, default=None,
            help="--jobs to Kbuild")
        group.add_argument(
            "--make_keep_going", action="store_true", default=False,
            help="Add --keep_going to Kbuild")
        group.add_argument(
            "--cache_dir", metavar="PATH",
            type=_require_absolute_path,
            default=absolute_cache_dir,
            help="Cache directory for --config=local.")
        group.add_argument(
            "--repo_manifest", metavar="<manifest.xml>",
            help="""Absolute path to repo manifest file, generated with """
                 """`repo manifest -r`.""",
            type=_require_absolute_path,
        )
        group.add_argument(
            "--ignore_missing_projects",
            action='store_true',
            help="""ignore projects defined in the repo manifest, but """
                 """missing from the workspace""",
        )
        group.add_argument(
            "--kleaf_localversion",
            help=textwrap.dedent("""\
                Default is true.
                Use Kleaf's logic to determine localversion, not
                scripts/setlocalversion. This removes the unstable patch number
                from scmversion.
                """),
            action="store_true",
            default=True,
        )
        group.add_argument(
            "--nokleaf_localversion",
            dest="kleaf_localversion",
            action="store_false",
            help="Equivalent to --kleaf_localversion=false",
        )
        group.add_argument(
            "--user_clang_toolchain",
            metavar="PATH",
            help="Absolute path to a custom clang toolchain",
            type=_require_absolute_path,
        )

    def _parse_command_args(self):
        """Parses the given list of command_args.

        After calling this function, the following attributes are set:
        - known_args: A namespace holding options known by this Bazel wrapper script
        - transformed_command_args: The transformed list of command_args to replace
          existing command_args to be fed to the Bazel binary
        - env: A dictionary containing the new environment variables for the subprocess.
        """

        parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
        self.add_command_args_to_parser(parser)

        # known_args: List of arguments known by this bazel wrapper. These
        #   are stripped from the final bazel invocation.
        # remaining_command_args: the rest of the arguments
        # Skip startup options (before command) and target_patterns (after --)
        self.known_args, self.transformed_command_args = parser.parse_known_args(
            self.command_args)

        if self.known_args.experimental_strip_sandbox_path:
            sys.stderr.write(
                "WARNING: --experimental_strip_sandbox_path is deprecated; use "
                "--strip_execroot.\n"
            )
            self.known_args.strip_execroot = True

        if self.known_args.strip_execroot:
            # Force enable color now that we are piping the stderr / stdout.
            # Caveat: This prints ANSI color codes to a redirected stream if
            # the other one is a terminal and --strip_execroot is set. Bazel
            # can't forcifully enable color in only one stream.
            if sys.stdout.isatty() or sys.stderr.isatty():
                self.transformed_command_args.append("--color=yes")

        if self.known_args.use_prebuilt_gki:
            self.transformed_command_args.append("--use_prebuilt_gki")
            self.transformed_command_args.append("--config=internet")
            self.env[
                "KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"] = f"gki_prebuilts={self.known_args.use_prebuilt_gki}"

        if self.known_args.make_jobs is not None:
            self.env["KLEAF_MAKE_JOBS"] = str(self.known_args.make_jobs)

        self.env["KLEAF_MAKE_KEEP_GOING"] = "true" if self.known_args.make_keep_going else "false"

        if self.known_args.repo_manifest is not None:
            self.env["KLEAF_REPO_MANIFEST"] = self.known_args.repo_manifest

        if self.known_args.ignore_missing_projects:
            self.env["KLEAF_IGNORE_MISSING_PROJECTS"] = "true"

        if self.known_args.kleaf_localversion:
            self.env["KLEAF_USE_KLEAF_LOCALVERSION"] = "true"

        if self.known_args.user_clang_toolchain is not None:
            self.env["KLEAF_USER_CLANG_TOOLCHAIN_PATH"] = self.known_args.user_clang_toolchain

        self._handle_bazelrc()

    def _handle_bazelrc(self):
        """Rewrite bazelrc files."""
        self.gen_bazelrc_dir = self.absolute_out_dir / "bazel/bazelrc"
        os.makedirs(self.gen_bazelrc_dir, exist_ok=True)

        self.transformed_startup_options += self._transform_bazelrc_files([
            # Add support for various configs
            # Do not sort, the order here might matter.
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/ants.bazelrc",
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/android_ci.bazelrc",
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/local.bazelrc",
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/fast.bazelrc",
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/rbe.bazelrc",
        ])

        self.transformed_startup_options += self._transform_bazelrc_files([
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/stamp.bazelrc",
        ])
        stamp_extra_bazelrc = self.gen_bazelrc_dir / "stamp_extra.bazelrc"
        with open(stamp_extra_bazelrc, "w") as f:
            workspace_status_common_sh = self._kleaf_repo_rel() / \
                "build/kernel/kleaf/workspace_status_common.sh"
            workspace_status_sh = self._kleaf_repo_rel() / \
                "build/kernel/kleaf/workspace_status.sh"
            f.write(textwrap.dedent(f"""\
                # By default, do not embed scmversion.
                build --workspace_status_command={shlex.quote(str(workspace_status_common_sh))}
                # With --config=stamp, embed scmversion.
                build:stamp --workspace_status_command={shlex.quote(str(workspace_status_sh))}
            """))
        self.transformed_startup_options += self._transform_bazelrc_files([
            stamp_extra_bazelrc,
        ])

        self.transformed_startup_options += self._transform_bazelrc_files([
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/release.bazelrc",
            self.kleaf_repo_dir / FLAGS_BAZEL_RC,
        ])

        cache_dir_bazelrc = self.gen_bazelrc_dir / "cache_dir.bazelrc"
        with open(cache_dir_bazelrc, "w") as f:
            # The label //build/... will be re-written by _transform_bazelrc_files.
            f.write(textwrap.dedent(f"""\
                build --//build/kernel/kleaf:cache_dir={shlex.quote(str(self.known_args.cache_dir))}
            """))

        if not self.known_startup_options.help:
            self.transformed_startup_options += self._transform_bazelrc_files([
                cache_dir_bazelrc,
            ])

        self.transformed_startup_options += self._transform_bazelrc_files([
            # Toolchains and platforms
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/hermetic_cc.bazelrc",
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/platforms.bazelrc",
            # Control Network access - with no internet by default.
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/network.bazelrc",
            # Experimental bzlmod support
            self.kleaf_repo_dir / "build/kernel/kleaf/bazelrc/bzlmod.bazelrc",

            self.kleaf_repo_dir / "build/kernel/kleaf/common.bazelrc",
        ])

    def _build_final_args(self) -> list[str]:
        """Builds the final arguments for the subprocess."""
        # final_args:
        # bazel [startup_options] [additional_startup_options] command [transformed_command_args] -- [target_patterns]

        final_args = [self.bazel_path] + self.transformed_startup_options

        if self.command is not None:
            final_args.append(self.command)
        final_args += self.transformed_command_args
        if self.dash_dash is not None:
            final_args.append(self.dash_dash)
        final_args += self.target_patterns

        if self.command == "clean":
            sys.stderr.write(
                f"INFO: Removing cache directory for $OUT_DIR: {self.known_args.cache_dir}\n")
            shutil.rmtree(self.known_args.cache_dir, ignore_errors=True)
        else:
            os.makedirs(self.known_args.cache_dir, exist_ok=True)

        return final_args

    def _transform_bazelrc_files(self, bazelrc_files: list[pathlib.Path]) -> list[str]:
        """Given a list of bazelrc files, return startup options."""
        startup_options = []
        for old_path in bazelrc_files:
            new_path = self._rewrite_bazelrc_file(old_path)
            startup_options.append(f"--bazelrc={new_path}")
        return startup_options

    def _rewrite_bazelrc_file(self, old_path: pathlib.Path) -> pathlib.Path:
        """Given a bazelrc file, rewrite and return the path."""
        if self._kleaf_repository_is_top_workspace():
            # common case; Kleaf tooling is in main Bazel workspace
            return old_path
        with open(old_path) as old_file:
            content = old_file.read()

        # Rewrite //build to @<kleaf_repo_name>//build
        content = content.replace(
            "//build", f"{self._kleaf_repo_name()}//build")

        new_path = self.gen_bazelrc_dir / old_path.name
        os.makedirs(new_path.parent, exist_ok=True)
        with open(new_path, "w") as new_file:
            new_file.write(content)
        return new_path

    def _kleaf_repository_is_top_workspace(self):
        """Returns true if the Kleaf repository is the top-level workspace @."""
        return self.workspace_dir == self.kleaf_repo_dir

    def _kleaf_repo_name(self):
        """Returns the name to the Kleaf repository."""
        if self._kleaf_repository_is_top_workspace():
            return "@"
        # The main repository must refer to the Kleaf repository as @kleaf.
        # TODO(b/276493276): Once we completely migrate to bzlmod, labels
        # in bazelrc may be referred to as @kleaf//, then _rewrite_bazelrc_file
        # may be deleted.
        return f"@kleaf"

    def _kleaf_repo_rel(self):
        """Return root of the Kleaf repository relative to the top-level workspace.

        If the root of the Kleaf repository is not relative to the top-level workspace,
        return the absolute path as-is.
        """
        kleaf_repo_rel = self.kleaf_repo_dir
        if kleaf_repo_rel.is_relative_to(self.workspace_dir):
            kleaf_repo_rel = kleaf_repo_rel.relative_to(self.workspace_dir)
        return kleaf_repo_rel

    def _print_help(self):
        print("===============================")

        show_kleaf_help_menu = self.command == "help" and self.transformed_command_args and \
            self.transformed_command_args[0] == "kleaf"

        if show_kleaf_help_menu:
            print("Kleaf help menu:")
            self.print_kleaf_help(self.kleaf_repo_dir)
        else:
            print("Kleaf help menu:")
            print("  $ bazel help kleaf")

        print()
        print("===============================")

        if show_kleaf_help_menu:
            print("Native bazel help menu:")
            print("  $ bazel help")
            sys.exit(0)
        else:
            print("Native bazel help menu:")

    # Handle queries of kernel_build and kernel_abi_update targets.
    def _rebuild_kleaf_help_args(self):
        show_kleaf_targets = self.command == "help" and self.transformed_command_args and \
            self.transformed_command_args[0] == "kleaf" and \
            len(self.transformed_command_args) > 1 and \
            (self.transformed_command_args[1] in [
             "targets", "abi-targets", "abi_targets"])

        if not show_kleaf_targets:
            return

        # Transform the command to a query
        self.command = "query"
        _kleaf_help_command = self.transformed_command_args[1]
        # Inform about the ignored arguments if any.
        _ignored_args = self.transformed_command_args[2:]
        if _ignored_args:
            print("INFO: Ignoring arguments:", _ignored_args)
        # Suppress errors from malformed packages. e.g. clang packages with
        #   Soong dependencies, //external packages, etc.
        self.transformed_command_args = [
            "--keep_going",
            "--ui_event_filters=-error",
            "--noshow_progress"
        ]
        if _kleaf_help_command == "targets":
            print("Kleaf available targets:")
            self.transformed_command_args.append(_QUERY_TARGETS_ARG)
        else:
            print("Kleaf ABI update available targets:")
            self.transformed_command_args.append(_QUERY_ABI_TARGETS_ARG)

    def run(self):
        final_args = self._build_final_args()

        if self.known_startup_options.help or self.command == "help":
            self._print_help()

        # Whether to run bazel comamnd as subprocess
        run_as_subprocess = False
        # Regex to filter output / stderr lines
        filter_regex = None
        # Epilog coroutine after bazel command finishes
        epilog_coro = None

        if self.known_args.strip_execroot:
            run_as_subprocess = True
            if self.absolute_user_root.is_relative_to(self.absolute_out_dir):
                filter_regex = re.compile(
                    str(self.absolute_out_dir) + r"/\S+?/execroot/__main__/")
            else:
                filter_regex = re.compile(
                    str(self.absolute_user_root) + r"/\S+?/execroot/__main__/")

        if self.command == "clean":
            run_as_subprocess = True
            epilog_coro = self.remove_gen_bazelrc_dir()

        if run_as_subprocess:
            import asyncio
            import re
            asyncio.run(run(final_args, self.env, filter_regex, epilog_coro))
        else:
            os.execve(path=self.bazel_path, argv=final_args, env=self.env)

    async def remove_gen_bazelrc_dir(self):
        sys.stderr.write("INFO: Deleting generated bazelrc directory.\n")
        shutil.rmtree(self.gen_bazelrc_dir, ignore_errors=True)


async def output_filter(input_stream, output_stream, filter_regex):
    """Pipes input to output, optionally filtering lines with given filter_regex.

    If filter_regex is None, don't filter lines.
    """
    import re
    while not input_stream.at_eof():
        output = await input_stream.readline()
        if filter_regex:
            output = re.sub(filter_regex, "", output.decode()).encode()
        output_stream.buffer.write(output)
        output_stream.flush()


async def run(command, env, filter_regex, epilog_coro):
    """Runs command with env asynchronously.

    Outputs are filtered with filter_regex if it is not None.

    At the end, run the coroutine epilog_coro if it is not None.
    """
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
    if epilog_coro:
        await epilog_coro


if __name__ == "__main__":
    BazelWrapper(kleaf_repo_dir=pathlib.Path(sys.argv[1]),
                 bazel_args=sys.argv[2:], env=os.environ).run()
