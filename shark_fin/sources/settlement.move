// module typus_shark_fin::settlement {
//     use std::string;
//     use sui::table;
//     use typus_framework::utils;
//     use typus_framework::i64;
//     use typus_framework::vault::{Self, VaultRegistry};
//     use typus_shark_fin::payoff;
//     use typus_shark_fin::shark_fin::{Self, Config};

//     const E_VAULT_HAS_BEEN_SETTLED: u64 = 666;

//     // ======== Functions =========

//     fun settle_internal<T>(
//         vault_registry: &mut VaultRegistry<Config>,
//         expired_index: u64,
//     ) {
//         // TODO: check expiration_ts

//         // get price
//         let price = 95; // need to be replaced by oracle price
//         let payoff_config = shark_fin::get_payoff_config(vault::get_config<T, Config>(vault_registry,expired_index));

//         // calculate settlement roi
//         let roi = i64::from(payoff::get_shark_fin_payoff_by_price(price, payoff_config));
//         let roi_multiplier = i64::from(utils::multiplier(payoff::get_roi_decimal()));

//         // calculate payoff for vault user
//         // -> mm payoff = - user total payoff
//         let user_balance_value = vault::get_vault_deposit_value<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"))
//             + vault::get_vault_deposit_value<T, Config>(vault_registry, expired_index, string::utf8(b"regular"));
//         let rolling_share_supply = vault::get_vault_share_supply<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"));
//         let regular_share_supply = vault::get_vault_share_supply<T, Config>(vault_registry, expired_index, string::utf8(b"regular"));
//         let share_supply = rolling_share_supply + regular_share_supply;

//         assert!(user_balance_value == share_supply, E_VAULT_HAS_BEEN_SETTLED);

//         let user_final_balance = i64::div(&i64::mul(&i64::from(user_balance_value),&i64::add(&roi_multiplier, &roi)), &roi_multiplier);

//         let user_total_payoff = i64::sub(&user_final_balance, &i64::from(user_balance_value));
//         let rolling_user_payoff = i64::div(&i64::mul(&user_total_payoff, &i64::from(rolling_share_supply)), &i64::from(share_supply));
//         let regular_user_payoff = i64::sub(&user_total_payoff, &rolling_user_payoff);

//         // internal transfer
//         if (i64::compare(&user_total_payoff, &i64::zero()) != 0) {
//             if (i64::is_neg(&user_total_payoff)) {
//                 // Also rolling_user_payoff & regular_user_payoff are negative
//                 // split user payoff and transfer to mm
//                 let payoff_u64 = i64::as_u64(&i64::abs(&rolling_user_payoff));
//                 let coin = vault::extract_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"), payoff_u64);
//                 vault::join_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"maker"), coin);
//                 let payoff_u64 = i64::as_u64(&i64::abs(&regular_user_payoff));
//                 let coin = vault::extract_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"regular"), payoff_u64);
//                 vault::join_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"maker"), coin);
//             } else if (i64::is_neg(&user_total_payoff)) {
//                 // Also rolling_user_payoff & regular_user_payoff are positive
//                 // split mm payoff and transfer to users
//                 let coin = vault::extract_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"maker"), i64::as_u64(&rolling_user_payoff));
//                 vault::join_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"), coin);
//                 let coin = vault::extract_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"maker"), i64::as_u64(&regular_user_payoff));
//                 vault::join_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"regular"), coin);
//             }
//         }
//         // TODO: calculate performance fee
//     }

//     fun settle_roll_over<T>(
//         vault_registry: &mut VaultRegistry<Config>,
//         expired_index: u64,
//         new_index: u64,
//     ) {
//         // transfer deposit to new vault
//         let rolling_user_balance_value_at_expired = vault::get_vault_deposit_value<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"));
//         let coin = vault::extract_subvault_deposit<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"), rolling_user_balance_value_at_expired);
//         vault::join_subvault_deposit<T, Config>(vault_registry, new_index, string::utf8(b"rolling"), coin);

//         // transfer shares to new vault
//         // adjust the shares for new coming users and combine with table of old users
//         let share_price_decimal = 8;
//         let share_price_multiplier = utils::multiplier(share_price_decimal);

//         // let rolling_user_balance_value_at_expired = vault::get_vault_deposit_value<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"));
//         let rolling_user_share_supply_at_expired = vault::get_vault_share_supply<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"));

//         // combine share supply: use expired balance value instead of expired share
//         vault::add_share_supply<T, Config>(vault_registry, new_index, string::utf8(b"rolling"), rolling_user_balance_value_at_expired);

//         // adjust user share
//         let share_price = share_price_multiplier * rolling_user_balance_value_at_expired / rolling_user_share_supply_at_expired;

//         let i = 0;
//         let n = vault::get_vault_num_user<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"));
//         while (i < n) {
//             let contains = table::contains<u64, address>(vault::get_vault_user_map<T, Config>(vault_registry, expired_index, string::utf8(b"rolling")), i);
//             if (contains) {
//                 let user_address = vault::get_user_address<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"), i);
//                 let adjusted_shares_in_expired_pool = vault::get_user_share<T, Config>(vault_registry, expired_index, string::utf8(b"rolling"), user_address)
//                     * share_price
//                     / share_price_multiplier;

//                 if (table::contains<address, u64>(vault::get_mut_vault_users_table<T, Config>(vault_registry, new_index, string::utf8(b"rolling")), user_address)) {
//                     let user_share = vault::get_mut_user_share<T, Config>(vault_registry, new_index, string::utf8(b"rolling"), user_address);
//                     *user_share = *user_share + adjusted_shares_in_expired_pool;
//                 } else {
//                     table::add<address, u64>(vault::get_mut_vault_users_table<T, Config>(vault_registry, new_index, string::utf8(b"rolling")), user_address, adjusted_shares_in_expired_pool);
//                 };
//             };

//             i = i + 1;
//         };

//     }

//     // fun adjust_vault_stage<T>(dov: &mut Vault<T, Config>, stage: u64) {
//         // let dov_stage = get mut stage
//         // dov_stage = stage;
//     // }

//     public entry fun settle_without_roll_over<T>(
//         vault_registry: &mut VaultRegistry<Config>,
//         expired_index: u64,
//     ) {
//         settle_internal<T>(vault_registry, expired_index);
//     }

//     public entry fun settle_with_roll_over<T>(
//         vault_registry: &mut VaultRegistry<Config>,
//         expired_index: u64,
//         new_index: u64,
//     ) {
//         settle_internal<T>(vault_registry, expired_index);
//         settle_roll_over<T>(vault_registry, expired_index, new_index);
//         // adjust_vault_stage<T>(&mut expired_dov, 4);
//         // adjust_vault_stage<T>(&mut new_dov, 1);
//         // stage: 0 = warmup, 1 = auction, 2 = on-going, 3 = expired, 4 = settled
//     }

//     // ======== Events =========

//     struct VaultCreated has copy, drop {
//         expired_date: u64,
//         fee_percent: u64,
//         deposit_limit: u64,
//         strike: u64,
//     }
// }