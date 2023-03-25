#[test_only]
module typus_protected_put::test {
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin;
    use sui::tx_context;

    use std::string;
    use std::debug;
    use std::option;

    use typus_framework::i64;
    use typus_framework::vault;
    use typus_framework::utils;
    use typus_framework::asset;
    use typus_oracle::oracle::{Self, Oracle};
    use typus_oracle::unix_time::{Self, Time};

    use typus_protected_put::protected_put::{Self, ManagerCap, Registry};
    use typus_protected_put::payoff;

    #[test]
    fun test_new_vault(): Scenario {
        let underlying_asset = b"DOGE";
        let admin = @0x1;
        let current_ts_ms = 1671594861_000; // 2022/12/21 Wednesday 03:54:21
        let start_ts_ms_1 = 1671782400_000; // 2022/12/23 Friday 08:00:00
        let expiration_ts_ms_1 = 1671782400_000 + 604800_000;  // 2022/12/30 Friday 08:00:00
        let period = 1; // Weekly
        let strike_otm_pct = 500; // 0.05 * 10000

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        let token_decimal = 9;
        let share_decimal = 4;
        {
            protected_put::test_init(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, admin);
        let manager_cap = test_scenario::take_from_sender<ManagerCap>(scenario);
        let registry = test_scenario::take_shared<Registry>(scenario);

        unix_time::new_time(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, admin);
        let time_oracle = test_scenario::take_shared<Time>(scenario);
        test_scenario::next_tx(scenario, admin);
        let unix_time_key = test_scenario::take_from_sender<unix_time::Key>(scenario);

        unix_time::update(
            &mut time_oracle,
            &unix_time_key,
            current_ts_ms,
            test_scenario::ctx(scenario)
        );

        protected_put::new_protected_put_vault<SUI>(
            &manager_cap,
            &mut registry,
            token_decimal,
            share_decimal,
            &time_oracle,
            period,
            start_ts_ms_1,
            expiration_ts_ms_1,
            underlying_asset,
            strike_otm_pct,
            test_scenario::ctx(scenario)
        );
        test_scenario::return_to_sender<ManagerCap>(scenario, manager_cap);
        test_scenario::return_shared(registry);
        test_scenario::return_shared(time_oracle);
        test_scenario::return_to_sender<unix_time::Key>(scenario, unix_time_key);

        test_scenario::next_tx(scenario, admin);
        scenario_val
    }

    // #[test]
    // fun test_deposit(): Scenario {
    //     let admin = @0x1;
    //     let amount = 1000;
    //     let scenario_val = test_new_vault();
    //     let scenario = &mut scenario_val;
    //     let registry = test_scenario::take_shared<Registry>(scenario);
    //     let balance = balance::create_for_testing<SUI>(amount);
    //     let coin = coin::from_balance(balance, test_scenario::ctx(scenario));

    //     test_scenario::next_tx(scenario, admin);
    //     protected_put::deposit<SUI>(&mut registry, 0, &mut coin, amount, true, test_scenario::ctx(scenario));


    //     let current_vault = protected_put::test_get_vault<SUI>(
    //         &mut registry,
    //         0
    //     );
    //     let share = vault::test_get_user_share<ManagerCap, SUI>(current_vault, b"rolling", admin);

    //     assert!(share == amount / utils::multiplier(5), 0);

    //     test_scenario::return_shared(registry);
    //     transfer::transfer(coin, admin);

    //     test_scenario::next_tx(scenario, admin);
    //     scenario_val
    // }

    #[test]
    fun test_get_protected_put_payoff_by_price() {
        let underlying_asset = asset::new_asset(b"DOGE");
        let payoff_config = payoff::new_payoff_config(
            underlying_asset,
            2000,
            option::some<u64>(6000),
            option::some<u64>(1000000),
            option::some<u64>(80000000),
        );
        let aa = payoff::get_protected_put_payoff_by_price(
            5000,
            &payoff_config
        );

        assert!(i64::compare(&aa, &i64::neg_from(12333332)) == 0, 1);
    }

    #[test]
    fun test_settle() {
        let admin = @0x1;
        let price_decimal = 8;
        let current_ts_ms = 1671594861_000; // 2022/12/21 Wednesday 03:54:21
        let expiration_ts_ms_1 = 1671782400_000; // 2022/12/23 Friday 08:00:00
        let expiration_ts_ms_2 = 1672387200_000; // 2022/12/30 Friday 08:00:00
        let decay_speed = 1;

        let strike_otm_pct = 500; // 0.05 * 10000

        let underlying_asset = b"DOGE";

        let scenario_val = test_new_vault();
        let index = 0;
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
        let unix_time_key = test_scenario::take_from_sender<unix_time::Key>(scenario);

        unix_time::update(
            &mut time_oracle,
            &unix_time_key,
            current_ts_ms,
            test_scenario::ctx(scenario)
        );

        // user deposit
        let test_coin = coin::mint_for_testing<SUI>(50_000_000_000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin);
        protected_put::deposit<SUI>(&mut registry, 0, &mut test_coin, coin_amount, true, test_scenario::ctx(scenario));

        // auction
        let option_price_decimal = 5;
        let _option_price_multiplier = utils::multiplier(option_price_decimal);
        let initial_option_price = 5_000;
        let final_option_price = 1_000;
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
            &unix_time_key,
            start_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        let (_price, _, _, _) = oracle::get_oracle<SUI>(
            &price_oracle
        );

        protected_put::new_auction_with_next_protected_put_vault<SUI>(
            &manager_cap,
            &mut registry,
            &time_oracle,
            index,
            start_auction_ts_ms,
            end_auction_ts_ms,
            decay_speed,
            initial_option_price,
            final_option_price,
            expiration_ts_ms_2,
            underlying_asset,
            strike_otm_pct,
            test_scenario::ctx(scenario)
        );
        // new maker bid
        let current_time = start_auction_ts_ms + 300;
        let bid_size = 50_000_000_000;
        let bid_coin_value = (initial_option_price as u128) * (bid_size as u128) / (utils::multiplier(option_price_decimal) as u128);
        debug::print(&string::utf8(b"bid coin size:"));
        debug::print(&bid_size);
        debug::print(&string::utf8(b"bid coin value:"));
        debug::print(&bid_coin_value);
        let mm_test_coin = coin::mint_for_testing<SUI>((bid_coin_value as u64), test_scenario::ctx(scenario));
        unix_time::update(
            &mut time_oracle,
            &unix_time_key,
            current_time,
            test_scenario::ctx(scenario)
        );
        protected_put::new_bid<SUI>(
            &mut registry,
            0,
            bid_size,
            &mut mm_test_coin,
            &time_oracle,
            test_scenario::ctx(scenario)
        );

        let (_price,_price_decimal, _, _) = oracle::get_oracle<SUI>(
            &price_oracle
        );
        // let price_multiplier = utils::multiplier(price_decimal);

        // calculate sell size by vault balance value, which may actually calculate off-chain
        let (rolling_user_balance, regular_user_balance, maker_balance) = vault::test_get_balance<ManagerCap, SUI>(
            protected_put::test_get_vault<SUI>(&mut registry, 0),
        );

        let sell_size = rolling_user_balance + regular_user_balance;
        debug::print(&string::utf8(b"sell size:"));
        debug::print(&sell_size);

        unix_time::update(
            &mut time_oracle,
            &unix_time_key,
            end_auction_ts_ms + 1,
            test_scenario::ctx(scenario)
        );

        protected_put::delivery<SUI>(
            &manager_cap,
            &mut registry,
            0,
            sell_size,
            &time_oracle
        );

        // after auction
        let premium_roi = (utils::multiplier(payoff::get_roi_decimal()) as u128)
            * (maker_balance as u128)
            / (rolling_user_balance + regular_user_balance as u128);
        let exposure_ratio = bid_size * utils::multiplier(8) / coin_amount;
        oracle::update(
            &mut price_oracle,
            &oracle_key,
            10_000_000_000,
            end_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        unix_time::update(
            &mut time_oracle,
            &unix_time_key,
            end_auction_ts_ms,
            test_scenario::ctx(scenario)
        );
        let (price, _price_decimal, _, _) = oracle::get_oracle<SUI>(
            &price_oracle
        );
        let strike = price * (utils::multiplier(payoff::get_otm_decimal()) + strike_otm_pct) / utils::multiplier(payoff::get_otm_decimal());
        protected_put::update_payoff_config<SUI>(&manager_cap, &mut registry, 0, strike, (premium_roi as u64), exposure_ratio);

        let test_coin_2 = coin::mint_for_testing<SUI>(500000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin_2);
        protected_put::deposit<SUI>(&mut registry, 1, &mut test_coin_2, coin_amount, true, test_scenario::ctx(scenario));

        debug::print(&string::utf8(b"before settle"));
        debug::print(&string::utf8(b"vault 1"));
        vault::test_print_vault_summary<ManagerCap, SUI>(protected_put::test_get_vault(&registry, 0));
        debug::print(&string::utf8(b"vault 2"));
        vault::test_print_vault_summary<ManagerCap, SUI>(protected_put::test_get_vault(&registry, 1));

        oracle::update(
            &mut price_oracle,
            &oracle_key,
            9_000_000_000,
            expiration_ts_ms_2, // vault 0 expires
            test_scenario::ctx(scenario)
        );
        unix_time::update(
            &mut time_oracle,
            &unix_time_key,
            expiration_ts_ms_2, // vault 0 expires
            test_scenario::ctx(scenario)
        );

        // settle internal
        // protected_put::settle<SUI>(&manager_cap,&mut registry, 1, &price_oracle, &time_oracle);
        protected_put::settle_with_roll_over<SUI>(&manager_cap, &mut registry, 0, &price_oracle, &time_oracle);

        debug::print(&string::utf8(b"after settle"));
        debug::print(&string::utf8(b"vault 1"));
        vault::test_print_vault_summary<ManagerCap, SUI>(protected_put::test_get_vault(&registry, 0));
        debug::print(&string::utf8(b"vault 2"));
        vault::test_print_vault_summary<ManagerCap, SUI>(protected_put::test_get_vault(&registry, 1));

        coin::destroy_for_testing(test_coin);
        coin::destroy_for_testing(test_coin_2);
        coin::destroy_for_testing(mm_test_coin);
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender<ManagerCap>(scenario, manager_cap);
        test_scenario::return_to_sender<unix_time::Key>(scenario, unix_time_key);
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
        let index = 0;

        let user1 = @0xBABE1;
        let user2 = @0xBABE2;

        let registry = test_scenario::take_shared<Registry>(scenario);
        let manager_cap = test_scenario::take_from_sender<ManagerCap>(scenario);

        // user deposit
        test_scenario::next_tx(scenario, user1);
        let test_coin = coin::mint_for_testing<SUI>(300000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin);
        protected_put::deposit<SUI>(&mut registry, index, &mut test_coin, coin_amount, true, test_scenario::ctx(scenario));
        protected_put::unsubscribe<SUI>(&mut registry, index, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, user1);
        let test_coin_1 = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin_1);
        protected_put::deposit<SUI>(&mut registry, index, &mut test_coin_1, coin_amount, true, test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, user2);
        let test_coin_2 = coin::mint_for_testing<SUI>(500000, test_scenario::ctx(scenario));
        let coin_amount = coin::value<SUI>(&test_coin_2);
        protected_put::deposit<SUI>(&mut registry, index, &mut test_coin_2, coin_amount, true, test_scenario::ctx(scenario));

        debug::print(&string::utf8(b"A: after deposit"));
        vault::test_print_vault_summary<ManagerCap, SUI>(protected_put::test_get_vault(&registry, index));

        test_scenario::next_tx(scenario, user1);
        protected_put::unsubscribe<SUI>(&mut registry, index, test_scenario::ctx(scenario));

        debug::print(&string::utf8(b"B: user1 unsubscribed"));
        vault::test_print_vault_summary<ManagerCap, SUI>(protected_put::test_get_vault(&registry, index));

        coin::destroy_for_testing(test_coin);
        coin::destroy_for_testing(test_coin_1);
        coin::destroy_for_testing(test_coin_2);

        test_scenario::return_shared(registry);
        test_scenario::next_tx(scenario, admin);
        test_scenario::return_to_sender<ManagerCap>(scenario, manager_cap);

        test_scenario::end(scenario_val);
    }
}