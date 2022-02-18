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

_BUILD_NUM_ENV_VAR = "KLEAF_DOWNLOAD_BUILD_NUMBER_MAP"

def _sanitize_repo_name(x):
    """Sanitize x so it can be used as a repository name.

    Replacing invalid characters (those not in `[A-Za-z0-9-_.]`) with `_`.
    """
    ret = ""
    for c in x.elems():
        if not c.isalnum() and not c in "-_.":
            c = "_"
        ret += c
    return ret

def _parse_env(repository_ctx, var_name, expected_key):
    """
    Given that the environment variable named by `var_name` is set to the following:

    ```
    key=value[,key=value,...]
    ```

    Return a list of values, where key matches `expected_key`. If there
    are multiple matches, the first one is returned. If there is no match,
    return `None`.

    For example:
    ```
    MYVAR="myrepo=x,myrepo2=y" bazel ...
    ```

    Then `_parse_env(repository_ctx, "MYVAR", "myrepo")` returns `"x"`
    """
    for pair in repository_ctx.os.environ.get(var_name, "").split(","):
        pair = pair.strip()
        if not pair:
            continue

        tup = pair.split("=", 1)
        if len(tup) != 2:
            fail("Unrecognized token in {}, must be key=value:\n{}".format(var_name, pair))
        key, value = tup
        if key == expected_key:
            return value
    return None

_ARTIFACT_URL_FMT = "https://androidbuildinternal.googleapis.com/android/internal/build/v3/builds/{build_number}/{target}/attempts/latest/artifacts/{filename}/url?redirect=true"

def _download_artifact_repo_impl(repository_ctx):
    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file)

    build_number = _parse_env(repository_ctx, _BUILD_NUM_ENV_VAR, repository_ctx.attr.parent_repo)
    if not build_number:
        build_number = repository_ctx.attr.build_number

    if build_number:
        build_file = """filegroup(
        name="file",
        srcs=["{filename}"],
        visibility=["@{parent_repo}//{filename}:__pkg__"],
    )
    """.format(
            filename = repository_ctx.attr.filename,
            parent_repo = repository_ctx.attr.parent_repo,
        )
    else:
        SAMPLE_BUILD_NUMBER = "8077484"
        if repository_ctx.attr.parent_repo == "gki_prebuilts":
            msg = """
ERROR: {parent_repo}: No build_number specified. Fix by specifying `--use_prebuilt_gki=<build_number>"`, e.g.
    bazel build --use_prebuilt_gki={build_number} @{parent_repo}//{filename}
""".format(
                filename = repository_ctx.attr.filename,
                parent_repo = repository_ctx.attr.parent_repo,
                build_number = SAMPLE_BUILD_NUMBER,
            )

        else:
            msg = """
ERROR: {parent_repo}: No build_number specified.

Fix by one of the following:
- Specify `build_number` attribute in {parent_repo}
- Specify `--action_env={build_num_var}="{parent_repo}=<build_number>"`, e.g.
    bazel build \\
      --action_env={build_num_var}="{parent_repo}={build_number}" \\
      @{parent_repo}//{filename}
""".format(
                filename = repository_ctx.attr.filename,
                parent_repo = repository_ctx.attr.parent_repo,
                build_number = SAMPLE_BUILD_NUMBER,
                build_num_var = _BUILD_NUM_ENV_VAR,
            )
        build_file = """
load("@//build/kernel/kleaf:fail.bzl", "fail_rule")

fail_rule(
    name = "file",
    message = \"\"\"{}\"\"\"
)
""".format(msg)

    repository_ctx.file("file/BUILD.bazel", build_file)

    if build_number:
        urls = [_ARTIFACT_URL_FMT.format(
            build_number = build_number,
            target = repository_ctx.attr.target,
            filename = repository_ctx.attr.filename,
        )]
        download_path = repository_ctx.path("file/{}".format(repository_ctx.attr.filename))
        download_info = repository_ctx.download(
            url = urls,
            output = download_path,
            sha256 = repository_ctx.attr.sha256,
        )

_download_artifact_repo = repository_rule(
    implementation = _download_artifact_repo_impl,
    attrs = {
        "build_number": attr.string(),
        "parent_repo": attr.string(doc = "Name of the parent `download_artifacts_repo`"),
        "filename": attr.string(),
        "target": attr.string(doc = "Name of target on [ci.android.com](http://ci.android.com), e.g. `kernel_kleaf`"),
        "sha256": attr.string(default = ""),
    },
    environ = [
        _BUILD_NUM_ENV_VAR,
    ],
)

def _alias_repo_impl(repository_ctx):
    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file)

    for filename, actual in repository_ctx.attr.aliases.items():
        build_file = """alias(name="{filename}", actual="{actual}", visibility=["//visibility:public"])
""".format(filename = filename, actual = actual)
        repository_ctx.file("{}/BUILD.bazel".format(filename), build_file)

_alias_repo = repository_rule(
    implementation = _alias_repo_impl,
    attrs = {
        "aliases": attr.string_dict(),
    },
)

def download_artifacts_repo(
        name,
        target,
        files,
        build_number = None):
    """Create a [repository](https://docs.bazel.build/versions/main/build-ref.html#repositories) that contains artifacts downloaded from [ci.android.com](http://ci.android.com).

    For each item `file` in `files`, the label `@{name}//{file}` can refer to the downloaded file.

    For example:
    ```
    download_artifacts_repo(
        name = "gki_prebuilts",
        target = "kernel_kleaf",
        build_number = "8077484"
        files = ["vmlinux"],
    )
    ```

    You may refer to the file with the label `@gki_prebuilts//vmlinux`, etc.

    To refer to all downloaded files, you may use `@gki_prebuilts//...`

    You may leave the build_number empty. If so, you must override the build number at build time.
    See below.

    For the repo `gki_prebuilts`, you may override the build number with `--use_prebuilt_gki`,
    e.g.

    ```
    bazel build --use_prebuilt_gki=8078291 @gki_prebuilts//vmlinux
    ```

    Args:
        name: name of the repository.
        target: build target on [ci.android.com](http://ci.android.com)
        build_number: build number on [ci.android.com](http://ci.android.com)
        files: One of the following:

          - If a list, this is a list of file names on [ci.android.com](http://ci.android.com).
          - If a dict, keys are file names on [ci.android.com](http://ci.android.com), and values
            are corresponding SHA256 hash.
    """

    if type(files) == type([]):
        files = {filename: None for filename in files}

    for filename, sha256 in files.items():
        # Need a repo for each file because repository_ctx.download is blocking. Defining multiple
        # repos allows downloading in parallel.
        # e.g. @gki_prebuilts_vmlinux
        _download_artifact_repo(
            name = name + "_" + _sanitize_repo_name(filename),
            parent_repo = name,
            filename = filename,
            build_number = build_number,
            target = target,
            sha256 = sha256,
        )

    # Define a repo named @gki_prebuilts that contains aliases to individual files, e.g.
    # @gki_prebuilts//vmlinux
    _alias_repo(
        name = name,
        aliases = {
            filename: "@" + name + "_" + _sanitize_repo_name(filename) + "//file"
            for filename in files.keys()
        },
    )
