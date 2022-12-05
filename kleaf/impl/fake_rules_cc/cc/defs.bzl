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

"""Fake version of @rules_cc//cc:defs.bzl to avoid downloading it
from the Internet. rules_cc is needed during migration to native.X.
"""

# Needed by py_binary
cc_toolchain = native.cc_toolchain
cc_toolchain_suite = native.cc_toolchain_suite

# Needed by @remote_java_tools
# TODO(b/261489408): Clean up remote_java_* dependencies then delete the following
cc_binary = native.cc_binary
cc_library = native.cc_library
cc_proto_library = native.cc_proto_library
