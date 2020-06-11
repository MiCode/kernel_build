ABI Monitoring for Android Kernels
==================================

Overview
--------
In order to stabilize the in-kernel ABI of Android kernels, the ABI Monitoring
tooling has been created to collect and compare ABI representations from
existing kernel binaries (vmlinux + modules). The tools can be used to track
and mitigate changes to said ABI. This document describes the tooling, the
process of collecting and analyzing ABI representations and how such
representations can be used to ensure stability of the in-kernel ABI. Lastly,
this document gives some details about the process of contributing changes to
the Android kernels.

This directory contains the specific tools for the ABI analysis. It should be
used as part of the build scripts that are provided by this repository (see
`../build_abi.sh`).

Process Description
-------------------

Analyzing the kernel's ABI is done in multiple steps. Most of the steps can be
automated:

 1. Acquire the toolchain, build scripts and kernel sources through `repo`
 2. Provide any prerequisites (e.g. libabigail)
 3. Build the kernel and its ABI representation
 4. Analyze ABI differences between the build and a reference
 5. Update the ABI representation (if required)
 6. Working with symbol whitelists


The following instructions work for any kernel that can be built using a
supported toolchain (i.e. a prebuilt Clang toolchain). There exist [`repo`
manifests](https://android.googlesource.com/kernel/manifest/+refs) for all
Android common kernel branches, for some upstream branches (e.g.
upstream-linux-4.19.y) and several device specific kernels that ensure the
correct toolchain is used when building a kernel distribution.


Using the ABI Monitoring tooling
--------------------------------

### 1. Acquire the toolchain, build scripts and kernel sources through repo

Toolchain, build scripts (i.e. these scripts) and kernel sources can be
acquired with `repo`. For detailed documentation, refer to the corresponding
documentation on
[source.android.com](https://source.android.com/setup/build/building-kernels).

To illustrate the process, the following steps use `common-android-mainline`,
an Android kernel branch that is kept up-to-date with the upstream Linux
releases. In order to obtain this branch via `repo`, execute

```
  $ repo init -u https://android.googlesource.com/kernel/manifest -b common-android-mainline
  $ repo sync
```

### 2. Provide any prerequisites

**NOTE**: Googlers might want to follow the steps in
[go/kernel-abi-monitoring](http://go/kernel-abi-monitoring) to use a prebuilt
libabigail distribution.

The ABI tooling makes use of [libabigail](https://sourceware.org/libabigail/),
a library and collection of tools to analyze binaries. In order to use the
tooling, users are required to provide a functional libabigail installation.
The released version of your Linux distribution might not be a supported one;
hence, it is recommended way to use the `bootstrap` script which can be found in
this directory. The `bootstrap` script automates the process of acquiring and
building a valid libabigail distribution and needs to be executed without any
arguments like so:

```
  $ build/abi/bootstrap
```

The script will ensure the following system prerequisites are installed along
with their dependencies:

 - autoconf
 - libtool
 - libxml2-dev
 - pkg-config
 - python3

**NOTE**: At the moment, only apt based package managers are supported, but
`bootstrap` provides some hints to help users that have other package
managers.

The script continues with acquiring the sources for the correct versions of
*elfutils* and *libabigail* and will build the required binaries. At the very
end the script will print instructions to add the binaries to the local
`${PATH}`. The output will look similar to:

```
  NOTE: Export the following environment before running the executables:

  export PATH="/src/kernel/build/abi/abigail-inst/d7ae619f/bin:${PATH}"
  export LD_LIBRARY_PATH="/src/kernel/build/abi/abigail-inst/d7ae619f/lib:/src/kernel/build/abi/abigail-inst/d7ae619f/lib/elfutils:${LD_LIBRARY_PATH}"
```

**NOTE**: It is probably a good idea to save these instructions to reuse the
prebuilt binaries in a later session.

Follow the instructions to enable the prerequisites in your environment.

### 3. Build the kernel and its ABI representation

At this point you are ready to build a kernel with the correct toolchain and to
extract an ABI representation from its binaries (vmlinux + modules).

Similar to the usual Android kernel build process (using `build.sh`), this step
requires running `build_abi.sh`.

```
  $ BUILD_CONFIG=common/build.config.gki.aarch64 build/build_abi.sh
```

**NOTE**: `build_abi.sh` makes use of `build.sh` and therefore accepts the
same environment variables to customize the build. It also *requires* the same
variables that would need to be passed to `build.sh`, such as `BUILD_CONFIG`.

That builds the kernel and extracts the ABI representation into the `out`
directory. In this case `out/android-mainline/dist/abi.xml` would be a symbolic
link to `out/android-mainline/dist/abi-<id>.xml`. `id` is computed from
executing `git describe` against the kernel source tree.

### 4. Analyze ABI differences between the build and a reference representation

`build_abi.sh` is capable of analyzing and reporting any ABI differences when
a reference is provided via the environment variable `ABI_DEFINITION`.
`ABI_DEFINITION` should point to a reference file relative to the kernel source
tree and can be specified on the command line or (more commonly) as a value in
*build.config*. E.g.

```
  $ BUILD_CONFIG=common/build.config.gki.aarch64      \
    ABI_DEFINITION=abi_gki_aarch64.xml                \
    build/build_abi.sh
```

Above, the `build.config.gki.aarch64` defines the reference file (as
*abi_gki_aarch64.xml*) and therefore the analysis has been completed. If an
abidiff was executed, then `build_abi.sh` will print the location of the report
and identify any ABI breakage. If breakages are detected, then `build_abi.sh`
will terminate and return a non-zero exit code.

### 5. Update the ABI representation (if required)

To update the ABI dump, `build_abi.sh` can be invoked with the `--update` flag.
It will update the corresponding abi.xml file that is defined via the
build.config. It might also be useful to invoke the script with `--print-report`
to print the differences the update fixes. The report is useful to include in
the commit message when updating the abi.xml.

### 6. Working with symbol whitelists

`build_abi.sh` can be parameterized to filter symbols during extraction and
comparison with KMI (Kernel Module Interface) whitelists. These are simple
plain text files that list relevant ABI kernel symbols. E.g. a whitelist file
with the following content would limit ABI analysis to the ELF symbols with the
names `symbol1` and `symbol2`:

```
  [abi_whitelist]
    symbol1
    symbol2
```

**NOTE**: Please refer to the [libabigail
documentation](https://sourceware.org/libabigail/manual/kmidiff.html#environment)
for details about the KMI whitelist file format.

Changes to other ELF symbols would not be considered any longer unless they are
indirectly affecting symbols that are whitelisted. A whitelist file can be
specified -- similar to the abi baseline file via `ABI_DEFINITION=` -- in the
corresponding `build.config` configuration file with `KMI_WHITELIST=` as a file
relative to the kernel source directory (`$KERNEL_DIR`). In order to allow a
certain level of organization, additional whitelist files can be specified by
using `ADDITIONAL_KMI_WHITELISTS=` in the `build.config`. Similarly, it refers
to whitelists in the `$KERNEL_DIR` and multiple files need to be separated by
whitespaces.

In order to **create an initial whitelist or to update an existing one**, the
script `extract_symbols` is provided. When run pointing at a `DIST_DIR` of an
Android Kernel build, it will extract the symbols that are exported from
vmlinux _and_ are required by any module in the tree.

Consider `vmlinux` exporting the following symbols (usually done via the
EXPORT_SYMBOL* macros):

```
  func1
  func2
  func3
```

Also, consider there are two modules `modA.ko` and `modB.ko` which require the
following symbols (i.e. `undefined` entries in the symbol table):

```
  modA.ko:    func1 func2
  modB.ko:    func2`
```

From an ABI stability point of view we need to keep `func1` and `func2` stable
as these are used by an external module. On the contrary, while `func3` is
exported it is not actively used (i.e. required) by any module. The whitelist
would therefore contain `func1` and `func2` only.

`extract_symbols` offers a flag to update an existing or create a new whitelist
based on the above analysis: `--whitelist <path/to/abi_whitelist>`.

In order to update an existing whitelist based on a built Kernel tree, run
`extract_symbols` as follows. The example uses the *common-android-mainline*
branch of the Android Common Kernels following the official [build
documentation](https://source.android.com/setup/build/building-kernels) and
updates the whitelist for the GKI aarch64 Kernel.

```
  (build the kernel)
  $ BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh

  (update/create the whitelist)
  $ build/abi/extract_symbols out/android-mainline/dist --whitelist common/abi_gki_aarch64_whitelist
```

**NOTE**: Be aware that `extract_symbols` recursively discovers Kernel modules
by extension (*.ko) and considers all found ones. Orphan Kernel modules from
prior runs might lead to incorrect results. Hence, make sure the directory you
pass on to `extract_symbols` contains only the vmlinux and the modules you want
it to consider.


Working with the lower level ABI tooling
----------------------------------------

Most users will need to use `build_abi.sh`. In some cases, it might be
necessary to work with the lower level ABI tooling directly. There are
currently two commands -- `dump_abi` and `diff_abi` -- that are available to
collect and compare ABI files. These commands are used by `build_abi.sh`. See
the following sections for their usages.

### Creating ABI dumps from kernel trees

Provided a linux kernel tree with built vmlinux and kernel modules, the tool
`dump_abi` creates an ABI representation using the selected ABI tool. As of now
there is only one option: 'libabigail' (default). A sample invocation looks as
follows:

```
  $ dump_abi --linux-tree path/to/out --out-file /path/to/abi.xml
```

The file `abi.xml` will contain a combined textual ABI representation that can
be observed from vmlinux and the kernel modules in the given directory. This
file might be used for manual inspection, further analysis or as a reference
file to enforce ABI stability.

### Comparing ABI dumps

ABI dumps created by `dump_abi` can be compared with `diff_abi`. Ensure to use
the same abi-tool for `dump_abi` and `diff_abi`. A sample invocation looks like:

```
  $ diff_abi --baseline abi1.xml --new abi2.xml --report report.out
```

The report created is tool specific, but generally lists ABI changes detected
that affect the kernel's module interface. The files specified as `baseline`
and `new` are ABI representations collected with `dump_abi`. `diff_abi`
propagates the exit code of the underlying tool and therefore returns a
non-zero value in case the ABIs compared are incompatible.

### Using KMI whitelists

To filter dumps created with `dump_abi` or filter symbols compared with
`diff_abi`, each of those tools provides a parameter `--kmi-whitelist` that
takes a path to a KMI whitelist file:

```
  $ dump_abi --linux-tree path/to/out --out-file /path/to/abi.xml --kmi-whitelist /path/to/whitelist
```

### Comparing Kernel Binaries against the GKI reference KMI

While working on the GKI Kernel compliance, it might be useful to regularly
compare a local Kernel build to a reference GKI KMI representation without
having to use `build_abi.sh`. The tool `gki_check` is a lightweight tool to
do exactly that. Given a local Linux Kernel build tree, a sample invocation to
compare the local binaries' representation to e.g. the 5.4 representation:

```
  $ build/abi/gki_check --linux-tree path/to/out/ --kernel-version 5.4
```

`gki_check` uses parameter names consistent with `dump_abi` and `diff_abi`.
Hence, `--kmi-whitelist path/to/kmi_whitelist` can be used to limit that
comparison to whitelisted symbols by passing a KMI whitelist.

**NOTE:** When comparing the ABI representations between the GKI Kernel and the
locally built kernel, there might be cases that ABI changes are reported that
are purely caused by modifications to the kernel configuration (such as adding
modules with =m) without any other relevant code changes. As those are still
breakages, they need to be worked out in the Android Common Kernels. Please
contact kernel-team@android.com for advice.

Dealing with ABI breakages
--------------------------

As an example, the following patch introduces a very obvious ABI breakage:

```
  diff --git a/include/linux/mm_types.h b/include/linux/mm_types.h
  index 5ed8f6292a53..f2ecb34c7645 100644
  --- a/include/linux/mm_types.h
  +++ b/include/linux/mm_types.h
  @@ -339,6 +339,7 @@ struct core_state {
   struct kioctx_table;
   struct mm_struct {
      struct {
  +       int dummy;
          struct vm_area_struct *mmap;            /* list of VMAs */
          struct rb_root mm_rb;
          u64 vmacache_seqnum;                   /* per-thread vmacache */
```

Running `build_abi.sh` again with this patch applied, the tooling will exit with
a non-zero error code and will report an ABI difference similar to this:

```
  Leaf changes summary: 1 artifact changed
  Changed leaf types summary: 1 leaf type changed
  Removed/Changed/Added functions summary: 0 Removed, 0 Changed, 0 Added function
  Removed/Changed/Added variables summary: 0 Removed, 0 Changed, 0 Added variable

  'struct mm_struct at mm_types.h:372:1' changed:
    type size changed from 6848 to 6912 (in bits)
    there are data member changes:
  [...]
```

### How to fix a broken ABI on Android Gerrit

If you didn't intentionally break the kernel ABI, then you need to investigate
via the Android Gerrit test log to identify the issue(s) reported by the tool. Most
common causes of breakages are added or deleted functions, changed data
structures or changes to the ABI by adding config options that lead to any of
the aforementioned. Most likely you want to start with addressing the issues
found by the tool.

You can reproduce the KernelABI test locally by running the following command
with the same arguments that you would have run `build/build.sh` with.

Example command for the GKI kernels:

```
  $ BUILD_CONFIG=common/build.config.gki.aarch64 build/<b>build_abi.sh</b>
```

### Updating the Kernel ABI

If you need to update the kernel ABI, then you must update the corresponding
`abi.xml` file in the kernel source tree. This is most conveniently done by
using `build/build_abi.sh` like so:

```
  $ build/<b>build_abi.sh</b> --update --print-report
```

with the same arguments that you would have run `build/build.sh` with. This
updates the correct `abi.xml` in the source tree and prints the detected
differences. It is recommended to include the printed report in the commit
message (at least partially).


Android Kernel Branches with predefined ABI
-------------------------------------------

Some kernel branches might come with golden ABI representations for Android as
part of their source distribution. These ABI representations are supposed to be
accurate and should reflect the result of `build_abi.sh` as if you would execute
it on your own. As the ABI is heavily influenced by various kernel configuration
options, these .xml files usually belong to a certain configuration. E.g. the
`common-android-mainline` branch contains an `abi_gki_aarch64.xml` that
corresponds to the build result when using the `build.config.gki.aarch64`. In
particular, `build.config.gki.aarch64` also refers to this file as its
`ABI_DEFINITION`.

Such predefined ABI representations are used as a baseline definition when
comparing with `diff_abi` (s.a.). E.g. to validate a kernel patch in regards to
any changes to the ABI, create the ABI representation with the patch applied and
use `diff_abi` to compare it to the expected ABI for that particular source tree
/ configuration.

Caveats and known issues
------------------------

Version 1.8 of libabigail contains most, but not all currently required patches
to properly work on clang-built aarch64 Android kernels. Using a recent mm-next
is a sufficient workaround for that. The `bootstrap` script refers to a
sufficient commit from upstream.
