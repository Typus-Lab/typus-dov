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
    use typus_dov::vault;
    use typus_dov::utils;
    use typus_oracle::oracle::{Self, Oracle};
    use typus_oracle::unix_time::{Self, Time};

    use typus_covered_call::covered_call::{Self, ManagerCap, Registry};
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
            let manager_cap = test_scenario::take_from_sender<ManagerCap>(scenario);
            let registry = test_scenario::take_shared<Registry>(scenario);
            let price_decimal = 8;
            oracle::new_oracle<SUI>(price_decimal, test_scenario::ctx(scenario));
            test_scenario::next_tx(scenario, admin);
            let price_oracle = test_scenario::take_shared<Oracle<SUI>>(scenario);
            test_scenario::next_tx(scenario, admin);
            let oracle_key = test_scenario::take_from_address<oracle::Key<SUI>>(scenario, admin);

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
            test_scenario::return_to_sender<ManagerCap>(scenario, manager_cap);
            test_scenario::return_shared(registry);
            transfer::transfer(oracle_key, admin);
            transfer::share_object(price_oracle);
        };
        test_scenario::next_tx(scenario, admin);
        debug::print(&string::utf8(b"vault created"));
        scenario_val
    }

    #[test]
    fun test_deposit(): Scenario {
        let admin = @0x1;
        let scenario_val = test_new_vault();
        let scenario = &mut scenario_val;
        
        let registry = test_scenario::take_shared<Registry>(scenario);

        let balance = balance::create_for_testing<SUI>(1000);

        let coin = coin::from_balance(balance, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, admin);

        covered_call::deposit<SUI>(&mut registry, 0, &mut coin, 1000, true, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, admin);

        let current_vault = covered_call::test_get_vault<SUI>(
            &mut registry,
            0
        );

        let share = vault::test_get_user_share<ManagerCap, SUI>(current_vault, b"rolling", admin);

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
            asset::new_asset(b"BTC", 5000, 8),
            2000,
            option::some<u64>(6000),
            option::some<u64>(1000000),
        );
        let aa = payoff::get_covered_call_payoff_by_price(
            7000,
            &payoff_config
        );
        debug::print(&i64::is_neg(&aa));
        debug::print(&i64::abs(&aa));
        if (i64::is_neg(&aa)) {
            debug::print(&i64::neg(&aa));
        };
    }

    #[test]
    fun test_settle() {
        let admin = @0x1;
        let price_decimal = 8;
        let expiration_ts_ms_1 = 1000000;
        let expiration_ts_ms_2 = 2000000;

        let scenario_val = test_new_vault();
        let scenario = &mut scenario_val;
        
        let registry = test_scenario::take_shared<Registry>(scenario);
        let manager_cap = test_scenario::take_from_sender<ManagerCap>(scenario);

        // oracles
        oracle::new_oracle<SUI>(price_decimal, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, admin);
        let price_oracle = test_scenario::take_shared<Oracle<SUI>>(scenario);
        test_scenario::next_tx(scenario, admin);
        let oracle_key = test_scenario::take_from_address<oracle::Key<SUI>>(scenario, admin);
        oracle::update(
            &mut price_oracle,
            &oracle_key,
            10_000_000_000,
            0,
            test_scenario::ctx(scenario)
        );
        let sender = test_scenario::sender(scenario);
        test_scenario::next_tx(scenario, sender);

        unix_time::new_time(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, admin);
        let time_oracle = test_scenario::take_shared<Time>(scenario);
        test_scenario::next_tx(scenario, admin);
        let unix_time_manager_cap = test_scenario::take_from_sender<unix_time::Key>(scenario);

        // init covered call vault 1
        covered_call::new_covered_call_vault<SUI>(
            &manager_cap,
            &mut registry,
            expiration_ts_ms_1,
            b"BTC",
            2000,
            &price_oracle,
            test_scenario::ctx(scenario)
        );

        // user deposit
        let test_coin = coin::mint_for_testing<SUI>(50_000_000_000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin);
        covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin, coin_amount, true, test_scenario::ctx(scenario));

        // auction
        let option_price_decimal = 8;
        let _option_price_multiplier = utils::multiplier(option_price_decimal);
        let initial_option_price = 500_000_000;
        let final_option_price = 100_000_000;
        let start_auction_ts_ms = expiration_ts_ms_1 - 1000;
        let end_auction_ts_ms = start_auction_ts_ms + 500;
        oracle::update(
            &mut price_oracle,
            &oracle_key,
            10_000_000_000,
            start_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        unix_time::update(
            &mut time_oracle,
            &unix_time_manager_cap,
            start_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        let (_price, _, _, _) = oracle::get_oracle<SUI>(
            &price_oracle
        );

        covered_call::new_auction_with_next_covered_call_vault<SUI>(
            &manager_cap,
            &mut registry,
            1,
            start_auction_ts_ms,
            end_auction_ts_ms,
            2,
            initial_option_price,
            final_option_price,
            expiration_ts_ms_2,
            b"BTC",
            2000,
            &price_oracle,
            test_scenario::ctx(scenario)
        );
        // new maker bid
        let current_time = start_auction_ts_ms + 300;
        let bid_size = 100;
        let bid_coin_value = initial_option_price * bid_size;
        debug::print(&string::utf8(b"bid coin size:"));
        debug::print(&bid_size);

        let mm_test_coin = coin::mint_for_testing<SUI>(bid_coin_value, test_scenario::ctx(scenario));
        unix_time::update(
            &mut time_oracle,
            &unix_time_manager_cap,
            current_time,
            test_scenario::ctx(scenario)
        );
        covered_call::new_bid<SUI>(
            &mut registry,
            1,
            bid_size,
            &mut mm_test_coin,
            &time_oracle,
            test_scenario::ctx(scenario)
        );

        let (_price, price_decimal, _, _) = oracle::get_oracle<SUI>(
            &price_oracle
        );
        let price_multiplier = utils::multiplier(price_decimal);

        // calculate sell size by vault balance value, which may actually calculate off-chain
        let vault_1_balance = vault::test_get_balance<ManagerCap, SUI>(
            covered_call::test_get_vault<SUI>(&mut registry, 1),
            b"rolling"
        );
        vault_1_balance = vault_1_balance + vault::test_get_balance<ManagerCap, SUI>(
            covered_call::test_get_vault<SUI>(&mut registry, 1),
            b"regular"
        );

        let sell_size = vault_1_balance / price_multiplier;
        debug::print(&string::utf8(b"sell size:"));
        debug::print(&sell_size);

        unix_time::update(
            &mut time_oracle,
            &unix_time_manager_cap,
            end_auction_ts_ms + 1,
            test_scenario::ctx(scenario)
        );

        covered_call::delivery<SUI>(
            &manager_cap,
            &mut registry,
            1,
            sell_size,
            &time_oracle
        );

        // after auction
        let premium_roi = 100_000;
        oracle::update(
            &mut price_oracle,
            &oracle_key,
            10_000_000_000,
            end_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        unix_time::update(
            &mut time_oracle,
            &unix_time_manager_cap,
            end_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        let (price, _price_decimal, _, _) = oracle::get_oracle<SUI>(
            &price_oracle
        );
        covered_call::update_payoff_config<SUI>(&manager_cap, &mut registry, 1, price, premium_roi);

        let test_coin_2 = coin::mint_for_testing<SUI>(500000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin_2);
        covered_call::deposit<SUI>(&mut registry, 2, &mut test_coin_2, coin_amount, true, test_scenario::ctx(scenario));

        debug::print(&string::utf8(b"before settle"));
        debug::print(&string::utf8(b"vault 1"));
        test_print_vault_summary(&mut registry, 1);
        debug::print(&string::utf8(b"vault 2"));
        test_print_vault_summary(&mut registry, 2);
        
        oracle::update(
            &mut price_oracle,
            &oracle_key,
            9_800_000_000,
            expiration_ts_ms_1,
            test_scenario::ctx(scenario)
        );
        unix_time::update(
            &mut time_oracle,
            &unix_time_manager_cap,
            expiration_ts_ms_1,
            test_scenario::ctx(scenario)
        );

        // settle internal
        covered_call::settle<SUI>(&manager_cap,&mut registry, 1, &price_oracle, &time_oracle);
        // covered_call::settle_with_roll_over<SUI>(&manager_cap, &mut registry, 1, &price_oracle, &time_oracle);
        debug::print(&string::utf8(b"B"));

        debug::print(&string::utf8(b"after settle"));
        debug::print(&string::utf8(b"vault 1"));
        test_print_vault_summary(&mut registry, 1);
        debug::print(&string::utf8(b"vault 2"));
        test_print_vault_summary(&mut registry, 2);
        
        coin::destroy_for_testing(test_coin);
        coin::destroy_for_testing(test_coin_2);
        coin::destroy_for_testing(mm_test_coin);
        test_scenario::return_shared(registry); 
        test_scenario::return_to_sender<ManagerCap>(scenario, manager_cap);
        test_scenario::return_to_sender<unix_time::Key>(scenario, unix_time_manager_cap);
        transfer::transfer(oracle_key, tx_context::sender(test_scenario::ctx(scenario)));
        transfer::share_object(price_oracle);
        transfer::share_object(time_oracle);
        test_scenario::end(scenario_val); 
    }

    #[test]
    fun test_unsubscribe() {
        let admin = @0x1;
        let scenario_val = test_new_vault();
        let scenario = &mut scenario_val;

        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        
        let registry = test_scenario::take_shared<Registry>(scenario);
        let manager_cap = test_scenario::take_from_sender<ManagerCap>(scenario);

        oracle::new_oracle<SUI>(8, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, admin);
        let price_oracle = test_scenario::take_shared<Oracle<SUI>>(scenario);
        test_scenario::next_tx(scenario, admin);
        let oracle_key = test_scenario::take_from_address<oracle::Key<SUI>>(scenario, admin);
        oracle::update(
            &mut price_oracle,
            &oracle_key,
            98,
            10000000,
            test_scenario::ctx(scenario)
        );


        // init covered call vault 1
        covered_call::new_covered_call_vault<SUI>(
            &manager_cap,
            &mut registry,
            1,
            b"BTC",
            105,
            &price_oracle,
            test_scenario::ctx(scenario)
        );

        // user deposit
        test_scenario::next_tx(scenario, user1);
        let test_coin = coin::mint_for_testing<SUI>(300000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin);
        covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin, coin_amount, true, test_scenario::ctx(scenario));
        covered_call::unsubscribe<SUI>(&mut registry, 1, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, user1);
        let test_coin_1 = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin_1);
        covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin_1, coin_amount, true, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, user2);
        let test_coin_2 = coin::mint_for_testing<SUI>(500000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin_2);
        covered_call::deposit<SUI>(&mut registry, 1, &mut test_coin_2, coin_amount, true, test_scenario::ctx(scenario));

        debug::print(&string::utf8(b"A: after deposit"));
        test_print_vault_summary(&mut registry, 1);

        test_scenario::next_tx(scenario, user1);
        covered_call::unsubscribe<SUI>(&mut registry, 1, test_scenario::ctx(scenario));

        debug::print(&string::utf8(b"B: user1 unsubscribed"));
        test_print_vault_summary(&mut registry, 1);

        coin::destroy_for_testing(test_coin);
        coin::destroy_for_testing(test_coin_1);
        coin::destroy_for_testing(test_coin_2);

        test_scenario::return_shared(registry); 
        test_scenario::next_tx(scenario, admin);
        test_scenario::return_to_sender<ManagerCap>(scenario, manager_cap);
        transfer::transfer(oracle_key, tx_context::sender(test_scenario::ctx(scenario)));
        transfer::share_object(price_oracle);

        test_scenario::end(scenario_val);
    }

    #[test_only]
    fun test_print_vault_summary(registry: &mut Registry, index: u64) {
        let balance_rolling = vault::test_get_balance<ManagerCap, SUI>(covered_call::test_get_vault<SUI>(
            registry,
            index
        ), b"rolling");
        let share_rolling = vault::test_get_share_supply<ManagerCap, SUI>(covered_call::test_get_vault<SUI>(
            registry,
            index
        ), b"rolling");
        let balance_regular = vault::test_get_balance<ManagerCap, SUI>(covered_call::test_get_vault<SUI>(
            registry,
            index
        ), b"regular");
        let share_regular = vault::test_get_share_supply<ManagerCap, SUI>(covered_call::test_get_vault<SUI>(
            registry,
            index
        ), b"regular");
        let balance_maker = vault::test_get_balance<ManagerCap, SUI>(covered_call::test_get_vault<SUI>(
            registry,
            index
        ), b"maker");
        let share_maker = vault::test_get_share_supply<ManagerCap, SUI>(covered_call::test_get_vault<SUI>(
            registry,
            index
        ), b"maker");
        debug::print(&(balance_rolling));
        debug::print(&(balance_regular));
        debug::print(&(balance_maker));
        debug::print(&(share_rolling));
        debug::print(&(share_regular));
        debug::print(&(share_maker));
    }
}