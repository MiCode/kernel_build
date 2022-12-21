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

"""Utilities for handling `--cache_dir`."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _get_step(ctx, common_config_tags):
    """Returns a step for caching the output directory.

    Args:
        ctx: ctx
        common_config_tags: from `kernel_env[KernelEnvAttrInfo]`

    Returns:
      A struct with these fields:

      * inputs
      * tools
      * cmd
      * outputs
      * post_cmd
    """

    # Use a local cache directory for ${OUT_DIR} so that, even when this _kernel_build
    # target needs to be rebuilt, we are using $OUT_DIR from previous invocations. This
    # boosts --config=local builds. See (b/235632059).
    cache_dir_cmd = ""
    post_cmd = ""
    inputs = []
    if ctx.attr._config_is_local[BuildSettingInfo].value:
        if not ctx.attr._cache_dir[BuildSettingInfo].value:
            fail("--config=local requires --cache_dir.")

        config_tags_json = json.encode_indent(common_config_tags, indent = "  ")
        config_tags_json_file = ctx.actions.declare_file("{}_config_tags/config_tags.json".format(ctx.label.name))
        ctx.actions.write(config_tags_json_file, config_tags_json)
        inputs.append(config_tags_json_file)

        cache_dir_cmd = """
              KLEAF_CACHED_COMMON_OUT_DIR={cache_dir}/${{OUT_DIR_SUFFIX}}
              KLEAF_CACHED_OUT_DIR=${{KLEAF_CACHED_COMMON_OUT_DIR}}/${{KERNEL_DIR}}
              (
                  mkdir -p "${{KLEAF_CACHED_OUT_DIR}}"
                  KLEAF_CONIFG_TAGS="${{KLEAF_CACHED_COMMON_OUT_DIR}}/kleaf_config_tags.json"

                  # {config_tags_json_file} is readonly. If ${{KLEAF_CONIFG_TAGS}} exists,
                  # it should be readonly too.
                  # If ${{KLEAF_CONIFG_TAGS}} exists, copying fails, and then we diff the file
                  # to ensure we aren't polluting the sandbox for something else.
                  if ! cp -p {config_tags_json_file} "${{KLEAF_CONIFG_TAGS}}" 2>/dev/null; then
                    if ! diff -q {config_tags_json_file} "${{KLEAF_CONIFG_TAGS}}"; then
                      echo "Collision detected in ${{KLEAF_CONIFG_TAGS}}" >&2
                      diff {config_tags_json_file} "${{KLEAF_CONIFG_TAGS}}" >&2
                      echo 'Run `tools/bazel clean` and try again. If the error persists, report a bug.' >&2
                      exit 1
                    fi
                  fi

                  # source/ and build/ are symlinks to the source tree and $OUT_DIR, respectively,
                  rsync -aL --exclude=source --exclude=build \\
                      "${{OUT_DIR}}/" "${{KLEAF_CACHED_OUT_DIR}}/"
                  rsync -al --include=source --include=build --exclude='*' \\
                      "${{OUT_DIR}}/" "${{KLEAF_CACHED_OUT_DIR}}/"
              )

              export OUT_DIR=${{KLEAF_CACHED_OUT_DIR}}
              unset KLEAF_CACHED_OUT_DIR
              unset KLEAF_CACHED_COMMON_OUT_DIR
        """.format(
            cache_dir = ctx.attr._cache_dir[BuildSettingInfo].value,
            config_tags_json_file = config_tags_json_file.path,
        )

        post_cmd = """
            ln -sf ${{OUT_DIR_SUFFIX}} {cache_dir}/last_build
        """.format(
            cache_dir = ctx.attr._cache_dir[BuildSettingInfo].value,
        )
    return struct(
        inputs = inputs,
        tools = [],
        cmd = cache_dir_cmd,
        outputs = [],
        post_cmd = post_cmd,
    )

cache_dir = struct(
    get_step = _get_step,
)
