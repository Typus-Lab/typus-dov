module typus_dov::pool {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance, Supply};
    use sui::dynamic_field;
    use sui::coin::{Self, Coin};

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EPoolFull: u64 = 1;

    struct Pool has key {
        id: UID,
        num_of_pool: u64,
    }

    struct Share<phantom V> has drop {}

    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Pool {
            id,
            num_of_pool: 0
        })
    }

    struct Vault<phantom T> has key, store {
        id: UID,
        strike: u64,
        expired_type: u64,
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        deposit: Balance<T>,
        share_supply: Supply<Share<T>>,
    }

    entry fun new_vault<T>(
        pool: &mut Pool,
        strike: u64,
        expired_type: u64,
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        ctx: &mut TxContext
    ) {
        let vault = Vault<T> {
            id: object::new(ctx),
            strike,
            expired_type,
            expired_date,
            fee_percent,
            deposit_limit,
            deposit: balance::zero<T>(),
            share_supply: balance::create_supply(Share<T> {})
        };
        dynamic_field::add(&mut pool.id, pool.num_of_pool, vault);
        pool.num_of_pool = pool.num_of_pool + 1;
    }

    entry fun deposit<T>(
        pool: &mut Pool, index: u64, token: Coin<T>, ctx: &mut TxContext
    ) {
        let vault = get_mut_vault<T>(pool, index);

        transfer::transfer(
            deposit_(vault, token, ctx),
            tx_context::sender(ctx)
        );
    }

    public fun deposit_<T>(
        vault: &mut Vault<T>, token: Coin<T>, ctx: &mut TxContext
    ): Coin<Share<T>> {
        let deposit_value = coin::value(&token);

        assert!(deposit_value > 0, EZeroAmount);

        let tok_balance = coin::into_balance(token);

        let tok_amt = balance::join(&mut vault.deposit, tok_balance);

        assert!(tok_amt < vault.deposit_limit, EPoolFull);

        let balance = balance::increase_supply(&mut vault.share_supply, deposit_value);
        coin::from_balance(balance, ctx)
    }

    public fun get_mut_vault<T>(
        pool: &mut Pool,
        index: u64,
    ): &mut Vault<T> {
        dynamic_field::borrow_mut<u64, Vault<T>>(&mut pool.id, index)
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
            new_vault<SUI>(&mut pool, 0, 0, 0, 0, 0, test_scenario::ctx(scenario));
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
                let vault = get_mut_vault<SUI>(&mut pool, index);
                debug::print(vault);
                index = index + 1;
            };
            test_scenario::return_shared(pool)
        };

        test_scenario::end(scenario_val);
    }
}