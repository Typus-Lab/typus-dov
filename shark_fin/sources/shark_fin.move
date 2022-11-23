module typus_shark_fin::shark_fin {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::option;
    // use sui::event::emit;
    use typus_dov::vault::{Self, VaultRegistry};
    use typus_shark_fin::payoff::{Self, PayoffConfig};
    use std::string;
    use sui::coin::Coin;

    // ======== Structs =========

    struct Config has store, copy, drop {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    // ======== Functions =========

    fun init(ctx: &mut TxContext) {
        let manager_cap = vault::new_manager_cap<Config>(ctx);

        transfer::transfer(manager_cap, tx_context::sender(ctx));

        vault::new_vault_registry<Config>(ctx);
    }

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    public entry fun new_shark_fin_vault<T>(
        vault_registry: &mut VaultRegistry<Config>,
        expiration_ts: u64,
        is_bullish: bool,
        low_barrier_price: u64,
        high_barrier_price: u64,
        ctx: &mut TxContext
    ){
        let payoff_config = payoff::new_payoff_config(
            is_bullish,
            low_barrier_price,
            high_barrier_price,
            option::none(),
            option::none(),
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

    public entry fun deposit<T>(
        vault_registry: &mut VaultRegistry<PayoffConfig>,
        index: u64,
        rolling: bool,
        token: Coin<T>, 
        ctx: &mut TxContext
    ){
        let name = if (rolling) {
            string::utf8(b"rolling")
        } else {
            string::utf8(b"no_rolling")
        };

        let sub_vault = vault::get_mut_sub_vault(vault_registry, index, name);

        let value = vault::deposit<T, PayoffConfig>(sub_vault, token);

        vault::add_share<T, PayoffConfig>(sub_vault, value, ctx);
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