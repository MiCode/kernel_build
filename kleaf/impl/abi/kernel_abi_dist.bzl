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

load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load(":abi/abi_stgdiff.bzl", "STGDIFF_CHANGE_CODE")
load(":abi/abi_transitions.bzl", "abi_common_attrs", "with_vmlinux_transition")

visibility("//build/kernel/kleaf/...")

# buildifier: disable=unused-variable
def kernel_abi_dist(
        name,
        kernel_abi,
        kernel_build_add_vmlinux = None,
        ignore_diff = None,
        no_ignore_diff_target = None,
        **kwargs):
    """This macro is no longer supported. Invoking this macro triggers an error.

    Args:
      name: ignored
      kernel_abi: ignored
      kernel_build_add_vmlinux: ignored
      ignore_diff: ignored
      no_ignore_diff_target: ignored
      **kwargs: ignored

    Deprecated:
        Use [`kernel_abi_wrapped_dist`](#kernel_abi_wrapped_dist) instead.
    """

    # buildifier: disable=print
    fail("""{}: kernel_abi_dist is deprecated. use kernel_abi_wrapped_dist instead.
    See build/kernel/kleaf/docs/impl.md for creating pkg_files/pkg_install targets.
    See build/kernel/kleaf/docs/api_reference/kernel.md for using the
    kernel_abi_wrapped_dist macro.""".format(
        native.package_relative_label(name),
    ))

def kernel_abi_wrapped_dist(
        name,
        dist,
        kernel_abi,
        ignore_diff = None,
        no_ignore_diff_target = None,
        **kwargs):
    """A wrapper over `dist` for [`kernel_abi`](#kernel_abi).

    After calling the `dist`, return the exit code from `diff_abi`.

    Example:

    ```
    kernel_build(
        name = "tuna",
        base_kernel = "//common:kernel_aarch64",
        ...
    )
    kernel_abi(name = "tuna_abi", ...)
    pkg_files(
        name = "tuna_abi_dist_internal_files",
        srcs = [
            ":tuna",
            # "//common:kernel_aarch64", # remove GKI
            ":tuna_abi", ...             # Add kernel_abi to pkg_files
        ],
        strip_prefix = strip_prefix.files_only(),
        visibility = ["//visibility:private"],
    )
    pkg_install(
        name = "tuna_abi_dist_internal",
        srcs = [":tuna_abi_dist_internal_files"],
        visibility = ["//visibility:private"],
    )
    kernel_abi_wrapped_dist(
        name = "tuna_abi_dist",
        dist = ":tuna_abi_dist_internal",
        kernel_abi = ":tuna_abi",
    )
    ```

    **Implementation notes**:

    `with_vmlinux_transition` is applied on all targets by default. In
    particular, the `kernel_build` targets in `data` automatically builds
    `vmlinux` regardless of whether `vmlinux` is specified in `outs`.

    Args:
        name: name of the ABI dist target
        dist: The actual dist target (usually a `pkg_install`).

            Note: This dist target should include `kernel_abi` in `pkg_files`
            that the `pkg_install` installs, e.g.

            ```
            kernel_abi(name = "tuna_abi", ...)
            pkg_files(
                name = "tuna_abi_dist_files",
                srcs = [":tuna_abi", ...], # Add kernel_abi to pkg_files()
                # ...
            )
            pkg_install(
                name = "tuna_abi_dist_internal",
                srcs = [":tuna_abi_dist_files"],
                # ...
            )
            kernel_abi_wrapped_dist(
                name = "tuna_abi_dist",
                dist = ":tuna_abi_dist_internal",
                # ...
            )
            ```
        kernel_abi: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            name of the [`kernel_abi`](#kernel_abi) invocation.
        ignore_diff: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            If `True` and the return code of `stgdiff` signals the ABI difference,
            then the result is ignored.
        no_ignore_diff_target: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            If `ignore_diff` is `True`, this need to be set to a name of the target
            that doesn't have `ignore_diff`. This target will be recommended as an
            alternative to a user. If `no_ignore_diff_target` is None, there will
            be no alternative recommended.
        **kwargs: Additional attributes to the internal rule, e.g.
            [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
            See complete list
            [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    # TODO(b/231647455): Clean up hard-coded name "_abi_diff_executable".

    kernel_abi_wrapped_dist_internal(
        name = name,
        dist = dist,
        diff_stg = kernel_abi + "_diff_executable",
        ignore_diff = ignore_diff,
        no_ignore_diff_target = no_ignore_diff_target,
        enable_add_vmlinux = True,
        **kwargs
    )

def _kernel_abi_wrapped_dist_internal_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    script = hermetic_tools.setup + """
        # Copy to dist dir
        {dist} "$@"
    """.format(dist = ctx.executable.dist.short_path)

    if not ctx.attr.ignore_diff:
        script += """
            # Check return code of diff_abi and kmi_enforced
            {diff_stg}
        """.format(diff_stg = ctx.executable.diff_stg.short_path)
    else:
        no_ignore_diff_target_script = ""
        if ctx.attr.no_ignore_diff_target != None:
            no_ignore_diff_target_script = """
                echo "WARNING: Use 'tools/bazel run {label}' to see and fail on ABI difference." >&2
            """.format(
                label = ctx.attr.no_ignore_diff_target.label,
            )
        script += """
          # Store return code of diff_abi and ignore if diff was found
            rc=0
            {diff_stg} > /dev/null 2>&1 || rc=$?

            if [[ $rc -eq {change_code} ]]; then
                echo "WARNING: ABI DIFFERENCES HAVE BEEN DETECTED!" >&2
                {no_ignore_diff_target_script}
            else
                exit $rc
            fi
        """.format(
            diff_stg = ctx.executable.diff_stg.short_path,
            change_code = STGDIFF_CHANGE_CODE,
            no_ignore_diff_target_script = no_ignore_diff_target_script,
        )

    script_file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(script_file, script)

    runfiles = ctx.runfiles(files = [
        script_file,
        ctx.executable.diff_stg,
        ctx.executable.dist,
    ], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge_all([
        ctx.attr.dist[DefaultInfo].default_runfiles,
        ctx.attr.diff_stg[DefaultInfo].default_runfiles,
    ])
    return DefaultInfo(
        files = depset([script_file]),
        runfiles = runfiles,
        executable = script_file,
    )

kernel_abi_wrapped_dist_internal = rule(
    doc = """Common implementation for wrapping a dist target to maybe also run diff_stg.""",
    implementation = _kernel_abi_wrapped_dist_internal_impl,
    attrs = {
        "dist": attr.label(
            mandatory = True,
            executable = True,
            # Do not apply exec transition here to avoid building the kernel as a tool.
            cfg = "target",
        ),
        "diff_stg": attr.label(
            mandatory = True,
            executable = True,
            # Do not apply exec transition here to avoid building the kernel as a tool.
            cfg = "target",
        ),
        "ignore_diff": attr.bool(),
        "no_ignore_diff_target": attr.label(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | abi_common_attrs(),
    cfg = with_vmlinux_transition,
    toolchains = [hermetic_toolchain.type],
    executable = True,
)
