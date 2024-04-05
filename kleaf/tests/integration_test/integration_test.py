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
"""Integration tests for Kleaf.

The rest of the arguments are passed to absltest.

Example:

    bazel run //build/kernel/kleaf/tests/integration_test

    bazel run //build/kernel/kleaf/tests/integration_test \\
      -- --bazel_arg=--verbose_failures --bazel_arg=--announce_rc

    bazel run //build/kernel/kleaf/tests/integration_test \\
      -- KleafIntegrationTest.test_simple_incremental

    bazel run //build/kernel/kleaf/tests/integration_test \\
      -- --bazel_arg=--verbose_failures --bazel_arg=--announce_rc \\
         KleafIntegrationTest.test_simple_incremental \\
         --verbosity=2

    tools/bazel run //build/kernel/kleaf/tests/integration_test \\
      -- --bazel-arg=--verbose_failures --include-abi-tests \\
      KleafIntegrationTestAbiTest.test_non_exported_symbol_fails
"""

import argparse
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
import pathlib
import tempfile
import textwrap
import unittest
from typing import Callable, Iterable

from absl.testing import absltest
from build.kernel.kleaf.analysis.inputs import analyze_inputs

_BAZEL = pathlib.Path("tools/bazel")

# See local.bazelrc
_LOCAL = ["--//build/kernel/kleaf:config_local"]

_LTO_NONE = [
    "--lto=none",
    "--nokmi_symbol_list_strict_mode",
]

# Handy arguments to build as fast as possible.
_FASTEST = _LOCAL + _LTO_NONE


def load_arguments():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--bazel-arg",
                        action="append",
                        dest="bazel_args",
                        default=[],
                        help="arg to bazel build calls")
    parser.add_argument("--bazel-wrapper-arg",
                        action="append",
                        dest="bazel_wrapper_args",
                        default=[],
                        help="arg to bazel.py wrapper")
    parser.add_argument("--include-abi-tests",
                        action="store_true",
                        dest="include_abi_tests",
                        help="Include ABI Monitoring related tests." +
                        "NOTE: It requires a branch with ABI monitoring enabled.")
    return parser.parse_known_args()


arguments = None


class Exec(object):

    @staticmethod
    def check_call(args: list[str], **kwargs) -> None:
        """Executes a shell command."""
        kwargs.setdefault("text", True)
        sys.stderr.write(f"+ {' '.join(args)}\n")
        subprocess.check_call(args, **kwargs)

    @staticmethod
    def check_output(args: list[str], **kwargs) -> str:
        """Returns output of a shell command"""
        kwargs.setdefault("text", True)
        sys.stderr.write(f"+ {' '.join(args)}\n")
        return subprocess.check_output(args, **kwargs)

    @staticmethod
    def popen(args: list[str], **kwargs) -> subprocess.Popen:
        """Executes a shell command.

        Returns:
            the Popen object
        """
        kwargs.setdefault("text", True)
        sys.stderr.write(f"+ {' '.join(args)}\n")
        popen = subprocess.Popen(args, **kwargs)
        return popen

    @staticmethod
    def check_errors(args: list[str], **kwargs) -> str:
        """Returns errors of a shell command"""
        kwargs.setdefault("text", True)
        sys.stderr.write(f"+ {' '.join(args)}\n")
        return subprocess.run(
            args, check = False, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs).stdout

