module typus_dov::vault {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // ======== Structs =========

    struct ManagerCap<phantom P> has key, store { id: UID }

    struct VaultRegistry<phantom P>  has key {
        id: UID,
        num_of_vault: u64,
    }

    struct Vault<phantom T, P: store> has store {
        config: VaultConfig,
        payoff_config: P,
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
        vault_config: VaultConfig,
        payoff_config: P,
        ctx: &mut TxContext
    ) {
        let vault = Vault<T, P> {
            config: vault_config,
            payoff_config,
            deposit: balance::zero<T>(),
            share_supply: 0,
            users_table: table::new<address, u64>(ctx),
        };
        dynamic_field::add(&mut vault_registry.id, vault_registry.num_of_vault, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;
    }

    public fun deposit<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        index: u64, 
        token: Coin<T>, 
        ctx: &mut TxContext
    ) {
        let vault = get_mut_vault<T, P>(vault_registry, index);

        let sender = tx_context::sender(ctx);

        let deposit_value = coin::value(&token);

        assert!(deposit_value > 0, EZeroAmount);

        let tok_balance = coin::into_balance(token);

        let tok_amt = balance::join(&mut vault.deposit, tok_balance);

        assert!(tok_amt < vault.config.deposit_limit, EVaultFull);

        vault.share_supply = vault.share_supply + deposit_value;

        // check exist
        if (table::contains(& vault.users_table, sender)){
            let v = table::borrow_mut(&mut vault.users_table, sender);
            *v = *v + deposit_value;
        } else {
            table::add(&mut vault.users_table, sender, deposit_value);
        };

    }

    fun get_mut_vault<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        index: u64,
    ): &mut Vault<T, P> {
        dynamic_field::borrow_mut<u64, Vault<T, P>>(&mut vault_registry.id, index)
    }

    fun get_vault<T, P: store>(
        vault_registry: &mut VaultRegistry<P>,
        index: u64,
    ): Vault<T, P> {
        dynamic_field::remove<u64, Vault<T, P>>(&mut vault_registry.id, index)
    }

    // ======== Events =========

    struct RegistryCreated<phantom P> has copy, drop { id: ID }

    // ======== Errors =========

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EVaultFull: u64 = 1;

}