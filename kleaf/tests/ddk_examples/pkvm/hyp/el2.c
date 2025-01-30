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
#include <asm/kvm_pkvm_module.h>

int example_pkvm_module_hyp_init(const struct pkvm_module_ops *ops) {
    return 0;
}
