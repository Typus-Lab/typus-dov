// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::covered_call {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID, ID};
    // use std::string::{Self, String};
    // use sui::url::{Self, Url};
    // use sui::math;
    use sui::event::emit;
    use sui::balance::{Self, Balance};


    struct ManagerCap has key, store { id: UID }

    struct PoolRegistry has key {
        id: UID,
        num_of_pool: u64,
    }

    struct PoolConfig<T: key + store> has key, store {
        id: UID,
        expired_type: u64,
        expired_date: u64,
        strike: u64,
        underlying_asset: T,
        fee_percent: u64
    }

    struct Pool<T: key + store> has key, store {
        id: UID,
        config: PoolConfig<T>,
        deposit: Balance<T>,
    }

    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);

        emit(RegistryCreated { id: object::uid_to_inner(&id) });

        transfer::transfer(ManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
        transfer::share_object(PoolRegistry {
            id,
            num_of_pool: 0
        })
    }

    public entry fun new_config<T: key + store>(
        expired_type: u64,
        expired_date: u64,
        strike: u64,
        underlying_asset: T,
        fee_percent: u64,
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        emit(PoolConfigCreated { id: object::uid_to_inner(&id) });

        transfer::share_object(PoolConfig {
            id,
            expired_type,
            expired_date,
            strike,
            underlying_asset,
            fee_percent
        })
    }

    public entry fun new_pool<T: key + store>(
        _: &ManagerCap,
        config: PoolConfig<T>, 
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        emit(PoolCreated { id: object::uid_to_inner(&id) });

        transfer::share_object(Pool {
            id,
            config,
            deposit: balance::zero<T>()
        })
    }


    // ======== Events =========

    struct RegistryCreated has copy, drop { id: ID }
    struct PoolConfigCreated has copy, drop { id: ID }
    struct PoolCreated has copy, drop { id: ID }

    
}
