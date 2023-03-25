module typus_covered_call::covered_call {
    use std::option::{Self, Option};
    use std::vector;

    use sui::bag::{Self, Bag};
    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map;

    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_framework::dutch::{Self, Auction};
    use typus_framework::i64;
    use typus_framework::utils;
    use typus_framework::vault::{Self, Vault};
    use typus_oracle::oracle::{Self, Oracle};
    use typus_oracle::unix_time::{Self, Time};

    #[test_only]
    friend typus_covered_call::test;

    // ======== Constants ========

    const C_SHARE_PRICE_DECIMAL: u64 = 8;
    const C_USER_SHARE_TABLE_NAME: vector<u8> = b"user_share_table";
    const C_MAKER_SHARE_TABLE_NAME: vector<u8> = b"maker_share_table";

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
        fee_config: FeeConfig,
        token_decimal: u64,
        share_decimal: u64,
        period: u8, // Daily = 0, Weekly = 1, Monthly = 2
        start_ts_ms: u64,
        expiration_ts_ms: u64
    }

    struct FeeConfig has store, drop, copy {
        fee_decimal: u64,
        withdrawal_fee: u64,
        performance_fee: u64,
        delivery_fee: u64,
    }

    struct Registry has key {
        id: UID,
        num_of_vault: u64,
        records: Bag, // C_USER_SHARE_TABLE_NAME, C_MAKER_SHARE_TABLE_NAME
    }

    struct CoveredCallVault<phantom TOKEN> has store {
        config: Config,
        vault: Vault<ManagerCap, TOKEN>,
        auction: Option<Auction<ManagerCap, TOKEN>>,
        next: Option<u64>,
    }

    struct UserShareKey has copy, drop, store {
        index: u64,
        user: address,
        is_rolling: bool,
    }

    struct MakerShareKey has copy, drop, store {
        index: u64,
        maker: address,
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
        let records = bag::new(ctx);
        let user_share_table = table::new<UserShareKey, u64>(ctx);
        bag::add(&mut records, C_USER_SHARE_TABLE_NAME, user_share_table);
        let maker_balance_table = table::new<MakerShareKey, u64>(ctx);
        bag::add(&mut records, C_MAKER_SHARE_TABLE_NAME, maker_balance_table);


        let vault = Registry {
            id,
            num_of_vault: 0,
            records,
        };

        transfer::share_object(vault);
    }

    fun new_covered_call_vault_<TOKEN>(
        _manager_cap: &ManagerCap,
        registry: &mut Registry,
        token_decimal: u64,
        share_decimal: u64,
        time_oracle: &Time,
        period: u8,
        start_ts_ms: u64,
        expiration_ts_ms: u64,
        strike_otm_pct: u64, // in 4 decimal
        fee_decimal: u64,
        withdrawal_fee: u64,
        performance_fee: u64,
        delivery_fee: u64,
        ctx: &mut TxContext
    ): u64 {
        let payoff_config = payoff::new_payoff_config(
            strike_otm_pct,
            option::none(),
            option::none(),
            option::none(),
        );

        let fee_config = FeeConfig {
            fee_decimal,
            withdrawal_fee,
            performance_fee,
            delivery_fee,
        };

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        assert!(expiration_ts_ms > current_ts_ms, E_INVALID_TIME);

        let config = Config {
            payoff_config,
            fee_config,
            token_decimal,
            share_decimal,
            period,
            start_ts_ms,
            expiration_ts_ms
        };
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
        ctx: &mut TxContext,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        vault::disable_deposit(manager_cap, &mut covered_call_vault.vault);
        vault::disable_withdraw(manager_cap, &mut covered_call_vault.vault);

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        assert!(start_ts_ms >= current_ts_ms, E_INVALID_TIME);
        assert!(end_ts_ms >= start_ts_ms, E_INVALID_TIME);
        assert!(initial_price > final_price, E_INVALID_PRICE);

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
        emit(NewAuction {
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            token_decimal: covered_call_vault.config.token_decimal,
            share_decimal: covered_call_vault.config.share_decimal,
        });
    }

    fun get_mut_covered_call_vault<TOKEN>(
        registry: &mut Registry,
        index: u64,
    ): &mut CoveredCallVault<TOKEN> {
        dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(&mut registry.id, index)
    }

    fun settle_<TOKEN>(
        manager_cap: &ManagerCap,
        covered_call_vault: &mut CoveredCallVault<TOKEN>,
        token_decimal: u64,
        share_decimal: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let (price, _decimal, _unix_ms, _epoch) = oracle::get_oracle<TOKEN>(price_oracle);

        let current_ts_ms = unix_time::get_ts_ms(time_oracle);
        check_already_expired(covered_call_vault.config.expiration_ts_ms, current_ts_ms);

        // calculate settlement roi
        let roi = payoff::get_covered_call_payoff_by_price(price, &covered_call_vault.config.payoff_config);
        let roi_multiplier = utils::multiplier(payoff::get_roi_decimal());

        let settled_share_price = if (!i64::is_neg(&roi)) {
            utils::multiplier(C_SHARE_PRICE_DECIMAL) * (roi_multiplier + i64::as_u64(&roi)) / roi_multiplier
        } else {
            utils::multiplier(C_SHARE_PRICE_DECIMAL) * (roi_multiplier - i64::as_u64(&i64::abs(&roi))) / roi_multiplier
        };

        vault::settle_fund<ManagerCap, TOKEN>(
            manager_cap,
            &mut covered_call_vault.vault,
            settled_share_price,
            covered_call_vault.config.fee_config.performance_fee,
            token_decimal,
            share_decimal,
            C_SHARE_PRICE_DECIMAL,
            covered_call_vault.config.fee_config.fee_decimal,
        );
        // TODO: calculate performance fee
    }

    fun roll_over_<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
    ) {
        let covered_call_vault = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index);
        let token_decimal = covered_call_vault.config.token_decimal;
        let share_decimal = covered_call_vault.config.share_decimal;
        let (balance, scaled_user_shares) = vault::prepare_rolling<ManagerCap, TOKEN>(
            manager_cap,
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            token_decimal,
            share_decimal,
        );

        let next = *option::borrow(&get_mut_covered_call_vault<TOKEN>(registry, index).next);
        vault::rock_n_roll<ManagerCap, TOKEN>(
            manager_cap,
            &mut get_mut_covered_call_vault<TOKEN>(registry, next).vault,
            balance,
            scaled_user_shares
        );

        // update user receipt
        while (!vec_map::is_empty(&scaled_user_shares)) {
            let (user, share) = vec_map::pop(&mut scaled_user_shares);
            let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
            let user_share_key = UserShareKey {
                index,
                user,
                is_rolling: true,
            };
            if (table::contains(user_share_table, user_share_key)) {
                table::remove(user_share_table, user_share_key);
            };
            let user_share_key = UserShareKey {
                index: next,
                user,
                is_rolling: true,
            };
            if (table::contains(user_share_table, user_share_key)) {
                let user_share = table::borrow_mut(user_share_table, user_share_key);
                *user_share = *user_share + share;
            }
            else {
                table::add(
                    user_share_table,
                    user_share_key,
                    share,
                );
            };
        };

    }

    fun check_already_expired(expiration_ts_ms: u64, ts_ms: u64) {
        assert!(ts_ms >= expiration_ts_ms, E_VAULT_NOT_EXPIRED_YET);
    }

    // ======== Entry Functions =========

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

    public(friend) entry fun new_covered_call_vault<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        token_decimal: u64,
        share_decimal: u64,
        time_oracle: &Time,
        period: u8,
        start_ts_ms: u64,
        expiration_ts_ms: u64,
        strike_otm_pct: u64, // in 4 decimal
        fee_decimal: u64,
        withdrawal_fee: u64,
        performance_fee: u64,
        delivery_fee: u64,
        ctx: &mut TxContext
    ) {
        new_covered_call_vault_<TOKEN>(
            manager_cap,
            registry,
            token_decimal,
            share_decimal,
            time_oracle,
            period,
            start_ts_ms,
            expiration_ts_ms,
            strike_otm_pct,
            fee_decimal,
            withdrawal_fee,
            performance_fee,
            delivery_fee,
            ctx,
        );
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
            ctx,
        );
    }

    public(friend) entry fun new_auction_with_next_covered_call_vault<TOKEN>(
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
        strike_otm_pct: u64,
        ctx: &mut TxContext,
    ) {
        let covered_call_vault = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index);
        let next = new_covered_call_vault_<TOKEN>(
            manager_cap,
            registry,
            covered_call_vault.config.token_decimal,
            covered_call_vault.config.share_decimal,
            time_oracle,
            covered_call_vault.config.period,
            covered_call_vault.config.expiration_ts_ms,
            expiration_ts_ms,
            strike_otm_pct,
            covered_call_vault.config.fee_config.fee_decimal,
            covered_call_vault.config.fee_config.withdrawal_fee,
            covered_call_vault.config.fee_config.performance_fee,
            covered_call_vault.config.fee_config.delivery_fee,
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
            time_oracle,
            index,
            start_ts_ms,
            end_ts_ms,
            decay_speed,
            initial_price,
            final_price,
            ctx,
        );
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
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            strike
        );

        payoff::set_premium_roi(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            premium_roi
        );

        payoff::set_exposure_ratio(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
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
        let covered_call_vault = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index);
        let token_decimal = covered_call_vault.config.token_decimal;
        let share_decimal = covered_call_vault.config.share_decimal;
        let share = vault::deposit<ManagerCap, TOKEN>(
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            coin,
            amount,
            token_decimal,
            share_decimal,
            is_rolling,
            ctx
        );

        // update user receipt
        let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
        let user_share_key = UserShareKey {
            index,
            user: tx_context::sender(ctx),
            is_rolling,
        };
        if (table::contains(user_share_table, user_share_key)) {
            let user_share = table::borrow_mut(user_share_table, user_share_key);
            *user_share = *user_share + share;
        }
        else {
            table::add(
                user_share_table,
                user_share_key,
                share,
            );
        };

        // emit event
        emit(Deposit{
            index,
            amount,
            is_rolling,
            user: tx_context::sender(ctx)
        });
    }

    public(friend) entry fun withdraw<TOKEN>(
        registry: &mut Registry,
        index: u64,
        share: u64,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::withdraw<ManagerCap, TOKEN>(
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            if (share == 0) option::none() else option::some(share),
            is_rolling,
            ctx
        );

        // update user receipt
        let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
        let user_share_key = UserShareKey {
            index,
            user: tx_context::sender(ctx),
            is_rolling,
        };
        if (share == 0 || share >= *table::borrow(user_share_table, user_share_key)) {
            table::remove(user_share_table, user_share_key);
        }
        else {
            let user_share = table::borrow_mut(user_share_table, user_share_key);
            *user_share = *user_share - share;
        };

        // TODO: emit event
    }

    public(friend) entry fun claim<TOKEN>(
        registry: &mut Registry,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::claim<ManagerCap, TOKEN>(
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            ctx
        );

        // update user receipt
        let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
        let user_share_key = UserShareKey {
            index,
            user: tx_context::sender(ctx),
            is_rolling: true,
        };
        if (table::contains(user_share_table, user_share_key)) {
            table::remove(user_share_table, user_share_key);
        };
        let user_share_key = UserShareKey {
            index,
            user: tx_context::sender(ctx),
            is_rolling: false,
        };
        if (table::contains(user_share_table, user_share_key)) {
            table::remove(user_share_table, user_share_key);
        };

        // TODO: emit event
    }

    public(friend) entry fun claim_all<TOKEN>(
        registry: &mut Registry,
        index: vector<u64>,
        ctx: &mut TxContext
    ) {

        while (!vector::is_empty(&index)){
            let index = vector::pop_back(&mut index);
            vault::claim<ManagerCap, TOKEN>(
                &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
                ctx
            );

            // update user receipt
            let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
            let user_share_key = UserShareKey {
                index,
                user: tx_context::sender(ctx),
                is_rolling: true,
            };
            if (table::contains(user_share_table, user_share_key)) {
                table::remove(user_share_table, user_share_key);
            };
            let user_share_key = UserShareKey {
                index,
                user: tx_context::sender(ctx),
                is_rolling: false,
            };
            if (table::contains(user_share_table, user_share_key)) {
                table::remove(user_share_table, user_share_key);
            };
        }

        // TODO: emit event
    }

    public(friend) entry fun maker_claim<TOKEN>(
        registry: &mut Registry,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::maker_claim<ManagerCap, TOKEN>(
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            ctx
        );

        // update maker receipt
        let maker_share_table = bag::borrow_mut<vector<u8>, Table<MakerShareKey, u64>>(&mut registry.records, C_MAKER_SHARE_TABLE_NAME);
        let maker_share_key = MakerShareKey {
            index,
            maker: tx_context::sender(ctx),
        };
        table::remove(maker_share_table, maker_share_key);

        // TODO: emit event
    }

    public(friend) entry fun maker_claim_all<TOKEN>(
        registry: &mut Registry,
        index: vector<u64>,
        ctx: &mut TxContext
    ) {
        while (!vector::is_empty(&index)){
            let index = vector::pop_back(&mut index);
            vault::maker_claim<ManagerCap, TOKEN>(
                &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
                ctx
            );

            // update maker receipt
            let maker_share_table = bag::borrow_mut<vector<u8>, Table<MakerShareKey, u64>>(&mut registry.records, C_MAKER_SHARE_TABLE_NAME);
            let maker_share_key = MakerShareKey {
                index,
                maker: tx_context::sender(ctx),
            };
            table::remove(maker_share_table, maker_share_key);
        }

        // TODO: emit event
    }

    public(friend) entry fun subscribe<TOKEN>(
        registry: &mut Registry,
        index: u64,
        share: u64,
        ctx: &mut TxContext
    ) {
        vault::subscribe<ManagerCap, TOKEN>(
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            if (share == 0) option::none() else option::some(share),
            ctx,
        );

        // update user receipt
        let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
        let user_share_key = UserShareKey {
            index,
            user: tx_context::sender(ctx),
            is_rolling: false,
        };
        if (table::contains(user_share_table, user_share_key)) {
            let share = table::remove(user_share_table, user_share_key);
            let user_share_key = UserShareKey {
                index,
                user: tx_context::sender(ctx),
                is_rolling: true,
            };
            if (table::contains(user_share_table, user_share_key)) {
                let user_share = table::borrow_mut(user_share_table, user_share_key);
                *user_share = *user_share + share;
            }
            else {
                table::add(
                    user_share_table,
                    user_share_key,
                    share,
                );
            };
        };

        // TODO: emit event
    }

    public(friend) entry fun unsubscribe<TOKEN>(
        registry: &mut Registry,
        index: u64,
        share: u64,
        ctx: &mut TxContext
    ) {
        vault::unsubscribe<ManagerCap, TOKEN>(
            &mut get_mut_covered_call_vault<TOKEN>(registry, index).vault,
            if (share == 0) option::none() else option::some(share),
            ctx,
        );

        // update user receipt
        let user_share_table = bag::borrow_mut<vector<u8>, Table<UserShareKey, u64>>(&mut registry.records, C_USER_SHARE_TABLE_NAME);
        let user_share_key = UserShareKey {
            index,
            user: tx_context::sender(ctx),
            is_rolling: true,
        };
        if (table::contains(user_share_table, user_share_key)) {
            let share = table::remove(user_share_table, user_share_key);
            let user_share_key = UserShareKey {
                index,
                user: tx_context::sender(ctx),
                is_rolling: false,
            };
            if (table::contains(user_share_table, user_share_key)) {
                let user_share = table::borrow_mut(user_share_table, user_share_key);
                *user_share = *user_share + share;
            }
            else {
                table::add(
                    user_share_table,
                    user_share_key,
                    share,
                );
            };
        };

        // TODO: emit event
    }

    public(friend) entry fun new_bid<TOKEN>(
        registry: &mut Registry,
        index: u64,
        size: u64,
        coin: &mut Coin<TOKEN>,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        dutch::new_bid<ManagerCap, TOKEN>(
            option::borrow_mut(&mut covered_call_vault.auction),
            size,
            covered_call_vault.config.token_decimal,
            covered_call_vault.config.share_decimal,
            coin,
            time,
            ctx,
        );

        // TODO: emit event
    }

    public(friend) entry fun delivery<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        size: u64, // total auction size
        time: &Time,
    ) {
        let covered_call_vault = dynamic_field::borrow_mut<u64, CoveredCallVault<TOKEN>>(
            &mut registry.id,
            index
        );
        let (balance, maker_shares) = dutch::delivery<ManagerCap, TOKEN>(
            manager_cap,
            option::borrow_mut(&mut covered_call_vault.auction),
            size,
            covered_call_vault.config.token_decimal,
            covered_call_vault.config.share_decimal,
            time
        );
        vault::maker_deposit(
            manager_cap,
            &mut covered_call_vault.vault,
            balance,
            maker_shares,
        );

        // update maker share table
        while (!vec_map::is_empty(&maker_shares)) {
            let (maker, share) = vec_map::pop(&mut maker_shares);
            let maker_share_table = bag::borrow_mut<vector<u8>, Table<MakerShareKey, u64>>(&mut registry.records, C_MAKER_SHARE_TABLE_NAME);
            table::add(
                maker_share_table,
                MakerShareKey {
                    index,
                    maker,
                },
                share,
            );
        };

        // TODO: emit event
    }

    public(friend) entry fun settle<TOKEN>(
        manager_cap: &ManagerCap,
        registry: &mut Registry,
        index: u64,
        price_oracle: &Oracle<TOKEN>,
        time_oracle: &Time
    ) {
        let token_decimal = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).config.token_decimal;
        let share_decimal = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).config.share_decimal;

        settle_<TOKEN>(
            manager_cap,
            get_mut_covered_call_vault<TOKEN>(registry, index),
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
        let token_decimal = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).config.token_decimal;
        let share_decimal = dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).config.share_decimal;

        settle_(
            manager_cap,
            get_mut_covered_call_vault<TOKEN>(registry, index),
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
        token_decimal: u64,
        share_decimal: u64,
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
        &dynamic_field::borrow<u64, CoveredCallVault<TOKEN>>(&registry.id, index).vault
    }
}