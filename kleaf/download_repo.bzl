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

"""Instantiates a repository that downloads artifacts from http://ci.android.com."""

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
    repository_ctx.file("WORKSPACE.bazel", workspace_file, executable = False)

    build_number = _get_build_number(repository_ctx)
    if not build_number:
        _handle_no_build_number(repository_ctx)
    else:
        _download_from_build_number(repository_ctx, build_number)

def _get_build_number(repository_ctx):
    """Gets the value of build number, setting defaults if necessary."""
    build_number = _parse_env(repository_ctx, _BUILD_NUM_ENV_VAR, repository_ctx.attr.parent_repo)
    if not build_number:
        build_number = repository_ctx.attr.build_number
    return build_number

def _handle_no_build_number(repository_ctx):
    """Handles the case where the build number cannot be found."""

    SAMPLE_BUILD_NUMBER = "8077484"
    if repository_ctx.attr.parent_repo == "gki_prebuilts":
        msg = """
ERROR: {parent_repo}: No build_number specified. Fix by specifying `--use_prebuilt_gki=<build_number>"`, e.g.
    bazel build --use_prebuilt_gki={build_number} @{parent_repo}//{filename}
""".format(
            filename = repository_ctx.attr.local_filename,
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
            filename = repository_ctx.attr.local_filename,
            parent_repo = repository_ctx.attr.parent_repo,
            build_number = SAMPLE_BUILD_NUMBER,
            build_num_var = _BUILD_NUM_ENV_VAR,
        )
    build_file = """
load("{fail_bzl}", "fail_rule")

fail_rule(
    name = "file",
    message = \"\"\"{msg}\"\"\"
)
""".format(
        fail_bzl = Label(":fail.bzl"),
        msg = msg,
    )

    repository_ctx.file("file/BUILD.bazel", build_file, executable = False)

def _download_from_build_number(repository_ctx, build_number):
    local_filename = repository_ctx.attr.local_filename
    remote_filename = repository_ctx.attr.remote_filename_fmt.format(
        build_number = build_number,
    )

    # If there's a "/" in the remote filename, escape
    remote_filename = remote_filename.replace("/", "%2F")

    # Download the requested file
    urls = [_ARTIFACT_URL_FMT.format(
        build_number = build_number,
        target = repository_ctx.attr.target,
        filename = remote_filename,
    )]
    download_path = repository_ctx.path("file/{}".format(local_filename))
    download_info = repository_ctx.download(
        url = urls,
        output = download_path,
        sha256 = repository_ctx.attr.sha256,
        allow_fail = repository_ctx.attr.allow_fail,
    )

    # Define the filegroup to contain the file.
    # If failing and it is allowed, set filegroup to empty
    if not download_info.success and repository_ctx.attr.allow_fail:
        srcs = ""
    else:
        srcs = '"{}"'.format(local_filename)

    build_file = """filegroup(
    name="file",
    srcs=[{srcs}],
    visibility=["@{parent_repo}//{local_filename}:__pkg__"],
)
""".format(
        srcs = srcs,
        local_filename = local_filename,
        parent_repo = repository_ctx.attr.parent_repo,
    )
    repository_ctx.file("file/BUILD.bazel", build_file, executable = False)

_download_artifact_repo = repository_rule(
    implementation = _download_artifact_repo_impl,
    attrs = {
        "build_number": attr.string(
            doc = "the default build number to use if the environment variable is not set.",
        ),
        "parent_repo": attr.string(doc = "Name of the parent `download_artifacts_repo`"),
        "local_filename": attr.string(
            doc = "Filename and target name used locally to refer to the file.",
        ),
        "remote_filename_fmt": attr.string(
            doc = """Format string of the filename on [ci.android.com](http://ci.android.com).

            The filename on [ci.android.com](http://ci.android.com) is determined by
            `remote_filename_fmt.format(...)`, with the following keys:

            - `build_number`: the environment variable or the `build_number` attribute
            """,
        ),
        "target": attr.string(doc = "Name of target on [ci.android.com](http://ci.android.com), e.g. `kernel_aarch64`"),
        "sha256": attr.string(
            default = "",
            doc = "checksum of the downloaded file",
        ),
        "allow_fail": attr.bool(),
    },
    environ = [
        _BUILD_NUM_ENV_VAR,
    ],
)

# Avoid dependency to paths, since we do not necessary have skylib loaded yet.
def _basename(s):
    return s.split("/")[-1]

