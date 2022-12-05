module typus_dov::vault {
    use std::option::{Self, Option};
    use sui::vec_map;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use typus_dov::linked_list::{Self, LinkedList};
    use typus_dov::utils;

    // ======== Constants ========

    const C_VAULT_ROLLING: vector<u8> = b"rolling";
    const C_VAULT_REGULAR: vector<u8> = b"regular";
    const C_VAULT_MAKER: vector<u8> = b"maker";

    // ======== Errors ========

    const E_ZERO_AMOUNT: u64 = 0;
    const E_DEPOSIT_DISABLED: u64 = 1;
    const E_WITHDRAW_DISABLED: u64 = 2;
    const E_SUBSCRIBE_DISABLED: u64 = 3;
    const E_UNSUBSCRIBE_DISABLED: u64 = 4;
    const E_NEXT_VAULT_NOT_EXISTS: u64 = 5;
    const E_NOT_YET_SETTLED: u64 = 6;
    const E_HAS_BEEN_SETTLED: u64 = 7;

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
        user_shares: LinkedList<address, u64>,
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
    public fun new_vault<MANAGER, TOKEN, CONFIG: copy + drop + store, AUCTION: store>(
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
            user_shares: linked_list::new(ctx),
        };
        table::add(&mut vault.sub_vaults, C_VAULT_ROLLING, rolling_vault);
        
        let regular_vault = SubVault<TOKEN> {
            balance: balance::zero<TOKEN>(),
            share_supply: 0,
            user_shares: linked_list::new(ctx),
        };
        table::add(&mut vault.sub_vaults, C_VAULT_REGULAR, regular_vault);
        
        let maker_vault = SubVault<TOKEN> {
            balance: balance::zero<TOKEN>(),
            share_supply: 0,
            user_shares: linked_list::new(ctx),
        };
        table::add(&mut vault.sub_vaults, C_VAULT_MAKER, maker_vault);

        let vault_index = vault_registry.num_of_vault;
        dynamic_field::add(&mut vault_registry.id, vault_index, vault);
        vault_registry.num_of_vault = vault_registry.num_of_vault + 1;

        emit(VaultCreated<MANAGER, TOKEN, CONFIG, AUCTION> { config });

        vault_index
    }

    public fun new_next_vault<MANAGER, TOKEN, CONFIG: copy + drop + store, AUCTION: store>(
        _manager_cap: &MANAGER,
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        config: CONFIG,
        ctx: &mut TxContext
    ): u64 {
        let next_vault_index = new_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
            _manager_cap,
            vault_registry,
            config,
            ctx,
        );
        let vault = get_mut_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        option::fill(&mut vault.next_vault_index, next_vault_index);

        next_vault_index
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

    public fun settle_fund<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        _manager_cap: &MANAGER,
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        settled_share_price: u64,
        share_price_decimal: u64
    ) {
        let Vault {
            config: _,
            auction: _,
            next_vault_index,
            sub_vaults: _,
            able_to_deposit: atd,
            able_to_withdraw: atw,
        } = get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        assert!(option::is_some(next_vault_index), E_NEXT_VAULT_NOT_EXISTS);
        assert!((!*atd && *atw), E_NOT_YET_SETTLED);

        let balance = balance::value(
            &get_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry, vault_index, C_VAULT_ROLLING
            ).balance
        ) + balance::value(
            &get_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry, vault_index, C_VAULT_REGULAR
            ).balance
        );

        let share_supply = get_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
            vault_registry, vault_index, C_VAULT_ROLLING
        ).share_supply + get_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
            vault_registry, vault_index, C_VAULT_REGULAR
        ).share_supply;

        assert!(balance == share_supply, E_HAS_BEEN_SETTLED);

        let multiplier = utils::multiplier(share_price_decimal);

        if (settled_share_price > multiplier) {
            // user receives balance from maker
            let payoff = balance * (settled_share_price - multiplier) / multiplier;
            // transfer balance from maker to rolling users
            let rolling_share_supply = get_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry, vault_index, C_VAULT_ROLLING
            ).share_supply;
            let coin = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_MAKER
                ).balance,
                payoff * rolling_share_supply / share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_ROLLING
                ).balance,
                coin
            );
            // transfer balance from maker to regular users
            let coin = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_MAKER
                ).balance,
                payoff * (share_supply - rolling_share_supply) / share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_REGULAR
                ).balance,
                coin
            );
        }
        else if (settled_share_price < multiplier) {
            // maker receives balance from users
            let payoff = balance * (multiplier - settled_share_price) / multiplier;
            // transfer balance from rolling users to maker
            let rolling_share_supply = get_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry, vault_index, C_VAULT_ROLLING
            ).share_supply;
            let coin = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_ROLLING
                ).balance,
                payoff * rolling_share_supply / share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_MAKER
                ).balance,
                coin
            );
            // transfer balance from regular users to maker
            let coin = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_REGULAR
                ).balance,
                payoff * (share_supply - rolling_share_supply) / share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(
                    vault_registry, vault_index, C_VAULT_MAKER
                ).balance,
                coin
            );
        }
        
    }

    public fun rock_n_roll<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        _manager_cap: &MANAGER,
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
    ) {
        let Vault {
            config: _,
            auction: _,
            next_vault_index,
            sub_vaults: _,
            able_to_deposit: atd,
            able_to_withdraw: atw,
        } = get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        assert!(option::is_some(next_vault_index), E_NEXT_VAULT_NOT_EXISTS);
        assert!((!*atd && *atw), E_NOT_YET_SETTLED);

        // scale user shares
        let SubVault {
            balance,
            share_supply,
            user_shares,
        } = get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index, C_VAULT_ROLLING);
        let index = linked_list::first(user_shares);
        let total_balance = balance::value(balance);
        let scaled_shares = vec_map::empty();
        while (option::is_some(&index)) {
            let user = option::borrow(&index);
            vec_map::insert(
                &mut scaled_shares,
                *user,
                *linked_list::borrow(user_shares, *user) * total_balance / *share_supply
            );
            index = linked_list::next(user_shares, *user);
        };

        // transfer balance to next vault
        let balance = balance::split(balance, total_balance);
        let next_vault_index = *option::borrow(&get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index).next_vault_index);
        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, next_vault_index, C_VAULT_ROLLING);
        balance::join(&mut sub_vault.balance, balance);

        // add user shares to next vault
        while (!vec_map::is_empty(&scaled_shares)) {
            let (user, share) = vec_map::pop(&mut scaled_shares);
            add_share(sub_vault, user, share);
        }
    }

    public fun deposit<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        assert!(get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index).able_to_deposit, E_DEPOSIT_DISABLED);
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

            emit(UserDeposit<MANAGER, TOKEN, CONFIG, AUCTION> { user, sub_vault_type: C_VAULT_ROLLING, amount });
        }
        else {
            deposit_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_REGULAR,
                balance::split(coin::balance_mut(coin), amount),
                user,
            );

            emit(UserDeposit<MANAGER, TOKEN, CONFIG, AUCTION> { user, sub_vault_type: C_VAULT_REGULAR, amount });
        }
    }

    public fun withdraw<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        amount: Option<u64>,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        assert!(get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index).able_to_withdraw, E_WITHDRAW_DISABLED);
        let user = tx_context::sender(ctx);
        let balance = if (is_rolling) {
            let (share, balance) = withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_ROLLING,
                amount,
                user,
            );

            emit(UserWithdraw<MANAGER, TOKEN, CONFIG, AUCTION> { user, sub_vault_type: C_VAULT_ROLLING, share, amount:balance::value(&balance) });

            balance
        }
        else {
            let (share, balance) = withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
                vault_registry,
                vault_index,
                C_VAULT_REGULAR,
                amount,
                user,
            );

            emit(UserWithdraw<MANAGER, TOKEN, CONFIG, AUCTION> { user, sub_vault_type: C_VAULT_REGULAR, share, amount:balance::value(&balance) });

            balance
        };
        transfer::transfer(coin::from_balance(balance, ctx), user);
    }

    public fun subscribe<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        ctx: &mut TxContext
    ) {
        let Vault {
            config: _,
            auction: _,
            next_vault_index: _,
            sub_vaults: _,
            able_to_deposit: atd,
            able_to_withdraw: atw,
        } = get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        assert!((*atd && *atw) || (!*atd && !*atw), E_SUBSCRIBE_DISABLED);

        let user = tx_context::sender(ctx);
        let (_, balance) = withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
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

    public fun unsubscribe<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        ctx: &mut TxContext
    ) {
        let Vault {
            config: _,
            auction: _,
            next_vault_index: _,
            sub_vaults: _,
            able_to_deposit: atd,
            able_to_withdraw: atw,
        } = get_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index);
        assert!((*atd && *atw) || (!*atd && !*atw), E_UNSUBSCRIBE_DISABLED);

        let user = tx_context::sender(ctx);
        let (_, balance) = withdraw_<MANAGER, TOKEN, CONFIG, AUCTION>(
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
        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index, sub_vault_type);
        let share = balance::value(&balance);
        // join balance
        balance::join(&mut sub_vault.balance, balance);
        // add share
        add_share(sub_vault, user, share);
    }

    fun withdraw_<MANAGER, TOKEN, CONFIG: store, AUCTION: store>(
        vault_registry: &mut VaultRegistry<MANAGER, CONFIG>,
        vault_index: u64,
        sub_vault_type: vector<u8>,
        share: Option<u64>,
        user: address,
    ): (u64, Balance<TOKEN>) {
        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN, CONFIG, AUCTION>(vault_registry, vault_index, sub_vault_type);
        // remove share
        let share = remove_share(sub_vault, user , share);
        // extract balance
        let balance_amount = balance::value(&sub_vault.balance) * share / sub_vault.share_supply;
        (share, balance::split<TOKEN>(&mut sub_vault.balance, balance_amount))
    }

    fun add_share<TOKEN>(sub_vault: &mut SubVault<TOKEN>, user: address, share: u64) {
        sub_vault.share_supply = sub_vault.share_supply + share;
        if (linked_list::contains(&sub_vault.user_shares, user)){
            let user_share = linked_list::borrow_mut(&mut sub_vault.user_shares, user);
            *user_share = *user_share + share;
        } else {
            linked_list::push_back(&mut sub_vault.user_shares, user, share);
        };
    }

    fun remove_share<TOKEN>(sub_vault: &mut SubVault<TOKEN>, user: address, share: Option<u64>): u64 {
        if (option::is_some(&share)) {
            let share = option::extract(&mut share);
            if (share < *linked_list::borrow(&mut sub_vault.user_shares, user)) {
                let user_share = linked_list::borrow_mut(&mut sub_vault.user_shares, user);
                *user_share = *user_share - share;
                share
            }
            else {
                linked_list::remove(&mut sub_vault.user_shares, user)
            }
        }
        else {
            linked_list::remove(&mut sub_vault.user_shares, user)
        }
    }


    // ======== Events ========

    struct RegistryCreated<phantom MANAGER, phantom CONFIG> has copy, drop { id: ID }
    struct VaultCreated<phantom MANAGER, phantom TOKEN, CONFIG, phantom AUCTION> has copy, drop { config: CONFIG }
    struct UserDeposit<phantom MANAGER, phantom TOKEN, phantom CONFIG, phantom AUCTION> has copy, drop { user: address, sub_vault_type: vector<u8>, amount: u64 }
    struct UserWithdraw<phantom MANAGER, phantom TOKEN, phantom CONFIG, phantom AUCTION> has copy, drop { user: address, sub_vault_type: vector<u8>, share: u64, amount: u64 }

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