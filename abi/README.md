ABI Monitoring Utilities
========================

This directory contains scripts and utilities to compare, track and mitigate
changes to the kernel ABI. The comparison framework used is
[libabigail](https://sourceware.org/libabigail/), but this might change in the
future. Follow the instructions below to set up the current prerequisites.

Set up the prerequisites
------------------------
The script `bootstrap` will install the system prerequisites
 - libxml2-dev
 - elfutils

It will then acquire the libabigail sources and build the required binaries.
At the very end the script will print instructions how to add the binaries to
the local `${PATH}` to be used by the remaining utilities.

You can skip this step if your host system provides a suitable version of the
libabigail tooling including the binaries `abidw` and `abidiff`.


Creating ABI dumps from kernel trees
------------------------------------
Provided a linux kernel tree with built vmlinux and kernel modules, the tool
`dump_abi` creates an ABI representation using the selected abi tool. As of now
there is only one option: 'libabigail' (default). A sample invocation looks as
follows:
  $ dump_abi --linux-tree path/to/out --out-file /path/to/abidump.out


Comparing ABI dumps
-------------------
ABI dumps created by `dump_abi` can be compared with `diff_abi`. Ensure to use
the same abi-tool for `dump_abi` and `diff_abi`. A sample invocation looks as
follows:
  $ diff_abi --baseline dump1.out --new dump2.out --report report.out

The report created is tool specific, but generally lists ABI changes detected
that affect the Kernel's module interface.
