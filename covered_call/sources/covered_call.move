module typus_covered_call::covered_call {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    // use sui::event::emit;
    use typus_dov::vault::{Self, VaultRegistry, VaultConfig};
    use typus_covered_call::payoff::{PayoffConfig};

    // ======== Structs =========

    // ======== Functions =========

    fun init(ctx: &mut TxContext) {
        let manager_cap = vault::new_manager_cap<PayoffConfig>(ctx);

        transfer::transfer(manager_cap, tx_context::sender(ctx));

        vault::new_vault_registry<PayoffConfig>(ctx);
    }


    public entry fun new_covered_call_vault<T>(
        vault_registry: &mut VaultRegistry<PayoffConfig>,
        vault_config: VaultConfig,
        payoff_config: PayoffConfig,
        ctx: &mut TxContext
    ){
        vault::new_vault<T, PayoffConfig>(vault_registry, vault_config, payoff_config, ctx);
    }

    // ======== Events =========

    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        strike: u64,
    }
}