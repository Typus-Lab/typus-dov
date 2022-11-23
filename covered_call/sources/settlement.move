module typus_covered_call::settlement {
    use std::vector;
    use sui::table;
    use sui::balance;
    use typus_dov::utils;
    use typus_dov::i64;
    use typus_dov::vault::{Self, Vault};
    use typus_covered_call::payoff::{Self, PayoffConfig};

    // ======== Structs =========

    // ======== Functions =========

    fun settle_internal<T>(dov: &Vault<T, PayoffConfig>){
        // get price
        let price = 1; // need to be replaced by oracle price
        // let dov = vault::get_vault<T, P>
        let payoff_config = payoff::get_payoff_config_by_vault<T>(dov);
        // calculate settlement roi
        let roi = payoff::get_covered_call_payoff_by_price(price, payoff_config);
        let roi_multiplier = i64::from(utils::multiplier(payoff::get_roi_decimal()));
        // calculate payoff for vault user
        let user_balance = balance::value<T>(vault::get_vault_deposit<T, PayoffConfig>(dov));
        let user_final_balance = i64::div(&i64::mul(&i64::from(user_balance),&i64::add(&roi_multiplier, &roi)), &roi_multiplier);

        // calculate payoff for mm
        // get mm_balance from vault
        // mm_final_balance = mm_balance + diff, which diff = user_final_balance - user_balance
        
        // internal transfer
        if (!i64::is_neg(&user_final_balance)){
            if (i64::as_u64(&user_final_balance) > user_balance) {
                // transfer mm margin into vault.deposit
            } else if (i64::as_u64(&user_final_balance) < user_balance) {
                // transfer vault.deposit into mm margin
            }
        }

        // calculate performance fee
        

    }

    fun settle_roll_over<T>(
        expired_dov: &mut Vault<T, PayoffConfig>,
        new_dov: &mut Vault<T, PayoffConfig>,
        roll_over_list: &vector<address>,
    ){
        // transfer deposit to new vault
        // ???

        // transfer shares to new vault
        // adjust the shares for new coming users and combine with table of old users
        let share_price_decimal = 8;
        let share_price_multiplier = utils::multiplier(share_price_decimal);
        let user_balance_value = balance::value<T>(vault::get_vault_deposit<T, PayoffConfig>(expired_dov));
        let share_supply = vault::get_vault_share_supply<T, PayoffConfig>(expired_dov);

        // combine share supply
        vault::add_share_supply<T, PayoffConfig>(new_dov, user_balance_value);

        // adjust user share
        let share_price = share_price_multiplier * user_balance_value / *share_supply;
        let expired_dov_users_table = vault::get_vault_users_table<T, PayoffConfig>(expired_dov);
        
        let new_dov_users_table = vault::get_mut_vault_users_table<T, PayoffConfig>(new_dov);

        let i = 0;
        let n = vector::length<address>(roll_over_list);
        while (i < n) {
            let user_address = vector::borrow<address>(roll_over_list, i);
            let adjusted_shares_in_expired_pool = *table::borrow<address, u64>(expired_dov_users_table, *user_address) * share_price / share_price_multiplier;
            if (table::contains<address, u64>(new_dov_users_table, *user_address)){
                let user_share = table::borrow_mut<address, u64>(new_dov_users_table, *user_address);
                *user_share = *user_share + adjusted_shares_in_expired_pool;
            } else {
                table::add<address, u64>(new_dov_users_table, *user_address, adjusted_shares_in_expired_pool);
            };
            i = i + 1;
        };
        
    }

    fun adjust_vault_stage<T>(dov: &mut Vault<T, PayoffConfig>, stage: u64) {
        // let dov_stage = get mut stage
        // dov_stage = stage;
    }

    public entry fun settle_with_roll_over<T>(
        expired_dov: Vault<T, PayoffConfig>,
        new_dov: Vault<T, PayoffConfig>,
        roll_over_list: &vector<address>,
    ){
        settle_internal<T>(&expired_dov);
        settle_roll_over<T>(&mut expired_dov, &mut new_dov, roll_over_list);
        adjust_vault_stage<T>(&mut expired_dov, 4);
        adjust_vault_stage<T>(&mut new_dov, 1);
        // stage: 0 = warmup, 1 = auction, 2 = on-going, 3 = expired, 4 = settled
    }

    // ======== Events =========

    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        strike: u64,
    }
}