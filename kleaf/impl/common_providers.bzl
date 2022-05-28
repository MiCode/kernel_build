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

# Providers that are provided by multiple rules in different extensions.

KernelEnvInfo = provider(
    doc = """Describe a generic environment setup with some dependencies and a setup script.

`KernelEnvInfo` is a legacy name; it is not only provided by `kernel_env`, but
other rules like `kernel_config` and `kernel_build`. Hence, the `KernelEnvInfo`
is in its own extension instead of `kernel_env.bzl`.
    """,
    fields = {
        "dependencies": "dependencies required to use this environment setup",
        "setup": "setup script to initialize the environment",
    },
)
