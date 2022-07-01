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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@kernel_toolchain_info//:dict.bzl", "CLANG_VERSION")
load("//build/kernel/kleaf:hermetic_tools.bzl", "HermeticToolsInfo")
load(
    ":common_providers.bzl",
    "KernelEnvAttrInfo",
    "KernelEnvInfo",
)
load(":debug.bzl", "debug")
load(":kernel_dtstree.bzl", "DtstreeInfo")
load(":stamp.bzl", "stamp")
load(":status.bzl", "status")
load(":utils.bzl", "utils")

def _sanitize_label_as_filename(label):
    """Sanitize a Bazel label so it is safe to be used as a filename."""
    label_text = str(label)
    return "".join([c if c.isalnum() else "_" for c in label_text.elems()])

def _get_kbuild_symtypes(ctx):
    if ctx.attr.kbuild_symtypes == "auto":
        return ctx.attr._kbuild_symtypes_flag[BuildSettingInfo].value
    elif ctx.attr.kbuild_symtypes == "true":
        return True
    elif ctx.attr.kbuild_symtypes == "false":
        return False

    # Should not reach
    fail("{}: kernel_env has unknown value for kbuild_symtypes: {}".format(ctx.attr.label, ctx.attr.kbuild_symtypes))

def _kernel_env_impl(ctx):
    if ctx.attr._config_is_local[BuildSettingInfo].value and ctx.attr._config_is_stamp[BuildSettingInfo].value:
        fail("--config=local cannot be set with --config=stamp. " +
             "SCM version cannot be embedded without sandboxing. " +
             "See build/kernel/kleaf/sandbox.md.")

    srcs = [
        s
        for s in ctx.files.srcs
        if "/build.config" in s.path or s.path.startswith("build.config")
    ]

    build_config = ctx.file.build_config
    kconfig_ext = ctx.file.kconfig_ext
    dtstree_makefile = None
    dtstree_srcs = []
    if ctx.attr.dtstree != None:
        dtstree_makefile = ctx.attr.dtstree[DtstreeInfo].makefile
        dtstree_srcs = ctx.attr.dtstree[DtstreeInfo].srcs

    setup_env = ctx.file.setup_env
    preserve_env = ctx.file.preserve_env
    out_file = ctx.actions.declare_file("%s.sh" % ctx.attr.name)

    inputs = [
        ctx.file._build_utils_sh,
        build_config,
        setup_env,
        preserve_env,
    ]
    inputs += srcs
    inputs += ctx.attr._hermetic_tools[HermeticToolsInfo].deps

    command = ""
    command += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += debug.trap()

    if kconfig_ext:
        command += """
              export KCONFIG_EXT={kconfig_ext}
            """.format(
            kconfig_ext = kconfig_ext.short_path,
        )
    if dtstree_makefile:
        command += """
              export DTSTREE_MAKEFILE={dtstree}
            """.format(
            dtstree = dtstree_makefile.short_path,
        )

    command += """
        # error on failures
          set -e
          set -o pipefail
    """

    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        command += """
          export MAKEFLAGS="${MAKEFLAGS} V=1"
        """
    else:
        command += """
        # Run Make in silence mode to suppress most of the info output
          export MAKEFLAGS="${MAKEFLAGS} -s"
        """

    kbuild_symtypes = _get_kbuild_symtypes(ctx)
    command += """
        export KBUILD_SYMTYPES={}
    """.format("1" if kbuild_symtypes else "")

    # If multiple targets have the same KERNEL_DIR are built simultaneously
    # with --spawn_strategy=local, try to isolate their OUT_DIRs.
    command += """
          export OUT_DIR_SUFFIX={name}
    """.format(name = _sanitize_label_as_filename(ctx.label).removesuffix("_env"))

    set_source_date_epoch_ret = stamp.set_source_date_epoch(ctx)
    command += set_source_date_epoch_ret.cmd
    inputs += set_source_date_epoch_ret.deps

    command += stamp.set_localversion_cmd(ctx)

    command += """
        # create a build environment
          source {build_utils_sh}
          export BUILD_CONFIG={build_config}
          source {setup_env}
        # capture it as a file to be sourced in downstream rules
          {preserve_env} > {out}
        """.format(
        build_utils_sh = ctx.file._build_utils_sh.path,
        build_config = build_config.path,
        setup_env = setup_env.path,
        preserve_env = preserve_env.path,
        out = out_file.path,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelEnv",
        inputs = inputs,
        outputs = [out_file],
        progress_message = "Creating build environment for %s" % ctx.attr.name,
        command = command,
    )

    setup = ""
    setup += ctx.attr._hermetic_tools[HermeticToolsInfo].setup
    if ctx.attr._debug_annotate_scripts[BuildSettingInfo].value:
        setup += debug.trap()

    set_up_jobs_cmd = """
        # Increase parallelism # TODO(b/192655643): do not use -j anymore
          export MAKEFLAGS="${{MAKEFLAGS}} -j$(
            make_jobs="$({get_make_jobs_cmd})"
            if [[ -n "$make_jobs" ]]; then
              echo "$make_jobs"
            else
              nproc
            fi
          )"
    """.format(
        get_make_jobs_cmd = status.get_volatile_status_cmd(ctx, "MAKE_JOBS"),
    )

    dependencies = []
    set_up_scmversion_ret = stamp.set_up_scmversion(ctx)
    dependencies += set_up_scmversion_ret.deps

    setup += """
         # error on failures
           set -e
           set -o pipefail
         # utility functions
           source {build_utils_sh}
         # source the build environment
           source {env}
           {set_up_jobs_cmd}
         # re-setup the PATH to also include the hermetic tools, because env completely overwrites
         # PATH with HERMETIC_TOOLCHAIN=1
           {hermetic_tools_additional_setup}
         # setup LD_LIBRARY_PATH for prebuilts
           export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${{ROOT_DIR}}/{linux_x86_libs_path}
           {set_up_scmversion_cmd}
         # Set up KCONFIG_EXT
           if [ -n "${{KCONFIG_EXT}}" ]; then
             export KCONFIG_EXT_PREFIX=$(rel_path $(realpath $(dirname ${{KCONFIG_EXT}})) ${{ROOT_DIR}}/${{KERNEL_DIR}})/
           fi
           if [ -n "${{DTSTREE_MAKEFILE}}" ]; then
             export dtstree=$(rel_path $(realpath $(dirname ${{DTSTREE_MAKEFILE}})) ${{ROOT_DIR}}/${{KERNEL_DIR}})
           fi
         # Set up KCPPFLAGS
         # For Kleaf local (non-sandbox) builds, $ROOT_DIR is under execroot but
         # $ROOT_DIR/$KERNEL_DIR is a symlink to the real source tree under
         # workspace root, making $abs_srctree not under $ROOT_DIR.
           if [[ "$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}})" != "${{ROOT_DIR}}/${{KERNEL_DIR}}" ]]; then
             export KCPPFLAGS="$KCPPFLAGS -ffile-prefix-map=$(realpath ${{ROOT_DIR}}/${{KERNEL_DIR}})/="
           fi
           """.format(
        hermetic_tools_additional_setup = ctx.attr._hermetic_tools[HermeticToolsInfo].additional_setup,
        env = out_file.path,
        build_utils_sh = ctx.file._build_utils_sh.path,
        linux_x86_libs_path = ctx.files._linux_x86_libs[0].dirname,
        set_up_scmversion_cmd = set_up_scmversion_ret.cmd,
        set_up_jobs_cmd = set_up_jobs_cmd,
    )

    dependencies += ctx.files._tools + ctx.attr._hermetic_tools[HermeticToolsInfo].deps
    dependencies += [
        out_file,
        ctx.file._build_utils_sh,
        ctx.version_file,
    ]
    if kconfig_ext:
        dependencies.append(kconfig_ext)
    dependencies += dtstree_srcs
    return [
        KernelEnvInfo(
            dependencies = dependencies,
            setup = setup,
        ),
        KernelEnvAttrInfo(
            kbuild_symtypes = kbuild_symtypes,
        ),
        DefaultInfo(files = depset([out_file])),
    ]

