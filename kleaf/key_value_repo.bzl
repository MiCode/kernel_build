def _impl(repository_ctx):
    repository_content = ""

    for src in repository_ctx.attr.srcs:
        raw_content = repository_ctx.read(src)
        for line in raw_content.splitlines():
            key, value = line.split("=", 1)
            repository_content += '{} = "{}"'.format(key.strip(), value.strip())

    repository_ctx.file("BUILD", "")
    repository_ctx.file("dict.bzl", repository_content)

key_value_repo = repository_rule(
    implementation = _impl,
    local = True,
    doc = """Exposes a Bazel repository with key value pairs defined from srcs.

Configuration files shall contain a single pair of key and value separated
by '='. Keys and values are stripped, hence whitespace characters around the
separator are allowed.

Example:
Given a file `common/build.config.constants` with content
```
    CLANG_VERSION=r433403
```

The workspace file can instantiate a repository rule with
```
load("//build/kleaf:key_value_repo.bzl", "key_value_repo")

key_value_repo(
    name = "kernel_toolchain_info",
    srcs = ["//common:build.config.constants"],
)
```

and users of the repository can refer to the values with
```
load("@kernel_toolchain_info//:dict.bzl", "CLANG_VERSION")
```
""",
    attrs = {"srcs": attr.label_list(
        mandatory = True,
        doc = "Configuration files storing 'key=value' pairs.",
    )},
)
