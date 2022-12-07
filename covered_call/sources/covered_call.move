module typus_covered_call::covered_call {
    use std::option::{Self, Option};

    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_dov::asset;
    use typus_dov::dutch::{Self, Auction};
    use typus_dov::vault::{Self, Vault};
    use typus_oracle::oracle::{Self, Oracle};
    use typus_oracle::unix_time::Time;

    friend typus_covered_call::settlement;

    #[test_only]
    friend typus_covered_call::test;

    // ======== Errors ========

    const E_VAULT_NOT_EXPIRED_YET: u64 = 0;

    // ======== Structs =========

    struct ManagerCap has key, store {
        id: UID,
    }

    struct Config has store, drop, copy {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    struct Registry has key {
        id: UID,
        num_of_vault: u64,
    }

    struct CoveredCallVault<phantom TOKEN> has store {
        config: Config,
        vault: Vault<ManagerCap, TOKEN>,
        auction: Option<Auction<ManagerCap, TOKEN>>,
        next_index: Option<u64>,
    }

    // ======== Private Functions =========

    fun init(ctx: &mut TxContext) {
        init_(ctx);
    }

    fun init_(ctx: &mut TxContext) {
        transfer::transfer(
            ManagerCap {
                id: object::new(ctx)
            },
            tx_context::sender(ctx)
        );
        new_registry(ctx);
    }

    fun new_registry(
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        // emit(RegistryCreated { id: object::uid_to_inner(&id) });

        let vault = Registry {
            id,
            num_of_vault: 0
        };

        transfer::share_object(vault);
    }

    // ======== Public Functions =========

    public fun get_config<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &Config {
        &dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).config
    }

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    public fun get_next_index<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): Option<u64> {
        dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).next_index
    }

    public fun check_already_expired(config: &Config, ts_ms: u64) {
        assert!(ts_ms >= config.expiration_ts * 1000, E_VAULT_NOT_EXPIRED_YET);
    }

    public fun set_strike<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        price: u64
    ) {
        payoff::set_strike(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            price
        );
    }

    public fun set_premium_roi<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        premium_roi: u64
    ) {
        payoff::set_premium_roi(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            premium_roi
        );
    }

    public fun set_next_index<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        next_index: u64
    ) {
        option::fill(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .next_index,
            next_index
        );
    }

    fun new_auction_<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        ctx: &mut TxContext,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        vault::disable_deposit(manager_cap, &mut covered_call_vault.vault);
        vault::disable_withdraw(manager_cap, &mut covered_call_vault.vault);
        option::fill(
            &mut covered_call_vault.auction,
            dutch::new(
                start_ts_ms,
                end_ts_ms,
                decay_speed,
                initial_price,
                final_price,
                ctx,
            )
        );
    }

    // ======== Public Friend Functions =========

    public(friend) fun get_mut_vault<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &mut Vault<ManagerCap, TOKEN> {
        &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(&mut registry.id, index).vault
    }

    public(friend) fun get_mut_action<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &mut Auction<ManagerCap, TOKEN> {
        option::borrow_mut(&mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(&mut registry.id, index).auction)
    }

    // ======== Entry Functions =========

    public(friend) entry fun new_covered_call_vault<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        expiration_ts: u64,
        asset_name: vector<u8>,
        strike_otm_pct: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext
    ) {
        let (price, price_decimal, _, _) = oracle::get_oracle<TOKEN>(
            price_oracle
        );

        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(asset_name, price, price_decimal),
            strike_otm_pct,
            option::none(),
            option::none(),
        );

        let config = Config { payoff_config, expiration_ts };
        let vault = vault::new_vault<ManagerCap, TOKEN>(ctx);

        dynamic_field::add(
            &mut registry.id,
            registry.num_of_vault,
            CoveredCallVault {
                config,
                vault,
                auction: option::none(),
                next_index: option::none(),
            }
        );
        registry.num_of_vault = registry.num_of_vault + 1;
    }

    public(friend) entry fun deposit<TOKEN>(
        registry: &mut Registry,
        index: u64,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::deposit<ManagerCap, TOKEN>(
            get_mut_vault<TOKEN>(
                registry,
                index
            ),
            coin,
            amount,
            is_rolling,
            ctx
        );

    }

    public(friend) entry fun new_auction<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        ctx: &mut TxContext,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        vault::disable_deposit(manager_cap, &mut covered_call_vault.vault);
        vault::disable_withdraw(manager_cap, &mut covered_call_vault.vault);
        option::fill(
            &mut covered_call_vault.auction,
            dutch::new(
                start_ts_ms,
                end_ts_ms,
                decay_speed,
                initial_price,
                final_price,
                ctx,
            )
        );
    }

    public(friend) entry fun new_auction_with_next_vault<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        ctx: &mut TxContext,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        vault::disable_deposit(manager_cap, &mut covered_call_vault.vault);
        vault::disable_withdraw(manager_cap, &mut covered_call_vault.vault);
        option::fill(
            &mut covered_call_vault.auction,
            dutch::new(
                start_ts_ms,
                end_ts_ms,
                decay_speed,
                initial_price,
                final_price,
                ctx,
            )
        );
    }

    public(friend) entry fun withdraw<TOKEN>(
        registry: &mut Registry,
        index: u64,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::withdraw<ManagerCap, TOKEN>(
            get_mut_vault<TOKEN>(
                registry,
                index
            ),
            option::some(amount),
            is_rolling,
            ctx
        );
    }

    public(friend) entry fun subscribe<TOKEN>(
        registry: &mut Registry,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::subscribe<ManagerCap, TOKEN>(
            get_mut_vault<TOKEN>(
                registry,
                index
            ),
            ctx,
        );
    }

    public(friend) entry fun unsubscribe<TOKEN>(
        registry: &mut Registry,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::unsubscribe<ManagerCap, TOKEN>(
            get_mut_vault<TOKEN>(
                registry,
                index
            ),
            ctx,
        );
    }

    public(friend) entry fun new_bid<TOKEN>(
        registry: &mut Registry,
        index: u64,
        size: u64,
        coin: &mut Coin<TOKEN>,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        dutch::new_bid<ManagerCap, TOKEN>(
            option::borrow_mut(&mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            ).auction),
            size,
            coin,
            time,
            ctx,
        );
    }

    public(friend) entry fun remove_bid<TOKEN>(
        registry: &mut Registry,
        index: u64,
        bid_index: u64,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        dutch::remove_bid<ManagerCap, TOKEN>(
            option::borrow_mut(&mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            ).auction),
            bid_index,
            time,
            ctx,
        );
    }

    public(friend) entry fun delivery<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        size: u64,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        let (balance, maker_shares) = dutch::delivery<ManagerCap, TOKEN>(
            manager_cap,
            option::borrow_mut(&mut covered_call_vault.auction),
            size,
        );
        vault::maker_deposit(
            manager_cap,
            &mut covered_call_vault.vault,
            balance,
            maker_shares,
        );
    }

    // ======== Events =========

    // struct RegistryCreated<phantom phantom CONFIG> has copy, drop { id: ID }
    // struct VaultCreated<phantom phantom TOKEN, CONFIG, phantom AUCTION> has copy, drop {config: CONFIG }

    // struct VaultCreated has copy, drop {
    //     asset: String,
    //     expiration_ts: u64,
    //     strike: u64,
    // }

    // struct VaultDeposit has copy, drop {
    //     index: u64,
    //     amount: u64,
    //     rolling: bool,
    // }

    // ======== Test =========

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init_(ctx);
    }

}