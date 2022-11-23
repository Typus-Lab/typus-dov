module typus_covered_call::covered_call {
    use std::option;
    use std::string;

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    // use sui::event::emit;

    use typus_dov::vault::{Self, VaultRegistry};
    use typus_covered_call::payoff::{Self, PayoffConfig};

    // ======== Structs =========

    struct Config has store {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    // ======== Functions =========

    fun init(ctx: &mut TxContext) {
        let manager_cap = vault::new_manager_cap<Config>(ctx);

        transfer::transfer(manager_cap, tx_context::sender(ctx));

        vault::new_vault_registry<Config>(ctx);
    }

    // Entry Functions


    public entry fun new_covered_call_vault<T>(
        vault_registry: &mut VaultRegistry<Config>,
        strike: u64,
        expiration_ts: u64,
        ctx: &mut TxContext
    ){
        let payoff_config = payoff::new_payoff_config(
            strike,
            option::none(),
        );

        let config = Config {
            payoff_config,
            expiration_ts
        };

        let n = vault::new_vault<T, Config>(vault_registry, config, ctx);

        vault::new_sub_vault<T, Config>(vault_registry, n, string::utf8(b"rolling"), ctx);

        vault::new_sub_vault<T, Config>(vault_registry, n, string::utf8(b"regular"), ctx);

        vault::new_sub_vault<T, Config>(vault_registry, n, string::utf8(b"maker"), ctx);
    }

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    // ======== Events =========

    struct VaultCreated has copy, drop {
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        strike: u64,
    }
}