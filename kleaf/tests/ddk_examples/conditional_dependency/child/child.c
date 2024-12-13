/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2024 Google, Inc.
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

#include <linux/module.h>
#include "parent/parent_do_thing.h"

void child_do_thing(void) {
    parent_do_thing();
}

MODULE_DESCRIPTION("An example module for Kleaf demonstration purposes");
MODULE_AUTHOR("Hong, Yifan <elsk@google.com>");
MODULE_LICENSE("GPL v2");
