# Debugging Kleaf

## Debugging Options

This is a non exhaustive list of options to help debugging compilation issues:

* Customise Kleaf:
  * `--debug_annotate_scripts`: Runs all script invocations with `set -x` and a
 trap that executes `date` after every command.

  * `--debug_print_scripts`: Prints the content of the (generated) command scripts during rule execution.

* Customise Kbuild:
  * `--debug_make_verbosity`: Controls verbosity of `make` executions `E (default)
= Error, I = Info, D = Debug`

  * `--debug_modpost_warn`: Sets [`KBUILD_MODPOST_WARN=1`](https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-modpost-warn). TL; DR. can be set to avoid errors in case of undefined symbols in the final module linking stage. It changes such errors into warnings.

* Customise Bazel:
  * `--sandbox_debug`: Enables debugging features for the [sandboxing feature](https://bazel.build/docs/sandboxing).
  * `--verbose_failures`: If a command fails, print out the full command line.
  * `--jobs`: This option, which takes an integer argument, specifies a limit on the number of jobs that should be executed concurrently during the execution phase of the build.
  * For a complete list see https://bazel.build/docs/user-manual

## Debugging incremental build issues

Incremental build issues refers to issues where actions are executed in an
incremental build, but you do not expect them to be executed, or the reverse.

For example, if you are debugging why
`//common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe` is
rebuilt after you change a core kernel file, you may execute the following:

```shell
# Custom flags provided to the build; change accordingly
$ FLAGS="--config=fast"

# Build
$ tools/bazel build "${FLAGS}" //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe

# Record hashes of all input files to the action
# Note that kernel_module() defines multiple actions, so use mnemonic() to filter out
# the non-interesting ones.
$ build/kernel/kleaf/analysis/inputs.py -- "${FLAGS}" \
  'mnemonic(KernelModule, //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe)' \
  > out/hash_1.txt

# Change a core kernel file, e.g.
$ echo >> common/kernel/sched/core.c

# Build again
$ tools/bazel build "${FLAGS}" //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe

# Record hashes of all input files to the action
$ build/kernel/kleaf/analysis/inputs.py -- "${FLAGS}" \
  'mnemonic(KernelModule, //common-modules/virtual-device:x86_64/goldfish_drivers/goldfish_pipe)' \
  > out/hash_2.txt

# Compare hashes, e.g.
$ diff out/hash_1.txt out/hash_2.txt
```

Positional arguments to `build/kernel/kleaf/analysis/inputs.py` are fed directly to
`tools/bazel aquery`. Visit [Action Graph Query](https://bazel.build/query/aquery) for the
query language.
