// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::utils {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

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

    // extract balance from coin
    public fun extract_balance_from_coin<Token>(coin: &mut Coin<Token>, value: u64): Balance<Token> {
        let balance = coin::balance_mut(coin);
        balance::split(balance, value)
    }

    #[test]
    public fun test_i64() {
        use typus_dov::i64;
        use std::debug;
        let a = i64::from(10);
        let b = i64::from(6);
        let a1 = i64::from(4);
        let b1 = i64::from(0);
        let d = i64::sub(&b, &a);
        let d1 = i64::sub(&b1, &a1);
        let d2 = i64::add(&d, &i64::from(4));
        debug::print(&a,);
        debug::print(&d1);
        debug::print(&d2);
        // debug::print(&i64::as_u64(&d1));
    }
}