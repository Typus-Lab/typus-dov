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

    struct PoolConfig<phantom T> has key, store {
        id: UID,
        expired_type: u64,
        expired_date: u64,
        strike: u64,
        fee_percent: u64
    }

    struct Pool<phantom T> has key, store {
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

    public entry fun new_config<T>(
        expired_type: u64,
        expired_date: u64,
        strike: u64,
        fee_percent: u64,
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        emit(PoolConfigCreated { id: object::uid_to_inner(&id) });

        transfer::share_object(PoolConfig<T> {
            id,
            expired_type,
            expired_date,
            strike,
            fee_percent
        })
    }

    public entry fun new_pool<T>(
        _: &ManagerCap,
        pool_registry: &mut PoolRegistry,
        config: PoolConfig<T>, 
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        pool_registry.num_of_pool = pool_registry.num_of_pool + 1;

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
