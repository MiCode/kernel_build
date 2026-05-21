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

"""Tests utils.combine_depset()"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//build/kernel/kleaf/impl:utils.bzl", "utils")

def _assert_equal(x, y):
    if x != y:
        fail("{} != {}".format(x, y))

def _combine_depset_impl(ctx):
    empty_depset = depset()
    nested_empty = depset([], transitive = [])
    nested_nested_empty = depset([], transitive = [empty_depset])
    nested_nested_copy_empty = depset([], transitive = [depset()])
    empties = [empty_depset, nested_empty, nested_nested_empty, nested_nested_copy_empty]

    one_depset = depset([1])
    nested_one = depset(transitive = [one_depset])
    nested_copy_one = depset(transitive = [depset([1])])
    ones = [one_depset, nested_one, nested_copy_one]

    # Combine against empty
    for empty in empties:
        for one in ones:
            # This intentionally doesn't use depset_equal() because we want to
            # check that the returned object reference is `one`. That is, a
            # depset X combining against an empty depset should yield X itself.
            _assert_equal(one, utils.combine_depset(empty, one))
            _assert_equal(one, utils.combine_depset(one, empty))

    # Check ordering: x goes before y
    for one in ones:
        _assert_equal([1, 2], utils.combine_depset(one, depset([2])).to_list())
        _assert_equal([2, 1], utils.combine_depset(depset([2]), one).to_list())

    file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(file, "")
    return DefaultInfo(files = depset([file]))

_combine_depset = rule(implementation = _combine_depset_impl)

def combine_depset_test(name):
    """Checks utils.combine_depset()"""
    _combine_depset(name = name + "_internal")
    build_test(
        name = name,
        targets = [name + "_internal"],
    )
