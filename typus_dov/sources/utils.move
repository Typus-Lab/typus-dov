// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::utils {
    // decimals
    public fun multiplier(decimal: u64): u64 {
        let i = 0;
        let multi = 1;
        while (i < decimal) {
            multi = multi * 10;
            i = i + 1;
        };
        multi
    }
}