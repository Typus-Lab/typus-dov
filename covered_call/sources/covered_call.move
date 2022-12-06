module typus_covered_call::covered_call {
    use std::option::{Self, Option};

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::Coin;
    use sui::dynamic_field;

    use typus_dov::vault::{Self, Vault};
    use typus_dov::asset;
    use typus_covered_call::payoff::{Self, PayoffConfig};
    use typus_dov::dutch::Auction;
    use typus_oracle::oracle::{Self, Oracle};
    use sui::object::{Self, UID};

    friend typus_covered_call::settlement;

    #[test_only]
    friend typus_covered_call::test;

    // ======== Errors ========

    const E_VAULT_NOT_EXPIRED_YET: u64 = 0;

    // ======== Structs =========

    struct ManagerCap<phantom CONFIG> has key, store {
        id: UID,
    }

    struct Config has store, drop, copy {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    struct Registry<phantom MANAGER> has key {
        id: UID,
        num_of_vault: u64,
    }

    struct CoveredCallVault<phantom MANAGER, phantom TOKEN> has store {
        config: Config,
        vault: Vault<MANAGER, TOKEN>,
        auction: Option<Auction<MANAGER, TOKEN>>,
        next_index: Option<u64>,
    }

    // ======== Private Functions =========

    fun init(ctx: &mut TxContext) {
        init_(ctx);
    }

    fun init_(ctx: &mut TxContext) {
        transfer::transfer(
            ManagerCap<Config> {
                id: object::new(ctx)
            },
            tx_context::sender(ctx)
        );
        new_registry<ManagerCap<Config>>(ctx);
    }

    fun new_registry<MANAGER>(
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        // emit(RegistryCreated<MANAGER> { id: object::uid_to_inner(&id) });

        let vault = Registry<MANAGER> {
            id,
            num_of_vault: 0
        };

        transfer::share_object(vault);
    }

    // ======== Public Functions =========

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    public fun get_config<MANAGER, TOKEN, CONFIG: store>(
        registry: &mut Registry<MANAGER>,
        index: u64,
    ): &Config {
        &dynamic_field::borrow<u64, CoveredCallVault<MANAGER, TOKEN>>(&registry.id, index).config
    }

    public fun get_next_index<MANAGER, TOKEN, CONFIG: store>(
        registry: &mut Registry<MANAGER>,
        index: u64,
    ): Option<u64> {
        dynamic_field::borrow<u64, CoveredCallVault<MANAGER, TOKEN>>(&registry.id, index).next_index
    }

    public fun check_already_expired(config: &Config, ts_ms: u64) {
        assert!(ts_ms >= config.expiration_ts * 1000, E_VAULT_NOT_EXPIRED_YET);
    }

    public fun set_strike<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        registry: &mut Registry<MANAGER>,
        index: u64,
        price: u64
    ) {
        payoff::set_strike(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<MANAGER, TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            price
        );
    }

    public fun set_premium_roi<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        registry: &mut Registry<MANAGER>,
        index: u64,
        premium_roi: u64
    ) {
        payoff::set_premium_roi(
            &mut dynamic_field::borrow_mut<u64, CoveredCallVault<MANAGER, TOKEN>>(
                &mut registry.id,
                index
            )
            .config
            .payoff_config,
            premium_roi
        );
    }

    // ======== Public Friend Functions =========

    public(friend) fun get_mut_vault<MANAGER, TOKEN, CONFIG: store>(
        registry: &mut Registry<MANAGER>,
        index: u64,
    ): &mut Vault<MANAGER, TOKEN> {
        &mut dynamic_field::borrow_mut<u64, CoveredCallVault<MANAGER, TOKEN>>(&mut registry.id, index).vault
    }

    // ======== Entry Functions =========

    public(friend) entry fun new_covered_call_vault<TOKEN>(
        _manager_cap: &ManagerCap<Config>,
        registry: &mut Registry<ManagerCap<Config>>,
        expiration_ts: u64,
        asset_name: vector<u8>,
        strike_otm_pct: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext
    ) {
        let (price, price_decimal, _, _) = oracle::get_oracle<TOKEN>(
            price_oracle
        );

        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(asset_name, price, price_decimal),
            strike_otm_pct,
            option::none(),
            option::none(),
        );

        let config = Config { payoff_config, expiration_ts };
        let vault = vault::new_vault<ManagerCap<Config>, TOKEN>(ctx);

        dynamic_field::add(
            &mut registry.id,
            registry.num_of_vault,
            CoveredCallVault {
                config,
                vault,
                auction: option::none(),
                next_index: option::none(),
            }
        );
        registry.num_of_vault = registry.num_of_vault + 1;
    }

    public(friend) entry fun deposit<TOKEN>(
        registry: &mut Registry<ManagerCap<Config>>,
        index: u64,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::deposit<ManagerCap<Config>, TOKEN>(
            get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
                registry,
                index
            ),
            coin,
            amount,
            is_rolling,
            ctx
        );

    }

    public(friend) entry fun withdraw<TOKEN>(
        registry: &mut Registry<ManagerCap<Config>>,
        index: u64,
        amount: u64,
        is_rolling: bool,
        ctx: &mut TxContext
    ) {
        vault::withdraw<ManagerCap<Config>, TOKEN>(
            get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
                registry,
                index
            ),
            option::some(amount),
            is_rolling,
            ctx
        );
    }

    public(friend) entry fun subscribe<TOKEN>(
        registry: &mut Registry<ManagerCap<Config>>,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::subscribe<ManagerCap<Config>, TOKEN>(
            get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
                registry,
                index
            ),
            ctx,
        );
    }

    public(friend) entry fun unsubscribe<TOKEN>(
        registry: &mut Registry<ManagerCap<Config>>,
        index: u64,
        ctx: &mut TxContext
    ) {
        vault::unsubscribe<ManagerCap<Config>, TOKEN>(
            get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
                registry,
                index
            ),
            ctx,
        );
    }

    // ======== Events =========

    // struct RegistryCreated<phantom MANAGER, phantom CONFIG> has copy, drop { id: ID }
    // struct VaultCreated<phantom MANAGER, phantom TOKEN, CONFIG, phantom AUCTION> has copy, drop {config: CONFIG }

    // struct VaultCreated has copy, drop {
    //     asset: String,
    //     expiration_ts: u64,
    //     strike: u64,
    // }

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

}