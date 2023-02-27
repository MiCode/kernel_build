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
load("//build/bazel_common_rules/exec:exec.bzl", "exec", "exec_rule")
load(":abi/abi_transitions.bzl", "with_vmlinux_transition")
load(":utils.bzl", "utils")

def kernel_build_abi_dist(
        name,
        kernel_build_abi,
        kernel_build_add_vmlinux = None,
        **kwargs):
    """**Deprecated**. Use [`kernel_abi_dist`](#kernel_abi_dist) instead.

    A wrapper over `copy_to_dist_dir` for [`kernel_build_abi`](#kernel_build_abi).

    After copying all files to dist dir, return the exit code from `diff_abi`.

    Args:
      name: name of the dist target
      kernel_build_abi: name of the [`kernel_build_abi`](#kernel_build_abi)
        invocation.
      kernel_build_add_vmlinux: See
        [`kernel_abi_dist.kernel_build_add_vmlinux`](#kernel_abi_dist-kernel_build_add_vmlinux).
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
        kernel_build_add_vmlinux = kernel_build_add_vmlinux,
        **kwargs
    )

_kernel_abi_dist_exec = exec_rule(
    cfg = with_vmlinux_transition,
    attrs = {
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def kernel_abi_dist(
        name,
        kernel_abi,
        kernel_build_add_vmlinux = None,
        **kwargs):
    """A wrapper over `copy_to_dist_dir` for [`kernel_abi`](#kernel_abi).

    After copying all files to dist dir, return the exit code from `diff_abi`.

    **Implementation notes**:

    `with_vmlinux_transition` is applied on all targets by default. In
    particular, the `kernel_build` targets in `data` automatically builds
    `vmlinux` regardless of whether `vmlinux` is specified in `outs`.

    Args:
      name: name of the dist target
      kernel_abi: name of the [`kernel_abi`](#kernel_abi) invocation.
      kernel_build_add_vmlinux: If `True`, all `kernel_build` targets depended
        on by this change automatically applies a
        [transition](https://bazel.build/extending/config#user-defined-transitions)
        that always builds `vmlinux` and sets `kbuild_symtypes="true"`. For
        up-to-date implementation details, look for `with_vmlinux_transition`
        in `build/kernel/kleaf/impl/abi`.

        If there are multiple `kernel_build` targets in `data`, only keep the
        one for device build. Otherwise, the build may break. For example:

        ```
        kernel_build(
            name = "tuna",
            base_kernel = "//common:kernel_aarch64"
            ...
        )

        kernel_abi(...)
        kernel_abi_dist(
            name = "tuna_abi_dist",
            data = [
                ":tuna",
                # "//common:kernel_aarch64", # remove GKI
            ],
            kernel_build_add_vmlinux = True,
        )
        ```

        Enabling this option ensures that `tuna_abi_dist` doesn't build
        `//common:kernel_aarch64` and `:tuna` twice, once with the transition
        and once without. Enabling this ensures that `//common:kernel_aarch64`
        and `:tuna` always built with the transition.

        **Note**: Its value will be `True` by default in the future.
        During the migration period, this is `False` by default. Once all
        devices have been fixed, this attribute will be set to `True` by default.
      **kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    # TODO(b/231647455): Clean up hard-coded name "_abi_diff_executable".
    # TODO(b/264710236): Set kernel_build_add_vmlinux by default

    if kwargs.get("data") == None:
        kwargs["data"] = []

    # Use explicit + to prevent modifying the original list.
    kwargs["data"] = kwargs["data"] + [kernel_abi]

    copy_to_dist_dir(
        name = name + "_copy_to_dist_dir",
        **kwargs
    )

    exec_macro = _kernel_abi_dist_exec if kernel_build_add_vmlinux else exec
    exec_macro(
        name = name,
        data = [
            name + "_copy_to_dist_dir",
            kernel_abi + "_diff_executable",
            kernel_abi + "_diff_executable_xml",
        ],
        script = """
          # Copy to dist dir
            $(rootpath {copy_to_dist_dir}) $@
          # Check return code of diff_abi and kmi_enforced
            $(rootpath {diff_stg})
          # Same for XML ABI
            $(rootpath {diff_xml})
        """.format(
            copy_to_dist_dir = name + "_copy_to_dist_dir",
            diff_stg = kernel_abi + "_diff_executable",
            diff_xml = kernel_abi + "_diff_executable_xml",
        ),
    )
