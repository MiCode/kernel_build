# Copyright (C) 2021 The Android Open Source Project
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

def kernel_build(
        name,
        build_config,
        build_configs,
        sources,
        outs,
        toolchain_version = "r416183b",
        **kwargs):
    """Defines a kernel build target with all dependent targets.

        It uses a build_config to construct a deterministic build environment
        (e.g. 'common/build.config.gki.aarch64'). The included build_configs
        needs to be declared via build_configs (e.g. using a filegroup). The
        kernel sources need to be declared via sources (e.g. using a
        filegroup). outs declares the output files that are surviving the
        build. The effective output file names will be $(name)/$(output_file).
        Any other artifact is not guaranteed to be accessible after the rule
        has run. The default toolchain_version is defined with a sensible
        default, but can be overriden.

    Args:
        name: the final kernel target name
        build_config: the main build_config file
        build_configs: dependent build_configs (a target)
        sources: the kernel sources (a target)
        outs: the expected output files
        toolchain_version: the toolchain version to depend on
    """
    env_target = name + "_env"
    _env(env_target, build_config, build_configs, **kwargs)
    _kernel_build(name, env_target, sources, outs, toolchain_version, **kwargs)

def _env(name, build_config, build_configs, **kwargs):
    """Generates a rule that generates a source-able build environment."""
    native.genrule(
        name = name,
        srcs = [
            build_configs,
        ],
        tools = [
            "//build:_setup_env.sh",
            "//build/kleaf:preserve_env.sh",
        ],
        outs = [name + ".sh"],
        cmd = """
            # do not fail upon unset variables being read
              set +u
            # create a build environment
              export BUILD_CONFIG=%s
              source $(location //build:_setup_env.sh)
            # capture it as a file to be sourced in downstream rules
              $(location //build/kleaf:preserve_env.sh) > $@
            """ % build_config,
        **kwargs
    )

def _kernel_build(name, env, sources, outs, toolchain_version, **kwargs):
    """Generates a kernel build rule."""
    native.genrule(
        name = name,
        srcs = [
            sources,
        ],
        tools = [
            env,
            "//build:kernel-build-scripts",
            "//build:host-tools",
            "//prebuilts/clang/host/linux-x86/clang-%s:binaries" % toolchain_version,
            "//prebuilts/build-tools:linux-x86",
            "//prebuilts/kernel-build-tools:linux-x86",
        ],
        outs = [name + "/" + file for file in outs],  # e.g. kernel_aarch64/vmlinux
        cmd =
            # source the build environment
            "   source $(location %s)" % env +
            # setup the PATH to also include the host tools
            "\n export PATH=$$PATH:$$PWD/$$(dirname $$( echo $(locations //build:host-tools) | tr ' ' '\n' | head -n 1 ) )" +
            # invoke the actual build redirecting outputs to the output dir
            "\n DIST_DIR=$$PWD/$$(dirname $(location %s/vmlinux)) build/build.sh 2>&1" % name,
        message = "Building kernel",
        **kwargs
    )
