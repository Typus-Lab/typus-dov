module typus_dov::vault {
    use std::option::{Self, Option};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // ======== Constants ========

    const C_VAULT_ROLLING: vector<u8> = b"rolling";
    const C_VAULT_REGULAR: vector<u8> = b"regular";
    const C_VAULT_MAKER: vector<u8> = b"maker";

    // ======== Errors ========

    const E_ZERO_AMOUNT: u64 = 0;
    const E_USER_NOT_EXISTS: u64 = 1;
    const E_USER_ALREADY_EXISTS: u64 = 2;
    const E_SHARE_INSUFFICIENT : u64 = 3;
    const E_DEPOSIT_DISABLED: u64 = 4;
    const E_WITHDRAW_DISABLED: u64 = 5;

    // ======== Structs ========

    struct VaultRegistry<phantom MANAGER, phantom CONFIG> has key {
        id: UID,
        num_of_vault: u64,
    }

    struct Vault<phantom MANAGER, phantom TOKEN, CONFIG, AUCTION> has store {
        config: CONFIG,
        auction: Option<AUCTION>,
        next_vault_index: Option<u64>,
        sub_vaults: Table<vector<u8>, SubVault<TOKEN>>,
        able_to_deposit: bool,
        able_to_withdraw: bool,
    }

    struct SubVault<phantom TOKEN> has store {
        balance: Balance<TOKEN>,
        share_supply: u64,
        user_index: u64,
        users: Table<u64, address>,
        shares: Table<address, u64>
    }

    // ======== Public Functions ========

    /// Create a new VaultRegistry with explicit MANAGER and CONFIG
    public fun new_vault_registry<MANAGER, CONFIG>(
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        emit(RegistryCreated<MANAGER, CONFIG> { id: object::uid_to_inner(&id) });

        let vault = VaultRegistry<MANAGER, CONFIG> {
            id,
            num_of_vault: 0
        };

        transfer::share_object(vault);
    }

    /// Add a new Vault to VaultRegistry and return the Vault index
    public fun new_vault<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        _manager_cap: &MANAGER,
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        config: CONFIG,
        ctx: &mut TxContext
    ): u64 {
        let vault = Vault<MANAGER, TOKEN, CONFIG, AUCTION> {
            config,
            auction: option::none(),
            next_vault_index: option::none(),
            sub_vaults: table::new(ctx),
            able_to_deposit: true,
            able_to_withdraw: true,
        };
        
        let rolling_vault = SubVault<TOKEN> {
            balance: balance::zero<TOKEN>(),
            share_supply: 0,
            user_index: 0,
            users: table::new<u64, address>(ctx),
            shares: table::new<address, u64>(ctx),
        };
        table::add(&mut vault.sub_vaults, C_VAULT_ROLLING, rolling_vault);
        
        let regular_vault = SubVault<TOKEN> {
            balance: balance::zero<TOKEN>(),
            share_supply: 0,
            user_index: 0,
            users: table::new<u64, address>(ctx),
            shares: table::new<address, u64>(ctx),
        };
        table::add(&mut vault.sub_vaults, C_VAULT_REGULAR, regular_vault);
        
        let maker_vault = SubVault<TOKEN> {
            balance: balance::zero<TOKEN>(),
            share_supply: 0,
            user_index: 0,
            users: table::new<u64, address>(ctx),
            shares: table::new<address, u64>(ctx),
        };
        table::add(&mut vault.sub_vaults, C_VAULT_MAKER, maker_vault);

        let vault_index = vault_registry.num_of_vault;
        dynamic_field::add(&mut vault_registry.id, vault_index, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;

        vault_index
    }

    public fun new_auction<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        _manager_cap: &MANAGER,
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64, 
        auction: AUCTION,
    ) {
        let vault = get_mut_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        option::fill(&mut vault.auction, auction);
    }

    public fun deposit<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, E_ZERO_AMOUNT);

        let user = tx_context::sender(ctx);
        if (is_rolling) {
            deposit_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_ROLLING,
                balance::split(coin::balance_mut(coin), amount),
                user,
            );
        }
        else {
            deposit_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_REGULAR,
                balance::split(coin::balance_mut(coin), amount),
                user,
            );
        }
    }

    public fun withdraw<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        amount: Option<u64>,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let balance = if (is_rolling) {
            withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_ROLLING,
                amount,
                user,
            )
        }
        else {
            withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_REGULAR,
                amount,
                user,
            )
        };
        transfer::transfer(coin::from_balance(balance, ctx), user);
    }

    public fun unsubscribe<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let balance = withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
            vault_registry,
            vault_index,
            C_VAULT_ROLLING,
            option::none(),
            user,
        );
        deposit_<MANAGER, TOKEN, CONFIG, AUCTION>(
            vault_registry,
            vault_index,
            C_VAULT_REGULAR,
            balance,
            user,
        );
    }

    public fun subscribe<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let balance = withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
            vault_registry,
            vault_index,
            C_VAULT_REGULAR,
            option::none(),
            user,
        );
        deposit_<MANAGER, TOKEN, CONFIG, AUCTION>(
            vault_registry,
            vault_index,
            C_VAULT_ROLLING,
            balance,
            user,
        );
    }

    // ======== Private Functions ========

    fun get_vault<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
    ): &Vault<MANAGER, TOKEN, CONFIG, AUCTION> {
        dynamic_field::borrow<u64, Vault<MANAGER, TOKEN, CONFIG, AUCTION>>(&vault_registry.id, vault_index)
    }

    fun get_mut_vault<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
    ): &mut Vault<MANAGER, TOKEN, CONFIG, AUCTION> {
        dynamic_field::borrow_mut<u64, Vault<MANAGER, TOKEN, CONFIG, AUCTION>>(&mut vault_registry.id, vault_index)
    }

    fun get_sub_vault<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        sub_vault_type: vector<u8>
    ): &SubVault<TOKEN> {
        let vault = get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        table::borrow(&vault.sub_vaults, sub_vault_type)
    }

    fun get_mut_sub_vault<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        sub_vault_type: vector<u8>
    ): &mut SubVault<TOKEN> {
        let vault = get_mut_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        table::borrow_mut(&mut vault.sub_vaults, sub_vault_type)
    }

    fun deposit_<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        sub_vault_type: vector<u8>,
        balance: Balance<TOKEN>,
        user: address,
    ) {
        assert!(get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index).able_to_deposit, E_DEPOSIT_DISABLED);

        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index, sub_vault_type);
        let amount = balance::value(&balance);
        // charge coin
        balance::join(&mut sub_vault.balance, balance);
        // add share
        sub_vault.share_supply = sub_vault.share_supply + amount;
        if (table::contains(&sub_vault.shares, user)){
            let user_share = table::borrow_mut(&mut sub_vault.shares, user);
            *user_share = *user_share + amount;
        } else {
            table::add(&mut sub_vault.shares, user, amount);
        };
    }

    fun withdraw_<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        sub_vault_type: vector<u8>,
        amount: Option<u64>,
        user: address,
    ): Balance<TOKEN> {
        assert!(get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index).able_to_withdraw, E_WITHDRAW_DISABLED);

        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index, sub_vault_type);
        // update user share
        let amount = if (option::is_some(&amount)) {
            let amount = option::extract(&mut amount);
            if (amount < *table::borrow(&mut sub_vault.shares, user)) {
                let user_share = table::borrow_mut(&mut sub_vault.shares, user);
                *user_share = *user_share - amount;
                amount
            }
            else {
                table::remove(&mut sub_vault.shares, user)
            }
        }
        else {
            table::remove(&mut sub_vault.shares, user)
        };
        // extract the balance
        balance::split<TOKEN>(&mut sub_vault.balance, amount)
    }


    // ======== Events ========

    struct RegistryCreated<phantom MANAGER, phantom CONFIG> has copy, drop { id: ID }

    // // ======== Test Functions ========

    // #[test_only]
    // public fun test_only_new_vault_registry<C>(
    //     ctx: &mut TxContext
    // ): VaultRegistry<C> {
    //     let id = object::new(ctx);

    //     emit(RegistryCreated<C> { id: object::uid_to_inner(&id) });

    //     let vault = VaultRegistry<C> { id, num_of_vault: 0 };
    //     // transfer::share_object(vault);
    //    vault
    // }

    
    // #[test]
    // fun test_new_vault_registry_success(): VaultRegistry<sui::sui::SUI> {
    //     use sui::test_scenario;

    //     let admin = @0xFFFF;
    //     let scenario = test_scenario::begin(admin);

    //     let vault_registry = test_only_new_vault_registry(test_scenario::ctx(&mut scenario));
    //     assert!(vault_registry.num_of_vault == 0, 1);

    //     test_scenario::end(scenario);
    //     vault_registry
    // }
}