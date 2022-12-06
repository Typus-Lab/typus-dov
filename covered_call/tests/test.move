#[test_only]
module typus_covered_call::test {
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::balance;
    use sui::coin;
    use sui::tx_context;

    use std::string;
    use std::debug;
    use std::option;

    use typus_dov::i64;
    use typus_dov::asset;
    use typus_dov::dutch::Auction;
    use typus_dov::vault;
    use typus_oracle::oracle;

    use typus_covered_call::covered_call::{Self, ManagerCap, Config, Registry};
    use typus_covered_call::settlement;
    use typus_covered_call::payoff;

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
            let manager_cap = test_scenario::take_from_sender<ManagerCap<Config>>(scenario);
            let registry = test_scenario::take_shared<Registry<ManagerCap<Config>, Config>>(scenario);
            let (price_oracle, oracle_key) = oracle::test_new_oracle<SUI>(8, test_scenario::ctx(scenario));

            oracle::update(
                &mut price_oracle,
                &oracle_key,
                98,
                10000000,
                test_scenario::ctx(scenario)
            );

            covered_call::new_covered_call_vault<SUI>(
                &manager_cap,
                &mut registry,
                1,
                b"BTC",
                105,
                &price_oracle,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_to_sender<ManagerCap<Config>>(scenario, manager_cap);
            test_scenario::return_shared(registry);
            transfer::transfer(oracle_key, admin);
            transfer::transfer(price_oracle, admin);
        };
        test_scenario::next_tx(scenario, admin);
        debug::print(&string::utf8(b"vault created"));
        scenario_val
    }

    #[test]
    fun test_deposit<TOKEN>(): Scenario {
        let admin = @0x1;
        let scenario_val = test_new_vault();
        let scenario = &mut scenario_val;
        
        let registry = test_scenario::take_shared<Registry<ManagerCap<Config>, Config>>(scenario);

        let balance = balance::create_for_testing<TOKEN>(1000);

        let coin = coin::from_balance(balance, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, admin);

        covered_call::deposit<TOKEN>(&mut registry, 0, &mut coin, 1000, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, admin);

        let current_vault = covered_call::get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
            &mut registry,
            0
        );

        let share = vault::test_get_user_share<ManagerCap<Config>, TOKEN>(current_vault, true, admin);

        assert!(share == 1000, 0);

        debug::print(&string::utf8(b"Share: "));
        debug::print(&share);

        test_scenario::return_shared(registry);
        transfer::transfer(coin, admin);

        scenario_val
    }

    #[test]
    fun test_get_covered_call_payoff_by_price() {
        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(string::utf8(b"BTC"), 5000, 8),
            2000,
            option::some<u64>(6000),
            option::some<u64>(1000000),
        );
        let aa = payoff::get_covered_call_payoff_by_price(
            5500,
            &payoff_config
        );
        debug::print(&i64::is_neg(&aa));
        debug::print(&i64::abs(&aa));
        if (i64::is_neg(&aa)){
            debug::print(&i64::neg(&aa));
        };
    }

    // #[test]
    // fun test_settle(){
    //     let scenario_val = test_new_vault();
    //     let scenario = &mut scenario_val;
        
    //     let registry = test_scenario::take_shared<Registry<ManagerCap<Config>, Config>>(scenario);
    //     let manager_cap = test_scenario::take_from_sender<ManagerCap<Config>>(scenario);

    //     let (price_oracle, oracle_key) = oracle::test_new_oracle<SUI>(8, test_scenario::ctx(scenario));
    //     oracle::update(
    //         &mut price_oracle,
    //         &oracle_key,
    //         98,
    //         10000000,
    //         test_scenario::ctx(scenario)
    //     );

    //     // init covered call vault 1
    //     covered_call::new_covered_call_vault<SUI>(
    //         &manager_cap,
    //         &mut registry,
    //         1,
    //         b"BTC",
    //         105,
    //         &price_oracle,
    //         test_scenario::ctx(scenario)
    //     );

    //     // init covered call vault 2
    //     covered_call::new_covered_call_vault<SUI>(
    //         &manager_cap,
    //         &mut registry,
    //         2,
    //         b"BTC",
    //         105,
    //         &price_oracle,
    //         test_scenario::ctx(scenario)
    //     );

    //     // user deposit
    //     let test_coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(scenario));
    //     let coin_amount = coin::value<SUI>(&test_coin);
    //     covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin, coin_amount, test_scenario::ctx(scenario));
    //     let test_coin_2 = coin::mint_for_testing<SUI>(500000, test_scenario::ctx(scenario));
    //     let coin_amount = coin::value<SUI>(&test_coin_2);
    //     covered_call::deposit<SUI>(&mut registry, 2, &mut test_coin_2, coin_amount, test_scenario::ctx(scenario));

    //     covered_call::set_premium_roi<SUI>(&manager_cap, &mut registry, 1, 100000);

    //     // mm deposit
    //     let mm_test_coin = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(scenario));
    //     let mm_coin_amount = coin::value<SUI>(&mm_test_coin);
    //     covered_call::deposit<SUI>(
    //         &mut registry,
    //         1,
    //         &mut mm_test_coin,
    //         mm_coin_amount,
    //         test_scenario::ctx(scenario)
    //     );

    //     debug::print(&string::utf8(b"before settle"));
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, true);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, true);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, false);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, false);
    //     // settle internal
    //     // settlement::settle_without_roll_over<SUI>(&manager_cap,&mut registry, 1, &price_oracle);
    //     settlement::settle_with_roll_over<SUI>(&manager_cap, &mut registry, 1, &price_oracle);

    //     debug::print(&string::utf8(b"after settle"));
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, true);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, true);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, false);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 2, false);

    //     coin::destroy_for_testing(test_coin);
    //     coin::destroy_for_testing(test_coin_2);
    //     coin::destroy_for_testing(mm_test_coin);
    //     test_scenario::return_shared(registry); 
    //     test_scenario::return_to_sender<ManagerCap<Config>>(scenario, manager_cap);
    //     transfer::transfer(oracle_key, tx_context::sender(test_scenario::ctx(scenario)));
    //     transfer::share_object(price_oracle);
    //     test_scenario::end(scenario_val); 
    // }

    // #[test]
    // fun test_unsubscribe(){
    //     let scenario_val = test_new_vault();
    //     let scenario = &mut scenario_val;

    //     let user1 = @0xBABE1;
    //     let user2 = @0xBABE2;
    //     let user1_scenario = test_scenario::begin(user1);
    //     let user2_scenario = test_scenario::begin(user2);
        
    //     let registry = test_scenario::take_shared<Registry<ManagerCap<Config>, Config>>(scenario);
    //     let manager_cap = test_scenario::take_from_sender<ManagerCap<Config>>(scenario);

    //     let user1_ctx = test_scenario::ctx(&mut user1_scenario);
    //     let user2_ctx = test_scenario::ctx(&mut user2_scenario);

    //     let (price_oracle, oracle_key) = oracle::test_new_oracle<SUI>(8, test_scenario::ctx(scenario));
    //     oracle::update(
    //         &mut price_oracle,
    //         &oracle_key,
    //         98,
    //         10000000,
    //         test_scenario::ctx(scenario)
    //     );


    //     // init covered call vault 1
    //     covered_call::new_covered_call_vault<SUI>(
    //         &manager_cap,
    //         &mut registry,
    //         1,
    //         b"BTC",
    //         105,
    //         &price_oracle,
    //         test_scenario::ctx(scenario)
    //     );

    //     // user deposit
    //     let test_coin = coin::mint_for_testing<SUI>(300000, user1_ctx);
    //     let coin_amount = coin::value<SUI>(&test_coin);

    //     covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin, coin_amount, user1_ctx);
    //     covered_call::unsubscribe<SUI>(&mut registry, 1, user1_ctx);
    //     let test_coin_1 = coin::mint_for_testing<SUI>(1000000, user1_ctx);
    //     let coin_amount = coin::value<SUI>(&test_coin_1);

    //     covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin_1, coin_amount, user1_ctx);
    //     let test_coin_2 = coin::mint_for_testing<SUI>(500000, user2_ctx);
    //     let coin_amount = coin::value<SUI>(&test_coin_2);
    //     covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin_2, coin_amount, user2_ctx);

    //     debug::print(&string::utf8(b"A: after deposit"));
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);

    //     covered_call::unsubscribe<SUI>(
    //         &mut registry,
    //         1,
    //         user1_ctx
    //     );

    //     debug::print(&string::utf8(b"B: user1 unsubscribed"));
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, true);
    //     vault::test_get_balance<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);
    //     vault::test_get_share_supply<ManagerCap<Config>, SUI, Config, Auction<SUI>>(&mut registry, 1, false);

    //     coin::destroy_for_testing(test_coin);
    //     coin::destroy_for_testing(test_coin_1);
    //     coin::destroy_for_testing(test_coin_2);
        
    //     test_scenario::return_shared(registry); 
    //     test_scenario::return_to_sender<ManagerCap<Config>>(scenario, manager_cap);
    //     transfer::transfer(oracle_key, tx_context::sender(test_scenario::ctx(scenario)));
    //     transfer::share_object(price_oracle);

    //     test_scenario::end(scenario_val); 
    //     test_scenario::end(user1_scenario); 
    //     test_scenario::end(user2_scenario); 
    // }
}