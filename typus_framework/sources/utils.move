// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_framework::utils {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use std::vector;

    const E_ZERO_VALUE: u64 = 0;
    const E_INVALID_VALUE: u64 = 1;

    // decimals
    public fun multiplier(decimal: u64): u64 {
        let i = 0;
        let multiplier = 1;
        while (i < decimal) {
            multiplier = multiplier * 10;
            i = i + 1;
        };
        multiplier
    }

    // ensure value > 0 and valid
    public fun ensure_value(value: u64, decimal: u64) {
        assert!(value > 0, E_ZERO_VALUE);
        let multiplier = multiplier(decimal);
        assert!(value / multiplier > 0 && value % multiplier == 0, E_INVALID_VALUE)
    }

    // extract balance from coin
    public fun extract_balance_from_coin<Token>(coin: &mut Coin<Token>, value: u64): Balance<Token> {
        balance::split(coin::balance_mut(coin), value)
    }

    public fun merge_coins<Token>(coins: vector<Coin<Token>>): Coin<Token> {
        let len = vector::length(&coins);
        let merged = vector::pop_back(&mut coins);
        len = len - 1;
        while (len > 0) {
            let removed = vector::pop_back(&mut coins);
            coin::join(&mut merged, removed);
            len = len - 1;
        };
        vector::destroy_empty(coins);
        merged
    }
}