module typus_dov::vault {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::string::String;

    // ======== Structs =========

    struct ManagerCap<phantom P> has key, store { id: UID }

    struct VaultRegistry<phantom P> has key {
        id: UID,
        num_of_vault: u64,
    }

    struct Vault<phantom T, P: store> has store {
        // config: VaultConfig,
        payoff_config: P,
        sub_vaults: Table<String, SubVault<T>>
    }

    struct SubVault<phantom T> has store {
        deposit: Balance<T>,
        share_supply: u64,
        users_table: Table<address, u64>
    }

    struct VaultConfig has key, store {
        id: UID,
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
    }

    // ======== Functions =========

    public fun new_manager_cap<P>(
        ctx: &mut TxContext
    ): ManagerCap<P> {
        ManagerCap<P> { id: object::new(ctx) } 
    }

    public fun new_vault_registry<P>(
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        emit(RegistryCreated<P> { id: object::uid_to_inner(&id) });

        let vault = VaultRegistry<P> { id, num_of_vault: 0 };

        transfer::share_object(vault);
    }

    public fun new_vault<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        // vault_config: VaultConfig,
        payoff_config: P,
        ctx: &mut TxContext
    ): u64 {
        let vault = Vault<T, P> {
            // config: vault_config,
            payoff_config,
            sub_vaults: table::new<String, SubVault<T>>(ctx),
        };
        let n = vault_registry.num_of_vault;
        dynamic_field::add(&mut vault_registry.id, n, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;
        n
    }

    public fun new_sub_vault<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        index: u64, 
        name: String,
        ctx: &mut TxContext
    ) {
        let vault = get_mut_vault<T, P>(vault_registry, index);

        let sub_vault = SubVault<T> {
            deposit: balance::zero<T>(),
            share_supply: 0,
            users_table: table::new<address, u64>(ctx),
        };

        table::add(&mut vault.sub_vaults, name, sub_vault);
    }

    public entry fun new_vault_config(
        ctx: &mut TxContext
    ) {
        let vault = VaultConfig {
            id: object::new(ctx),
            expired_date: 0,
            fee_percent: 0,
            deposit_limit: 0, 
        };

        transfer::share_object(vault);
    }

    public fun deposit<T, P: store>(
        sub_vault: &mut SubVault<T> ,
        token: Coin<T>, 
    ): u64 {
        let deposit_value = coin::value(&token);

        assert!(deposit_value > 0, EZeroAmount);

        let tok_balance = coin::into_balance(token);

        let tok_amt = balance::join(&mut sub_vault.deposit, tok_balance);

        tok_amt
    }

    public fun add_share<T, P: store>(
        sub_vault: &mut SubVault<T> ,
        value: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        sub_vault.share_supply = sub_vault.share_supply + value;

        // check exist
        if (table::contains(& sub_vault.users_table, sender)){
            let v = table::borrow_mut(&mut sub_vault.users_table, sender);
            *v = *v + value;
        } else {
            table::add(&mut sub_vault.users_table, sender, value);
        };
    }

    fun get_mut_vault<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        index: u64,
    ): &mut Vault<T, P> {
        dynamic_field::borrow_mut<u64, Vault<T, P>>(&mut vault_registry.id, index)
    }

    public fun get_vault<T, P: store>(
        vault_registry: &VaultRegistry<P>,
        index: u64,
    ): &Vault<T, P> {
        dynamic_field::borrow<u64, Vault<T, P>>(&vault_registry.id, index)
    }

    public fun get_mut_sub_vault<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        index: u64,
        name: String
    ): &mut SubVault<T> {
        let vault = get_mut_vault<T, P>(vault_registry, index);
        table::borrow_mut(&mut vault.sub_vaults, name)
    }

    public fun get_payoff_config<T, P: store>(vault: &Vault<T, P>): &P {
        &vault.payoff_config
    }

    public fun get_vault_deposit<T, P: store>(vault: &Vault<T, P>): &Balance<T> {
        &vault.deposit
    }
    
    public fun get_vault_share_supply<T, P: store>(vault: &Vault<T, P>): &u64 {
        &vault.share_supply
    }

    public fun get_vault_users_table<T, P: store>(vault: &Vault<T, P>): &Table<address, u64> {
        &vault.users_table
    }

    public fun get_mut_vault_users_table<T, P: store>(vault: &mut Vault<T, P>): &mut Table<address, u64> {
        &mut vault.users_table
    }

    public fun add_share_supply<T, P: store>(vault: &mut Vault<T, P>, shares: u64) {
        vault.share_supply = vault.share_supply + shares;
    }
    // public fun get_payoff_config<T, P: store>(
    //     vault_registry: &VaultRegistry<P>,
    //     index: u64
    // ): &PayoffConfig{
    //     get_vault<T, P>()
    // }

    // ======== Events =========

    struct RegistryCreated<phantom P> has copy, drop { id: ID }

    // ======== Errors =========

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EVaultFull: u64 = 1;

}