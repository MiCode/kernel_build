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

load("//build/bazel_common_rules/exec:exec.bzl", "exec_test")

def diff_test(
        name,
        expected,
        actual):
    """Define a test that diff two files."""

    exec_test(
        name = name,
        data = [
            expected,
            actual,
            "//build/kernel:hermetic-tools",
            "//build/kernel:hermetic-tools/dirname",
            "//build/kernel:hermetic-tools/realpath",
        ],
        script = """
realpath=$(rootpath //build/kernel:hermetic-tools/realpath)
dirname=$(rootpath //build/kernel:hermetic-tools/dirname)
export PATH=$($realpath $($dirname $dirname))
expected=$(rootpath {expected})
actual=$(rootpath {actual})
if ! diff -q $actual $expected; then
  echo "ERROR: test fails. expected:\n$(cat $expected)\nactual:\n$(cat $actual)" >&2
  exit 1
fi
""".format(
            expected = expected,
            actual = actual,
        ),
    )
