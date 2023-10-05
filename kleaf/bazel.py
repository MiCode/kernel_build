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
import dataclasses
import os
import pathlib
import re
import shlex
import shutil
import sys
import textwrap
from typing import Tuple, Optional

_BAZEL_REL_PATH = "prebuilts/bazel/linux-x86_64/bazel"
_BAZEL_JDK_REL_PATH = "prebuilts/jdk/jdk11/linux-x86"
_BAZEL_RC_NAME = "build/kernel/kleaf/common.bazelrc"
_BAZEL_RC_DIR = "build/kernel/kleaf/bazelrc"
_FLAGS_BAZEL_RC = "build/kernel/kleaf/bazelrc/flags.bazelrc"

_FLAG_PATTERN = re.compile(
    r"build --flag_alias=(?P<short_name>[a-z_]+)=(?P<is_negated>no)?(?P<label>[a-zA-Z/:_-]+)$")

_FLAG_COMMENT_PATTERN = re.compile(
    r'(?P<comment>((#\s*.*)\n)*)(?P<rule>[a-z_]+)\(\s*name\s*=\s*"(?P<name>[a-zA-Z-_]+)"',
    flags=re.MULTILINE
)

_CONFIG_PATTERN = re.compile(
    r"^--config=(?P<config>[a-z_]+):\s*(?P<description>.*)$"
)

# Sync with the following files:
#   kleaf/impl/kernel_build.bzl
_QUERY_TARGETS_ARG = 'kind("kernel_build rule", //... except attr("tags", \
    "manual", //...) except //.source_date_epoch_dir/... except //out/...)'

# Sync with the following files:
#   kleaf/impl/abi/abi_update.bzl
#   kleaf/impl/abi/kernel_abi.bzl
_QUERY_ABI_TARGETS_ARG = 'kind("(update_source_file|abi_update) rule", //... except attr("tags", \
    "manual", //...) except //.source_date_epoch_dir/... except //out/...)'


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


