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

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//build/kernel/kleaf/tests:empty_test.bzl", "empty_test")
load("//build/kernel/kleaf/impl:common_providers.bzl", "KernelModuleInfo")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:kernel_modules_install.bzl", "kernel_modules_install")

def _get_module_staging_dir_impl(ctx):
    modules_staging_dws_list = ctx.attr.kernel_modules_install[KernelModuleInfo].modules_staging_dws_depset.to_list()
    if len(modules_staging_dws_list) != 1:
        fail("{}: {} is not a `kernel_modules_install`.".format(
            ctx.label,
            ctx.attr.kernel_modules_install.label,
        ))
    directory = modules_staging_dws_list[0].directory
    runfiles = ctx.runfiles(files = [directory])
    return DefaultInfo(files = depset([directory]), runfiles = runfiles)

_get_module_staging_dir = rule(
    implementation = _get_module_staging_dir_impl,
    attrs = {
        "kernel_modules_install": attr.label(providers = [KernelModuleInfo]),
    },
)

def _check_signature(
        name,
        base_kernel_module,
        expect_signature,
        directory):
    script = "//build/kernel/kleaf/artifact_tests:check_module_signature.py"
    modinfo = "//build/kernel:hermetic-tools/modinfo"
    args = [
        "--module",
        base_kernel_module,
        "--expect_signature" if expect_signature else "--noexpect_signature",
        "--modinfo",
        "$(location {})".format(modinfo),
    ]
    data = [modinfo]
    if directory:
        args += [
            "--dir",
            "$(location {})".format(directory),
        ]
        data.append(directory)
    native.py_test(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = data,
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/flags",
            "@io_abseil_py//absl/testing:absltest",
        ],
    )

def _check_signature_for_modules_install(
        name,
        kernel_modules_install,
        base_kernel_module,
        expect_signature):
    """Checks signature in the |base_kernel_module| in |kernel_modules_install|."""

    _get_module_staging_dir(
        name = name + "_modules_install_staging_dir",
        kernel_modules_install = kernel_modules_install,
    )
    _check_signature(
        name = name,
        directory = name + "_modules_install_staging_dir",
        base_kernel_module = base_kernel_module,
        expect_signature = expect_signature,
    )

def _create_one_device_modules_test(
        name,
        arch,
        base_kernel_label,
        base_kernel_module,
        expect_signature,
        module_outs = None):
    # A minimal device's kernel_build build_config.
    build_config_content = """
                KERNEL_DIR="{common_package}"

                . ${{ROOT_DIR}}/${{KERNEL_DIR}}/build.config.common
                . ${{ROOT_DIR}}/${{KERNEL_DIR}}/build.config.gki
                . ${{ROOT_DIR}}/${{KERNEL_DIR}}/build.config.{arch}

                MAKE_GOALS="modules"
                DEFCONFIG="device_modules_test_gki_defconfig"
                # For x86_64, ARCH should be x86 for config purposes (b/254348147)
                PRE_DEFCONFIG_CMDS="mkdir -p \\${{OUT_DIR}}/arch/${{ARCH/x86_64/x86}}/configs/ && ( cat ${{ROOT_DIR}}/${{KERNEL_DIR}}/arch/${{ARCH/x86_64/x86}}/configs/gki_defconfig && echo '# CONFIG_MODULE_SIG_ALL is not set' ) > \\${{OUT_DIR}}/arch/${{ARCH/x86_64/x86}}/configs/${{DEFCONFIG}};"
                POST_DEFCONFIG_CMDS=""
                """.format(
        common_package = base_kernel_label.package,
        arch = "aarch64" if arch == "arm64" else arch,
    )

    write_file(
        name = name + "_build_config",
        content = build_config_content.split("\n"),
        out = name + "_build_config/build.config",
    )

    kernel_build(
        name = name + "_kernel_build",
        tags = ["manual"],
        build_config = name + "_build_config",
        outs = [],
        base_kernel = base_kernel_label,
        module_outs = module_outs,
    )

    kernel_modules_install(
        name = name + "_modules_install",
        tags = ["manual"],
        kernel_build = name + "_kernel_build",
    )

    tests = []
    _check_signature_for_modules_install(
        name = name + "_modules_install_check_signature_test",
        kernel_modules_install = name + "_modules_install",
        base_kernel_module = base_kernel_module,
        expect_signature = expect_signature,
    )
    tests.append(name + "_modules_install_check_signature_test")

    native.test_suite(
        name = name,
        tests = tests,
    )

def device_modules_test(
        name,
        base_kernel_label,
        base_kernel_module,
        arch):
    """Tests for device's modules.

    This test checks that device targets contains proper modules.

    Args:
        name: name of the test
        base_kernel_label: GKI kernel; must be a full [Label](https://bazel.build/rules/lib/Label).
        base_kernel_module: Any module from `base_kernel`. If `base_kernel`
          does not contain any in-tree modules, this should be `None`, and
          no tests will be defined.
        arch: architecture of `base_kernel`. This is either `"arm64"` or `"x86_64"`.
    """

    if not base_kernel_module:
        empty_test(name = name)
        return

    tests = []
    _create_one_device_modules_test(
        name = name + "_use_gki_module",
        arch = arch,
        base_kernel_module = base_kernel_module,
        base_kernel_label = base_kernel_label,
        expect_signature = True,
    )
    tests.append(name + "_use_gki_module")

    _create_one_device_modules_test(
        name = name + "_use_device_module",
        arch = arch,
        base_kernel_module = base_kernel_module,
        base_kernel_label = base_kernel_label,
        expect_signature = False,
        module_outs = [base_kernel_module],
    )
    tests.append(name + "_use_device_module")

    native.test_suite(
        name = name,
        tests = tests,
    )
