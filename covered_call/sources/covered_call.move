module typus_covered_call::covered_call {
    use std::option::{Self, Option};

    use sui::balance::Balance;
    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_dov::asset;
    use typus_dov::dutch::{Self, Auction};
    use typus_dov::i64;
    use typus_dov::vault::{Self, Vault};
    use typus_dov::utils;
    use typus_oracle::oracle::{Self, Oracle};
    use typus_oracle::unix_time::{Self, Time};

    #[test_only]
    friend typus_covered_call::test;

    // ======== Errors ========
    const E_VAULT_NOT_EXPIRED_YET: u64 = 0;

    // ======== Structs =========

    struct ManagerCap has key {
        id: UID,
    }

    struct Config has store, drop, copy {
        payoff_config: PayoffConfig,
        expiration_ts_ms: u64
    }

    struct Registry has key {
        id: UID,
        num_of_vault: u64,
    }

    struct CoveredCallVault<phantom TOKEN> has store {
        config: Config,
        vault: Vault<ManagerCap, TOKEN>,
        auction: Option<Auction<ManagerCap, TOKEN>>,
        next: Option<u64>,
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

    fun new_covered_call_vault_<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        expiration_ts_ms: u64,
        asset_name: vector<u8>,
        strike_otm_pct: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext
    ): u64 {
        let (price, price_decimal, _, _) = oracle::get_oracle<TOKEN>(
            price_oracle
        );

        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(asset_name, price, price_decimal),
            strike_otm_pct,
            option::none(),
            option::none(),
        );

        let config = Config { payoff_config, expiration_ts_ms };
        let vault = vault::new_vault<ManagerCap, TOKEN>(ctx);
        let index = registry.num_of_vault;

        dynamic_field::add(
            &mut registry.id,
            index,
            CoveredCallVault {
                config,
                vault,
                auction: option::none(),
                next: option::none(),
            }
        );
        registry.num_of_vault = registry.num_of_vault + 1;

        index
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

    fun get_mut_covered_call_vault<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &mut CoveredCallVault<TOKEN> {
        dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(&mut registry.id, index)
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

    public fun get_next_covered_call_vault_index<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): Option<u64> {
        dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).next
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

    public fun check_already_expired(expiration_ts_ms: u64, ts_ms: u64) {
        assert!(ts_ms >= expiration_ts_ms, E_VAULT_NOT_EXPIRED_YET);
    }

    // ======== Public Friend Functions =========

    public(friend) fun get_mut_vault<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &mut Vault<ManagerCap, TOKEN> {
        &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(&mut registry.id, index).vault
    }

    // ======== Entry Functions =========

    public(friend) entry fun new_covered_call_vault<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        expiration_ts_ms: u64,
        asset_name: vector<u8>,
        strike_otm_pct: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext
    ) {
        new_covered_call_vault_<TOKEN>(
            manager_cap,
            registry,
            expiration_ts_ms,
            asset_name,
            strike_otm_pct,
            price_oracle,
            ctx,
        );
    }

    public(friend) entry fun new_manager(
        _manager_cap: &ManagerCap,
        user: address,
        ctx: &mut TxContext
    ) {
        transfer::transfer(
            ManagerCap {
                id: object::new(ctx)
            },
            user
        );
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
        new_auction_<TOKEN>(
            manager_cap,
            registry,
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            ctx,
        );
    }

    public(friend) entry fun new_auction_with_next_covered_call_vault<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        expiration_ts_ms: u64,
        asset_name: vector<u8>,
        strike_otm_pct: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext,
    ) {
        let next = new_covered_call_vault_<TOKEN>(
            manager_cap,
            registry,
            expiration_ts_ms,
            asset_name,
            strike_otm_pct,
            price_oracle,
            ctx,
        );
        option::fill(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .next,
            next
        );
        new_auction_<TOKEN>(
            manager_cap,
            registry,
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            ctx,
        );
    }

    public(friend) entry fun withdraw<TOKEN>(
        registry: &mut Registry,
        index: u64,
        amount: Option<u64>,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::withdraw<ManagerCap, TOKEN>(
            get_mut_vault<TOKEN>(
                registry,
                index
            ),
            amount,
            is_rolling,
            ctx
        );
    }

    public(friend) entry fun withdraw_all<TOKEN>(
        registry: &mut Registry,
        indexes: VecMap<u64, bool>,
        ctx: &mut TxContext
    ) {
        while (!vec_map::is_empty(&indexes)){
            let (index, is_rolling) = vec_map::pop(&mut indexes);
            vault::withdraw<ManagerCap, TOKEN>(
                get_mut_vault<TOKEN>(
                    registry,
                    index
                ),
                option::none(),
                is_rolling,
                ctx
            );
        }
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

    public entry fun settle_without_roll_over<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        expired_index: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let covered_call_vault = get_mut_covered_call_vault<TOKEN>(
            registry,
            expired_index
        );

        settle_internal<TOKEN>(
            manager_cap,
            &mut covered_call_vault.vault,
            &covered_call_vault.config.payoff_config,
            covered_call_vault.config.expiration_ts_ms,
            price_oracle,
            time_oracle
        );
    }

    public entry fun settle_prepare_rolling<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        expired_index: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let covered_call_vault = get_mut_covered_call_vault<TOKEN>(
            registry,
            expired_index
        );

        settle_internal<TOKEN>(
            manager_cap,
            &mut covered_call_vault.vault,
            &covered_call_vault.config.payoff_config,
            covered_call_vault.config.expiration_ts_ms,
            price_oracle,
            time_oracle
        );

        let (balance, scaled_user_shares) = vault::prepare_rolling<ManagerCap, TOKEN>(
            manager_cap,
            &mut covered_call_vault.vault
        );

        settle_rock_n_roll<TOKEN>(
            manager_cap,
            registry,
            expired_index,
            balance,
            scaled_user_shares
        );
    }

    fun settle_rock_n_roll<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        expired_index: u64,
        balance: Balance<TOKEN>,
        scaled_user_shares: VecMap<address, u64>
    ) {
        let next_index = get_next_covered_call_vault_index<TOKEN>(registry, expired_index);
        let next_index = option::borrow<u64>(&next_index);

        let new_vault = get_mut_vault<TOKEN>(
            registry,
            *next_index
        );

        vault::rock_n_roll<ManagerCap, TOKEN>(
            manager_cap,
            new_vault,
            balance,
            scaled_user_shares
        );   
    }

    fun settle_internal<TOKEN>(
        manager_cap: &ManagerCap,
        expired_vault: &mut Vault<ManagerCap, TOKEN>,
        payoff_config: &PayoffConfig,
        expiration_ts_ms: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let (price, _decimal, _unix_ms, _epoch) = oracle::get_oracle<TOKEN>(price_oracle);

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        check_already_expired(expiration_ts_ms, current_ts_ms);

        // calculate settlement roi
        let roi = payoff::get_covered_call_payoff_by_price(price, payoff_config);
        let roi_multiplier = utils::multiplier(payoff::get_roi_decimal());

        // debug::print(&string::utf8(b"roi"));
        // debug::print(&roi);

        let share_price_decimal = 8;
        let settled_share_price = if (!i64::is_neg(&roi)) {
            utils::multiplier(share_price_decimal) * (roi_multiplier + i64::as_u64(&roi)) / roi_multiplier
        } else {
            utils::multiplier(share_price_decimal) * (roi_multiplier + i64::as_u64(&i64::abs(&roi))) / roi_multiplier
        };

        vault::settle_fund<ManagerCap, TOKEN>(
            manager_cap,
            expired_vault,
            settled_share_price,
            share_price_decimal
        );
        // TODO: calculate performance fee
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