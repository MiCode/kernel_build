# Kunit with Kleaf

These examples demonstrate how to run Kunit tests for the Android kernel. Kleaf
is able to support both in-tree and out-of-tree (DDK) Kunit test modules.

Tests with both in-tree and out-of-tree test modules can be set up with the help
of the [`kunit_test`](../../docs/api_reference/kernel.md#kunit_test) Bazel rule.
Examples of in-tree and out-of-tree tests can be found in [in_tree/](in_tree/)
and [out_of_tree/](out_of_tree/) directories respectively.

## Test setup

A couple of things need to be ensured before running a Kunit test with Kleaf.

1.  ADB should be installed on the host machine and the device running the
    kernel under test must be discoverable by ADB.
1.  Kunit test framework should be available (and enabled) on the device under
    test. In case Kunit is not available, it can be installed using `insmod
    kunit.ko enable=1`.

## Running the test

Once the test setup is complete, Kunit tests can simply be run with the help of
`bazel test` verb as follows:

```
bazel test //path/to/kunit/test:target --test_arg=--device="<device_serial>"
```

Bazel outputs the outcome of the test and prints the full Kunit test report in
case of a test failure.

Note that the `device` test argument can be skipped if only 1 device is
connected to the host machine.
