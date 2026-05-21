/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2025 Google, Inc.
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#include <kunit/test.h>
#include <linux/math.h>
#include <linux/module.h>

MODULE_DESCRIPTION("An example test module for kunit");
MODULE_AUTHOR("Siddharth Nayyar <sidnayyar@google.com>");
MODULE_LICENSE("GPL v2");

static void test_success(struct kunit *test)
{
        KUNIT_EXPECT_EQ(test, 3, abs_diff(8, 5));
        KUNIT_EXPECT_EQ(test, 1, mult_frac(3, 2, 6));
        KUNIT_EXPECT_EQ(test, 9, rounddown(10, 3));
}

static void test_failure(struct kunit *test)
{
        KUNIT_FAIL(test, "This test never passes.");
}

static struct kunit_case example_test_cases[] = {
        KUNIT_CASE(test_success),
        KUNIT_CASE(test_failure),
        {}
};

static struct kunit_suite example_test_suite = {
        .name = "ddk-example",
        .test_cases = example_test_cases,
};
kunit_test_suite(example_test_suite);