def _alias_repo_impl(repository_ctx):
    workspace_file = """workspace(name = "{}")
""".format(repository_ctx.name)
    repository_ctx.file("WORKSPACE.bazel", workspace_file, executable = False)

    for local_filename, actual in repository_ctx.attr.aliases.items():
        build_file = """\
alias(
    name="{local_file_basename}",
    actual="{actual}",
    visibility=["//visibility:public"]
)
""".format(local_file_basename = _basename(local_filename), actual = actual)
        repository_ctx.file("{}/BUILD.bazel".format(local_filename), build_file, executable = False)

_alias_repo = repository_rule(
    implementation = _alias_repo_impl,
    attrs = {
        "aliases": attr.string_dict(doc = """
        - Keys: local filename.
        - Value: label to the actual target.
        """),
    },
    environ = [
        _BUILD_NUM_ENV_VAR,
    ],
)

def _transform_files_arg(repo_name, files):
    """Standardizes files / optional_files for download_artifacts_repo.

    Returns dict[str, dict[str, str]]"""

    if files == None:
        files = {}

    if type(files) == type([]):
        files = {filename: None for filename in files}

    if type(files) == type({}):
        new_files = {}
        for key, value in files.items():
            if value == None:
                value = {}
            if type(value) == str:
                value = {"sha256": value}
            if type(value) != type({}):
                fail("@{}: Invalid value {}".format(repo_name, value))
            new_files[key] = value
        files = new_files

    return files

def download_artifacts_repo(
        name,
        target,
        files = None,
        optional_files = None,
        build_number = None):
    """Create a [repository](https://docs.bazel.build/versions/main/build-ref.html#repositories) that contains artifacts downloaded from [ci.android.com](http://ci.android.com).

    For each item `file` in `files`, the label `@{name}//{file}` can refer to the downloaded file.

    For example:
    ```
    download_artifacts_repo(
        name = "gki_prebuilts",
        target = "kernel_aarch64",
        build_number = "9359437"
        files = ["vmlinux"],
        optional_files = ["abi_symbollist"],
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

            - If a list, this is equivalent to `{file: {} for file in files}`.
            - If a dict:
                - Keys are the local file names. Unlike `remote_filename_fmt`, the name
                  is used as-is.
                - Values are one of the following:
                - If a string, this is equivalent to `{"sha256": value}`
                - If a dict, the dictionary may contain these keys:
                    - "sha256": the corresponding SHA256 hash
                    - "remote_filename_fmt": the file name on [ci.android.com](http://ci.android.com).
                        If unspecified, use the local file name.
                        The remote filename may be a format string that accepts the following keys:
                        - `build_number`

            Examples:
            ```
            files = ["vmlinux"]
            ```

            ```
            files = {
                "vmlinux": "34c4db6e8f4f5f7a3ce18380fb0dd26cff9b66e9ec9a4046db1499b577e4709a"
            }
            ```

            ```
            files = {
                "manifest.xml": {
                    "sha256sum": "b45303a82e281977c684838fd6f4100a73bddffacae978593a6ef16e0bcc68ac",
                    "remote_filename_fmt": "manifest_{build_number}.xml"
                }
            }
            ```

        optional_files: Same as `files`, but it is optional. If the file is not in the given
          build, it will not be downloaded, and the label (e.g. `@gki_prebuilts//abi_symbollist`)
          points to an empty filegroup.
    """

    files = _transform_files_arg(name, files)
    optional_files = _transform_files_arg(name, optional_files)

    for files_dict, allow_fail in ((files, False), (optional_files, True)):
        for local_filename, file_metadata in files_dict.items():
            # Need a repo for each file because repository_ctx.download is blocking. Defining multiple
            # repos allows downloading in parallel.
            # e.g. @gki_prebuilts_vmlinux
            _download_artifact_repo(
                name = name + "_" + _sanitize_repo_name(local_filename),
                parent_repo = name,
                local_filename = local_filename,
                build_number = build_number,
                target = target,
                sha256 = file_metadata.get("sha256"),
                remote_filename_fmt = file_metadata.get("remote_filename_fmt", local_filename),
                allow_fail = allow_fail,
            )

    # Define a repo named @gki_prebuilts that contains aliases to individual files, e.g.
    # @gki_prebuilts//vmlinux
    _alias_repo(
        name = name,
        aliases = {
            local_filename: "@" + name + "_" + _sanitize_repo_name(local_filename) + "//file"
            for local_filename in (list(files.keys()) + list(optional_files.keys()))
        },
    )