class KleafIntegrationTestBase(unittest.TestCase):

    def _check_call(self,
                    command: str,
                    command_args: list[str],
                    startup_options=(),
                    **kwargs) -> None:
        """Executes a bazel command."""
        startup_options = list(startup_options)
        startup_options.append(f"--bazelrc={self._bazel_rc.name}")
        command_args = list(command_args)
        command_args.extend(arguments.bazel_wrapper_args)
        Exec.check_call([str(_BAZEL)] + startup_options + [
            command,
        ] + command_args, **kwargs)

    def _build(self, command_args: list[str], **kwargs) -> None:
        """Executes a bazel build command."""
        self._check_call("build", command_args, **kwargs)

    def _check_output(self, command: str, command_args: list[str],
                      use_bazelrc=True,
                      **kwargs) -> str:
        """Returns output of a bazel command."""

        args = [str(_BAZEL)]
        if use_bazelrc:
            args.append(f"--bazelrc={self._bazel_rc.name}")
        args.append(command)
        args += command_args

        return Exec.check_output(args, **kwargs)

    def _check_errors(self, command: str, command_args: list[str],
                      use_bazelrc=True,
                      **kwargs) -> str:
        """Returns errors of a bazel command."""

        args = [str(_BAZEL)]
        if use_bazelrc:
            args.append(f"--bazelrc={self._bazel_rc.name}")
        args.append(command)
        args += command_args

        return Exec.check_errors(args, **kwargs)

    def _popen(self, command: str, command_args: list[str], **kwargs) \
            -> subprocess.Popen:
        return Exec.popen([
            str(_BAZEL),
            f"--bazelrc={self._bazel_rc.name}",
            command,
        ] + command_args, **kwargs)

    def setUp(self) -> None:
        self.assertTrue(os.environ.get("BUILD_WORKSPACE_DIRECTORY"),
                        "BUILD_WORKSPACE_DIRECTORY is not set")
        os.chdir(os.environ["BUILD_WORKSPACE_DIRECTORY"])
        sys.stderr.write(
            f"BUILD_WORKSPACE_DIRECTORY={os.environ['BUILD_WORKSPACE_DIRECTORY']}\n"
        )

        self.assertTrue(_BAZEL.is_file())

        self._bazel_rc = tempfile.NamedTemporaryFile()
        self.addCleanup(self._bazel_rc.close)
        with open(self._bazel_rc.name, "w") as f:
            f.write(f"import %workspace%/build/kernel/kleaf/common.bazelrc\n")
            for arg in arguments.bazel_args:
                f.write(f"build {shlex.quote(arg)}\n")

    def restore_file_after_test(self, path: pathlib.Path | str):
        with open(path) as file:
            old_content = file.read()

        def cleanup():
            with open(path, "w") as new_file:
                new_file.write(old_content)

        self.addCleanup(cleanup)
        return cleanup

    def filter_lines(
        self,
        path: pathlib.Path | str,
        pred: Callable[[str], bool],
    ):
        """Filters lines in a file."""
        output_file_obj = tempfile.NamedTemporaryFile(mode="w", delete=False)
        with open(path) as input_file:
            with output_file_obj as output_file:
                for line in input_file:
                    if pred(line):
                        output_file.write(line)
        shutil.move(output_file.name, path)

    def replace_lines(
        self,
        path: pathlib.Path | str,
        pred: Callable[[str], bool],
        replacements: Iterable[str],
    ):
        """Replaces lines in a file."""
        output_file_obj = tempfile.NamedTemporaryFile(mode="w", delete=False)
        it = iter(replacements)
        with open(path) as input_file:
            with output_file_obj as output_file:
                for line in input_file:
                    if pred(line):
                        replaced_line = next(it)
                        output_file.write(replaced_line)
                        if not replaced_line.endswith("\n"):
                            output_file.write("\n")
                    else:
                        output_file.write(line)
        shutil.move(output_file.name, path)

    def _sha256(self, path: pathlib.Path | str) -> str:
        """Gets the hash for a file."""
        hash = hashlib.sha256()
        with open(path, "rb") as file:
            chunk = None
            while chunk != b'':
                chunk = file.read(4096)
                hash.update(chunk)
        return hash.hexdigest()

    def _touch(self, path: pathlib.Path | str, append_text="\n") -> None:
        """Modifies a file so it (may) trigger a rebuild for certain targets."""
        self.restore_file_after_test(path)

        with open(path, "a") as file:
            file.write(append_text)

    def _touch_core_kernel_file(self):
        """Modifies a core kernel file."""
        self._touch(f"{self._common()}/kernel/sched/core.c")

    def _common(self) -> str:
        """Returns the common package."""
        return "common"


