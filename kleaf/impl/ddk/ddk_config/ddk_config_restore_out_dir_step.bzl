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

"""Step that restores out_dir from a ddk_config/ddk_module_config."""

load(
    ":common_providers.bzl",
    "StepInfo",
)

visibility("//build/kernel/kleaf/impl/...")

def _ddk_config_restore_out_dir_step_impl(
        _subrule_ctx,
        out_dir):
    if not out_dir:
        return StepInfo(
            inputs = depset(),
            cmd = "",
            tools = [],
            outputs = [],
        )
    cmd = """
        rsync -aL {out_dir}/.config ${{OUT_DIR}}/.config

        if [[ "${{kleaf_do_not_rsync_out_dir_include}}" == "1" ]]; then
            kleaf_out_dir_include_candidate="{out_dir}/include/"
        else
            rsync -aL --chmod=D+w {out_dir}/include/ ${{OUT_DIR}}/include/
            # Restore real value of $ROOT_DIR in auto.conf.cmd
            sed -i'' -e 's:${{ROOT_DIR}}:'"${{ROOT_DIR}}"':g' ${{OUT_DIR}}/include/config/auto.conf.cmd
        fi
    """.format(
        out_dir = out_dir.path,
    )
    return StepInfo(
        inputs = depset([out_dir]),
        cmd = cmd,
        tools = [],
        outputs = [],
    )

ddk_config_restore_out_dir_step = subrule(implementation = _ddk_config_restore_out_dir_step_impl)
