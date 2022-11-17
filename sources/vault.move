module typus_dov::vault {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance, Supply};
    use sui::dynamic_field;
    use sui::coin::{Self, Coin};
    use sui::event::emit;

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EVaultFull: u64 = 1;

    struct ManagerCap has key, store { id: UID }

    struct VaultRegistry  has key {
        id: UID,
        num_of_vault: u64,
    }

    struct VaultConfig has store {
        expired_type: u64,
        expired_date: u64,
        strike: u64,
        fee_percent: u64,
        deposit_limit: u64,
    }


    struct Vault<phantom T> has key, store {
        id: UID,
        config: VaultConfig,
        deposit: Balance<T>,
        share_supply: Supply<Share>,
    }

    struct Share has drop {
        vault_id: ID
    }

    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);

        emit(RegistryCreated { id: object::uid_to_inner(&id) });

        transfer::transfer(ManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));

        transfer::share_object(VaultRegistry {
            id,
            num_of_vault: 0
        })
    }

    public entry fun new_vault<T>(
        vault_registry: &mut VaultRegistry,
        strike: u64,
        expired_type: u64,
        expired_date: u64,
        fee_percent: u64,
        deposit_limit: u64,
        ctx: &mut TxContext
    ) {
        let config = VaultConfig{
            expired_type,
            expired_date,
            strike,
            fee_percent,
            deposit_limit,
        };

        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        emit(VaultCreated{
            id,
            expired_type,
            expired_date,
            strike,
            fee_percent,
            deposit_limit,
        });

        let vault = Vault<T> {
            id: uid,
            config,
            deposit: balance::zero<T>(),
            share_supply: balance::create_supply(Share{vault_id: id})
        };
        dynamic_field::add(&mut vault_registry.id, vault_registry.num_of_vault, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;
    }

    entry fun deposit<T>(
        vault_registry: &mut VaultRegistry, index: u64, token: Coin<T>, ctx: &mut TxContext
    ) {
        let vault = get_mut_vault<T>(vault_registry, index);

        transfer::transfer(
            deposit_(vault, token, ctx),
            tx_context::sender(ctx)
        );
    }

    public fun deposit_<T>(
        vault: &mut Vault<T>, token: Coin<T>, ctx: &mut TxContext
    ): Coin<Share> {
        let deposit_value = coin::value(&token);

        assert!(deposit_value > 0, EZeroAmount);

        let tok_balance = coin::into_balance(token);

        let tok_amt = balance::join(&mut vault.deposit, tok_balance);

        assert!(tok_amt < vault.config.deposit_limit, EVaultFull);

        let balance = balance::increase_supply(&mut vault.share_supply, deposit_value);
        coin::from_balance(balance, ctx)
    }

    public fun get_mut_vault<T>(
        vault_registry: &mut VaultRegistry,
        index: u64,
    ): &mut Vault<T> {
        dynamic_field::borrow_mut<u64, Vault<T>>(&mut vault_registry.id, index)
    }

    // ======== Events =========
    struct RegistryCreated has copy, drop { id: ID }
    struct VaultCreated has copy, drop {
        id: ID,
        expired_type: u64,
        expired_date: u64,
        strike: u64,
        fee_percent: u64,
        deposit_limit: u64,
    }
}