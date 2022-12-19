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

"""Dist rules for devices with ABI monitoring enabled."""

load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load("//build/bazel_common_rules/exec:exec.bzl", "exec")
load(":utils.bzl", "utils")

def kernel_build_abi_dist(
        name,
        kernel_build_abi,
        **kwargs):
    """**Deprecated**. Use [`kernel_abi_dist`](#kernel_abi_dist) instead.

    A wrapper over `copy_to_dist_dir` for [`kernel_build_abi`](#kernel_build_abi).

    After copying all files to dist dir, return the exit code from `diff_abi`.

    Args:
      name: name of the dist target
      kernel_build_abi: name of the [`kernel_build_abi`](#kernel_build_abi)
        invocation.
      **kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).

    Deprecated:
      Use [`kernel_abi_dist`](#kernel_abi_dist) instead.
    """

    # buildifier: disable=print
    print("""
WARNING: kernel_build_abi_dist is deprecated. Use kernel_abi_dist instead.

You may try copy-pasting the following definition to BUILD.bazel
(note: this is not necessarily accurate and likely unformatted):

kernel_abi_dist(
    {kwargs}
)
""".format(
        kwargs = utils.kwargs_to_def(
            name = name,
            kernel_abi = kernel_build_abi + "_abi",
            **kwargs
        ),
    ))

    kernel_abi_dist(
        name = name,
        kernel_abi = kernel_build_abi + "_abi",
        **kwargs
    )

def kernel_abi_dist(
        name,
        kernel_abi,
        **kwargs):
    """A wrapper over `copy_to_dist_dir` for [`kernel_abi`](#kernel_abi).

    After copying all files to dist dir, return the exit code from `diff_abi`.

    Args:
      name: name of the dist target
      kernel_abi: name of the [`kernel_abi`](#kernel_abi) invocation.
      **kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    # TODO(b/231647455): Clean up hard-coded name "_abi_diff_executable".

    if kwargs.get("data") == None:
        kwargs["data"] = []

    # Use explicit + to prevent modifying the original list.
    kwargs["data"] = kwargs["data"] + [kernel_abi]

    copy_to_dist_dir(
        name = name + "_copy_to_dist_dir",
        **kwargs
    )

    exec(
        name = name,
        data = [
            name + "_copy_to_dist_dir",
            kernel_abi + "_diff_executable",
        ],
        script = """
          # Copy to dist dir
            $(rootpath {copy_to_dist_dir}) $@
          # Check return code of diff_abi and kmi_enforced
            $(rootpath {diff})
        """.format(
            copy_to_dist_dir = name + "_copy_to_dist_dir",
            diff = kernel_abi + "_diff_executable",
        ),
    )
