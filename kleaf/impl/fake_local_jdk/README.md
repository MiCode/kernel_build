This is the directory for a fake `local_jdk` to avoid fetching `rules_java` for any exec targets.

The dependency chain is as follows:

1. Bazel needs to know the properties of every registered toolchain (because it builds a database
   out of them)
2. The exec and target platform is a property of a the JDK/JRE toolchains
3. The exec and target platforms of the local JDK are determined by the local JDK discovery process
4. The local JDK discovery process is implemented by the `@local_jdk` repository
5. The `@local_jdk` repository depends on `@rules_java` because it is fastidious and thus uses the
   currently-not-very-useful Starlark wrapper

So it's not that `py_binary` needs anything Java, it's that the `@local_jdk` repository is
unconditionally fetched no matter what. The workaround is to define a fake `@local_jdk` repository.

Reference bug: https://issuetracker.google.com/issues/245624185
