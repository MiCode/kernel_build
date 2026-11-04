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

"""Test that a given kernel module has the built with DDK modinfo tag."""

def contains_mark_test(name, kernel_module, depmod = None):
    """Check that a kernel module is marked as built with DDK.

    Args:
        name: name of test
        kernel_module: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
          A label producing kernel module files.
        depmod: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
          Label to the depmod tool used for testing.
    """

    # Default to
    if depmod == None:
        # This was modified for backport purposes.
        depmod = "//prebuilts/kernel-build-tools:linux-x86/bin/depmod"

    args = [
        "--kernel_module",
        "$(rootpaths {})".format(kernel_module),
        "--depmod",
        "$(rootpath {})".format(depmod),
    ]

    native.py_test(
        name = name,
        python_version = "PY3",
        main = "contains_mark_test.py",
        srcs = ["//build/kernel/kleaf/tests/built_with_ddk_test:contains_mark_test.py"],
        data = [kernel_module, depmod],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
    )
