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

def kernel_module_test(
        name,
        modules = None,
        **kwargs):
    """A test on artifacts produced by [kernel_module](#kernel_module).

    Args:
        name: name of test
        modules: The list of `*.ko` kernel modules, or targets that produces
            `*.ko` kernel modules (e.g. [kernel_module](#kernel_module)).
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:kernel_module_test.py"
    modinfo = "//build/kernel:hermetic-tools/modinfo"
    args = ["--modinfo", "$(location {})".format(modinfo)]
    data = [modinfo]
    if modules:
        args.append("--modules")
        args += ["$(locations {})".format(module) for module in modules]
        data += modules

    native.py_test(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = data,
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
        **kwargs
    )

def kernel_build_test(
        name,
        target = None,
        **kwargs):
    """A test on artifacts produced by [kernel_build](#kernel_build).

    Args:
        name: name of test
        target: The [`kernel_build()`](#kernel_build).
        kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """
    script = "//build/kernel/kleaf/artifact_tests:kernel_build_test.py"
    strings = "//build/kernel:hermetic-tools/strings"
    args = ["--strings", "$(location {})".format(strings)]
    if target:
        args += ["--artifacts", "$(locations {})".format(target)]

    native.py_test(
        name = name,
        main = script,
        srcs = [script],
        python_version = "PY3",
        data = [target, strings],
        args = args,
        timeout = "short",
        deps = [
            "@io_abseil_py//absl/testing:absltest",
        ],
        **kwargs
    )
