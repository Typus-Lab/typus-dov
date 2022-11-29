module typus_covered_call::payoff {
    use std::option::{Self, Option};
    use typus_dov::i64::{Self, I64};
    use typus_dov::utils;
    use typus_dov::asset::Asset;

    friend typus_covered_call::covered_call;
    friend typus_covered_call::settlement;

    // ======== Constants =========

    const ROI_DECIMAL: u64 = 8;

    // ======== Errors =========

    const E_NO_CONFIG_CONTAINS_NONE: u64 = 888;

    // ======== Structs =========

    struct PayoffConfig has store, drop {
        asset: Asset,
        strike: u64,
        premium_roi: Option<u64>,
    }

    // ======== Functions =========

    public fun get_roi_decimal(): u64 {
        ROI_DECIMAL
    }

    public(friend) fun new_payoff_config(
        asset: Asset,
        strike: u64,
        premium_roi: Option<u64>,
    ): PayoffConfig {
        PayoffConfig {
            asset,
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
        let strike = payoff_config.strike;
        let premium_roi = payoff_config.premium_roi;
        
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
}