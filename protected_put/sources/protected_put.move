module typus_protected_put::protected_put {
    use std::option::{Self, Option};
    use std::vector;

    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event::emit;

    use typus_protected_put::payoff::{Self, PayoffConfig};
    use typus_dov::dutch::{Self, Auction};
    use typus_dov::i64;
    use typus_dov::vault::{Self, Vault};
    use typus_dov::utils;
    use typus_dov::asset::{Self, Asset};
    use typus_oracle::oracle::{Self, Oracle};
    use typus_oracle::unix_time::{Self, Time};

    #[test_only]
    friend typus_protected_put::test;

    // ======== Constants ========

    const C_SHARE_PRICE_DECIMAL: u64 = 8;

    // ======== Errors ========
    const E_VAULT_NOT_EXPIRED_YET: u64 = 0;
    const E_INDEX_AND_FLAG_LENGTH_MISMATCH: u64 = 1;
    const E_INVALID_TIME: u64 = 2;
    const E_INVALID_PRICE: u64 = 3;

    // ======== Structs =========

    struct ManagerCap has key {
        id: UID,
    }

    struct Config has store, drop, copy {
        payoff_config: PayoffConfig,
        token_decimal: u64,
        share_decimal: u64,
        expiration_ts_ms: u64
    }

    struct Registry has key {
        id: UID,
        num_of_vault: u64,
    }

    struct ProtectedPutVault<phantom TOKEN> has store {
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

    fun new_protected_put_vault_<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        token_decimal: u64,
        share_decimal: u64,
        time_oracle: &Time,
        expiration_ts_ms: u64,
        underlying_asset: Asset,
        strike_otm_pct: u64, // in 4 decimal
        ctx: &mut TxContext
    ): u64 {

        let payoff_config = payoff::new_payoff_config(
            underlying_asset,
            strike_otm_pct,
            option::none(),
            option::none(),
            option::none(),
        );

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        assert!(expiration_ts_ms > current_ts_ms, E_INVALID_TIME);

        let config = Config { payoff_config, token_decimal, share_decimal, expiration_ts_ms };
        let vault = vault::new_vault<ManagerCap, TOKEN>(ctx);
        let index = registry.num_of_vault;

        dynamic_field::add(
            &mut registry.id,
            index,
            ProtectedPutVault {
                config,
                vault,
                auction: option::none(),
                next: option::none(),
            }
        );
        registry.num_of_vault = registry.num_of_vault + 1;


        emit(VaultCreated<TOKEN>{
            expiration_ts_ms,
            strike_otm_pct,
        });

        index
    }

    fun new_auction_<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        time_oracle: &Time,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        price_decimal: u64,
        ctx: &mut TxContext,
    ) {
        let protected_put_vault = dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
            &mut registry.id,
            index
        );
        vault::disable_deposit(manager_cap, &mut protected_put_vault.vault);
        vault::disable_withdraw(manager_cap, &mut protected_put_vault.vault);

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        assert!(start_ts_ms >= current_ts_ms, E_INVALID_TIME);
        assert!(end_ts_ms >= start_ts_ms, E_INVALID_TIME);
        assert!(initial_price > final_price, E_INVALID_PRICE);

        option::fill(
            &mut protected_put_vault.auction,
            dutch::new(
                start_ts_ms,
                end_ts_ms,
                decay_speed,
                initial_price,
                final_price,
                price_decimal,
                ctx,
            )
        );
        emit(NewAuction{
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            price_decimal
        });
    }

    fun get_mut_protected_put_vault<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &mut ProtectedPutVault<TOKEN> {
        dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(&mut registry.id, index)
    }

    fun settle_<TOKEN>(
        manager_cap: &ManagerCap,
        protected_put_vault: &mut ProtectedPutVault<TOKEN>,
        token_decimal: u64,
        share_decimal: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let (price, _decimal, _unix_ms, _epoch) = oracle::get_oracle<TOKEN>(price_oracle);

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        check_already_expired(protected_put_vault.config.expiration_ts_ms, current_ts_ms);

        // calculate settlement roi
        let roi = payoff::get_protected_put_payoff_by_price(price, &protected_put_vault.config.payoff_config);
        let roi_multiplier = utils::multiplier(payoff::get_roi_decimal());

        let settled_share_price = if (!i64::is_neg(&roi)) {
            utils::multiplier(C_SHARE_PRICE_DECIMAL) * (roi_multiplier + i64::as_u64(&roi)) / roi_multiplier
        } else {
            utils::multiplier(C_SHARE_PRICE_DECIMAL) * (roi_multiplier - i64::as_u64(&i64::abs(&roi))) / roi_multiplier
        };

        vault::settle_fund<ManagerCap, TOKEN>(
            manager_cap,
            &mut protected_put_vault.vault,
            settled_share_price,
            token_decimal,
            share_decimal,
            C_SHARE_PRICE_DECIMAL
        );
        // TODO: calculate performance fee
    }

    fun roll_over_<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
    ) {
        let protected_put_vault = dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index);
        let token_decimal = protected_put_vault.config.token_decimal;
        let share_decimal = protected_put_vault.config.share_decimal;
        let (balance, scaled_user_shares) = vault::prepare_rolling<ManagerCap, TOKEN>(
            manager_cap,
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
            token_decimal,
            share_decimal
        );

        let next = *option::borrow(&get_mut_protected_put_vault<TOKEN>(registry, index).next);
        vault::rock_n_roll<ManagerCap, TOKEN>(
            manager_cap,
            &mut get_mut_protected_put_vault<TOKEN>(registry, next).vault,
            balance,
            scaled_user_shares
        );
    }

    fun check_already_expired(expiration_ts_ms: u64, ts_ms: u64) {
        assert!(ts_ms >= expiration_ts_ms, E_VAULT_NOT_EXPIRED_YET);
    }

    // ======== Entry Functions =========

    public(friend) entry fun new_protected_put_vault<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        token_decimal: u64,
        share_decimal: u64,
        time_oracle: &Time,
        expiration_ts_ms: u64,
        underlying_asset: vector<u8>,
        strike_otm_pct: u64, // in 4 decimal
        ctx: &mut TxContext
    ) {
        let underlying_asset = asset::new_asset(underlying_asset);
        new_protected_put_vault_<TOKEN>(
            manager_cap,
            registry,
            token_decimal,
            share_decimal,
            time_oracle,
            expiration_ts_ms,
            underlying_asset,
            strike_otm_pct,
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

    public(friend) entry fun remove_manager(
        manager_cap: ManagerCap,
    ) {
        let ManagerCap { id } = manager_cap;
        object::delete(id);
    }

    // after delivery
    public(friend) entry fun update_payoff_config<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        strike: u64,
        premium_roi: u64,
        exposure_ratio: u64
    ) {
        
        payoff::set_strike(
            &mut dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            strike
        );

        payoff::set_premium_roi(
            &mut dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            premium_roi
        );

        payoff::set_exposure_ratio(
            &mut dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            exposure_ratio
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
        let protected_put_vault = dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index);
        let token_decimal = protected_put_vault.config.token_decimal;
        let share_decimal = protected_put_vault.config.share_decimal;
        vault::deposit<ManagerCap, TOKEN>(
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
            coin,
            amount,
            token_decimal,
            share_decimal,
            is_rolling,
            ctx
        );
        emit(Deposit{
            index,
            amount,
            is_rolling,
            user: tx_context::sender(ctx)
        });
    }

    public(friend) entry fun new_auction<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        time_oracle: &Time,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        ctx: &mut TxContext,
    ) {
        let protected_put_vault = dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index);
        let token_decimal = protected_put_vault.config.token_decimal;
        let share_decimal = protected_put_vault.config.share_decimal;
        new_auction_<TOKEN>(
            manager_cap,
            registry,
            time_oracle,
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            token_decimal - share_decimal,
            ctx,
        );
    }

    public(friend) entry fun new_auction_with_next_protected_put_vault<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        time_oracle: &Time,
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        expiration_ts_ms: u64,
        underlying_asset: vector<u8>,
        strike_otm_pct: u64,
        ctx: &mut TxContext,
    ) {
        let protected_put_vault = dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index);
        let token_decimal = protected_put_vault.config.token_decimal;
        let share_decimal = protected_put_vault.config.share_decimal;
        let underlying_asset = asset::new_asset(underlying_asset);
        let next = new_protected_put_vault_<TOKEN>(
            manager_cap,
            registry,
            token_decimal,
            share_decimal,
            time_oracle,
            expiration_ts_ms,
            underlying_asset,
            strike_otm_pct,
            ctx,
        );
        option::fill(
            &mut dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .next,
            next
        );
        new_auction_<TOKEN>(
            manager_cap,
            registry,
            time_oracle,
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            token_decimal - share_decimal,
            ctx,
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
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
            if (amount == 0) option::none() else option::some(amount),
            is_rolling,
            ctx
        );
    }

    public(friend) entry fun claim<TOKEN>(
        registry: &mut Registry,
        index: u64,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::claim<ManagerCap, TOKEN>(
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
            if (amount == 0) option::none() else option::some(amount),
            is_rolling,
            ctx
        );
    }

    public(friend) entry fun claim_all<TOKEN>(
        registry: &mut Registry,
        index: vector<u64>,
        is_rolling: vector<bool>,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&index) == vector::length(&is_rolling), E_INDEX_AND_FLAG_LENGTH_MISMATCH);

        while (!vector::is_empty(&index)){
            let index = vector::pop_back(&mut index);
            let is_rolling = vector::pop_back(&mut is_rolling);
            vault::claim<ManagerCap, TOKEN>(
                &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
                option::none(),
                is_rolling,
                ctx
            );
        }
    }

    public(friend) entry fun maker_claim<TOKEN>(
        registry: &mut Registry,
        index: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        vault::maker_claim<ManagerCap, TOKEN>(
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
            if (amount == 0) option::none() else option::some(amount),
            ctx
        );
    }

    public(friend) entry fun maker_claim_all<TOKEN>(
        registry: &mut Registry,
        index: vector<u64>,
        ctx: &mut TxContext
    ) {
        while (!vector::is_empty(&index)){
            let index = vector::pop_back(&mut index);
            vault::maker_claim<ManagerCap, TOKEN>(
                &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
                option::none(),
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
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
            ctx,
        );
    }

    public(friend) entry fun unsubscribe<TOKEN>(
        registry: &mut Registry,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::unsubscribe<ManagerCap, TOKEN>(
            &mut get_mut_protected_put_vault<TOKEN>(registry, index).vault,
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
            option::borrow_mut(&mut dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
                &mut registry.id,
                index
            ).auction),
            size,
            coin,
            time,
            ctx,
        );
    }

    // public(friend) entry fun remove_bid<TOKEN>(
    //     registry: &mut Registry,
    //     index: u64,
    //     bid_index: u64,
    //     time: &Time,
    //     ctx: &mut TxContext,
    // ) {
    //     dutch::remove_bid<ManagerCap, TOKEN>(
    //         option::borrow_mut(&mut dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
    //             &mut registry.id,
    //             index
    //         ).auction),
    //         bid_index,
    //         time,
    //         ctx,
    //     );
    // }

    public(friend) entry fun delivery<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        size: u64, // total auction size
        time: &Time,
    ) {
        let protected_put_vault = dynamic_field::borrow_mut<u64, ProtectedPutVault<TOKEN>>(
            &mut registry.id,
            index
        );
        let (balance, maker_shares) = dutch::delivery<ManagerCap, TOKEN>(
            manager_cap,
            option::borrow_mut(&mut protected_put_vault.auction),
            size,
            time
        );
        vault::maker_deposit(
            manager_cap,
            &mut protected_put_vault.vault,
            balance,
            maker_shares,
        );
    }

    public(friend) entry fun settle<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let protected_put_vault = dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index);
        let token_decimal = protected_put_vault.config.token_decimal;
        let share_decimal = protected_put_vault.config.share_decimal;

        settle_<TOKEN>(
            manager_cap,
            get_mut_protected_put_vault<TOKEN>(registry, index),
            token_decimal,
            share_decimal,
            price_oracle,
            time_oracle
        );
    }

    public(friend) entry fun roll_over<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
    ) {
        roll_over_<TOKEN>(
            manager_cap,
            registry,
            index,
        );
    }

    public(friend) entry fun settle_with_roll_over<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let protected_put_vault = dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index);
        let token_decimal = protected_put_vault.config.token_decimal;
        let share_decimal = protected_put_vault.config.share_decimal;

        settle_(
            manager_cap,
            get_mut_protected_put_vault<TOKEN>(registry, index),
            token_decimal,
            share_decimal,
            price_oracle,
            time_oracle,
        );
        roll_over_<TOKEN>(
            manager_cap,
            registry,
            index,
        );
    }

    // ======== Events =========

    struct VaultCreated<phantom TOKEN> has copy, drop {
        expiration_ts_ms: u64,
        strike_otm_pct: u64,
    }

    struct Deposit has copy, drop {
        index: u64,
        amount: u64,
        is_rolling: bool,
        user: address
    }

    struct NewAuction has copy, drop {
        index: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        price_decimal: u64,
    }


    // ======== Test =========

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init_(ctx);
    }

    #[test_only]
    public fun test_get_vault<TOKEN>(
        registry: &Registry,
        index: u64,
    ): &Vault<ManagerCap, TOKEN> {
        &dynamic_field::borrow<u64, ProtectedPutVault<TOKEN>>(&registry.id, index).vault
    }

}