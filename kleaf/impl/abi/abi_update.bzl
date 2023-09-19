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

"""When `bazel run`, updates an ABI definition."""

load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _abi_update_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    script = """
        # run_additional_setup keeps the original PATH to host tools at the
        # end of PATH. This is intentionally not hermetic and uses git
        # from the host machine.
        {semi_hermetic_setup}

        # nodiff_update is self-contained and hermetic.
        {nodiff_update}

        # Use the semi-hermetic environment to execute git commands
        # Create git commit if requested
        if [[ $1 == "--commit" ]]; then
            real_abi_def="$(realpath {abi_definition})"
            git -C $(dirname ${{real_abi_def}}) add $(basename ${{real_abi_def}})
            git -C $(dirname ${{real_abi_def}}) commit -F $(realpath {git_message})
        fi

        # Re-instate a hermetic environment
        {hermetic_setup}
        {diff}
        if [[ $1 == "--commit" ]]; then
            echo
            echo "INFO: git commit created. Execute the following to edit the commit message:"
            echo "        git -C $(dirname $(rootpath {abi_definition})) commit --amend"
        fi
    """.format(
        hermetic_setup = hermetic_tools.run_setup,
        semi_hermetic_setup = hermetic_tools.run_additional_setup,
        nodiff_update = ctx.executable.nodiff_update.short_path,
        abi_definition = ctx.file.abi_definition_stg.short_path,
        git_message = ctx.file.git_message.short_path,
        diff = ctx.executable.diff.short_path,
    )

    executable = ctx.actions.declare_file("{}.sh".format(ctx.attr.name))
    ctx.actions.write(executable, script, is_executable = True)

    runfiles = ctx.runfiles(files = [
        ctx.file.abi_definition_stg,
        ctx.file.git_message,
    ], transitive_files = hermetic_tools.deps)
    runfiles = runfiles.merge_all([
        ctx.attr.nodiff_update[DefaultInfo].default_runfiles,
        ctx.attr.diff[DefaultInfo].default_runfiles,
    ])

    return DefaultInfo(
        files = depset([executable]),
        executable = executable,
        runfiles = runfiles,
    )

abi_update = rule(
    implementation = _abi_update_impl,
    attrs = {
        "abi_definition_stg": attr.label(
            doc = "source ABI definition file",
            allow_single_file = True,
        ),
        "git_message": attr.label(
            doc = "git commit message",
            allow_single_file = True,
        ),
        "nodiff_update": attr.label(
            doc = "executable to update without showing diff result",
            executable = True,
            # Use target platform for the executable because the underlying
            # ABI definition abi_dump from kernel_build is built against the
            # target platform.
            cfg = "target",
        ),
        "diff": attr.label(
            doc = "show diff result",
            executable = True,
            # Use target platform for the executable because the underlying
            # ABI definition abi_dump from kernel_build is built against the
            # target platform.
            cfg = "target",
        ),
    },
    toolchains = [hermetic_toolchain.type],
    executable = True,
)