# NOTE: It requires a branch with ABI monitoring enabled.
#   Include these using the flag --include-abi-tests
class KleafIntegrationTestAbiTest(KleafIntegrationTestBase):

    def test_non_exported_symbol_fails(self):
        """Tests the following:

        - Validates a non-exported symbol makes the build fail.
          For this particular example use db845c mixed build.

        This test requires a branch with ABI monitoring enabled.
        """

        if not arguments.include_abi_tests:
          self.skipTest("Skipping test_non_exported_symbol_fails test.")

        # Select an arbitrary driver and unexport a symbols.
        self.driver_file = f"{self._common()}/drivers/i2c/i2c-core-base.c"
        self.restore_file_after_test(self.driver_file)
        self.replace_lines(self.driver_file,
                           lambda x: re.search("EXPORT_SYMBOL_GPL\(i2c_adapter_type\);", x),
                           [""])

        # Check for errors in the logs.
        output = self._check_errors("build", [f"//{self._common()}:db845c", "--config=fast"])

        def matching_line(line): return re.match(
             r"^ERROR: modpost: \"i2c_adapter_type\" \[.*\] undefined!$",
             line)
        self.assertTrue(
             any([matching_line(line) for line in output.splitlines()]))


# Slow integration tests belong to their own shard.
class KleafIntegrationTestShard1(KleafIntegrationTestBase):

    def test_incremental_switch_local_and_lto(self):
        """Tests the following:

        - switching from non-local to local and back works
        - with --config=local, changing from --lto=none to --lto=thin and back works

        See b/257288175."""
        self._build([f"//{self._common()}:kernel_dist"] + _LTO_NONE + _LOCAL)
        self._build([f"//{self._common()}:kernel_dist"] + _LTO_NONE)
        self._build([f"//{self._common()}:kernel_dist"] + _LTO_NONE + _LOCAL)
        self._build([f"//{self._common()}:kernel_dist"] +
                    ["--lto=thin"] + _LOCAL)
        self._build([f"//{self._common()}:kernel_dist"] + _LTO_NONE + _LOCAL)

    def test_config_sync(self):
        """Test that, with --config=local, .config is reflected in vmlinux.

        See b/312268956.
        """

        gki_defconfig_path = (
            f"{self._common()}/arch/arm64/configs/gki_defconfig")
        restore_defconfig = self.restore_file_after_test(gki_defconfig_path)
        extract_ikconfig = f"{self._common()}/scripts/extract-ikconfig"

        with open(gki_defconfig_path, encoding="utf-8") as f:
            self.assertIn("CONFIG_UAPI_HEADER_TEST=y\n", f)

        self._build([f"//{self._common()}:kernel_aarch64", "--config=fast"])
        vmlinux = pathlib.Path(
            f"bazel-bin/{self._common()}/kernel_aarch64/vmlinux")

        output = subprocess.check_output([extract_ikconfig, vmlinux], text=True)
        self.assertIn("CONFIG_UAPI_HEADER_TEST=y", output.splitlines())

        self.filter_lines(gki_defconfig_path,
                          lambda x: "CONFIG_UAPI_HEADER_TEST" not in x)
        self._build([f"//{self._common()}:kernel_aarch64", "--config=fast"])

        output = subprocess.check_output([extract_ikconfig, vmlinux], text=True)
        self.assertIn("# CONFIG_UAPI_HEADER_TEST is not set",
                      output.splitlines())

        restore_defconfig()
        self._build([f"//{self._common()}:kernel_aarch64", "--config=fast"])

        output = subprocess.check_output([extract_ikconfig, vmlinux], text=True)
        self.assertIn("CONFIG_UAPI_HEADER_TEST=y", output.splitlines())

