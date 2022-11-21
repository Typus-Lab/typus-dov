// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::calculation {
    use typus_dov::payoff::{Self, PayoffConfig};
    use std::option;
    const ROI_DECIMAL: u64 = 8;
    const E_NO_CONFIG_CONTAINS_NONE: u64 = 888;
    const E_NO_VAULT_TYPE_NOT_EXIST: u64 = 999;

    // payoff represents the RoI per week
    /// e.g. a bullish shark fin vault: vault_type = 1
    /// low_barrier_roi = 1000, high_barrier_roi = 3000, high_roi_constant = 1500,
    /// low_barrier_price = 5000, high_barrier_price = 6000,
    /// 1. given price = 4000, payoff return = 1000
    /// 2. given price = 6500, payoff return = 1500
    /// 3. given price = 5500, payoff return = 1000 + (3000 - 1000) * (5500 - 5000) / (6000 - 5000) = 2000
    public fun get_shark_fin_payoff_by_price(price: u64, payoff_config: &PayoffConfig): u64{
        // get values from PayoffConfig
        let is_bullish = payoff::get_payoff_config_is_bullish(payoff_config);
        let low_barrier_price = payoff::get_payoff_config_low_barrier_price(payoff_config);
        let high_barrier_price = payoff::get_payoff_config_high_barrier_price(payoff_config);
        let low_barrier_roi = payoff::get_payoff_config_low_barrier_roi(payoff_config);
        let high_barrier_roi = payoff::get_payoff_config_high_barrier_roi(payoff_config);
        let high_roi_constant = payoff::get_payoff_config_high_roi_constant(payoff_config);
        
        assert!(option::is_some(&low_barrier_roi), E_NO_CONFIG_CONTAINS_NONE);
        assert!(option::is_some(&high_barrier_roi), E_NO_CONFIG_CONTAINS_NONE);
        assert!(option::is_some(&high_roi_constant), E_NO_CONFIG_CONTAINS_NONE);

        let low_barrier_roi = option::borrow<u64>(&low_barrier_roi);
        let high_barrier_roi = option::borrow<u64>(&high_barrier_roi);
        let high_roi_constant = option::borrow<u64>(&high_roi_constant);

        // vault_type: bullish shark fin = 1, bearish shark fin = 2
        if (is_bullish) {
            if (price < low_barrier_price) {
                *low_barrier_roi
            } else if (price > high_barrier_price) {
                *high_roi_constant
            } else {
                *low_barrier_roi
                + (*high_barrier_roi - *low_barrier_roi) 
                * (price - low_barrier_price) 
                / (high_barrier_price - low_barrier_price)
            }
        } else {
            if (price > high_barrier_price) {
                *low_barrier_roi
            } else if (price < low_barrier_price) {
                *high_roi_constant
            } else {
                *high_barrier_roi
                - (*high_barrier_roi - *low_barrier_roi) 
                * (price - low_barrier_price) 
                / (high_barrier_price - low_barrier_price)
            }
        }
    }

    #[test]
    /// get_shark_fin_payoff_by_price
    fun test_get_shark_fin_payoff_by_price() {
        use std::debug;
        use std::option;
        use typus_dov::payoff;
        let payoff_config = payoff::new_payoff_config(
            false,
            5000,
            6000,
            option::some<u64>(1000),
            option::some<u64>(3000),
            option::some<u64>(1500),
        );
        let aa = get_shark_fin_payoff_by_price(
            5000,
            &payoff_config
        );
        debug::print(&aa);
        
    }
}
