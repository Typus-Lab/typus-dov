module typus_shark_fin::shark_fin {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    // use sui::event::emit;
    use typus_dov::vault::{Self, VaultRegistry};
    use typus_shark_fin::payoff::{Self, PayoffConfig};
    use std::string;

    // ======== Structs =========

    // ======== Functions =========

    fun init(ctx: &mut TxContext) {
        let manager_cap = vault::new_manager_cap<PayoffConfig>(ctx);

        transfer::transfer(manager_cap, tx_context::sender(ctx));

        vault::new_vault_registry<PayoffConfig>(ctx);
    }


    public entry fun new_shark_fin_vault<T>(
        vault_registry: &mut VaultRegistry<PayoffConfig>,
        expiration_ts: u64,
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        ctx: &mut TxContext
    ){
        let config = payoff::new_config(
            expiration_ts,
            is_bullish,
            low_barrier_price,
            high_barrier_price
        );

        let n = vault::new_vault<T, PayoffConfig>(vault_registry, *payoff::get_payoff_config(&config), ctx);

        vault::new_sub_vault<T, PayoffConfig>(vault_registry, n, string::utf8(b"rolling"), ctx);

        vault::new_sub_vault<T, PayoffConfig>(vault_registry, n, string::utf8(b"regular"), ctx);

        vault::new_sub_vault<T, PayoffConfig>(vault_registry, n, string::utf8(b"maker"), ctx);
    }

    // ======== Events =========

    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
    }
}