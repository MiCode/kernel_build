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
