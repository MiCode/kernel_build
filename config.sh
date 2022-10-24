#!/usr/bin/env bash

# Usage:
#   build/config.sh <config editor> <make options>*
#
# Example:
#   build/config.sh menuconfig|config|nconfig|... (default to menuconfig)
#
# Runs a configuration editor inside kernel/build environment.
#
# In addition to the environment variables considered in build/build.sh, the
# the following can be defined:
#
#   FRAGMENT_CONFIG
#     If set, the FRAGMENT_CONFIG file (absolute or relative to ROOT_DIR) is
#     updated with the options selected by the config editor.
#
# Note: When editing a FRAGMENT_CONFIG, config.sh is intentionally
#       unintelligent about removing "redundant" configuration options. That is,
#       setting CONFIG_ARM_SMMU=m using config.sh, then unsetting it would
#       result in a fragment config with CONFIG_ARM_SMMU explicitly unset.
#       This behavior is desired since it is unknown whether the base
#       configuration without the fragment would have CONFIG_ARM_SMMU (un)set.
#       If desire is to let the base configuration properly control a CONFIG_
#       option, then remove the line from FRAGMENT_CONFIG

export ROOT_DIR=$($(dirname $(readlink -f $0))/gettop.sh)

# Disable hermetic toolchain for ncurses
# TODO: Support hermetic toolchain with ncurses menuconfig, xconfig
HERMETIC_TOOLCHAIN=0

set -e
set -a
source "${ROOT_DIR}/build/_setup_env.sh"
set -a

# Disable mixed build
GKI_BUILD_CONFIG=

menucommand="${1:-menuconfig}"
MAKE_ARGS="${@:2}"

if [[ "${menucommand}" =~ "*config" ]]; then
  MAKE_ARGS="$*"
  menucommand="menuconfig"
fi

# let all the POST_DEFCONFIG_CMDS run since they may clean up loose files, then exit
append_cmd POST_DEFCONFIG_CMDS "exit"
# menuconfig should go first. If POST_DEFCONFIG_CMDS modifies the .config, then we probably don't
# want those changes to end up in the resulting saved defconfig
POST_DEFCONFIG_CMDS="menuconfig ${menucommand} && ${POST_DEFCONFIG_CMDS}"

${ROOT_DIR}/build/build.sh ${MAKE_ARGS}
