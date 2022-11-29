#[test_only]
module typus_covered_call::test {
    use std::option;
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::balance;
    use sui::coin;
    use std::string;
    // use std::debug;

    use typus_dov::asset;
    use typus_dov::vault::{Self, VaultRegistry};
    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_covered_call::covered_call::{Self, Config};

    #[test]
    fun test_new_vault(): Scenario {
        let admin = @0x1;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            covered_call::test_init(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, admin);
        {
            let registry = test_scenario::take_shared<VaultRegistry<Config>>(scenario);
            covered_call::new_covered_call_vault<SUI>(
                &mut registry,
                1,
                asset::new_asset(&string::utf8(b"BTC"), 100000000, 8),
                true,
                1,
                2,
                test_scenario::ctx(scenario)
            );
            vault::get_vault<SUI, Config>(&registry, 0);     

            test_scenario::return_shared(registry)
        };
        test_scenario::next_tx(scenario, admin);
        scenario_val
    }

    #[test]
    fun test_deposit(): Scenario {
        let admin = @0x1;
        let scenario_val = test_new_vault();
        let scenario = &mut scenario_val;
        
        let registry = test_scenario::take_shared<VaultRegistry<Config>>(scenario);

        let balance = balance::create_for_testing<SUI>(1000);

        let coin = coin::from_balance(balance, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, admin);

        covered_call::deposit<SUI>(&mut registry, 0, true, &mut coin, 1000, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, admin);

        let share = vault::get_user_share<SUI, Config>(&mut registry, 0, string::utf8(b"rolling"), admin);

        assert!(share == 1000, 0);

        test_scenario::return_shared(registry);
        transfer::transfer(coin, admin);

        scenario_val
    }

    #[test]
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
        };

    }

    // // ======== Test Functions =========
    // #[test]
    // fun test_settle_internal(): VaultRegistry<Config> {
    //     // use sui::transfer;
    //     use sui::test_scenario;
    //     use sui::sui::SUI;
    //     use sui::coin;
    //     use typus_covered_call::covered_call::{Self, Config};
    //     use typus_dov::vault;

    //     let admin = @0xFFFF;
    //     let admin_scenario = test_scenario::begin(admin);
    //     let ctx = test_scenario::ctx(&mut admin_scenario);
    //     let vault_registry = vault::test_only_new_vault_registry<Config>(ctx);
    //     covered_call::new_covered_call_vault<SUI>(
    //         &mut vault_registry,
    //         1,
    //         true,
    //         90,
    //         110,
    //         ctx
    //     );
    //     covered_call::new_covered_call_vault<SUI>(
    //         &mut vault_registry,
    //         2,
    //         true,
    //         95,
    //         115,
    //         ctx
    //     );

    //     // user deposit
    //     let test_coin = coin::mint_for_testing<SUI>(1000000, ctx);
    //     let coin_amount = coin::value<SUI>(&test_coin);
    //     covered_call::deposit<SUI>(
    //         &mut vault_registry,
    //         0,
    //         true,
    //         &mut test_coin,
    //         coin_amount,
    //         ctx
    //     );

    //     // mm deposit
    //     let mm_test_coin = coin::mint_for_testing<SUI>(10000, ctx);
    //     let value = vault::deposit<SUI, Config>(
    //         &mut vault_registry,
    //         0, 
    //         string::utf8(b"maker"),
    //         &mut mm_test_coin,
    //         10000
    //     );
    //     vault::add_share<SUI, Config>(&mut vault_registry, 0, string::utf8(b"maker"), value, ctx);

    //     // settle internal
    //     settle_without_roll_over<SUI>(&mut vault_registry, 0);
    //     coin::destroy_for_testing(test_coin);
    //     coin::destroy_for_testing(mm_test_coin);
    //     test_scenario::end(admin_scenario);
       
    //     vault_registry
    // }
}