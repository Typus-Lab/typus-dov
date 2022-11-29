module typus_dov::oracle {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::event::emit;

    // ======== Structs =========

    struct ManagerCap<phantom T> has key, store { id: UID }

    struct Oracle<phantom T> has key {
        id: UID,
        price: u64,
        unix_ms: u64,
        epoch: u64,
    }

    // ======== Functions =========

    public entry fun new_oracle<T>(
        ctx: &mut TxContext
    ) {
        let oracle = Oracle<T> { 
            id: object::new(ctx),
            price: 0,
            unix_ms: 0,
            epoch: tx_context::epoch(ctx)
        };

        transfer::share_object(oracle);

        let manager_cap = ManagerCap<T> { id: object::new(ctx) };

        transfer::transfer(manager_cap, tx_context::sender(ctx));
    }

    public entry fun update<T>(
        oracle: &mut Oracle<T>,
        _: &ManagerCap<T>,
        price: u64,
        unix_ms: u64,
        ctx: &mut TxContext
    ) {
        oracle.price = price;
        oracle.unix_ms = unix_ms;
        oracle.epoch = tx_context::epoch(ctx);
    }

    public fun get_oracle<T>(
        oracle: &Oracle<T>
    ): (u64, u64, u64) {
        (oracle.price, oracle.unix_ms, oracle.epoch)
    }

    entry fun emit_epoch(ctx: &mut TxContext){
        emit(EpochEvent { epoch: tx_context::epoch(ctx) });
    }

    struct EpochEvent has copy, drop { epoch: u64 }
}