module typus_covered_call::settlement {
    use std::string;
    use sui::table;
    use sui::balance;
    use typus_dov::utils;
    use typus_dov::i64;
    use typus_dov::vault::{Self, Vault};
    use typus_covered_call::payoff::{Self, Config};

    const E_VAULT_HAS_BEEN_SETTLED: u64 = 666;

    // ======== Structs =========

    // ======== Functions =========

    fun settle_internal<T>(dov: &mut Vault<T, Config>){
        // get price
        let price = 1; // need to be replaced by oracle price
        let payoff_config = payoff::get_payoff_config(vault::get_config(dov));

        // calculate settlement roi
        let roi = payoff::get_covered_call_payoff_by_price(price, payoff_config);
        let roi_multiplier = i64::from(utils::multiplier(payoff::get_roi_decimal()));

        // calculate payoff for vault user
        // -> mm payoff = - user total payoff

        let user_balance_value = balance::value<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"rolling")))
            + balance::value<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"regular")));
        let rolling_share_supply = *vault::get_vault_share_supply<T, Config>(dov, string::utf8(b"rolling"));
        let regular_share_supply = *vault::get_vault_share_supply<T, Config>(dov, string::utf8(b"regular"));
        let share_supply = rolling_share_supply + regular_share_supply;

        assert!(user_balance_value == share_supply, E_VAULT_HAS_BEEN_SETTLED);

        let user_final_balance = i64::div(&i64::mul(&i64::from(user_balance_value),&i64::add(&roi_multiplier, &roi)), &roi_multiplier);
        
        let user_total_payoff = i64::sub(&user_final_balance, &i64::from(user_balance_value));
        let rolling_user_payoff = i64::div(&i64::mul(&user_total_payoff, &i64::from(rolling_share_supply)), &i64::from(share_supply));
        let regular_user_payoff = i64::sub(&user_total_payoff, &rolling_user_payoff);

        // internal transfer
        if (i64::compare(&user_total_payoff, &i64::zero()) != 0) {
            if (i64::is_neg(&user_total_payoff)){
                // Also rolling_user_payoff & regular_user_payoff are negative
                // split user payoff and transfer to mm
                let payoff_u64 = i64::as_u64(&i64::abs(&rolling_user_payoff));
                let coin = balance::split<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"rolling")), payoff_u64);
                balance::join<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"maker")), coin);
                let payoff_u64 = i64::as_u64(&i64::abs(&regular_user_payoff));
                let coin = balance::split<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"regular")), payoff_u64);
                balance::join<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"maker")), coin);
            } else if (i64::is_neg(&user_total_payoff)){
                // Also rolling_user_payoff & regular_user_payoff are positive
                // split mm payoff and transfer to users
                let coin = balance::split<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"maker")), i64::as_u64(&rolling_user_payoff));
                balance::join<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"rolling")), coin);
                let coin = balance::split<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"maker")), i64::as_u64(&regular_user_payoff));
                balance::join<T>(vault::get_mut_vault_deposit<T, Config>(dov, string::utf8(b"regular")), coin);
            }
        }
        // TODO: calculate performance fee
    }

    fun settle_roll_over<T>(
        expired_dov: &mut Vault<T, Config>,
        new_dov: &mut Vault<T, Config>,
    ){
        // transfer deposit to new vault
        let rolling_user_balance_value_at_expired = balance::value<T>(vault::get_mut_vault_deposit<T, Config>(expired_dov, string::utf8(b"rolling")));
        let rolling_user_balance_at_new = vault::get_mut_vault_deposit<T, Config>(new_dov, string::utf8(b"rolling"));
        let coin =  balance::split<T>(
            vault::get_mut_vault_deposit<T, Config>(expired_dov, string::utf8(b"rolling")),
            rolling_user_balance_value_at_expired
        );
        balance::join<T>(rolling_user_balance_at_new, coin);

        // transfer shares to new vault
        // adjust the shares for new coming users and combine with table of old users
        let share_price_decimal = 8;
        let share_price_multiplier = utils::multiplier(share_price_decimal);

        let rolling_user_balance_value_at_expired = balance::value<T>(vault::get_mut_vault_deposit<T, Config>(expired_dov, string::utf8(b"rolling")));
        let rolling_user_share_supply_at_expired = vault::get_vault_share_supply<T, Config>(expired_dov, string::utf8(b"rolling"));

        // combine share supply: use expired balance value instead of expired share
        vault::add_share_supply<T, Config>(new_dov, string::utf8(b"rolling"), rolling_user_balance_value_at_expired);

        // adjust user share
        let share_price = share_price_multiplier * rolling_user_balance_value_at_expired / *rolling_user_share_supply_at_expired;

        let expired_dov_users_table = vault::get_vault_users_table<T, Config>(expired_dov, string::utf8(b"rolling"));
        let new_dov_users_table = vault::get_mut_vault_users_table<T, Config>(new_dov, string::utf8(b"rolling"));

        let i = 0;
        let n = *vault::get_vault_user_index<T, Config>(expired_dov, string::utf8(b"rolling"));
        while (i < n) {
            if (table::contains<u64, address>(vault::get_vault_user_map<T, Config>(expired_dov, string::utf8(b"rolling")), i)) {
                let user_address = table::borrow<u64, address>(vault::get_vault_user_map<T, Config>(expired_dov, string::utf8(b"rolling")), i);
                let adjusted_shares_in_expired_pool = *table::borrow<address, u64>(expired_dov_users_table, *user_address) 
                    * share_price 
                    / share_price_multiplier;

                if (table::contains<address, u64>(new_dov_users_table, *user_address)){
                    let user_share = table::borrow_mut<address, u64>(new_dov_users_table, *user_address);
                    *user_share = *user_share + adjusted_shares_in_expired_pool;
                } else {
                    table::add<address, u64>(new_dov_users_table, *user_address, adjusted_shares_in_expired_pool);
                };
            };
            
            i = i + 1;
        };
        
    }

    // fun adjust_vault_stage<T>(dov: &mut Vault<T, Config>, stage: u64) {
        // let dov_stage = get mut stage
        // dov_stage = stage;
    // }

    // public entry fun settle_without_roll_over<T>(
    //     expired_dov: Vault<T, Config>,
    // ){
        // settle_internal<T>(&mut expired_dov);
    // }

    // public entry fun settle_with_roll_over<T>(
    //     expired_dov: Vault<T, Config>,
    //     new_dov: Vault<T, Config>,
    // ){
        // settle_internal<T>(&mut expired_dov);
        // settle_roll_over<T>(&mut expired_dov, &mut new_dov);
        // adjust_vault_stage<T>(&mut expired_dov, 4);
        // adjust_vault_stage<T>(&mut new_dov, 1);
        // stage: 0 = warmup, 1 = auction, 2 = on-going, 3 = expired, 4 = settled
    // }

    // ======== Events =========

    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        strike: u64,
    }
}