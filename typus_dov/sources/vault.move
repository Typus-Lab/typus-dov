module typus_dov::vault {
    use std::option::{Self, Option};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event::emit;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

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
    const E_NOT_YET_ACTIVATED: u64 = 6;
    const E_NOT_YET_SETTLED: u64 = 8;
    const E_ALREADY_SETTLED: u64 = 9;
    const E_ALREADY_ACTIVATED: u64 = 10;

    // ======== Structs ========

    struct Vault<phantom MANAGER, phantom TOKEN> has store {
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

    /// Add a new Vault to Vault and return the Vault index
    public fun new_vault<MANAGER, TOKEN>(
        ctx: &mut TxContext
    ): Vault<MANAGER, TOKEN> {
        let vault = Vault<MANAGER, TOKEN> {
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

        vault
    }

    public fun settle_fund<MANAGER, TOKEN>(
        manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>,
        settled_share_price: u64,
        share_price_decimal: u64
    ) {
        assert!(!vault_initialized(vault), E_NOT_YET_ACTIVATED);
        assert!(!vault_settled(vault), E_ALREADY_SETTLED);

        let total_balance = balance::value(
            &get_sub_vault<MANAGER, TOKEN>(
                vault, C_VAULT_ROLLING
            ).balance
        ) + balance::value(
            &get_sub_vault<MANAGER, TOKEN>(
                vault, C_VAULT_REGULAR
            ).balance
        );

        let total_share_supply = get_sub_vault<MANAGER, TOKEN>(
            vault, C_VAULT_ROLLING
        ).share_supply + get_sub_vault<MANAGER, TOKEN>(
            vault, C_VAULT_REGULAR
        ).share_supply;

        assert!(total_balance == total_share_supply, E_ALREADY_SETTLED);

        let multiplier = utils::multiplier(share_price_decimal);

        if (settled_share_price > multiplier) {
            // user receives balance from maker
            let payoff = total_balance * (settled_share_price - multiplier) / multiplier;
            // transfer balance from maker to rolling users
            let rolling_share_supply = get_sub_vault<MANAGER, TOKEN>(
                vault, C_VAULT_ROLLING
            ).share_supply;
            let balance = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_MAKER
                ).balance,
                payoff * rolling_share_supply / total_share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_ROLLING
                ).balance,
                balance
            );
            // transfer balance from maker to regular users
            let balance = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_MAKER
                ).balance,
                payoff * (total_share_supply - rolling_share_supply) / total_share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_REGULAR
                ).balance,
                balance
            );
        }
        else if (settled_share_price < multiplier) {
            // maker receives balance from users
            let payoff = total_balance * (multiplier - settled_share_price) / multiplier;
            // transfer balance from rolling users to maker
            let rolling_share_supply = get_sub_vault<MANAGER, TOKEN>(
                vault, C_VAULT_ROLLING
            ).share_supply;
            let balance = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_ROLLING
                ).balance,
                payoff * rolling_share_supply / total_share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_MAKER
                ).balance,
                balance
            );
            // transfer balance from regular users to maker
            let balance = balance::split<TOKEN>(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_REGULAR
                ).balance,
                payoff * (total_share_supply - rolling_share_supply) / total_share_supply
            );
            balance::join(
                &mut get_mut_sub_vault<MANAGER, TOKEN>(
                    vault, C_VAULT_MAKER
                ).balance,
                balance
            );
        };
        enable_withdraw(manager_cap, vault);
    }

    public fun prepare_rolling<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>,
    ): (Balance<TOKEN>, VecMap<address, u64>) {
        assert!(vault_settled(vault), E_NOT_YET_SETTLED);

        let SubVault {
            balance,
            share_supply,
            user_shares,
        } = get_mut_sub_vault<MANAGER, TOKEN>(vault, C_VAULT_ROLLING);
        let index = linked_list::first(user_shares);
        let total_balance = balance::value(balance);
        let scaled_user_shares = vec_map::empty();
        while (option::is_some(&index)) {
            let user = option::borrow(&index);
            vec_map::insert(
                &mut scaled_user_shares,
                *user,
                *linked_list::borrow(user_shares, *user) * total_balance / *share_supply
            );
            index = linked_list::next(user_shares, *user);
        };

        (balance::split(balance, total_balance), scaled_user_shares)
    }

    public fun rock_n_roll<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>,
        balance: Balance<TOKEN>,
        scaled_user_shares: VecMap<address, u64>,
    ) {
        assert!(vault_initialized(vault), E_ALREADY_ACTIVATED);

        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN>(vault, C_VAULT_ROLLING);
        balance::join(&mut sub_vault.balance, balance);
        while (!vec_map::is_empty(&scaled_user_shares)) {
            let (user, share) = vec_map::pop(&mut scaled_user_shares);
            add_share(sub_vault, user, share);
        }
    }

    public fun deposit<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        assert!(vault_initialized(vault), E_ALREADY_ACTIVATED);
        assert!(amount > 0, E_ZERO_AMOUNT);

        let user = tx_context::sender(ctx);
        let sub_vault_type = if (is_rolling) {
            deposit_<MANAGER, TOKEN>(
                vault,
                C_VAULT_ROLLING,
                balance::split(coin::balance_mut(coin), amount),
                user,
            );

            C_VAULT_ROLLING
        }
        else {
            deposit_<MANAGER, TOKEN>(
                vault,
                C_VAULT_REGULAR,
                balance::split(coin::balance_mut(coin), amount),
                user,
            );

            C_VAULT_REGULAR
        };

        emit(UserDeposit<MANAGER, TOKEN> { user, sub_vault_type, amount });
    }

    public fun withdraw<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        amount: Option<u64>,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        assert!(vault_initialized(vault), E_ALREADY_ACTIVATED);

        let user = tx_context::sender(ctx);
        let (balance, sub_vault_type, share, amount) = if (is_rolling) {
            let (share, balance) = withdraw_<MANAGER, TOKEN>(
                vault,
                C_VAULT_ROLLING,
                amount,
                user,
            );
            let amount = balance::value(&balance);

            (balance, C_VAULT_ROLLING, share, amount)
        }
        else {
            let (share, balance) = withdraw_<MANAGER, TOKEN>(
                vault,
                C_VAULT_REGULAR,
                amount,
                user,
            );
            let amount = balance::value(&balance);

            (balance, C_VAULT_REGULAR, share, amount)
        };
        transfer::transfer(coin::from_balance(balance, ctx), user);

        emit(UserWithdraw<MANAGER, TOKEN> { user, sub_vault_type, share, amount });
    }

    public fun claim<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        amount: Option<u64>,
        is_rolling: bool,
        ctx: &mut TxContext,
    ) {
        assert!(vault_settled(vault), E_NOT_YET_SETTLED);
        
        let user = tx_context::sender(ctx);
        let (balance, sub_vault_type, share, amount) = if (is_rolling) {
            let (share, balance) = withdraw_<MANAGER, TOKEN>(
                vault,
                C_VAULT_ROLLING,
                amount,
                user,
            );
            let amount = balance::value(&balance);

            (balance, C_VAULT_ROLLING, share, amount)
        }
        else {
            let (share, balance) = withdraw_<MANAGER, TOKEN>(
                vault,
                C_VAULT_REGULAR,
                amount,
                user,
            );
            let amount = balance::value(&balance);

            (balance, C_VAULT_REGULAR, share, amount)
        };
        transfer::transfer(coin::from_balance(balance, ctx), user);

        emit(UserWithdraw<MANAGER, TOKEN> { user, sub_vault_type, share, amount });
    }

    public fun subscribe<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        ctx: &mut TxContext
    ) {
        assert!(vault_initialized(vault) || vault_activated(vault), E_SUBSCRIBE_DISABLED);

        let user = tx_context::sender(ctx);
        let (_, balance) = withdraw_<MANAGER, TOKEN>(
            vault,
            C_VAULT_REGULAR,
            option::none(),
            user,
        );
        deposit_<MANAGER, TOKEN>(
            vault,
            C_VAULT_ROLLING,
            balance,
            user,
        );
    }

    public fun unsubscribe<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        ctx: &mut TxContext
    ) {
        assert!(vault_initialized(vault) || vault_activated(vault), E_UNSUBSCRIBE_DISABLED);

        let user = tx_context::sender(ctx);
        let (_, balance) = withdraw_<MANAGER, TOKEN>(
            vault,
            C_VAULT_ROLLING,
            option::none(),
            user,
        );
        deposit_<MANAGER, TOKEN>(
            vault,
            C_VAULT_REGULAR,
            balance,
            user,
        );
    }

    public fun maker_deposit<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>,
        balance: Balance<TOKEN>,
        maker_shares: VecMap<address, u64>,
    ) {
        assert!(!vault_initialized(vault), E_NOT_YET_ACTIVATED);
        assert!(!vault_settled(vault), E_ALREADY_SETTLED);

        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN>(vault, C_VAULT_MAKER);
        balance::join(&mut sub_vault.balance, balance);
        while (!vec_map::is_empty(&maker_shares)) {
            let (user, share) = vec_map::pop(&mut maker_shares);
            add_share(sub_vault, user, share);
        }
    }

    public fun maker_claim<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        amount: Option<u64>,
        ctx: &mut TxContext,
    ) {
        assert!(vault_settled(vault), E_NOT_YET_SETTLED);

        let user = tx_context::sender(ctx);
        let (share, balance) = withdraw_<MANAGER, TOKEN>(
            vault,
            C_VAULT_MAKER,
            amount,
            user,
        );
        let amount = balance::value(&balance);

        transfer::transfer(coin::from_balance(balance, ctx), user);

        emit(UserWithdraw<MANAGER, TOKEN> { user, sub_vault_type: C_VAULT_MAKER, share, amount });
    }

    public fun enable_deposit<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>
    ) {
        vault.able_to_deposit = true;
    }

    public fun disable_deposit<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>
    ) {
        vault.able_to_deposit = false;
    }

    public fun enable_withdraw<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>
    ) {
        vault.able_to_withdraw = true;
    }

    public fun disable_withdraw<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        vault: &mut Vault<MANAGER, TOKEN>
    ) {
        vault.able_to_withdraw = false;
    }

    // ======== Private Functions ========

    fun get_sub_vault<MANAGER, TOKEN>(
        vault: &Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>
    ): &SubVault<TOKEN> {
        table::borrow(&vault.sub_vaults, sub_vault_type)
    }

    fun get_mut_sub_vault<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>
    ): &mut SubVault<TOKEN> {
        table::borrow_mut(&mut vault.sub_vaults, sub_vault_type)
    }

    fun deposit_<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>,
        balance: Balance<TOKEN>,
        user: address,
    ) {
        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN>(vault, sub_vault_type);
        let share = balance::value(&balance);
        // join balance
        balance::join(&mut sub_vault.balance, balance);
        // add share
        add_share(sub_vault, user, share);
    }

    fun withdraw_<MANAGER, TOKEN>(
        vault: &mut Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>,
        share: Option<u64>,
        user: address,
    ): (u64, Balance<TOKEN>) {
        let sub_vault = get_mut_sub_vault<MANAGER, TOKEN>(vault, sub_vault_type);
        let share_supply = sub_vault.share_supply;
        // remove share
        let share = remove_share(sub_vault, user, share);
        // extract balance
        let balance_amount = balance::value(&sub_vault.balance) * share / share_supply;
        (share, balance::split<TOKEN>(&mut sub_vault.balance, balance_amount))
    }

    fun add_share<TOKEN>(sub_vault: &mut SubVault<TOKEN>, user: address, share: u64) {
        sub_vault.share_supply = sub_vault.share_supply + share;
        if (linked_list::contains(&sub_vault.user_shares, user)) {
            let user_share = linked_list::borrow_mut(&mut sub_vault.user_shares, user);
            *user_share = *user_share + share;
        } else {
            linked_list::push_back(&mut sub_vault.user_shares, user, share);
        };
    }

    fun remove_share<TOKEN>(sub_vault: &mut SubVault<TOKEN>, user: address, share: Option<u64>): u64 {
        if (linked_list::contains(&sub_vault.user_shares, user)) {
            if (option::is_some(&share)) {
                let share = option::extract(&mut share);
                if (share < *linked_list::borrow(&mut sub_vault.user_shares, user)) {
                    let user_share = linked_list::borrow_mut(&mut sub_vault.user_shares, user);
                    *user_share = *user_share - share;
                    sub_vault.share_supply = sub_vault.share_supply - share;
                    share
                }
                else {
                    let user_share = linked_list::remove(&mut sub_vault.user_shares, user);
                    sub_vault.share_supply = sub_vault.share_supply - user_share;
                    user_share
                }
            }
            else {
                let user_share = linked_list::remove(&mut sub_vault.user_shares, user);
                sub_vault.share_supply = sub_vault.share_supply - user_share;
                user_share
            }
        }
        else {
            0
        }
    }

    fun vault_initialized<MANAGER, TOKEN>(vault: &Vault<MANAGER, TOKEN>): bool {
        vault.able_to_deposit && vault.able_to_withdraw
    }

    fun vault_activated<MANAGER, TOKEN>(vault: &Vault<MANAGER, TOKEN>): bool {
        !vault.able_to_deposit && !vault.able_to_withdraw
    }

    fun vault_settled<MANAGER, TOKEN>(vault: &Vault<MANAGER, TOKEN>): bool {
        !vault.able_to_deposit && vault.able_to_withdraw
    }

    // ======== Events =========

    struct UserDeposit<phantom MANAGER, phantom TOKEN> has copy, drop { user: address, sub_vault_type: vector<u8>, amount: u64 }
    
    struct UserWithdraw<phantom MANAGER, phantom TOKEN> has copy, drop { user: address, sub_vault_type: vector<u8>, share: u64, amount: u64 }

    // ======== Test =========

    #[test_only]
    struct TestManagerCap has key {
        id: sui::object::UID,
    }

    #[test_only]
    fun init_test_manager(ctx: &mut TxContext) {
        transfer::transfer(
            TestManagerCap {
                id: sui::object::new(ctx)
            },
            tx_context::sender(ctx)
        );
    }


    #[test_only]
    public fun test_get_user_share<MANAGER, TOKEN>(
        vault: &Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>,
        user: address
    ): u64 {
        *linked_list::borrow<address, u64>(
            &get_sub_vault<MANAGER, TOKEN>(
                vault, sub_vault_type
            ).user_shares,
            user
        )
    }

    #[test_only]
    public fun test_get_balance<MANAGER, TOKEN>(
        vault: &Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>,
    ): u64 {
        let balance = &get_sub_vault<MANAGER, TOKEN>(
            vault, sub_vault_type
        ).balance;
        balance::value<TOKEN>(balance)
    }

    #[test_only]
    public fun test_get_share_supply<MANAGER, TOKEN>(
        vault: &Vault<MANAGER, TOKEN>,
        sub_vault_type: vector<u8>,
    ): u64 {
        let share_supply = &get_sub_vault<MANAGER, TOKEN>(
            vault, sub_vault_type
        ).share_supply;
        *share_supply
    }

    #[test]
    public fun test_new_vault(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;
        use sui::table;

        let admin = @0xFFFF;
        let scenario = test_scenario::begin(admin);

        let vault = new_vault(test_scenario::ctx(&mut scenario));
        assert!(table::length(&vault.sub_vaults) == 3, 1);
        assert!(vault.able_to_deposit && vault.able_to_withdraw, 2);
        test_scenario::end(scenario);
        vault
    }

    #[test]
    public fun test_deposit_success(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        // use std::debug;
        use typus_dov::linked_list;

        let vault = test_new_vault();

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let scenario = test_scenario::begin(admin);
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, user1);

        let init_amount = 100;
        let add_amount = 200;
        // deposit for the first time
        deposit(&mut vault, &mut coin, init_amount, true, test_scenario::ctx(&mut scenario) );
        let sub_vault = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        assert!(balance::value(&sub_vault.balance) == init_amount, 1);
       
        // deposit for second time
        deposit(&mut vault, &mut coin, add_amount, true, test_scenario::ctx(&mut scenario) );
        let sub_vault = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        assert!(balance::value(&sub_vault.balance) == init_amount + add_amount, 2);

        let user1_share = linked_list::borrow(&sub_vault.user_shares, user1);
        assert!(*user1_share == init_amount + add_amount, 3);
        
        coin::destroy_for_testing(coin);
        test_scenario::end(scenario);
        vault
    }

    #[test]
    #[expected_failure]
    public fun test_deposit_fail_with_deposit_disabled(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
 
        let vault = test_new_vault();

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let scenario = test_scenario::begin(admin);

        init_test_manager(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let manager_cap = test_scenario::take_from_sender<TestManagerCap>(&scenario);
       
        // admin disables withdraw
        disable_deposit(&manager_cap, &mut vault);

        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));
        // try to deposit
        test_scenario::next_tx(&mut scenario, user1);
        let deposit_amount = 100;
        deposit(&mut vault, &mut coin, deposit_amount, true, test_scenario::ctx(&mut scenario) );
   
        coin::destroy_for_testing(coin);
        test_scenario::next_tx(&mut scenario, admin);
        test_scenario::return_to_sender<TestManagerCap>(&scenario, manager_cap);
        test_scenario::end(scenario);
       
        vault
    }

    #[test]
    #[expected_failure]
    public fun test_deposit_failure_with_insufficient_fund(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
   
        let vault = test_new_vault();

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let scenario = test_scenario::begin(admin);
        let balance = 1000;
        let coin = coin::mint_for_testing<SUI>(balance, test_scenario::ctx(&mut scenario));

        // try to deposit more than the balance
        let deposit_amount = balance + 1;
        test_scenario::next_tx(&mut scenario, user1);
        deposit(&mut vault, &mut coin, deposit_amount, true, test_scenario::ctx(&mut scenario) );
        
        coin::destroy_for_testing(coin);
        test_scenario::end(scenario);
        vault
    }

    #[test]
    public fun test_withdraw_success(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        // use std::debug;
        use typus_dov::linked_list;
        
        let vault = test_deposit_success();

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let scenario = test_scenario::begin(admin);
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, user1);

        let deposit_amount = 300;
        let withdraw_amount_first = 50;
       
        // withdraw for the first time
        let sub_vault_before = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        let sub_vault_before_bal = balance::value(&sub_vault_before.balance);
        withdraw(&mut vault, option::some(withdraw_amount_first), true, test_scenario::ctx(&mut scenario));
        let sub_vault = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        assert!(sub_vault_before_bal - balance::value(&sub_vault.balance) == withdraw_amount_first, 1);
       
        let user1_share = linked_list::borrow(&sub_vault.user_shares, user1);
        assert!(*user1_share == deposit_amount - withdraw_amount_first, 2);
        
        // withdraw for the second time
        let sub_vault_before = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        let sub_vault_before_bal = balance::value(&sub_vault_before.balance);
        withdraw(&mut vault, option::none(), true, test_scenario::ctx(&mut scenario));
        let sub_vault = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        assert!(sub_vault_before_bal - balance::value(&sub_vault.balance) == deposit_amount - withdraw_amount_first, 3);
        assert!(balance::value(&sub_vault.balance) == 0, 4);

        assert!(!linked_list::contains(&sub_vault.user_shares, user1), 5);
        
        coin::destroy_for_testing(coin);
        test_scenario::end(scenario);
        vault
    }

    #[test]
    public fun test_withdraw_success_with_larger_amount(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;
        use typus_dov::linked_list;

        let vault = test_deposit_success();

        let user1 = @0xBABE1;
        let scenario = test_scenario::begin(user1);

        let deposit_amount = 300;
        let withdraw_amount = deposit_amount + 1;
       
        // withdraw with amount larger than previous deposit amount
        withdraw(&mut vault, option::some(withdraw_amount), true, test_scenario::ctx(&mut scenario));
        let sub_vault = get_mut_sub_vault<TestManagerCap, sui::sui::SUI>(&mut vault, C_VAULT_ROLLING);
        assert!(balance::value(&sub_vault.balance) == 0, 1);
        assert!(!linked_list::contains(&sub_vault.user_shares, user1), 2);
        
        test_scenario::end(scenario);
        vault
    }

    #[test]
    #[expected_failure]
    public fun test_withdraw_fail(): Vault<TestManagerCap, sui::sui::SUI>  {
        use sui::test_scenario;

        let vault = test_deposit_success();

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let scenario = test_scenario::begin(admin);
        
        init_test_manager(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let manager_cap = test_scenario::take_from_sender<TestManagerCap>(&scenario);
       
        // admin disables withdraw
        disable_withdraw(&manager_cap, &mut vault);

        // try to withdraw when withdraw is disabled
        test_scenario::next_tx(&mut scenario, user1);
        withdraw(&mut vault, option::none(), true, test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, admin);
        test_scenario::return_to_sender<TestManagerCap>(&scenario, manager_cap);

        test_scenario::end(scenario);
        vault
    }
}