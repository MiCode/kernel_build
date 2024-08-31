# Copyright (C) 2019 The Android Open Source Project
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

# This is an implementation detail of build.sh and friends. Do not source
# directly as it will spoil your shell and make build.sh unusable. You have
# been warned! If you have a good reason to source the result of this file into
# a shell, please let kernel-team@android.com know and we are happy to help
# with your use case.


# This is a dummy to not break people that have a workflow that includes
# sourcing build/envsetup.sh into a shell when working with Android repo.
# The actual functionality of this script has been moved to _setup_env.sh.
#
# It turns out that build/envsetup.sh was sourced into the shell by a lot of
# people. Mostly due to the fact that old documentation asked people to do so
# (including this script itself). Unfortunately, this causes more harm than it
# does any good. Mostly it spoils the shell with environment variables that are
# only valid in the context of a very specific build configuration. To overcome
# this, the content of this file has been moved to _setup_env.sh and callers
# within this project have been adjusted. This script serves as a dummy to not
# break people sourcing it, but it will from now on emit a deprecation warning.
# That script might be removed at a later time.
#
# For further information on the Android Kernel build process with the tooling
# of this project, please refer to
# https://source.android.com/setup/build/building-kernels.
#
# For any questions or concerns, please contact kernel-team@android.com.

echo "Sourcing 'build/envsetup.sh' for Android Kernels is deprecated and no longer valid!"
echo "Please refer to the documentation in said script for details."
