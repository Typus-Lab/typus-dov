// module typus_shark_fin::payoff {
//     use std::option::{Self, Option};
//     use typus_framework::asset::Asset;

//     // ======== Friends =========

//     friend typus_shark_fin::shark_fin;
//     friend typus_shark_fin::settlement;

//     #[test_only]
//     friend typus_shark_fin::test;

//     // ======== Constants =========

//     const ROI_DECIMAL: u64 = 8;

//     // ======== Structs =========

//     struct PayoffConfig has store, drop {
//         asset: Asset,
//         is_bullish: bool,
//         low_barrier_price: u64,
//         high_barrier_price: u64,
//         low_barrier_roi: Option<u64>,
//         high_barrier_roi: Option<u64>,
//         high_roi_constant: Option<u64>,
//     }

//     // ======== Functions =========

//     public fun get_roi_decimal(): u64 {
//         ROI_DECIMAL
//     }

//     public(friend) fun new_payoff_config(
//         asset: Asset,
//         is_bullish: bool,
//         low_barrier_price: u64,
//         high_barrier_price: u64,
//         low_barrier_roi: Option<u64>,
//         high_barrier_roi: Option<u64>,
//         high_roi_constant: Option<u64>,
//     ): PayoffConfig {
//         PayoffConfig {
//             asset,
//             is_bullish,
//             low_barrier_price,
//             high_barrier_price,
//             low_barrier_roi,
//             high_barrier_roi,
//             high_roi_constant,
//         }
//     }

//     public(friend) fun set_low_barrier_roi(payoff_config: &mut PayoffConfig, low_barrier_roi: u64) {
//         option::fill(&mut payoff_config.low_barrier_roi, low_barrier_roi);
//     }
//     public(friend) fun set_high_barrier_roi(payoff_config: &mut PayoffConfig, high_barrier_roi: u64) {
//         option::fill(&mut payoff_config.high_barrier_roi, high_barrier_roi);
//     }
//     public(friend) fun set_high_roi_constant(payoff_config: &mut PayoffConfig, high_roi_constant: u64) {
//         option::fill(&mut payoff_config.high_roi_constant, high_roi_constant);
//     }

//     /// payoff represents the RoI per week
//     /// e.g. a bullish shark fin vault: vault_type = 1
//     /// low_barrier_roi = 1000, high_barrier_roi = 3000, high_roi_constant = 1500,
//     /// low_barrier_price = 5000, high_barrier_price = 6000,
//     /// 1. given price = 4000, payoff return = 1000
//     /// 2. given price = 6500, payoff return = 1500
//     /// 3. given price = 5500, payoff return = 1000 + (3000 - 1000) * (5500 - 5000) / (6000 - 5000) = 2000
//     public fun get_shark_fin_payoff_by_price(price: u64, payoff_config: &PayoffConfig): u64{
//         // get values from PayoffConfig
//         let low_barrier_price = payoff_config.low_barrier_price;
//         let high_barrier_price = payoff_config.high_barrier_price;
//         let low_barrier_roi = payoff_config.low_barrier_roi;
//         let high_barrier_roi = payoff_config.high_barrier_roi;
//         let high_roi_constant = payoff_config.high_roi_constant;

//         let low_barrier_roi = option::borrow<u64>(&low_barrier_roi);
//         let high_barrier_roi = option::borrow<u64>(&high_barrier_roi);
//         let high_roi_constant = option::borrow<u64>(&high_roi_constant);

//         // vault_type: bullish shark fin = 1, bearish shark fin = 2
//         if (payoff_config.is_bullish) {
//             if (price < low_barrier_price) {
//                 *low_barrier_roi
//             } else if (price > high_barrier_price) {
//                 *high_roi_constant
//             } else {
//                 *low_barrier_roi
//                 + (*high_barrier_roi - *low_barrier_roi)
//                 * (price - low_barrier_price)
//                 / (high_barrier_price - low_barrier_price)
//             }
//         } else {
//             if (price > high_barrier_price) {
//                 *low_barrier_roi
//             } else if (price < low_barrier_price) {
//                 *high_roi_constant
//             } else {
//                 *high_barrier_roi
//                 - (*high_barrier_roi - *low_barrier_roi)
//                 * (price - low_barrier_price)
//                 / (high_barrier_price - low_barrier_price)
//             }
//         }
//     }
// }
