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

_CAPTURED_ENV_VARS = [
    "BUILD_CONFIG",
]

def _capture_env_impl(rctx):
    env_vars = {}
    for env_var in _CAPTURED_ENV_VARS:
        env_value = rctx.os.environ.get(env_var)
        env_vars[env_var] = env_value

    rctx.file("BUILD.bazel", """
exports_files(["env.bzl"])
""")

    # Re-export captured environment variables in a .bzl file.
    rctx.file("env.bzl", "\n".join([
        item[0] + " = \"" + str(item[1]) + "\""
        for item in env_vars.items()
    ]))

_capture_env = repository_rule(
    implementation = _capture_env_impl,
    configure = True,
    environ = _CAPTURED_ENV_VARS,
    doc = "A repository rule to capture environment variables.",
)

def capture_env():
    _capture_env(name = "capture_env")
