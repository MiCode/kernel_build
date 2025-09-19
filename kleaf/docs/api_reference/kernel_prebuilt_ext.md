<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Extension that helps building Android kernel and drivers.

<a id="kernel_prebuilt_ext"></a>

## kernel_prebuilt_ext

<pre>
kernel_prebuilt_ext = use_extension("@kleaf//build/kernel/kleaf:kernel_prebuilt_ext.bzl", "kernel_prebuilt_ext")
kernel_prebuilt_ext.declare_kernel_prebuilts(<a href="#kernel_prebuilt_ext.declare_kernel_prebuilts-name">name</a>, <a href="#kernel_prebuilt_ext.declare_kernel_prebuilts-auto_download_config">auto_download_config</a>, <a href="#kernel_prebuilt_ext.declare_kernel_prebuilts-download_config">download_config</a>,
                                             <a href="#kernel_prebuilt_ext.declare_kernel_prebuilts-local_artifact_path">local_artifact_path</a>, <a href="#kernel_prebuilt_ext.declare_kernel_prebuilts-mandatory">mandatory</a>, <a href="#kernel_prebuilt_ext.declare_kernel_prebuilts-target">target</a>)
</pre>

Extension that manages what prebuilts Kleaf should use.


**TAG CLASSES**

<a id="kernel_prebuilt_ext.declare_kernel_prebuilts"></a>

### declare_kernel_prebuilts

Declares a repo that contains kernel prebuilts

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kernel_prebuilt_ext.declare_kernel_prebuilts-name"></a>name |  name of repository   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kernel_prebuilt_ext.declare_kernel_prebuilts-auto_download_config"></a>auto_download_config |  If `True`, infer `download_config` and `mandatory` from `target`.   | Boolean | optional |  `False`  |
| <a id="kernel_prebuilt_ext.declare_kernel_prebuilts-download_config"></a>download_config |  Configure the list of files to download.<br><br>Key: local file name.<br><br>Value: remote file name format string, with the following anchors:     * {build_number}     * {target}   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kernel_prebuilt_ext.declare_kernel_prebuilts-local_artifact_path"></a>local_artifact_path |  Directory to local artifacts.<br><br>If set, `artifact_url_fmt` is ignored.<br><br>Only the root module may call `declare()` with this attribute set.<br><br>If relative, it is interpreted against workspace root.<br><br>If absolute, this is similar to setting `artifact_url_fmt` to `file://<absolute local_artifact_path>/{filename}`, but avoids using `download()`. Files are symlinked not copied, and `--config=internet` is not necessary.   | String | optional |  `""`  |
| <a id="kernel_prebuilt_ext.declare_kernel_prebuilts-mandatory"></a>mandatory |  Configure whether files are mandatory.<br><br>Key: local file name.<br><br>Value: Whether the file is mandatory.<br><br>If a file name is not found in the dictionary, default value is `True`. If mandatory, failure to download the file results in a build failure.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kernel_prebuilt_ext.declare_kernel_prebuilts-target"></a>target |  Name of the build target as identified by the remote build server.<br><br>This attribute has two effects:<br><br>* Replaces the `{target}` anchor in `artifact_url_fmt`.     If `artifact_url_fmt` does not have the `{target}` anchor,     this has no effect.<br><br>* If `auto_download_config` is `True`, `download_config`     and `mandatory` is inferred from a     list of known configs keyed on `target`.   | String | optional |  `"kernel_aarch64"`  |


