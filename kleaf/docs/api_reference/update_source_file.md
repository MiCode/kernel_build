<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Upon `bazel run`, updates a source file.

[TOC]

<a id="update_source_file"></a>

## update_source_file

<pre>
load("@kleaf//build/kernel/kleaf:update_source_file.bzl", "update_source_file")

update_source_file(<a href="#update_source_file-name">name</a>, <a href="#update_source_file-deps">deps</a>, <a href="#update_source_file-src">src</a>, <a href="#update_source_file-dst">dst</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="update_source_file-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="update_source_file-deps"></a>deps |  Additional files to depend on. You may add targets here to ensure these targets are built before updating the source file. This can be useful if you want to exercise additional checks.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="update_source_file-src"></a>src |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="update_source_file-dst"></a>dst |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


