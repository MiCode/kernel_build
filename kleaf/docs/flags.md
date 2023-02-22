### Debugging Options

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

