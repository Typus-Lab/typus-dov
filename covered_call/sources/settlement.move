module typus_covered_call::settlement {
    use std::string;
    use std::debug;
    use std::option;
    
    use typus_dov::utils;
    use typus_dov::i64;
    use typus_dov::vault;

    use typus_covered_call::payoff;
    use typus_covered_call::covered_call::{Self, Config, ManagerCap, Registry};

    use typus_oracle::oracle::{Self, Oracle};

    const E_VAULT_HAS_BEEN_SETTLED: u64 = 666;
    // ======== Functions =========

    fun settle_internal<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut Registry<ManagerCap<Config>>,
        expired_index: u64,
        price_oracle: &Oracle<TOKEN>,
    ) {
        let config = covered_call::get_config<ManagerCap<Config>, TOKEN, Config>(vault_registry, expired_index); 

        let (price, _decimal, unix_ms, _epoch) = oracle::get_oracle<TOKEN>(price_oracle);

        covered_call::check_already_expired(config, unix_ms);

        let payoff_config = covered_call::get_payoff_config(config);

        debug::print(payoff_config);

        // calculate settlement roi
        let roi = payoff::get_covered_call_payoff_by_price(price, payoff_config);
        let roi_multiplier = utils::multiplier(payoff::get_roi_decimal());

        debug::print(&string::utf8(b"roi"));
        debug::print(&roi);

        let share_price_decimal = 8;
        let settled_share_price = if (!i64::is_neg(&roi)) {
            utils::multiplier(share_price_decimal) * (roi_multiplier + i64::as_u64(&roi)) / roi_multiplier
        } else {
            utils::multiplier(share_price_decimal) * (roi_multiplier + i64::as_u64(&i64::abs(&roi))) / roi_multiplier
        };

        let expired_vault = covered_call::get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
            vault_registry,
            expired_index
        );

        vault::settle_fund<ManagerCap<Config>, TOKEN>(
            manager_cap,
            expired_vault,
            settled_share_price,
            share_price_decimal
        );
        
        // TODO: calculate performance fee
    }

    fun settle_roll_over<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut Registry<ManagerCap<Config>>,
        expired_index: u64,
        price_oracle: &Oracle<TOKEN>,
    ){

        let config = covered_call::get_config<ManagerCap<Config>, TOKEN, Config>(vault_registry, expired_index); 

        let (_price, _decimal, unix_ms, _epoch) = oracle::get_oracle<TOKEN>(price_oracle);

        covered_call::check_already_expired(config, unix_ms);

        let (balance, scaled_user_shares) = vault::prepare_rolling<ManagerCap<Config>, TOKEN>(
            manager_cap,
            covered_call::get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
                vault_registry,
                expired_index
            )
        );

        let next_index = covered_call::get_next_index<ManagerCap<Config>, TOKEN, Config>(vault_registry, expired_index);
        let next_index = option::borrow<u64>(&next_index);
        vault::rock_n_roll<ManagerCap<Config>, TOKEN>(
            manager_cap,
            covered_call::get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
                vault_registry,
                *next_index
            ),
            balance,
            scaled_user_shares
        ); 
        
    }

    public entry fun settle_without_roll_over<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut Registry<ManagerCap<Config>>,
        expired_index: u64,
        price_oracle: &Oracle<TOKEN>,
    ){
        settle_internal<TOKEN>(manager_cap, vault_registry, expired_index, price_oracle);
    }

    public entry fun settle_with_roll_over<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut Registry<ManagerCap<Config>>,
        expired_index: u64,
        price_oracle: &Oracle<TOKEN>,
    ) {
        settle_internal<TOKEN>(manager_cap, vault_registry, expired_index, price_oracle);
        settle_roll_over<TOKEN>(manager_cap, vault_registry, expired_index, price_oracle);
    }

    // ======== Events =========

    // TODO: emit settle event
    struct Settle has copy, drop {
        settle_price: u64
    }

}