module typus_shark_fin::payoff {
    use std::option::{Self, Option};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;


    // ======== Errors =========

    const E_NO_CONFIG_CONTAINS_NONE: u64 = 888;


    // ======== Structs =========

    struct PayoffConfig has key, store {
        id: UID,
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        low_barrier_roi: Option<u64>,
        high_barrier_roi: Option<u64>,
        high_roi_constant: Option<u64>,
    }

    // ======== Functions =========

    public fun get_payoff_config_is_bullish(payoff_config: &PayoffConfig): bool {
        payoff_config.is_bullish
    }

    public fun get_payoff_config_low_barrier_price(payoff_config: &PayoffConfig): u64 {
        payoff_config.low_barrier_price
    }

    public fun get_payoff_config_high_barrier_price(payoff_config: &PayoffConfig): u64 {
        payoff_config.high_barrier_price
    }

    public fun get_payoff_config_low_barrier_roi(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.low_barrier_roi
    }

    public fun get_payoff_config_high_barrier_roi(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.high_barrier_roi
    }

    public fun get_payoff_config_high_roi_constant(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.high_roi_constant
    }

    public fun new_payoff_config(
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        low_barrier_roi: Option<u64>,
        high_barrier_roi: Option<u64>,
        high_roi_constant: Option<u64>,
        ctx: &mut TxContext
    ): PayoffConfig {
        PayoffConfig {
            id: object::new(ctx),
            is_bullish,
            low_barrier_price,
            high_barrier_price,
            low_barrier_roi,
            high_barrier_roi,
            high_roi_constant,
        }
    }

    // payoff represents the RoI per week
    /// e.g. a bullish shark fin vault: vault_type = 1
    /// low_barrier_roi = 1000, high_barrier_roi = 3000, high_roi_constant = 1500,
    /// low_barrier_price = 5000, high_barrier_price = 6000,
    /// 1. given price = 4000, payoff return = 1000
    /// 2. given price = 6500, payoff return = 1500
    /// 3. given price = 5500, payoff return = 1000 + (3000 - 1000) * (5500 - 5000) / (6000 - 5000) = 2000
    public fun get_shark_fin_payoff_by_price(price: u64, payoff_config: &PayoffConfig): u64{
        // get values from PayoffConfig
        let is_bullish = get_payoff_config_is_bullish(payoff_config);
        let low_barrier_price = get_payoff_config_low_barrier_price(payoff_config);
        let high_barrier_price = get_payoff_config_high_barrier_price(payoff_config);
        let low_barrier_roi = get_payoff_config_low_barrier_roi(payoff_config);
        let high_barrier_roi = get_payoff_config_high_barrier_roi(payoff_config);
        let high_roi_constant = get_payoff_config_high_roi_constant(payoff_config);
        
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
        let payoff_config = new_payoff_config(
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