class BazelWrapper(object):
    def __init__(self, root_dir: pathlib.Path, bazel_args: list[str], env):
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

        self.bazel_path = self.root_dir / _BAZEL_REL_PATH

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

    def _add_startup_option_to_parser(self, parser):
        group = parser.add_argument_group(
            title="Startup options - Wrapper flags",
            description="Startup options known by the Kleaf Bazel wrapper.",)
        group.add_argument(
            "--output_root",
            metavar="PATH",
            type=_require_absolute_path,
            default=_require_absolute_path(self.root_dir / "out"),
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

        parser = argparse.ArgumentParser(add_help=False)
        self._add_startup_option_to_parser(parser)

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

    def _add_command_args_to_parser(self, parser):
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

        parser = argparse.ArgumentParser(add_help=False)
        self._add_command_args_to_parser(parser)

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

        if self.known_args.repo_manifest is not None:
            self.env["KLEAF_REPO_MANIFEST"] = self.known_args.repo_manifest

        if self.known_args.ignore_missing_projects:
            self.env["KLEAF_IGNORE_MISSING_PROJECTS"] = "true"

        if self.known_args.kleaf_localversion:
            self.env["KLEAF_USE_KLEAF_LOCALVERSION"] = "true"

        if self.known_args.user_clang_toolchain is not None:
            self.env["KLEAF_USER_CLANG_TOOLCHAIN_PATH"] = self.known_args.user_clang_toolchain

        cache_dir_bazel_rc = self.absolute_out_dir / "bazel/cache_dir.bazelrc"
        os.makedirs(os.path.dirname(cache_dir_bazel_rc), exist_ok=True)
        with open(cache_dir_bazel_rc, "w") as f:
            f.write(textwrap.dedent(f"""\
                build --//build/kernel/kleaf:cache_dir={shlex.quote(str(self.known_args.cache_dir))}
            """))

        if not self.known_startup_options.help:
            self.transformed_startup_options.append(
                f"--bazelrc={cache_dir_bazel_rc}")

    def _build_final_args(self) -> list[str]:
        """Builds the final arguments for the subprocess."""
        # final_args:
        # bazel [startup_options] [additional_startup_options] command [transformed_command_args] -- [target_patterns]

        bazel_jdk_path = self.root_dir / _BAZEL_JDK_REL_PATH
        final_args = [self.bazel_path] + self.transformed_startup_options

        if not self.known_startup_options.help:
            final_args += [
                f"--server_javabase={bazel_jdk_path}",
                f"--bazelrc={self.root_dir / _BAZEL_RC_NAME}",
            ]
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

    def _print_kleaf_help(self):
        parser = argparse.ArgumentParser(
            prog="bazel",
            add_help=False,
            usage="bazel [<startup options>] <command> [<args>] [--] [<target patterns>]",
            formatter_class=argparse.RawTextHelpFormatter,
        )

        parser.add_argument_group(
            title="Startup options",
            description=textwrap.dedent("""\
                Consists of "Wrapper flags" and "Native flags".
                """))
        self._add_startup_option_to_parser(parser)
        parser.add_argument_group(
            title="Startup options - Native flags",
            description="$ bazel help startup_options")

        parser.add_argument_group(
            title="Command",
            description="""$ bazel help""",
        )

        self._add_command_args_to_parser(parser)
        bazelrc_parser = FlagsBazelrcParser(
            self.root_dir / _FLAGS_BAZEL_RC)
        bazelrc_parser.add_to(parser, root_dir=self.root_dir)

        config_group = parser.add_argument_group(
            title="Args - configs"
        )
        for f in os.listdir(self.root_dir / _BAZEL_RC_DIR):
            bazelrc_parser = ConfigBazelrcParser(
                self.root_dir / _BAZEL_RC_DIR / f)
            bazelrc_parser.add_to(config_group, root_dir=self.root_dir)

        # Additional helper queries for target discovery.
        kleaf_group = parser.add_argument_group(
            title=textwrap.dedent("""\
                                  Kleaf Help - Query commands.
                                  Usage: bazel help kleaf [<command>]"""),
        )
        kleaf_group.add_argument(
            "targets",
            help="List kernel_build targets under current WORKSPACE",
        )
        kleaf_group.add_argument(
            "abi_targets",
            help="List ABI related targets under current WORKSPACE",
        )

        parser.add_argument_group(
            title="Target patterns",
            description="$ bazel help target-syntax"
        )

        parser.print_help()

    def _print_help(self):
        print("===============================")

        show_kleaf_help_menu = self.command == "help" and self.transformed_command_args and \
            self.transformed_command_args[0] == "kleaf"

        if show_kleaf_help_menu:
            print("Kleaf help menu:")
            self._print_kleaf_help()
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

        if self.known_args.strip_execroot:
            import asyncio
            import re
            if self.absolute_user_root.is_relative_to(self.absolute_out_dir):
                filter_regex = re.compile(
                    str(self.absolute_out_dir) + r"/\S+?/execroot/__main__/")
            else:
                filter_regex = re.compile(
                    str(self.absolute_user_root) + r"/\S+?/execroot/__main__/")
            asyncio.run(run(final_args, self.env, filter_regex))
        else:
            os.execve(path=self.bazel_path, argv=final_args, env=self.env)


class BazelrcSection(object):
    def __init__(self):
        self.comments: list[str] = []

    def add_comment(self, comment_line: str):
        self.comments.append(comment_line)

    def handle_line(self, line):
        pass

    def add_to(self, parser_or_group, root_dir: pathlib.Path):
        raise NotImplementedError


class BazelrcParser(object):
    def __init__(self, path: pathlib.Path):
        with open(path) as f:
            cur_section = self.new_section()
            self.sections = [cur_section]
            for line in f:
                line = line.strip()
                if not line:
                    cur_section = self.new_section()
                    self.sections.append(cur_section)
                    continue
                if line.startswith("#"):
                    cur_section.add_comment(line.removeprefix("#").strip())
                else:
                    cur_section.handle_line(line)

    def new_section(self) -> BazelrcSection:
        raise NotImplementedError

    def add_to(self, parser_or_group, root_dir: pathlib.Path):
        parser_or_group.add_argument_group("Args - Kleaf flags")

        for section in self.sections:
            section.add_to(parser_or_group, root_dir=root_dir)


@dataclasses.dataclass
class FlagAlias(object):
    short_name: str
    label: str
    is_negated: bool

    _build_file_cache = {}

    def read_flag_comment(self, root_dir: pathlib.Path):
        # TODO(b/256052600): Use buildozer
        build_file_rel = self.label.removeprefix('//')
        build_file_rel = build_file_rel[:build_file_rel.index(":")]
        label_name = self.label[self.label.index(":") + 1:]
        build_file = root_dir / build_file_rel / "BUILD.bazel"

        self._rule = None
        self._description = ""

        if build_file not in FlagAlias._build_file_cache:
            with open(build_file) as f:
                FlagAlias._build_file_cache[build_file] = {}
                for mo in _FLAG_COMMENT_PATTERN.finditer(f.read()):
                    FlagAlias._build_file_cache[build_file][mo.group("name")] = {
                        "rule": mo.group("rule"),
                        "comment": mo.group("comment"),
                    }

        parsed_build_file = FlagAlias._build_file_cache[build_file]
        if label_name in parsed_build_file:
            self._rule = parsed_build_file[label_name]["rule"]
            comment = parsed_build_file[label_name]["comment"]
            if self.is_negated:
                self._description = "Negates the following flag: \n"
            else:
                self._description = ""
            self._description += "\n".join(
                line.removeprefix("#").strip() for line in comment.split("\n")
            )

    def add_to_group(self, group, root_dir: pathlib.Path):
        self.read_flag_comment(root_dir=root_dir)

        kwargs = {
            "help": self._description,
        }
        if self._rule == "bool_flag":
            kwargs["action"] = "store_true"
        elif self._rule == "label_flag":
            kwargs["metavar"] = "LABEL"
        else:
            kwargs["metavar"] = "VAL"

        group.add_argument(
            f"--{self.short_name}",
            **kwargs
        )


class FlagsSection(BazelrcSection):
    def __init__(self):
        super().__init__()
        self.flags: list[FlagAlias] = []

    def handle_line(self, line):
        mo = _FLAG_PATTERN.match(line)
        if not mo:
            return
        self.flags.append(FlagAlias(
            short_name=mo.group("short_name"),
            is_negated=mo.group("is_negated") == "no",
            label=mo.group("label")
        ))

    def add_to(self, parser: argparse.ArgumentParser, root_dir: pathlib.Path):
        if not self.flags:
            # Skip for license header
            return

        title = None
        description = None
        if self.comments:
            title = self.comments[0]
            if len(self.comments) > 1:
                description = "\n".join(self.comments[1:])

        title = "Args - " + title

        group = parser.add_argument_group(
            title=title,
            description=description,
        )

        for alias in self.flags:
            try:
                alias.add_to_group(group, root_dir=root_dir)
            except argparse.ArgumentError:
                # For flags like --use_prebuilt_gki, its help is already printed by the wrapper.
                # Skip them.
                pass


class FlagsBazelrcParser(BazelrcParser):
    def new_section(self):
        return FlagsSection()


class ConfigSection(BazelrcSection):
    def add_to(self, group, root_dir: pathlib.Path):
        if not self.comments:
            return
        mo = _CONFIG_PATTERN.match(self.comments[0])
        if not mo:
            return

        config = mo.group("config")
        description_first_line = mo.group("description").strip()
        description = []
        if description_first_line:
            description.append(description_first_line)
        description += self.comments[1:]
        description = "\n".join(description)
        group.add_argument(f"--config={config}",
                           help=description,
                           action="store_true")


class ConfigBazelrcParser(BazelrcParser):
    def new_section(self):
        return ConfigSection()


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
    BazelWrapper(root_dir=pathlib.Path(sys.argv[1]),
                 bazel_args=sys.argv[2:], env=os.environ).run()
