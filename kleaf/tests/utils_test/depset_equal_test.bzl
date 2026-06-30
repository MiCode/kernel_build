# Copyright (C) 2025 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Tests utils.depset_equal()"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")

def _assert_depset_equal(x, y):
    if not utils.depset_equal(x, y):
        fail("depset_equal({}, {}) is false".format(x, y))
    if not utils.depset_equal(y, x):
        fail("depset_equal({}, {}) is false".format(y, x))

def _assert_depset_not_equal(x, y):
    if utils.depset_equal(x, y):
        fail("depset_equal({}, {}) is true".format(x, y))
    if utils.depset_equal(y, x):
        fail("depset_equal({}, {}) is true".format(y, x))

def _depset_equal_impl(ctx):
    empty_depset = depset()
    nested_empty = depset([], transitive = [])
    nested_nested_empty = depset([], transitive = [empty_depset])
    nested_nested_copy_empty = depset([], transitive = [depset()])

    one_depset = depset([1])
    nested_one = depset(transitive = [one_depset])
    nested_copy_one = depset(transitive = [depset([1])])

    empties = [empty_depset, nested_empty, nested_nested_empty, nested_nested_copy_empty]
    for i in range(len(empties)):
        for j in range(i, len(empties)):
            _assert_depset_equal(empties[i], empties[j])

    ones = [one_depset, nested_one, nested_copy_one]
    for i in range(len(ones)):
        for j in range(i, len(ones)):
            _assert_depset_equal(ones[i], ones[j])

    for empty in empties:
        for one in ones:
            _assert_depset_not_equal(empty, one)

    file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(file, "")
    return DefaultInfo(files = depset([file]))

_depset_equal = rule(implementation = _depset_equal_impl)

def depset_equal_test(name):
    """Checks utils.depset_equal()"""
    _depset_equal(name = name + "_internal")
    build_test(
        name = name,
        targets = [name + "_internal"],
    )
