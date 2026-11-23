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

"""A central location for the list of [config settings](https://bazel.build/extending/config) that
affects the following:

- kernel_build
- kernel_config

This is important for non-sandboxed actions because they may cause clashing in the out/cache
directory.

Only *_flag / *_settings / attributes that affects the content of the cached $OUT_DIR should be
mentioned here. In particular:
- --config=stamp is not in these lists because we don't have two parallel builds
  with and without --config=stamp, and we should reuse the same cache for stamped / un-stamped
  builds.
- --allow_undeclared_modules is not listed because it only affects artifact collection.
- --preserve_cmd is not listed because it only affects artifact collection.
- The following is not listed because it is already handled by defconfig_fragments. See
  kernel_env.bzl, _handle_config_tags:
  - btf_debug_info
  - gcov
  - kcov
  - lto (b/257288175)
  - trim_nonlisted_kmi

"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":abi/base_kernel_utils.bzl", "base_kernel_utils")
load(":abi/force_add_vmlinux_utils.bzl", "force_add_vmlinux_utils")
load(":compile_commands_utils.bzl", "compile_commands_utils")
load(":kernel_toolchains_utils.bzl", "kernel_toolchains_utils")
load(":kgdb.bzl", "kgdb")

visibility("//build/kernel/kleaf/...")

def _kernel_build_config_settings_raw():
    return dicts.add(
        force_add_vmlinux_utils.config_settings_raw(),
        base_kernel_utils.config_settings_raw(),
        kgdb.config_settings_raw(),
        compile_commands_utils.config_settings_raw(),
        {
            "_use_kmi_symbol_list_strict_mode": "//build/kernel/kleaf:kmi_symbol_list_strict_mode",
            "_debug": "//build/kernel/kleaf:debug",
            "_kasan": "//build/kernel/kleaf:kasan",
            "_kasan_sw_tags": "//build/kernel/kleaf:kasan_sw_tags",
            "_kasan_generic": "//build/kernel/kleaf:kasan_generic",
            "_kcov": "//build/kernel/kleaf:kcov",
            "_kcsan": "//build/kernel/kleaf:kcsan",
            "_preserve_kbuild_output": "//build/kernel/kleaf:preserve_kbuild_output",
        },
    )

def _kernel_build_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_build_config_settings_raw().items()
    }

def _kernel_config_config_settings_raw():
    return kgdb.config_settings_raw()

def _kernel_config_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_config_config_settings_raw().items()
    }

def _kernel_env_config_settings_raw():
    return dicts.add(
        _kernel_build_config_settings_raw(),
        _kernel_config_config_settings_raw(),
        force_add_vmlinux_utils.config_settings_raw(),
        kgdb.config_settings_raw(),
        compile_commands_utils.config_settings_raw(),
        {
            "_kbuild_symtypes_flag": "//build/kernel/kleaf:kbuild_symtypes",
            "_kconfig_werror": "//build/kernel/kleaf:kconfig_werror",
        },
    )

def _kernel_env_config_settings():
    return {
        attr_name: attr.label(default = label)
        for attr_name, label in _kernel_env_config_settings_raw().items()
    }

def _kernel_env_get_config_tags(
        ctx,
        mnemonic_prefix,
        pre_defconfig_fragments,
        post_defconfig_fragments):
    """Return necessary files for KernelEnvAttrInfo's fields related to "config tags"

    config_tags is the mechanism to isolate --cache_dir.

    Requires `ctx.attr._cache_dir_config_tags`.

    Args:
        ctx: ctx
        mnemonic_prefix: prefix to mnemonics for actions created within this function.
        pre_defconfig_fragments: a `list[File]` of pre defconfig fragments.
        post_defconfig_fragments: a `list[File]` of post defconfig fragments.

    Returns:
        A struct with two fields:

        - common: A File that contains a JSON object containing build configurations
          and defconfig fragments.
        - env: A File that contains comments about build configurations
          defconfig fragments, and the target name, for `kernel_env` output.
    """

    # base: just all the different config settings
    base_config_tags = _kernel_env_get_base_config_tags(ctx)
    base_config_tags_file = ctx.actions.declare_file("{}/base_config_tags.json".format(ctx.label.name))
    ctx.actions.write(base_config_tags_file, json.encode_indent(base_config_tags, indent = "    "))

    # common: base + post_defconfig_fragments
    common_config_tags_file = ctx.actions.declare_file("{}/common_config_tags.json".format(ctx.label.name))
    args = ctx.actions.args()
    args.add("--base", base_config_tags_file)
    if pre_defconfig_fragments:
        args.add_all("--pre_defconfig_fragments", pre_defconfig_fragments)
    if post_defconfig_fragments:
        args.add_all("--post_defconfig_fragments", post_defconfig_fragments)
    args.add("--dest", common_config_tags_file)
    ctx.actions.run(
        outputs = [common_config_tags_file],
        inputs = depset([base_config_tags_file], transitive = [depset(post_defconfig_fragments)]),
        executable = ctx.executable._cache_dir_config_tags,
        arguments = [args],
        mnemonic = "{}CommonConfigTags".format(mnemonic_prefix),
        progress_message = "Creating common_config_tags %{label}",
    )

    # env: common + label of this kernel_env, prefixed with #
    env_config_tags_file = ctx.actions.declare_file("{}/config_tags.txt".format(ctx.label.name))
    args = ctx.actions.args()
    args.add("--base", common_config_tags_file)
    args.add("--target", str(ctx.label))
    args.add("--dest", env_config_tags_file)
    args.add("--comment")
    ctx.actions.run(
        outputs = [env_config_tags_file],
        inputs = [common_config_tags_file],
        executable = ctx.executable._cache_dir_config_tags,
        arguments = [args],
        mnemonic = "{}ConfigTags".format(mnemonic_prefix),
        progress_message = "Creating config_tags %{label}",
    )

    return struct(
        common = common_config_tags_file,
        env = env_config_tags_file,
    )

def _kernel_env_get_base_config_tags(ctx):
    """Returns dict to compute `OUT_DIR_SUFFIX` for `kernel_env`."""
    attr_to_label = _kernel_env_config_settings_raw()

    ret = {}
    for attr_name in attr_to_label:
        attr_target = getattr(ctx.attr, attr_name)
        attr_val = attr_target[BuildSettingInfo].value
        ret[str(attr_target.label)] = attr_val

    toolchains = kernel_toolchains_utils.get(ctx)
    ret["toolchain_host_sysroot"] = toolchains.host_sysroot

    return ret

# Map of config settings to shortened names
_PROGRESS_MESSAGE_SETTINGS_MAP = {
    "force_add_vmlinux": "with_vmlinux",
    "force_ignore_base_kernel": "",  # already covered by with_vmlinux or build_compile_commands
    "kmi_symbol_list_strict_mode": "",  # Hide because not interesting
}

def _create_progress_message_item(attr_key, attr_val, map):
    print_attr_key = map.get(attr_key, attr_key)

    # In _SETTINGS_MAP but value is set to empty to ignore it
    if not print_attr_key:
        return None

    # Empty values that are not interesting enough are dropped
    if not attr_val:
        return None
    if attr_val == True:
        return print_attr_key
    elif attr_val == False:
        return "no{}".format(print_attr_key)
    else:
        return "{}={}".format(print_attr_key, attr_val)

def _get_progress_message_note(
        ctx,
        pre_defconfig_fragments,
        post_defconfig_fragments):
    """Returns a description text for progress message.

    This is a shortened and human-readable version of `kernel_env_get_config_tags`.

    Args:
        ctx: ctx
        pre_defconfig_fragments: a `list[File]` of pre defconfig fragments.
        post_defconfig_fragments: a `list[File]` of post defconfig fragments.

    Returns:
        A string to be added to the end of `progress_message`
    """
    attr_to_label = _kernel_env_config_settings_raw()

    ret = []
    for attr_name in attr_to_label:
        attr_target = getattr(ctx.attr, attr_name)
        attr_label_name = attr_target.label.name
        attr_val = attr_target[BuildSettingInfo].value
        item = _create_progress_message_item(
            attr_label_name,
            attr_val,
            _PROGRESS_MESSAGE_SETTINGS_MAP,
        )
        if not item:
            continue
        ret.append(item)

    # Files under build/kernel/kleaf/impl/defconfig are named as *_defconfig.
    # For progress_messsage, we only care about the part before _defconfig.
    # See kernel_build.pre_defconfig_fragments and
    # kernel_build.post_defconfig_fragments documentation.
    for file in pre_defconfig_fragments + post_defconfig_fragments:
        ret.append(file.basename.removesuffix("_defconfig"))

    ret = sorted(sets.to_list(sets.make(ret)))
    ret = ";".join(ret)
    if ret:
        ret = " ({})".format(ret)
    return ret

kernel_config_settings = struct(
    of_kernel_build = _kernel_build_config_settings,
    of_kernel_config = _kernel_config_config_settings,
    of_kernel_env = _kernel_env_config_settings,
    kernel_env_get_config_tags = _kernel_env_get_config_tags,
    get_progress_message_note = _get_progress_message_note,
)
