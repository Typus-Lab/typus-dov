module typus_covered_call::covered_call {
    use std::option;
    use std::string;

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::Coin;

    use typus_dov::vault::{Self, ManagerCap, VaultRegistry};
    use typus_dov::asset;
    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_dov::dutch::Auction;

    // ======== Structs =========

    struct Config has store, drop {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    // ======== Functions =========

    fun init_(ctx: &mut TxContext) {
        let manager_cap = vault::new_manager_cap<Config>(ctx);

        transfer::transfer(manager_cap, tx_context::sender(ctx));

        vault::new_vault_registry<Config>(ctx);
    }

    fun init(ctx: &mut TxContext) {
        init_(ctx);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init_(ctx);
    }

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    public fun set_premium_roi<T>(manager_cap: &ManagerCap<Config>, vault_registry: &mut VaultRegistry<Config>, index: u64, premium_roi: u64) {
        let config = vault::get_mut_config<T, Config>(manager_cap, vault_registry, index);
        payoff::set_premium_roi(&mut config.payoff_config, premium_roi);
    }

    // Entry Functions
    public entry fun new_covered_call_vault<T>(
        vault_registry: &mut VaultRegistry<Config>,
        expiration_ts: u64,
        asset_name: vector<u8>,
        strike: u64,
        ctx: &mut TxContext
    ){
        let price = 100;
        let price_decimal = 8;
        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(string::utf8(asset_name), price, price_decimal),
            strike,
            option::none(),
        );

        let config = Config {
            payoff_config,
            expiration_ts
        };

        let n = vault::new_vault<T, Config, Auction<T>>(vault_registry, config, ctx);

        vault::new_sub_vault<T, Config, Auction<T>>(vault_registry, n, string::utf8(b"rolling"), ctx);

        vault::new_sub_vault<T, Config, Auction<T>>(vault_registry, n, string::utf8(b"regular"), ctx);

        vault::new_sub_vault<T, Config, Auction<T>>(vault_registry, n, string::utf8(b"maker"), ctx);
    }

    public entry fun deposit<T>(
        vault_registry: &mut VaultRegistry<Config>,
        index: u64,
        rolling: bool,
        coin: &mut Coin<T>,
        amount: u64,
        ctx: &mut TxContext
    ){
        let name = if (rolling) {
            string::utf8(b"rolling")
        } else {
            string::utf8(b"regular")
        };

        let value = vault::deposit<T, Config>(vault_registry, index, name, coin, amount);

        vault::add_share<T, Config>(vault_registry, index, name, value, ctx);
    }


    #[test_only]
    public fun get_sub_vault_deposit<T>(vault_registry: &mut VaultRegistry<Config>, index: u64): vector<u64> {
        use std::vector;
        let deposit_value_rolling = vault::get_vault_deposit_value<T, Config>(vault_registry, index, string::utf8(b"rolling"));
        let deposit_value_regular = vault::get_vault_deposit_value<T, Config>(vault_registry, index, string::utf8(b"regular"));
        let deposit_value_mm = vault::get_vault_deposit_value<T, Config>(vault_registry, index, string::utf8(b"maker"));
        let vec = vector::empty<u64>();
        vector::push_back<u64>(&mut vec, deposit_value_rolling);
        vector::push_back<u64>(&mut vec, deposit_value_regular);
        vector::push_back<u64>(&mut vec, deposit_value_mm);
        vec
    }
    #[test_only]
    public fun get_sub_vault_share_supply<T>(vault_registry: &mut VaultRegistry<Config>, index: u64): vector<u64> {
        use std::vector;
        let share_supply_rolling = vault::get_vault_share_supply<T, Config>(vault_registry, index, string::utf8(b"rolling"));
        let share_supply_regular = vault::get_vault_share_supply<T, Config>(vault_registry, index, string::utf8(b"regular"));
        let share_supply_mm = vault::get_vault_share_supply<T, Config>(vault_registry, index, string::utf8(b"maker"));
        let vec = vector::empty<u64>();
        vector::push_back<u64>(&mut vec, share_supply_rolling);
        vector::push_back<u64>(&mut vec, share_supply_regular);
        vector::push_back<u64>(&mut vec, share_supply_mm);
        vec
    }



    // ======== Events =========

    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        strike: u64,
    }

    // Tests

    // #[test]
    // fun test_new_vault() {
    //     use sui::test_scenario;
    //     use std::debug;
    //     use sui::sui::SUI;

    //     let admin = @0x1;
    //     let scenario_val = test_scenario::begin(admin);
    //     let scenario = &mut scenario_val;
    //     {
    //         test_init(test_scenario::ctx(scenario));
    //     };
    //     test_scenario::next_tx(scenario, admin);
    //     {
    //         let registry = test_scenario::take_shared<VaultRegistry<Config>>(scenario);
    //         new_covered_call_vault<SUI>(
    //             &mut registry,
    //             1,
    //             b"BTC",
    //             105,
    //             test_scenario::ctx(scenario)
    //         );
    //         vault::get_vault<SUI, Config>(&registry, 0);     

    //         test_scenario::return_shared(registry)
    //     };
    //     test_scenario::next_tx(scenario, admin);
    //     debug::print(&string::utf8(b"done"));
    //     test_scenario::end(scenario_val); 
    // }
}