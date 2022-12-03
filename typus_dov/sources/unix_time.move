module typus_dov::unix_time {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::event::emit;

    // ======== Structs =========

    struct ManagerCap has key, store { id: UID }

    struct Time has key {
        id: UID,
        ts_ms: u64,
        epoch: u64,
    }

    // ======== Functions =========

    public entry fun new_time(
        ctx: &mut TxContext
    ) {
        let time = Time { 
            id: object::new(ctx),
            ts_ms: 0,
            epoch: tx_context::epoch(ctx)
        };

        transfer::share_object(time);

        let manager_cap = ManagerCap { id: object::new(ctx) };

        transfer::transfer(manager_cap, tx_context::sender(ctx));
    }

    public entry fun update(
        time: &mut Time,
        _manager_cap: &ManagerCap,
        ts_ms: u64,
        ctx: &mut TxContext
    ) {
        time.ts_ms = ts_ms;
        time.epoch = tx_context::epoch(ctx);
        emit(TimeEvent { ts_ms, epoch: tx_context::epoch(ctx) });
    }

    public fun get_time(
        time: &Time
    ): (u64, u64) {
        (time.ts_ms , time.epoch)
    }

    public fun get_ts_ms(
        time: &Time
    ): u64 {
        time.ts_ms
    }

    public fun get_epoch(
        time: &Time
    ): u64 {
        time.epoch
    }

    #[test_only]
    public fun new_time_for_testing(
        ctx: &mut TxContext
    ): Time {
        let time = Time { 
            id: object::new(ctx),
            ts_ms: 0,
            epoch: tx_context::epoch(ctx)
        };

        let manager_cap = ManagerCap { id: object::new(ctx) };

        transfer::transfer(manager_cap, tx_context::sender(ctx));
        time
    }
    
    #[test_only]
    public fun destroy_for_testing(self: Time){
        let Time{
            id,
            ts_ms: _,
            epoch: _,
        } = self;
        object::delete(id);
    }

    struct TimeEvent has copy, drop { ts_ms: u64, epoch: u64 }
}