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
 6. Working with symbol lists


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

### 6. Working with symbol lists

`build_abi.sh` can be parameterized to filter symbols during extraction and
comparison with KMI (Kernel Module Interface) symbol lists. These are simple
plain text files that list relevant ABI kernel symbols. E.g. a symbol list file
with the following content would limit ABI analysis to the ELF symbols with the
names `symbol1` and `symbol2`:

```
  [abi_whitelist]
    symbol1
    symbol2
```

**NOTE**: Please refer to the [libabigail
documentation](https://sourceware.org/libabigail/manual/kmidiff.html#environment)
for details about the KMI symbol list file format.

Changes to other ELF symbols would not be considered any longer unless they are
indirectly affecting symbols that are part of the KMI. A symbol list file can be
specified -- similar to the abi baseline file via `ABI_DEFINITION=` -- in the
corresponding `build.config` configuration file with `KMI_WHITELIST=` as a file
relative to the kernel source directory (`$KERNEL_DIR`). In order to allow a
certain level of organization, additional symbol list files can be specified by
using `ADDITIONAL_KMI_WHITELISTS=` in the `build.config`. Similarly, it refers
to symbol lists in the `$KERNEL_DIR` and multiple files need to be separated by
whitespaces.

In order to **create an initial symbol list or to update an existing one**, the
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
exported it is not actively used (i.e. required) by any module. The symbol list
would therefore contain `func1` and `func2` only.

`extract_symbols` offers a flag to update an existing or create a new symbol list
based on the above analysis: `--whitelist <path/to/abi_symbol_list>`.

In order to update an existing symbol list based on a built Kernel tree, run
`extract_symbols` as follows. The example uses the *common-android-mainline*
branch of the Android Common Kernels following the official [build
documentation](https://source.android.com/setup/build/building-kernels) and
updates the symbol lists for the GKI aarch64 Kernel.

```
  (build the kernel)
  $ BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh

  (update/create the symbol list)
  $ build/abi/extract_symbols out/android-mainline/dist --whitelist common/android/abi_gki_aarch64
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

### Using KMI symbol lists

To filter dumps created with `dump_abi` or filter symbols compared with
`diff_abi`, each of those tools provides a parameter `--kmi-whitelist` that
takes a path to a KMI symbol list file:

```
  $ dump_abi --linux-tree path/to/out --out-file /path/to/abi.xml --kmi-whitelist /path/to/symbol_list
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
Hence, `--kmi-whitelist path/to/kmi_symbol_list` can be used to limit that
comparison to allowed symbols by passing a KMI symbol list.

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

Enforcing the KMI using module versioning
-----------------------------------------

The GKI kernels use [module versioning
](https://www.kernel.org/doc/html/latest/kbuild/modules.html?highlight=modules%20symvers#module-versioning)
(`CONFIG_MODVERSIONS`) as an measure to enforce KMI compliance at runtime.
Module versioning can cause CRC mismatch failures at module load time if the
expected KMI of a module does not match the vmlinux KMI. For example, here is
a typical failure occuring at module load time due to a CRC mismatch for the
symbol `module_layout()`:

```
  init: Loading module /lib/modules/kernel/.../XXX.ko with args ""
  XXX: disagrees about version of symbol module_layout
  init: Failed to insmod '/lib/modules/kernel/.../XXX.ko' with args ''
```

### Why do we need module versioning?

Module versioning is useful for many reasons:

1. It catches changes in data structure visibility. If modules can change
   opaque data structures, i.e. data structures that are not part of the KMI,
   modules will break after future changes to the structure.
2. It adds a run time check to avoid accidentally loading a module that is not
   KMI compatible with the kernel. This prevents hard-to-debug runtime issues/
   kernel crashes that will show up in the future.
3. `abidiff` has some current limitations in identifying ABI differences in
   certain convoluted cases (they are being worked on) that `CONFIG_MODVERSIONS`
   can catch.

As an example for (1), consider the [fwnode
](https://android.googlesource.com/kernel/common/+/987d0b5bcf096a478aaf96faf5a288b4c95e9d37/include/linux/device.h#598)
field in [struct device
](https://android.googlesource.com/kernel/common/+/987d0b5bcf096a478aaf96faf5a288b4c95e9d37/include/linux/device.h#535).
That field MUST be opaque to modules so that they cannot make changes to fields
of `device.->fw_node` or make assumptions about its size.

However, if a module includes `<linux/fwnode.h>` (directly or indirectly), then
the `fwnode` field in the `struct device` is no longer opaque to it. The module
can then make changes to `device->fwnode->dev` or `device->fwnode->ops`. That
is problematic for several reasons:

1. It can break assumptions the core kernel code is making about its internal
   data structures.
2. If a future kernel update changes the `struct fwnode_handle` (the data type
   of `fwnode`), then the module will no longer work with the new kernel.
   Moreover, `abidiff` will not show any differences because the module is
   breaking the KMI by directly manipulating internal data structures in ways that
   cannot be captured by only inspecting the binary representation as of now.

Having module versioning enabled prevents all of these issues.

### How to check for CRC mismatch without booting the device?

In the meantime, any full kernel build with `CONFIG_MODVERSIONS` enabled will
generate a `Module.symvers` file as part of the normal build process. The file
has one line for every symbol exported by the kernel (`vmlinux`) and the
modules. Each line consists of the CRC value, symbol name, symbol namespace,
vmlinux/module name exporting the symbol and export type (EXPORT\_SYMBOL vs
EXPORT\_SYMBOL\_GPL).

You can compare the `Module.symvers` files between the GKI build and your build
to check for any CRC differences in the symbols exported by `vmlinux`. If there
is a CRC value difference in any symbol exported by `vmlinux` **AND** is used
by one of the modules you load in your device, the module will fail to load.

If you do not have all the build artifacts, but just have the vmlinux file of
the GKI kernel and your kernel, you can compare the CRC value for a specific
symbol by running the following command on both the kernels and comparing the
output:

```
  $ nm <path to vmlinux>/vmlinux | grep __crc_<symbol name>
```

For example, to check the CRC value for the `module_layout` symbol,

```
  $ nm vmlinux | grep __crc_module_layout
  0000000008663742 A __crc_module_layout
```

### How to fix CRC mismatch?

If you get a CRC mismatch when loading the module, here is how to you fix it:

1. Build the GKI and your kernels, but add the `KBUILD_SYMTYPES=1` in front of
   the command you use to build the kernel. This will generate a `.symtypes`
   files for each `.o` file. For example:

    ```
      $ KBUILD_SYMTYPES=1 \
      BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
    ```

2. Find the `.c` file in which the symbol with CRC mismatch is exported. For example:

    ```
      $ cd common && git grep EXPORT_SYMBOL.*module_layout
      kernel/module.c:EXPORT_SYMBOL(module_layout);
    ```

3. That `.c` file will have a corresponding `.symtypes` file in the GKI and
   your kernel built artifacts.

    ```
      $ cd out/$BRANCH/common && ls -1 kernel/module.*
      kernel/module.o
      kernel/module.o.symversions
      kernel/module.symtypes
    ```

    a. The format of this file is one (potentially very long) line per symbol.

    b. `[s|u|e|etc]#` at the start of the line means the symbol is of data type
       [struct|union|enum|etc]. For example:

    ```
      t#bool typedef _Bool bool
    ```

    c. A missing '#' prefix in the start of the line indicates the symbol is
       a function. For example:

    ```
       find_module s#module * find_module ( const char * )
    ```

4. Compare those two files and fix all the differences.

    **NOTE:** if you use vimdiff, `:set wrap` is recommended

#### Case 1: Differences due to data type visibility

If one kernel keeps a symbol/data type opaque to the modules and the
other kernel does not, then it shows up as a difference between the `.symtypes`
files of the two kernels. The `.symtypes` file from one of the kernels will
have `UNKNOWN` for a symbol and the other `.symtypes` file will have an
expanded view of the symbol/data type.

Say you add this line to `include/linux/device.h` in your kernel:

```
  #include <linux/fwnode.h>
```

That will cause CRC mismatches and one of them would be for `module_layout()`.
If you compare the `module.symtypes` for that symbol, it will look like this:

```
  $ diff -u <GKI>/kernel/module.symtypes \
      <your kernel>/kernel/module.symtypes
  --- <GKI>/kernel/module.symtypes
  +++ <your kernel>/kernel/module.symtypes
  @@ -334,12 +334,15 @@
  ...
  -s#fwnode_handle struct fwnode_handle { UNKNOWN }
  +s#fwnode_reference_args struct fwnode_reference_args { s#fwnode_handle * fwnode ; unsigned int nargs ; t#u64 args [ 8 ] ; }
  ...
```

If your kernel has it as `UNKNOWN` and the GKI kernel has the expanded view of
the symbol (very unlikely), then merge the latest Android Common Kernel into
your kernel so that you are using the latest GKI kernel base.

In most instances, the GKI kernel has it as `UNKNOWN`, but your kernel has the
internal details of the symbol because of changes made to your kernel. This is
because one of the files in your kernel added a `#include` that is not present
in the GKI kernel.

To identify the `#include` that causes the difference, follow these steps:

1. Open the header file that defines the symbol/data type having this
   difference. For example, `include/linux/fwnode.h` for the  `struct
   fwnode_handle`.
2. Add the following code at the top of the header file.

    ```
      #ifdef CRC_CATCH
      #error "Included from here"
      #endif
    ```

3. Then in the module's `.c` file that has a CRC mismatch, add the following as
   the first line before any of the #include lines.

    ```
      #define CRC_CATCH 1
    ```

4. Now compile your module. You will get a build time error that shows the chain
   of header file `#include` that led to this CRC mismatch.

    ```
      In file included from .../drivers/clk/XXX.c:16:
      In file included from .../include/linux/of_device.h:5:
      In file included from .../include/linux/cpu.h:17:
      In file included from .../include/linux/node.h:18:
      .../include/linux/device.h:16:2: error: "Included from here"
      #error "Included from here"
    ```

5. One of the links in this chain of `#include` is due to a change done in your
   kernel, that is missing in the GKI kernel.
6. Once you have identified the change, revert it in your kernel or [upload it to
   ACK and get it merged](https://android.googlesource.com/kernel/common/+/987d0b5bcf096a478aaf96faf5a288b4c95e9d37/README.md).

#### Case 2: Differences due to data type changes

If the CRC mismatch for a symbol/data type is not due to a difference in
visibility, then it is due to actual changes (additions/removals/changes) in
the data type itself. Typically `abidiff` would have caught this, but if it
misses any due to known detection gaps, `CONFIG_MODVERSIONS` would catch it.

Say you make this change in your kernel:

```
  diff --git a/include/linux/iommu.h b/include/linux/iommu.h
  --- a/include/linux/iommu.h
  +++ b/include/linux/iommu.h
  @@ -259,7 +259,7 @@ struct iommu_ops {
     void (*iotlb_sync)(struct iommu_domain *domain);
     phys_addr_t (*iova_to_phys)(struct iommu_domain *domain, dma_addr_t iova);
     phys_addr_t (*iova_to_phys_hard)(struct iommu_domain *domain,
  -        dma_addr_t iova);
  +        dma_addr_t iova, unsigned long trans_flag);
     int (*add_device)(struct device *dev);
     void (*remove_device)(struct device *dev);
     struct iommu_group *(*device_group)(struct device *dev);
```

That will cause a lot of CRC mismatches, but one of them would be for
`devm_of_platform_populate()`.

If you compare the .symtypes for that symbol, it will look like this:

```
  $ diff -u <GKI>/drivers/of/platform.symtypes \
      <your kernel>/drivers/of/platform.symtypes
  --- <GKI>/drivers/of/platform.symtypes
  +++ <your kernel>/drivers/of/platform.symtypes
  @@ -399,7 +399,7 @@
  ...
  -s#iommu_ops struct iommu_ops { ... ; t#phy
  s_addr_t ( * iova_to_phys_hard ) ( s#iommu_domain * , t#dma_addr_t ) ; int
    ( * add_device ) ( s#device * ) ; ...
  +s#iommu_ops struct iommu_ops { ... ; t#phy
  s_addr_t ( * iova_to_phys_hard ) ( s#iommu_domain * , t#dma_addr_t , unsigned long ) ; int ( * add_device ) ( s#device * ) ; ...
```

To identify the changed type, follow these steps:

1. Find the definition of the symbol in the source code (usually `.h` files).
2. If there is a straight forward symbol difference between your kernel and the GKI
   kernel, then do a `git blame` to find the commit.
3. Sometimes a symbol is deleted in a tree and you also want to delete it in
   the other tree. To find the change that deleted the line, run this command
   on the tree where the line was deleted:

    a. `git log -S "copy paste of deleted line/word" -- <file where it was deleted>`

    **NOTE:** Do not copy-paste tabs

    b. You will get a short list of commits. The first one is probably the one
       you are looking for. Otherwise, go through the list until you find the
       commit.

4. Once you have identified the change, revert it in your kernel or [upload it
   to ACK and get it merged](https://android.googlesource.com/kernel/common/+/987d0b5bcf096a478aaf96faf5a288b4c95e9d37/README.md).
