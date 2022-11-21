module typus_dov::payoff {
    use std::option::{Option};

    struct PayoffConfig has store, drop {
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        low_barrier_roi: Option<u64>,
        high_barrier_roi: Option<u64>,
        high_roi_constant: Option<u64>,
    }

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
    ): PayoffConfig {
        PayoffConfig {
            is_bullish,
            low_barrier_price,
            high_barrier_price,
            low_barrier_roi,
            high_barrier_roi,
            high_roi_constant,
        }
    }
}