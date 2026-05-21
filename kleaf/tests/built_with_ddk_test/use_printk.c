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

/*
Reference: https://docs.kernel.org/core-api/printk-basics.html
*/

#define pr_fmt(fmt) "%s:%s: " fmt, KBUILD_MODNAME, __func__

#include <linux/module.h> // Transitively includes <linux/printk.h>

MODULE_DESCRIPTION("A test module for DDK testing purposes");
MODULE_AUTHOR("Ulises Mendez Martinez <umendez@google.com>");
MODULE_LICENSE("GPL v2");

void use_printk(void) {
    printk(KERN_INFO "Hello world!\n");
    pr_info("Bye World!\n");
}