def _get_tools(toolchain_version):
    return [
        Label(e)
        for e in (
            "//build/kernel:kernel-build-scripts",
            "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
        )
    ]

kernel_env = rule(
    implementation = _kernel_env_impl,
    doc = """Generates a rule that generates a source-able build environment.

          A build environment is defined by a single entry build config file
          that can refer to further build config files.

          Example:
          ```
              kernel_env(
                  name = "kernel_aarch64_env,
                  build_config = "build.config.gki.aarch64",
                  srcs = glob(["build.config.*"]),
              )
          ```
          """,
    attrs = {
        "build_config": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "label referring to the main build config",
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            doc = """labels that this build config refers to, including itself.
            E.g. ["build.config.gki.aarch64", "build.config.gki"]""",
        ),
        "setup_env": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:_setup_env.sh"),
            doc = "label referring to _setup_env.sh",
        ),
        "preserve_env": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel/kleaf:preserve_env.sh"),
            doc = "label referring to the script capturing the environment",
        ),
        "toolchain_version": attr.string(
            doc = "the toolchain to use for this environment",
            default = CLANG_VERSION,
        ),
        "kconfig_ext": attr.label(
            allow_single_file = True,
            doc = "an external Kconfig.ext file sourced by the base kernel",
        ),
        "dtstree": attr.label(
            providers = [DtstreeInfo],
            doc = "Device tree",
        ),
        "kbuild_symtypes": attr.string(
            doc = "`KBUILD_SYMTYPES`",
            default = "auto",
            values = ["true", "false", "auto"],
        ),
        "_tools": attr.label_list(default = _get_tools),
        "_hermetic_tools": attr.label(default = "//build/kernel:hermetic-tools", providers = [HermeticToolsInfo]),
        "_build_utils_sh": attr.label(
            allow_single_file = True,
            default = Label("//build/kernel:build_utils.sh"),
        ),
        "_debug_annotate_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_annotate_scripts",
        ),
        "_config_is_local": attr.label(default = "//build/kernel/kleaf:config_local"),
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_kbuild_symtypes_flag": attr.label(default = "//build/kernel/kleaf:kbuild_symtypes"),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
        "_linux_x86_libs": attr.label(default = "//prebuilts/kernel-build-tools:linux-x86-libs"),
    },
)
