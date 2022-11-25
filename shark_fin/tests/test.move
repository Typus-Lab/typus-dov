#[test_only]
module typus_shark_fin::test {
    use std::option;
    use sui::test_scenario;

    use typus_dov::vault::{Self, VaultRegistry};
    use typus_shark_fin::payoff::{Self, PayoffConfig};


    #[test]
    fun test_new_vault() {
        use sui::sui::SUI;
        use typus_shark_fin::shark_fin::{Self, Config};

        let admin = @0x1;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            shark_fin::test_init(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, admin);
        {
            let registry = test_scenario::take_shared<VaultRegistry<Config>>(scenario);
            shark_fin::new_shark_fin_vault<SUI>(
                &mut registry,
                1,
                true,
                1,
                2,
                test_scenario::ctx(scenario)
            );
            vault::get_vault<SUI, Config>(&registry, 0);     

            test_scenario::return_shared(registry)
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_get_shark_fin_payoff_by_price(): PayoffConfig {

        let payoff_config = payoff::new_payoff_config(
            false,
            5000,
            6000,
            option::none(),
            option::none(),
            option::none(),
        );

        payoff::set_low_barrier_roi(&mut payoff_config, 1);
        payoff::set_high_barrier_roi(&mut payoff_config, 5);
        payoff::set_high_roi_constant(&mut payoff_config, 3);

        let result = payoff::get_shark_fin_payoff_by_price(
            5000,
            &payoff_config
        );
        assert!(result == 5, 0);

        payoff_config
    }


    // // ======== Test Functions =========
    // #[test]
    // fun test_settle_internal(): VaultRegistry<Config> {
    //     // use sui::transfer;
    //     use sui::test_scenario;
    //     use sui::sui::SUI;
    //     use sui::coin;
    //     use typus_shark_fin::shark_fin::{Self, Config};
    //     use typus_dov::vault;

    //     let admin = @0xFFFF;
    //     let admin_scenario = test_scenario::begin(admin);
    //     let ctx = test_scenario::ctx(&mut admin_scenario);
    //     let vault_registry = vault::test_only_new_vault_registry<Config>(ctx);
    //     shark_fin::new_shark_fin_vault<SUI>(
    //         &mut vault_registry,
    //         1,
    //         true,
    //         90,
    //         110,
    //         ctx
    //     );
    //     shark_fin::new_shark_fin_vault<SUI>(
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
    //     shark_fin::deposit<SUI>(
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