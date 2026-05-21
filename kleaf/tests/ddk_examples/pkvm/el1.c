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

#include <linux/init.h>
#include <linux/module.h>
#include <asm/kvm_pkvm_module.h>

int __kvm_nvhe_example_pkvm_module_hyp_init(const struct pkvm_module_ops *ops);

static int __init example_pkvm_module_init(void)
{
    unsigned long token;

    return pkvm_load_el2_module(__kvm_nvhe_example_pkvm_module_hyp_init, &token);
}
module_init(example_pkvm_module_init);

MODULE_DESCRIPTION("An example module for Kleaf demonstration purposes");
MODULE_AUTHOR("Hong, Yifan <elsk@google.com>");
MODULE_LICENSE("GPL v2");
