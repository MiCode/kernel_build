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

"""Utility functions to handle scmversion."""

load(":status.bzl", "status")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _get_status_at_path(ctx, status_name, quoted_src_path):
    # {path}:{scmversion} {path}:{scmversion} ...

    cmd = """extract_git_metadata "$({stable_status_cmd})" {quoted_src_path}""".format(
        stable_status_cmd = status.get_stable_status_cmd(ctx, status_name),
        quoted_src_path = quoted_src_path,
    )
    return cmd

def _write_localversion_step(ctx, out_path):
    """Return command and inputs to set up scmversion.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
        out_path: output path of localversion file
    """

    # workspace_status.py does not prepend BRANCH and KMI_GENERATION before
    # STABLE_SCMVERSION because their values aren't known at that point.
    # Emulate the logic in setlocalversion to prepend them.

    if ctx.attr._config_is_stamp[BuildSettingInfo].value:
        deps = [ctx.info_file]
        stable_scmversion_cmd = _get_status_at_path(ctx, "STABLE_SCMVERSIONS", '"${KERNEL_DIR}"')
    else:
        deps = []
        stable_scmversion_cmd = "echo '-maybe-dirty'"

    # TODO(b/227520025): Remove the following logic in setlocalversion.
    cmd = """
        (
            # Extract the Android release version. If there is no match, then return 255
            # and clear the variable $android_release
            set +e
            if [[ "$BRANCH" == "android-mainline" ]]; then
                android_release="mainline"
            else
                android_release=$(echo "$BRANCH" | sed -e '/android[0-9]\\{{2,\\}}/!{{q255}}; s/^\\(android[0-9]\\{{2,\\}}\\)-.*/\\1/')
                if [[ $? -ne 0 ]]; then
                    android_release=
                fi
            fi
            set -e
            if [[ -n "$KMI_GENERATION" ]] && [[ $(expr $KMI_GENERATION : '^[0-9]\\+$') -eq 0 ]]; then
                echo "Invalid KMI_GENERATION $KMI_GENERATION" >&2
                exit 1
            fi
            scmversion=""
            stable_scmversion=$({stable_scmversion_cmd})
            if [[ -n "$stable_scmversion" ]]; then
                scmversion_prefix=
                if [[ -n "$android_release" ]] && [[ -n "$KMI_GENERATION" ]]; then
                    scmversion_prefix="-$android_release-$KMI_GENERATION"
                elif [[ -n "$android_release" ]]; then
                    scmversion_prefix="-$android_release"
                fi
                scmversion="${{scmversion_prefix}}${{stable_scmversion}}"
            fi
            echo $scmversion
        ) > {out_path}
    """.format(
        stable_scmversion_cmd = stable_scmversion_cmd,
        out_path = out_path,
    )
    return struct(deps = deps, cmd = cmd)

def _get_ext_mod_scmversion(ctx, ext_mod):
    """Return command and inputs to get the SCM version for an external module.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
        ext_mod: Defines the directory of the external module
    """
    if not ctx.attr._config_is_stamp[BuildSettingInfo].value:
        cmd = """
            rm -f ${OUT_DIR}/localversion
        """
        return struct(deps = [], cmd = cmd)

    scmversion_cmd = _get_status_at_path(ctx, "STABLE_SCMVERSIONS", shell.quote(ext_mod))

    cmd = """
        ( {scmversion_cmd} ) > ${{OUT_DIR}}/localversion
    """.format(scmversion_cmd = scmversion_cmd)

    return struct(deps = [ctx.info_file], cmd = cmd)

def _set_source_date_epoch(ctx):
    """Return command and inputs to set the value of `SOURCE_DATE_EPOCH`.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
    """
    if ctx.attr._config_is_stamp[BuildSettingInfo].value:
        return struct(deps = [ctx.info_file], cmd = """
              export SOURCE_DATE_EPOCH=$({source_date_epoch_cmd})
        """.format(source_date_epoch_cmd = status.get_stable_status_cmd(ctx, "STABLE_SOURCE_DATE_EPOCH")))
    else:
        return struct(deps = [], cmd = """
              export SOURCE_DATE_EPOCH=0
        """)

def _set_localversion_cmd(_ctx):
    """Return command that sets `LOCALVERSION` for `--config=stamp`, otherwise empty.

    After setting `LOCALVERSION`, `setlocalversion` script reduces code paths
    that executes `git`.
    """

    # Suppress the behavior of setlocalversion looking into .git directory to decide whether
    # to append a plus sign or not.
    return """
        export LOCALVERSION=""
    """

stamp = struct(
    write_localversion_step = _write_localversion_step,
    get_ext_mod_scmversion = _get_ext_mod_scmversion,
    set_source_date_epoch = _set_source_date_epoch,
    set_localversion_cmd = _set_localversion_cmd,
)
