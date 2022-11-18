module typus_dov::vault {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance, Supply};
    use sui::dynamic_field;
    use sui::coin::{Self, Coin};
    use sui::event::emit;
    use std::option::{Self, Option};
    use sui::table::{Self, Table};

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EVaultFull: u64 = 1;

    struct ManagerCap has key, store { id: UID }

    struct VaultRegistry  has key {
        id: UID,
        num_of_vault: u64,
    }

    struct VaultConfig has store {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
    }

    struct Vault<phantom T> has store {
        config: VaultConfig,
        payoff_config: PayoffConfig,
        deposit: Balance<T>,
        share_supply: Supply<Share>,
        users: Table<address, Balance<Share>>
    }

    struct PayoffConfig has store, drop {
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        low_barrier_roi: Option<u64>,
        high_barrier_roi: Option<u64>,
        high_roi_constant: Option<u64>,
    }

    struct Share has drop {}

    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);

        emit(RegistryCreated { id: object::uid_to_inner(&id) });

        transfer::transfer(ManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));

        transfer::share_object(VaultRegistry {
            id,
            num_of_vault: 0
        })
    }

    public entry fun new_vault<T>(
        vault_registry: &mut VaultRegistry,
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        ctx: &mut TxContext
    ) {
        let config = VaultConfig{
            expired_date,
            fee_percent,
            deposit_limit,
        };

        let payoff_config = PayoffConfig {
            is_bullish,
            low_barrier_price,
            high_barrier_price,
            low_barrier_roi: option::none(),
            high_barrier_roi: option::none(),
            high_roi_constant: option::none(),
        };

        emit(VaultCreated{
            expired_date,
            fee_percent,
            deposit_limit,
            low_barrier_price,
            high_barrier_price
        });

        let vault = Vault<T> {
            config,
            payoff_config,
            deposit: balance::zero<T>(),
            share_supply: balance::create_supply(Share{}),
            users: table::new<address, Balance<Share>>(ctx),
        };
        dynamic_field::add(&mut vault_registry.id, vault_registry.num_of_vault, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;
    }

    entry fun deposit<T>(
        vault_registry: &mut VaultRegistry, index: u64, token: Coin<T>, ctx: &mut TxContext
    ) {
        let vault = get_mut_vault<T>(vault_registry, index);

        let sender = tx_context::sender(ctx);

        let token = deposit_(vault, token, ctx);

        table::add(&mut vault.users, sender, coin::into_balance(token));
    }

    public fun deposit_<T>(
        vault: &mut Vault<T>, token: Coin<T>, ctx: &mut TxContext
    ): Coin<Share> {
        let deposit_value = coin::value(&token);

        assert!(deposit_value > 0, EZeroAmount);

        let tok_balance = coin::into_balance(token);

        let tok_amt = balance::join(&mut vault.deposit, tok_balance);

        assert!(tok_amt < vault.config.deposit_limit, EVaultFull);

        let balance = balance::increase_supply(&mut vault.share_supply, deposit_value);
        coin::from_balance(balance, ctx)
    }

    public fun get_mut_vault<T>(
        vault_registry: &mut VaultRegistry,
        index: u64,
    ): &mut Vault<T> {
        dynamic_field::borrow_mut<u64, Vault<T>>(&mut vault_registry.id, index)
    }

    public fun get_payoff_config_is_bullish(payoff_config: &PayoffConfig): bool {
        payoff_config.is_bullish
    }

    public fun get_payoff_config_low_barrier_price(payoff_config: &PayoffConfig): u64 {
        payoff_config.low_barrier_price
    }

    public fun get_payoff_config_high_barrier_price(payoff_config: &PayoffConfig): u64 {
        payoff_config.high_barrier_price
    }

    public fun get_payoff_config_low_barrier_roi(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.low_barrier_roi
    }

    public fun get_payoff_config_high_barrier_roi(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.high_barrier_roi
    }

    public fun get_payoff_config_high_roi_constant(payoff_config: &PayoffConfig): Option<u64> {
        payoff_config.high_roi_constant
    }

    #[test_only]
    public fun new_payoff_config(
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        low_barrier_roi: Option<u64>,
        high_barrier_roi: Option<u64>,
        high_roi_constant: Option<u64>,
    ): PayoffConfig{
        PayoffConfig {
            is_bullish,
            low_barrier_price,
            high_barrier_price,
            low_barrier_roi,
            high_barrier_roi,
            high_roi_constant,
        }
    }
    

    // ======== Events =========
    struct RegistryCreated has copy, drop { id: ID }
    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        low_barrier_price: u64,
        high_barrier_price: u64,
    }

    // ======== Test-only code =========
    #[test]
    /// new vault
    fun test_new_vault() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xBABE;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            // init(test_scenario::ctx(scenario));
            let ctx = test_scenario::ctx(scenario);
            let id = object::new(ctx);
            emit(RegistryCreated { id: object::uid_to_inner(&id) });
            transfer::transfer(ManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
            transfer::share_object(VaultRegistry {
                id,
                num_of_vault: 0
            })
        };

        test_scenario::next_tx(scenario, admin);
        {
            let registry = test_scenario::take_shared<VaultRegistry>(scenario);
            new_vault<SUI>(
                &mut registry,
                1,
                1,
                1,
                true,
                1,
                2,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(registry)
        };

        test_scenario::end(scenario_val);
    }

}