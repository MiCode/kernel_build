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

// This code is here to showcase how local defines can be used.
// See BUILD.bazel where it is being defined.
#if !defined(FOO)
#error el2.c must be compiled with -DFOO!
#endif

int example_pkvm_module_hyp_init(const struct pkvm_module_ops *ops) {
    return 0;
}
