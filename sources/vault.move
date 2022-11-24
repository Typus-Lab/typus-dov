module typus_dov::vault {
    use std::string::String;
    use sui::balance::{Self, Balance};
    use sui::coin::Coin;
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use typus_dov::utils;

    // ======== Structs =========

    struct ManagerCap<phantom C> has key, store { id: UID }

    struct VaultRegistry<phantom C> has key {
        id: UID,
        num_of_vault: u64,
    }

    struct Vault<phantom T, C: store> has store {
        config: C,
        sub_vaults: Table<String, SubVault<T>>
    }

    struct SubVault<phantom T> has store {
        index: u64,
        deposit: Balance<T>,
        share_supply: u64,
        user_map: Table<u64, address>,
        users_table: Table<address, u64>
    }

    // struct VaultConfig has key, store {
    //     id: UID,
    //     expired_date: u64,
    //     fee_percent: u64,
    //     deposit_limit: u64,
    // }

    // ======== Functions =========

    public fun new_manager_cap<C>(
        ctx: &mut TxContext
    ): ManagerCap<C> {
        ManagerCap<C> { id: object::new(ctx) } 
    }

    public fun new_vault_registry<C>(
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        emit(RegistryCreated<C> { id: object::uid_to_inner(&id) });

        let vault = VaultRegistry<C> { id, num_of_vault: 0 };

        transfer::share_object(vault);
    }

    public fun new_vault<T, C: store>(
        vault_registry: &mut VaultRegistry<C>,
        // vault_config: VaultConfig,
        config: C,
        ctx: &mut TxContext
    ): u64 {
        let vault = Vault<T, C> {
            config,
            sub_vaults: table::new<String, SubVault<T>>(ctx),
        };
        let n = vault_registry.num_of_vault;
        dynamic_field::add(&mut vault_registry.id, n, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;
        n
    }

    public fun new_sub_vault<T, C: store>(
        vault_registry: &mut VaultRegistry<C>,
        index: u64, 
        name: String,
        ctx: &mut TxContext
    ) {
        let vault = get_mut_vault<T, C>(vault_registry, index);

        let sub_vault = SubVault<T> {
            index: 0,
            deposit: balance::zero<T>(),
            share_supply: 0,
            user_map: table::new<u64, address>(ctx),
            users_table: table::new<address, u64>(ctx),
        };

        table::add(&mut vault.sub_vaults, name, sub_vault);
    }

    // public entry fun new_vault_config(
    //     ctx: &mut TxContext
    // ) {
    //     let vault = VaultConfig {
    //         id: object::new(ctx),
    //         expired_date: 0,
    //         fee_percent: 0,
    //         deposit_limit: 0, 
    //     };

    //     transfer::share_object(vault);
    // }

    public fun deposit<T, C: store>(
        sub_vault: &mut SubVault<T> ,
        coin: &mut Coin<T>,
        amount: u64,
    ): u64 {
        assert!(amount > 0, EZeroAmount);

        let balance = utils::extract_balance_from_coin(coin, amount);
        let amount = balance::join(&mut sub_vault.deposit, balance);

        amount
    }

    public fun add_share<T, C: store>(
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

    fun get_mut_vault<T, C: store>(
        vault_registry: &mut VaultRegistry<C>,
        index: u64,
    ): &mut Vault<T, C> {
        dynamic_field::borrow_mut<u64, Vault<T, C>>(&mut vault_registry.id, index)
    }

    public fun get_vault<T, C: store>(
        vault_registry: &VaultRegistry<C>,
        index: u64,
    ): &Vault<T, C> {
        dynamic_field::borrow<u64, Vault<T, C>>(&vault_registry.id, index)
    }

    public fun get_mut_sub_vault<T, C: store>(
        vault_registry: &mut VaultRegistry<C>,
        index: u64,
        name: String
    ): &mut SubVault<T> {
        let vault = get_mut_vault<T, C>(vault_registry, index);
        table::borrow_mut(&mut vault.sub_vaults, name)
    }

    public fun get_config<T, C: store>(vault: &Vault<T, C>): &C {
        &vault.config
    }

    public fun get_vault_deposit_value<T, C: store>(vault: &Vault<T, C>, name: String): u64 {
        let sub_vault = table::borrow(&vault.sub_vaults, name);
        balance::value<T>(&sub_vault.deposit)
    }
    
    public fun extract_subvault_deposit<T, C: store>(vault: &mut Vault<T, C>, name: String, value: u64): Balance<T> {
        let sub_vault = table::borrow_mut(&mut vault.sub_vaults, name);
        balance::split<T>(&mut sub_vault.deposit, value)
    }

    public fun join_subvault_deposit<T, C: store>(vault: &mut Vault<T, C>, name: String, coin: Balance<T>): u64 {
        let sub_vault = table::borrow_mut(&mut vault.sub_vaults, name);
        balance::join<T>(&mut sub_vault.deposit, coin)
    }
    
    public fun get_vault_share_supply<T, C: store>(vault: &Vault<T, C>, name: String): u64 {
        let sub_vault = table::borrow(&vault.sub_vaults, name);
        sub_vault.share_supply
    }

    public fun get_vault_users_table<T, C: store>(vault: &Vault<T, C>, name: String): &Table<address, u64> {
        let sub_vault = table::borrow(&vault.sub_vaults, name);
        &sub_vault.users_table
    }

    public fun get_mut_vault_users_table<T, C: store>(vault: &mut Vault<T, C>, name: String): &mut Table<address, u64> {
        let sub_vault = table::borrow_mut(&mut vault.sub_vaults, name);
        &mut sub_vault.users_table
    }

    public fun get_vault_user_index<T, C: store>(vault: &Vault<T, C>, name: String): &u64 {
        let sub_vault = table::borrow(&vault.sub_vaults, name);
        &sub_vault.index
    }

    public fun get_vault_user_map<T, C: store>(vault: &Vault<T, C>, name: String): &Table<u64, address> {
        let sub_vault = table::borrow(&vault.sub_vaults, name);
        &sub_vault.user_map
    }

    public fun add_share_supply<T, C: store>(vault: &mut Vault<T, C>, name: String, shares: u64) {
        let sub_vault = table::borrow_mut(&mut vault.sub_vaults, name);
        sub_vault.share_supply = sub_vault.share_supply + shares;
    }

    // ======== Events =========

    struct RegistryCreated<phantom C> has copy, drop { id: ID }

    // ======== Errors =========

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EVaultFull: u64 = 1;

}