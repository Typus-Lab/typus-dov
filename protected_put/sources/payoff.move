module typus_protected_put::payoff {
    use std::option::{Self, Option};
    use typus_framework::i64::{Self, I64};
    use typus_framework::utils;
    use typus_framework::asset::Asset;

    friend typus_protected_put::protected_put;

    #[test_only]
    friend typus_protected_put::test;

    // ======== Constants =========

    const ROI_PCT_DECIMAL: u64 = 8;
    const OTM_PCT_DECIMAL: u64 = 4;
    const EXPOSURE_RATIO_DECIMAL: u64 = 8;

    // ======== Errors =========

    const E_NO_CONFIG_CONTAINS_NONE: u64 = 888;

    // ======== Structs =========

    struct PayoffConfig has store, drop, copy {
        underlying_asset: Asset,
        strike_otm_pct: u64,
        strike: Option<u64>,
        premium_roi: Option<u64>,
        exposure_ratio: Option<u64>
    }

    // ======== Functions =========

    public fun get_underlying_asset(payoff_config: &PayoffConfig): Asset {
        payoff_config.underlying_asset
    }

    public fun get_otm_decimal(): u64 {
        OTM_PCT_DECIMAL
    }

    public fun get_roi_decimal(): u64 {
        ROI_PCT_DECIMAL
    }

    public(friend) fun new_payoff_config(
        underlying_asset: Asset,
        strike_otm_pct: u64,
        strike: Option<u64>,
        premium_roi: Option<u64>,
        exposure_ratio: Option<u64>
    ): PayoffConfig {
        PayoffConfig {
            underlying_asset,
            strike_otm_pct,
            strike,
            premium_roi,
            exposure_ratio
        }
    }

    public(friend) fun set_premium_roi(payoff_config: &mut PayoffConfig, premium_roi: u64) {
        option::fill(&mut payoff_config.premium_roi, premium_roi);
    }

    public(friend) fun set_exposure_ratio(payoff_config: &mut PayoffConfig, exposure_ratio: u64) {
        option::fill(&mut payoff_config.exposure_ratio, exposure_ratio);
    }

    public(friend) fun set_strike(payoff_config: &mut PayoffConfig, strike: u64) {
        option::fill(&mut payoff_config.strike, strike);
    }

    // payoff represents the RoI per week
    /// e.g. a protected put vault:
    /// premium_roi = 1_000_000, strike = 5_000, ROI_PCT_MULTIPLIER = 100_000_000, exposure_ratio = 100_000_000
    /// 1. given price = 5_500, payoff return = premium = 1_000_000
    /// 2. given price = 4_000, payoff return = 1_000_000 - 1 * 100_000_000 * (5_000 - 4_000) / 5_000 = -19_000_000
    public fun get_protected_put_payoff_by_price(price: u64, payoff_config: &PayoffConfig): I64{
        // get values from PayoffConfig
        let strike = payoff_config.strike;
        let premium_roi = payoff_config.premium_roi;
        let exposure_ratio = payoff_config.exposure_ratio;

        assert!(option::is_some(&strike), E_NO_CONFIG_CONTAINS_NONE);
        assert!(option::is_some(&premium_roi), E_NO_CONFIG_CONTAINS_NONE);
        assert!(option::is_some(&exposure_ratio), E_NO_CONFIG_CONTAINS_NONE);

        let strike = option::borrow<u64>(&strike);
        let premium_roi = option::borrow<u64>(&premium_roi);
        let exposure_ratio = option::borrow<u64>(&exposure_ratio);

        if (price > *strike) {
            i64::from(*premium_roi)
        } else {
            i64::sub(
                &i64::from(*premium_roi),
                &i64::from(
                    (utils::multiplier(ROI_PCT_DECIMAL) * (*strike - price) / *strike)
                    * *exposure_ratio / utils::multiplier(EXPOSURE_RATIO_DECIMAL)
                )
            )
        }
    }
}