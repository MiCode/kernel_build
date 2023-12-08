# Copyright (C) 2024 The Android Open Source Project
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

"""Default content for `@kleaf//build:kernel_toolchain_ext.bzl` if the common
package is checked out at `common/`. In this case, symlink this file to
`build/kernel_toolchain_ext.bzl` under the `@kleaf` module.

Do not `load()` this extension directly. Instead, load
`@kleaf//build:kernel_toolchain_ext.bzl`.

If common package is checked out at a different location other than
`common/` (e.g. at `aosp/`),
the user must replace `@kleaf//build:kernel_toolchain_ext.bzl` with the following
content:

```
load("//build/kernel/kleaf/bzlmod:make_kernel_toolchain_ext.bzl", "make_kernel_toolchain_ext")

kernel_toolchain_ext = make_kernel_toolchain_ext(
    toolchain_constants = "//aosp:build.config.constants",
)
```

The above equivalent to `define_kleaf_workspace(common_kernel_package = "//aosp")`.

Note: Under the directory of `@kleaf//build`, you also need a `BUILD.bazel`
file to make this a package. If it does not already exist, you may create a
symlink to `build/kernel/kleaf/bzlmod/empty_BUILD.bazel` in your repo manifest.
"""

# Not using relative label because this file is used as
# //build:kernel_toolchain_ext.bzl
load("//build/kernel/kleaf/bzlmod:make_kernel_toolchain_ext.bzl", "make_kernel_toolchain_ext")

visibility("public")

kernel_toolchain_ext = make_kernel_toolchain_ext(
    toolchain_constants = "//common:build.config.constants",
)