class KleafIntegrationTestShard2(KleafIntegrationTestBase):

    def test_user_clang_toolchain(self):
        """Test --user_clang_toolchain option."""

        clang_version = None
        build_config_constants = f"{self._common()}/build.config.constants"
        with open(build_config_constants) as f:
            for line in f.read().splitlines():
                if line.startswith("CLANG_VERSION="):
                    clang_version = line.strip().split("=", 2)[1]
        self.assertIsNotNone(clang_version)
        clang_dir = f"prebuilts/clang/host/linux-x86/clang-{clang_version}"
        clang_dir = os.path.realpath(clang_dir)

        # Do not use --config=local to ensure the toolchain dependency is
        # correct.
        args = [
            f"--user_clang_toolchain={clang_dir}",
            f"//{self._common()}:kernel",
        ] + _LTO_NONE
        self._build(args)

# Quick integration tests. Each test case should finish within 1 minute.
# The whole test suite should finish within 5 minutes. If the whole test suite
# takes too long, consider sharding QuickIntegrationTest too.
class QuickIntegrationTest(KleafIntegrationTestBase):

    def test_change_to_core_kernel_does_not_affect_modules_prepare(self):
        """Tests that, with a small change to the core kernel, modules_prepare does not change.

        See b/254357038, b/267385639, b/263415662.
        """
        modules_prepare_archive = \
            f"bazel-bin/{self._common()}/kernel_aarch64_modules_prepare/modules_prepare_outdir.tar.gz"

        # This also tests that fixdep is not needed.
        self._build([f"//{self._common()}:kernel_aarch64_modules_prepare"] +
                    _FASTEST)
        first_hash = self._sha256(modules_prepare_archive)

        old_modules_archive = tempfile.NamedTemporaryFile(delete=False)
        shutil.copyfile(modules_prepare_archive, old_modules_archive.name)

        self._touch_core_kernel_file()

        self._build([f"//{self._common()}:kernel_aarch64_modules_prepare"] +
                    _FASTEST)
        second_hash = self._sha256(modules_prepare_archive)

        if first_hash == second_hash:
            os.unlink(old_modules_archive.name)

        self.assertEqual(
            first_hash, second_hash,
            textwrap.dedent(f"""\
                             Check their content here:
                             old: {old_modules_archive.name}
                             new: {modules_prepare_archive}"""))

    def test_module_does_not_depend_on_vmlinux(self):
        """Tests that, the inputs for building a module does not include vmlinux and System.map.

        See b/254357038."""
        vd_modules = self._check_output("query", [
            'kind("^_kernel_module rule$", //common-modules/virtual-device/...)'
        ]).splitlines()
        self.assertTrue(vd_modules)

        print(
            f"+ build/kernel/kleaf/analysis/inputs.py 'mnemonic(\"KernelModule.*\", {vd_modules[0]})'"
        )
        input_to_module = analyze_inputs(
            aquery_args=[f'mnemonic("KernelModule.*", {vd_modules[0]})'] +
            _FASTEST).keys()
        self.assertFalse([
            path
            for path in input_to_module if pathlib.Path(path).name == "vmlinux"
        ], "An external module must not depend on vmlinux")
        self.assertFalse([
            path for path in input_to_module
            if pathlib.Path(path).name == "System.map"
        ], "An external module must not depend on System.map")

    def test_override_javatmp(self):
        """Tests that out/bazel/javatmp can be overridden.

        See b/267580482."""
        default_java_tmp = pathlib.Path("out/bazel/javatmp")
        new_java_tmp = tempfile.TemporaryDirectory()
        self.addCleanup(new_java_tmp.cleanup)
        try:
            shutil.rmtree(default_java_tmp)
        except FileNotFoundError:
            pass
        self._check_call(startup_options=[
            f"--host_jvm_args=-Djava.io.tmpdir={new_java_tmp.name}"
        ],
            command="build",
            command_args=["//build/kernel/kleaf:empty_test"] +
            _FASTEST)
        self.assertFalse(default_java_tmp.exists())

    def test_override_absolute_out_dir(self):
        """Tests that out/ can be overridden.

        See b/267580482."""
        default_out = pathlib.Path("out")
        new_out = tempfile.TemporaryDirectory()
        self.addCleanup(new_out.cleanup)
        try:
            shutil.rmtree(default_out)
        except FileNotFoundError:
            pass
        self._check_call(command="build",
                         command_args=["//build/kernel/kleaf:empty_test"] +
                         _FASTEST)
        self.assertTrue(default_out.exists())
        shutil.rmtree(default_out)
        self._check_call(startup_options=[f"--output_root={new_out.name}"],
                         command="build",
                         command_args=["//build/kernel/kleaf:empty_test"] +
                         _FASTEST)
        self.assertFalse(default_out.exists())

    def test_config_uapi_header_test(self):
        """Tests that CONFIG_UAPI_HEADER_TEST is not deleted.

        To keep CONFIG_UAPI_HEADER_TEST, USERCFLAGS needs to set --sysroot and
        --target properly, and USERLDFLAGS needs to set --sysroot.

        See b/270996321 and b/190019968."""

        archs = [
            ("aarch64", "arm64"),
            ("x86_64", "x86"),
            # TODO(b/271919464): Need NDK_TRIPLE for riscv so --sysroot is properly set
            # ("riscv64", "riscv"),
        ]

        for arch, srcarch in archs:
            with self.subTest(arch=arch, srcarch=srcarch):
                gki_defconfig = f"{self._common()}/arch/{srcarch}/configs/gki_defconfig"
                self.restore_file_after_test(gki_defconfig)

                self._check_call("run", [
                    f"//{self._common()}:kernel_{arch}_config", "--",
                    "olddefconfig"
                ] + _FASTEST)

                with open(gki_defconfig) as f:
                    new_gki_defconfig_content = f.read()
                self.assertTrue(
                    "CONFIG_UAPI_HEADER_TEST=y"
                    in new_gki_defconfig_content.splitlines(),
                    f"gki_defconfig should still have CONFIG_UAPI_HEADER_TEST=y after "
                    f"`bazel run //{self._common()}:kernel_aarch64_config "
                    f"-- olddefconfig`, but got\n{new_gki_defconfig_content}")

                # It should be fine to call the same command subsequently.
                self._check_call("run", [
                    f"//{self._common()}:kernel_{arch}_config", "--",
                    "olddefconfig"
                ] + _FASTEST)

    def test_menuconfig_merge(self):
        """Test that menuconfig works with a raw merge_config.sh in PRE_DEFCONFIG_CMDS.

        See `menuconfig_merge_test/` for details.

        See b/276889737 and b/274878805."""

        args = [
            "//build/kernel/kleaf/tests/integration_test/menuconfig_merge_test:menuconfig_merge_test_config",
        ] + _FASTEST

        output = self._check_output("run", args)

        def matching_line(line): return re.match(
            r"^Updating .*common/arch/arm64/configs/menuconfig_test_defconfig$",
            line)
        self.assertTrue(
            any([matching_line(line) for line in output.splitlines()]))

        # It should be fine to call the same command subsequently.
        self._check_call("run", args)

    def test_menuconfig_fragment(self):
        """Test that menuconfig works with a FRAGMENT_CONFIG defined.

        See `menuconfig_fragment_test/` for details.

        See b/276889737 and b/274878805."""

        args = [
            "//build/kernel/kleaf/tests/integration_test/menuconfig_fragment_test:menuconfig_fragment_test_config",
        ] + _FASTEST

        output = self._check_output("run", args)

        expected_line = f"Updated {os.environ['BUILD_WORKSPACE_DIRECTORY']}/build/kernel/kleaf/tests/integration_test/menuconfig_fragment_test/defconfig.fragment"
        self.assertTrue(expected_line, output.splitlines())

        # It should be fine to call the same command subsequently.
        self._check_call("run", args)

    def test_ddk_defconfig_must_present(self):
        """Test that for ddk_module, items in defconfig must be in the final .config.

        See b/279105294.
        """

        args = [
            "//build/kernel/kleaf/tests/integration_test/ddk_negative_test:defconfig_must_present_test_module_config",
        ] + _FASTEST
        popen = self._popen("build",
                            args,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
        _, stderr = popen.communicate()
        self.assertNotEqual(popen.returncode, 0)
        self.assertIn(
            "CONFIG_DELETED_SET: actual '', expected 'CONFIG_DELETED_SET=y' from build/kernel/kleaf/tests/integration_test/ddk_negative_test/defconfig.",
            stderr)
        self.assertNotIn("DECLARED_SET", stderr)
        self.assertNotIn("DECLARED_UNSET", stderr)

    @unittest.skip("b/293357796")
    def test_dash_dash_help(self):
        """Test that `bazel --help` works."""
        self._check_output("--help", [], use_bazelrc=False)

    def test_help(self):
        """Test that `bazel help` works."""
        self._check_output("help", [])

    def test_help_kleaf(self):
        """Test that `bazel help kleaf` works."""
        self._check_output("help", ["kleaf"])


class ScmversionIntegrationTest(KleafIntegrationTestBase):

    def setUp(self) -> None:
        super().setUp()

        self.strings = "bazel-bin/build/kernel/hermetic-tools/llvm-strings"
        self.uname_pattern_prefix = re.compile(
            r"^Linux version [0-9]+[.][0-9]+[.][0-9]+(\S*)")

        self.build_config_common_path = f"{self._common()}/build.config.common"
        self.restore_file_after_test(self.build_config_common_path)

        self.gki_defconfig_path = f"{self._common()}/arch/arm64/configs/gki_defconfig"
        self.restore_file_after_test(self.gki_defconfig_path)

        self.makefile_path = f"{self._common()}/Makefile"
        self.restore_file_after_test(self.makefile_path)

    def _setup_mainline(self):
        with open(self.build_config_common_path, "a") as f:
            f.write("BRANCH=android-mainline\n")
            f.write("unset KMI_GENERATION\n")

        # Writing to defconfig directly requires us to disable check_defconfig,
        # because the ordering is not correct.
        self.build_config_gki_aarch64_path = f"{self._common()}/build.config.gki.aarch64"
        self.restore_file_after_test(self.build_config_gki_aarch64_path)
        with open(self.build_config_gki_aarch64_path, "a") as f:
            f.write("POST_DEFCONFIG_CMDS=true\n")

        extraversion_pattern = re.compile(r"^EXTRAVERSION\s*=")
        self.replace_lines(self.makefile_path,
                           lambda x: re.search(extraversion_pattern, x),
                           ["EXTRAVERSION = -rc999"])

    def _setup_release_branch(self):
        with open(self.build_config_common_path, "a") as f:
            f.write(
                textwrap.dedent("""\
                BRANCH=android99-100.110
                KMI_GENERATION=56
            """))

        localversion_pattern = re.compile(r"^CONFIG_LOCALVERSION=")
        self.filter_lines(self.gki_defconfig_path,
                          lambda x: not re.search(localversion_pattern, x))
        extraversion_pattern = re.compile(r"^EXTRAVERSION\s*=")
        self.replace_lines(self.makefile_path,
                           lambda x: re.search(extraversion_pattern, x),
                           ["EXTRAVERSION ="])

    def _get_vmlinux_scmversion(self):
        strings_output = Exec.check_output([
            self.strings, f"bazel-bin/{self._common()}/kernel_aarch64/vmlinux"
        ])
        ret = []
        for line in strings_output.splitlines():
            mo = re.search(self.uname_pattern_prefix, line)
            if mo:
                ret.append(mo.group(1))
        self.assertTrue(ret)
        print(f"scmversion = {ret}")
        return ret

    @staticmethod
    def _env_without_build_number():
        env = dict(os.environ)
        env.pop("BUILD_NUMBER", None)
        # Fix this error to execute `repo` properly:
        #  ModuleNotFoundError: No module named 'color'
        env.pop("PYTHONSAFEPATH", None)
        return env

    @staticmethod
    def _env_with_build_number(build_number):
        env = dict(os.environ)
        env["BUILD_NUMBER"] = str(build_number)
        # Fix this error to execute `repo` properly:
        #  ModuleNotFoundError: No module named 'color'
        env.pop("PYTHONSAFEPATH", None)
        return env

    def test_mainline_no_stamp(self):
        self._setup_mainline()
        self._check_call(
            "build",
            _FASTEST + [
                "--config=local",
                f"//{self._common()}:kernel_aarch64",
            ],
            env=ScmversionIntegrationTest._env_without_build_number())
        for scmversion in self._get_vmlinux_scmversion():
            self.assertEqual("-rc999-mainline-maybe-dirty", scmversion)

    def test_mainline_stamp(self):
        self._setup_mainline()
        self._check_call(
            "build",
            _FASTEST + [
                "--config=stamp",
                "--config=local",
                f"//{self._common()}:kernel_aarch64",
            ],
            env=ScmversionIntegrationTest._env_without_build_number())
        scmversion_pat = re.compile(
            r"^-rc999-mainline(-[0-9]{5,})?-g[0-9a-f]{12,40}(-dirty)?$")
        for scmversion in self._get_vmlinux_scmversion():
            self.assertRegexpMatches(scmversion, scmversion_pat)

    def test_mainline_ab(self):
        self._setup_mainline()
        self._check_call(
            "build",
            _FASTEST + [
                "--config=stamp",
                "--config=local",
                f"//{self._common()}:kernel_aarch64",
            ],
            env=ScmversionIntegrationTest._env_with_build_number("123456"))
        scmversion_pat = re.compile(
            r"^-rc999-mainline(-[0-9]{5,})?-g[0-9a-f]{12,40}(-dirty)?-ab123456$"
        )
        for scmversion in self._get_vmlinux_scmversion():
            self.assertRegexpMatches(scmversion, scmversion_pat)

    def test_release_branch_no_stamp(self):
        self._setup_release_branch()
        self._check_call(
            "build",
            _FASTEST + [
                "--config=local",
                f"//{self._common()}:kernel_aarch64",
            ],
            env=ScmversionIntegrationTest._env_without_build_number())
        for scmversion in self._get_vmlinux_scmversion():
            self.assertEqual("-android99-56-maybe-dirty", scmversion)

    def test_release_branch_stamp(self):
        self._setup_release_branch()
        self._check_call(
            "build",
            _FASTEST + [
                "--config=stamp",
                "--config=local",
                f"//{self._common()}:kernel_aarch64",
            ],
            env=ScmversionIntegrationTest._env_without_build_number())
        scmversion_pat = re.compile(
            r"^-android99-56(-[0-9]{5,})?-g[0-9a-f]{12,40}(-dirty)?$")
        for scmversion in self._get_vmlinux_scmversion():
            self.assertRegexpMatches(scmversion, scmversion_pat)

    def test_release_branch_ab(self):
        self._setup_release_branch()
        self._check_call(
            "build",
            _FASTEST + [
                "--config=stamp",
                "--config=local",
                f"//{self._common()}:kernel_aarch64",
            ],
            env=ScmversionIntegrationTest._env_with_build_number("123456"))
        scmversion_pat = re.compile(
            r"^-android99-56(-[0-9]{5,})?-g[0-9a-f]{12,40}(-dirty)?-ab123456$")
        for scmversion in self._get_vmlinux_scmversion():
            self.assertRegexpMatches(scmversion, scmversion_pat)


if __name__ == "__main__":
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
