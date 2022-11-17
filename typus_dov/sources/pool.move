module typus_dov::pool {
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field;

    struct Pool has key {
        id: UID,
        num_of_pool: u64,
    }

    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Pool {
            id,
            num_of_pool: 0
        })
    }

    struct Vault<phantom T> has store {
        strike: u64,
        expired_type: u64,
        expired_date: u64,
        fee_percent: u64,
        deposit: Balance<T>,
    }

    public entry fun new_vault<T>(
        pool: &mut Pool,
        strike: u64,
        expired_type: u64,
        expired_date: u64,
        fee_percent: u64,
    ) {
        let vault = Vault<T> {
            strike,
            expired_type,
            expired_date,
            fee_percent,
            deposit: balance::zero<T>(),
        };
        dynamic_field::add(&mut pool.id, pool.num_of_pool, vault);
        pool.num_of_pool = pool.num_of_pool + 1;
    }

    public fun get_vault<T>(
        pool: &mut Pool,
        index: u64,
    ): &Vault<T> {
        dynamic_field::borrow<u64, Vault<T>>(&mut pool.id, index)
    }

    #[test]
    fun test_pool_initialization() {
        use std::debug;
        use sui::test_scenario;
        use sui::sui::SUI;
        

        let admin = @0xBABE;
        let scenario_val = test_scenario::begin(admin);

        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, admin);
        {
            let pool = test_scenario::take_shared<Pool>(scenario);
            new_vault<SUI>(&mut pool, 0, 0, 0, 0);
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let pool = test_scenario::take_shared<Pool>(scenario);
            new_vault<SUI>(&mut pool, 1, 1, 1, 1);
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let pool = test_scenario::take_shared<Pool>(scenario);
            new_vault<SUI>(&mut pool, 2, 2, 2, 2);
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let pool = test_scenario::take_shared<Pool>(scenario);
            debug::print(&pool);
            let index = 0;
            loop {
                if (index >= pool.num_of_pool) {
                    break
                };
                let vault = get_vault<SUI>(&mut pool, index);
                debug::print(vault);
                index = index + 1;
            };
            test_scenario::return_shared(pool)
        };

        test_scenario::end(scenario_val);
    }
}