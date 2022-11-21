module typus_shark_fin::payoff {
    use std::option::{Self, Option};
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;


    // ======== Errors =========

    const E_NO_CONFIG_CONTAINS_NONE: u64 = 888;

    // ======== Structs =========

    struct PayoffConfig has store, drop {
        id: UID,
        strike: u64,
        premium_roi: Option<u64>,
    }
    // ======== Functions =========

    public fun get_payoff_config_strike(payoff_config: &PayoffConfig): u64 {
        payoff_config.strike
    }

    public fun get_payoff_config_premium_roi(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.premium_roi
    }


    public fun new_payoff_config(
        strike: u64,
        premium_roi: Option<u64>,
        ctx: &mut TxContext
    ): PayoffConfig {
        PayoffConfig {
            id: object::new(ctx),
            strike,
            premium_roi,
        }
    }

    // payoff represents the RoI per week
    /// e.g. a covered call vault:
    /// premium_roi = 1000, strike = 5000
    /// 1. given price = 4000, payoff return = premium = 1000
    /// 2. given price = 5500, payoff return = 1000 - ROI_DECIMAL * (5500 - 5000) / 5000 = -4000 = -999_000
    public fun get_covered_call_payoff_by_price(price: u64, payoff_config: &PayoffConfig): I64{
        // get values from PayoffConfig
        let strike = get_payoff_config_strike(payoff_config);
        let premium_roi = get_payoff_config_premium_roi(payoff_config);
        
        assert!(option::is_some(&premium_roi), E_NO_CONFIG_CONTAINS_NONE);

        let premium_roi = option::borrow<u64>(&premium_roi);

        if (price < strike) {
            i64::from(*premium_roi)
        } else {
            i64::sub(
                &i64::from(*premium_roi),
                &i64::from(utils::multiplier(ROI_DECIMAL) * (price - strike) / strike)
            )
        }
    }

    #[test]
    /// get_shark_fin_payoff_by_price
    fun test_get_covered_call_payoff_by_price() {
        use std::debug;
        use std::option;
        let payoff_config = new_payoff_config(
            5000,
            option::some<u64>(1000),
        );
        let aa = get_covered_call_payoff_by_price(
            6000,
            &payoff_config
        );
        debug::print(&i64::is_neg(&aa));
        debug::print(&i64::abs(&aa));
        if (i64::is_neg(&aa)){
            debug::print(&i64::neg(&aa));
        }
    }
}