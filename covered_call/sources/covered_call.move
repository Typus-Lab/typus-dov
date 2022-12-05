module typus_covered_call::covered_call {
    use std::option;
    use std::string::{Self, String};

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::Coin;
    use sui::event::emit;

    use typus_dov::vault::{Self, VaultRegistry};
    use typus_dov::asset;
    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_dov::dutch::Auction;
    use typus_oracle::oracle::{Self, Oracle};
    use sui::object::{Self, UID};

    // ======== Structs =========

    struct ManagerCap<phantom CONFIG> has key {
        id: UID,
    }

    struct Config has store, drop, copy {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    // ======== Functions =========

    fun init_(ctx: &mut TxContext) {
        let manager_cap = ManagerCap<Config> {
            id: object::new(ctx)
        };
        transfer::transfer(manager_cap, tx_context::sender(ctx));
        vault::new_vault_registry<ManagerCap<Config>, Config>(ctx);
    }

    fun init(ctx: &mut TxContext) {
        init_(ctx);
    }

    public fun get_config<TOKEN>(
        vault_registry: &mut VaultRegistry<ManagerCap<Config>, Config>,
        vault_index: u64,
    ): &Config {
        vault::get_config<ManagerCap<Config>, TOKEN, Config, Auction<TOKEN>>(vault_registry, vault_index)
    }
     

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    public fun check_already_expired(config: &Config, unix_ms: u64) {
        assert!(unix_ms >= config.expiration_ts * 1000, E_VAULT_NOT_EXPIRED_YET);
    }

    public fun set_premium_roi<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut VaultRegistry<ManagerCap<Config>, Config>,
        index: u64,
        premium_roi: u64
    ){
        let config = vault::get_mut_config<ManagerCap<Config>, TOKEN, Config, Auction<TOKEN>>(
            manager_cap,
            vault_registry,
            index
        );
        payoff::set_premium_roi(&mut config.payoff_config, premium_roi);
    }

    public entry fun new_covered_call_vault<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut VaultRegistry<ManagerCap<Config>, Config>,
        expiration_ts: u64,
        asset_name: vector<u8>,
        strike: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext
    ){
        let (price, price_decimal, _, _) = oracle::get_oracle<TOKEN>(
            price_oracle
        );

        let asset = string::utf8(asset_name);
        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(asset, price, price_decimal),
            strike,
            option::none(),
        );

        let _n = vault::new_vault<ManagerCap<Config>, TOKEN, Config, Auction<TOKEN>>(
            manager_cap,
            vault_registry,
            Config { payoff_config, expiration_ts },
            ctx
        );

        emit(VaultCreated{
            asset,
            expiration_ts,
            strike,
        });
    }

    public entry fun deposit<TOKEN>(
        vault_registry: &mut VaultRegistry<ManagerCap<Config>, Config>,
        index: u64,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        ctx: &mut TxContext
    ){
        let rolling = true;

        vault::deposit<ManagerCap<Config>, TOKEN, Config, Auction<TOKEN>>(
            vault_registry,
            index,
            coin,
            amount,
            rolling,
            ctx
        );

    }

    public entry fun unsubscribe<TOKEN>(
        vault_registry: &mut VaultRegistry<ManagerCap<Config>, Config>,
        index: u64,
        ctx: &mut TxContext
    ){
        vault::unsubscribe<ManagerCap<Config>, TOKEN, Config, Auction<TOKEN>>(
            vault_registry, index, ctx
        );
    }

    public entry fun withdraw<TOKEN>(
        vault_registry: &mut VaultRegistry<ManagerCap<Config>, Config>,
        index: u64,
        amount: u64,
        ctx: &mut TxContext
    ){
        let rolling = false;

        vault::withdraw<ManagerCap<Config>, TOKEN, Config, Auction<TOKEN>>(
            vault_registry, 
            index,
            option::some(amount),
            rolling,
            ctx
        );
    }

    const E_VAULT_NOT_EXPIRED_YET: u64 = 777;

    // ======== Events =========

    struct VaultCreated has copy, drop {
        asset: String,
        expiration_ts: u64,
        strike: u64,
    }

    // struct VaultDeposit has copy, drop {
    //     index: u64,
    //     amount: u64,
    //     rolling: bool,
    // }

    // ======== Test =========

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init_(ctx);
    }

    // #[test_only]
    // public fun get_sub_vault_deposit<T>(vault_registry: &mut VaultRegistry<Config>, index: u64): vector<u64> {
    //     use std::vector;
    //     let deposit_value_rolling = vault::get_vault_deposit_value<T, Config, Auction<T>>(vault_registry, index, string::utf8(b"rolling"));
    //     let deposit_value_regular = vault::get_vault_deposit_value<T, Config, Auction<T>>(vault_registry, index, string::utf8(b"regular"));
    //     let deposit_value_mm = vault::get_vault_deposit_value<T, Config, Auction<T>>(vault_registry, index, string::utf8(b"maker"));
    //     let vec = vector::empty<u64>();
    //     vector::push_back<u64>(&mut vec, deposit_value_rolling);
    //     vector::push_back<u64>(&mut vec, deposit_value_regular);
    //     vector::push_back<u64>(&mut vec, deposit_value_mm);
    //     vec
    // }
    // #[test_only]
    // public fun get_sub_vault_share_supply<T>(vault_registry: &mut VaultRegistry<Config>, index: u64): vector<u64> {
    //     use std::vector;
    //     let share_supply_rolling = vault::get_vault_share_supply<T, Config, Auction<T>>(vault_registry, index, string::utf8(b"rolling"));
    //     let share_supply_regular = vault::get_vault_share_supply<T, Config, Auction<T>>(vault_registry, index, string::utf8(b"regular"));
    //     let share_supply_mm = vault::get_vault_share_supply<T, Config, Auction<T>>(vault_registry, index, string::utf8(b"maker"));
    //     let vec = vector::empty<u64>();
    //     vector::push_back<u64>(&mut vec, share_supply_rolling);
    //     vector::push_back<u64>(&mut vec, share_supply_regular);
    //     vector::push_back<u64>(&mut vec, share_supply_mm);
    //     vec
    // }
}