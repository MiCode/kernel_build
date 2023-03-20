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
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _get_scmversion_cmd(srctree, scmversion):
    """Return a shell script that sets up .scmversion file in the source tree conditionally.

    Args:
      srctree: Path to the source tree where `setlocalversion` were supposed to run with.
      scmversion: The result of executing `setlocalversion` if it were executed on `srctree`.
    """
    return """
         # Set up scm version
           (
              # Save scmversion to .scmversion if .scmversion does not already exist.
              # If it does exist, then it is part of "srcs", so respect its value.
              # If .git exists, we are not in sandbox. _kernel_config disables
              # CONFIG_LOCALVERSION_AUTO in this case.
              if [[ ! -d {srctree}/.git ]] && [[ ! -f {srctree}/.scmversion ]]; then
                scmversion={scmversion}
                if [[ -n "${{scmversion}}" ]]; then
                    mkdir -p {srctree}
                    echo $scmversion > {srctree}/.scmversion
                fi
              fi
           )
""".format(
        srctree = srctree,
        scmversion = scmversion,
    )

def _get_localversion(ctx):
    """Return command and inputs to set up scmversion.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
    """

    # workspace_status.py does not prepend BRANCH and KMI_GENERATION before
    # STABLE_SCMVERSION because their values aren't known at that point.
    # Emulate the logic in setlocalversion to prepend them.

    if ctx.attr._config_is_stamp[BuildSettingInfo].value:
        deps = [ctx.info_file]
        stable_scmversion_cmd = status.get_stable_status_cmd(ctx, "STABLE_SCMVERSION")
    else:
        deps = []
        stable_scmversion_cmd = "echo '-maybe-dirty'"

    # TODO(b/227520025): Remove the following logic in setlocalversion.
    cmd = """$(
            # On mainline, CONFIG_LOCALVERSION is set to "-mainline". Use that.
            existing_localversion=$(${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config -s LOCALVERSION)
            if [[ -n ${{existing_localversion}} ]] && \
               [[ ${{existing_localversion}} != "n" ]] && \
               [[ ${{existing_localversion}} != "undef" ]]; then
               echo -n ${{existing_localversion}}
            fi

            # Extract the Android release version. If there is no match, then return 255
            # and clear the variable $android_release
            set +e
            android_release=$(echo "$BRANCH" | sed -e '/android[0-9]\\{{2,\\}}/!{{q255}}; s/^\\(android[0-9]\\{{2,\\}}\\)-.*/\\1/')
            if [[ $? -ne 0 ]]; then
                android_release=
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
        )
    """.format(
        stable_scmversion_cmd = stable_scmversion_cmd,
        setup_cmd = _get_scmversion_cmd(
            srctree = "${ROOT_DIR}/${KERNEL_DIR}",
            scmversion = "${scmversion}",
        ),
    )
    return struct(deps = deps, cmd = cmd)

def _scmversion_config_step(ctx):
    """Return a command for `kernel_config` to set `CONFIG_LOCALVERSION_AUTO` and `CONFIG_LOCALVERSION` properly.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
    """

    localversion_ret = _get_localversion(ctx)

    # Disable CONFIG_LOCALVERSION_AUTO to prevent the setlocalversion script looking into .git. Then
    # set CONFIG_LOCALVERSION to the full value.
    cmd = """
        (
            localversion={localversion_cmd}
            ${{KERNEL_DIR}}/scripts/config --file ${{OUT_DIR}}/.config \
                -d LOCALVERSION_AUTO \
                --set-str LOCALVERSION ${{localversion}}
        )

        make -C ${{KERNEL_DIR}} ${{TOOL_ARGS}} O=${{OUT_DIR}} olddefconfig
    """.format(
        localversion_cmd = localversion_ret.cmd,
    )
    return struct(
        cmd = cmd,
        deps = localversion_ret.deps,
    )

def _get_ext_mod_scmversion(ctx, ext_mod):
    """Return command and inputs to get the SCM version for an external module.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
        ext_mod: Defines the directory of the external module
    """
    if not ctx.attr._config_is_stamp[BuildSettingInfo].value:
        return struct(deps = [], cmd = "")

    # {ext_mod}:{scmversion} {ext_mod}:{scmversion} ...
    scmversion_cmd = status.get_stable_status_cmd(ctx, "STABLE_SCMVERSION_EXT_MOD")
    scmversion_cmd += """ | sed -n 's|.*\\<{ext_mod}:\\(\\S\\+\\).*|\\1|p'""".format(ext_mod = ext_mod)

    # workspace_status.py does not set STABLE_SCMVERSION if setlocalversion
    # should not run on KERNEL_DIR. However, for STABLE_SCMVERSION_EXT_MOD,
    # we may have a missing item if setlocalversion should not run in
    # a certain directory. Hence, be lenient about failures.
    scmversion_cmd += " || true"

    return struct(deps = [ctx.info_file], cmd = _get_scmversion_cmd(
        srctree = "${{ROOT_DIR}}/{ext_mod}".format(ext_mod = ext_mod),
        scmversion = "$({})".format(scmversion_cmd),
    ))

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
    scmversion_config_step = _scmversion_config_step,
    get_ext_mod_scmversion = _get_ext_mod_scmversion,
    set_source_date_epoch = _set_source_date_epoch,
    set_localversion_cmd = _set_localversion_cmd,
)
