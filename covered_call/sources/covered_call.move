module typus_covered_call::covered_call {
    use std::option::{Self, Option};
    use std::string;

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::Coin;
    use sui::event::emit;
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

    // ======== Structs =========

    struct ManagerCap<phantom CONFIG> has key, store {
        id: UID,
    }

    struct Config has store, drop, copy {
        payoff_config: PayoffConfig,
        expiration_ts: u64
    }

    struct Registry<phantom MANAGER, phantom CONFIG> has key {
        id: UID,
        num_of_vault: u64,
    }

    struct CoveredCallVault<phantom MANAGER, phantom TOKEN> has store {
        config: Config,
        vault: Vault<MANAGER, TOKEN>,
        next_index: Option<u64>,
        auction: Option<Auction<MANAGER, TOKEN>>
    }

    // ======== Private Functions =========

    fun init_(ctx: &mut TxContext) {
        let manager_cap = ManagerCap<Config> {
            id: object::new(ctx)
        };
        transfer::transfer(manager_cap, tx_context::sender(ctx));
        new_registry<ManagerCap<Config>, Config>(ctx);
    }

    fun init(ctx: &mut TxContext) {
        init_(ctx);
    }

    fun new_registry<MANAGER, CONFIG>(
        ctx: &mut TxContext
    ) {
        let id = object::new(ctx);

        // emit(RegistryCreated<MANAGER, CONFIG> { id: object::uid_to_inner(&id) });

        let vault = Registry<MANAGER, CONFIG> {
            id,
            num_of_vault: 0
        };

        transfer::share_object(vault);
    }

    fun new_vault<MANAGER, TOKEN>(
        config: Config,
        vault: Vault<MANAGER, TOKEN>,
        next_index: Option<u64>,
        auction: Option<Auction<MANAGER, TOKEN>>
    ): CoveredCallVault<MANAGER, TOKEN> {
        CoveredCallVault<MANAGER, TOKEN> {
            config,
            vault,
            next_index,
            auction
        }
    }

    fun get_vault<MANAGER, TOKEN, CONFIG: store>(
        vault_registry: &mut Registry<MANAGER, CONFIG>,
        vault_index: u64,
    ): &Vault<MANAGER, TOKEN> {
        &dynamic_field::borrow<u64, CoveredCallVault<MANAGER, TOKEN>>(&vault_registry.id, vault_index).vault
    }

    // ======== Public Functions =========

    public fun get_payoff_config(config: &Config): &PayoffConfig {
        &config.payoff_config
    }

    public fun get_config<MANAGER, TOKEN, CONFIG: store>(
        vault_registry: &mut Registry<MANAGER, CONFIG>,
        vault_index: u64,
    ): &Config {
        &dynamic_field::borrow<u64, CoveredCallVault<MANAGER, TOKEN>>(&vault_registry.id, vault_index).config
    }

    public fun get_next_index<MANAGER, TOKEN, CONFIG: store>(
        vault_registry: &mut Registry<MANAGER, CONFIG>,
        vault_index: u64,
    ): Option<u64> {
        dynamic_field::borrow<u64, CoveredCallVault<MANAGER, TOKEN>>(&vault_registry.id, vault_index).next_index
    }

    public fun check_already_expired(config: &Config, unix_ms: u64) {
        assert!(unix_ms >= config.expiration_ts * 1000, E_VAULT_NOT_EXPIRED_YET);
    }

    // ======== Public Friend Functions =========

    public(friend) fun get_mut_vault<MANAGER, TOKEN, CONFIG: store>(
        vault_registry: &mut Registry<MANAGER, CONFIG>,
        vault_index: u64,
    ): &mut Vault<MANAGER, TOKEN> {
        &mut dynamic_field::borrow_mut<u64, CoveredCallVault<MANAGER, TOKEN>>(&mut vault_registry.id, vault_index).vault
    }

    public(friend) fun get_mut_config<MANAGER, TOKEN, CONFIG: store>(
        _manager_cap: &MANAGER,
        vault_registry: &mut Registry<MANAGER, CONFIG>,
        vault_index: u64,
    ): &mut Config {
        &mut dynamic_field::borrow_mut<u64, CoveredCallVault<MANAGER, TOKEN>>(&mut vault_registry.id, vault_index).config
    }

    // ======== Public Entry Functions =========

    public entry fun set_strike<MANAGER, TOKEN: store>(
        manager_cap: &MANAGER,
        vault_registry: &mut Registry<MANAGER, Config>,
        index: u64,
        price: u64
    ){
        let config = get_mut_config<MANAGER, TOKEN, Config>(
            manager_cap,
            vault_registry,
            index
        );
        payoff::set_strike(&mut config.payoff_config, price);
    }

    public entry fun set_premium_roi<MANAGER, TOKEN: store>(
        manager_cap: &MANAGER,
        vault_registry: &mut Registry<MANAGER, Config>,
        index: u64,
        premium_roi: u64
    ){
        let config = get_mut_config<MANAGER, TOKEN, Config>(
            manager_cap,
            vault_registry,
            index
        );
        payoff::set_premium_roi(&mut config.payoff_config, premium_roi);
    }

    public entry fun new_covered_call_vault<TOKEN>(
        manager_cap: &ManagerCap<Config>,
        vault_registry: &mut Registry<ManagerCap<Config>, Config>,
        expiration_ts: u64,
        asset_name: vector<u8>,
        strike_otm_pct: u64,
        price_oracle: &Oracle<TOKEN>,
        ctx: &mut TxContext
    ){
        let (price, price_decimal, _, _) = oracle::get_oracle<TOKEN>(
            price_oracle
        );

        let asset = string::utf8(asset_name);
        let payoff_config = payoff::new_payoff_config(
            asset::new_asset(asset, price, price_decimal),
            strike_otm_pct,
            option::none(),
            option::none(),
        );

        let config = Config { payoff_config, expiration_ts };
        let vault_ = vault::new_vault<ManagerCap<Config>, TOKEN>(ctx);
        let covered_call = new_vault<ManagerCap<Config>, TOKEN>(
            config,
            vault_,
            option::none(),
            option::none()
        );

        let vault_index = vault_registry.num_of_vault;

        dynamic_field::add(&mut vault_registry.id, vault_index, covered_call);

        // emit(VaultCreated{
        //     asset,
        //     expiration_ts,
        //     strike,
        // });
    }

    public entry fun deposit<TOKEN>(
        vault_registry: &mut Registry<ManagerCap<Config>, Config>,
        index: u64,
        coin: &mut Coin<TOKEN>,
        amount: u64,
        ctx: &mut TxContext
    ){
        let rolling = true;

        let mut_vault = get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
            vault_registry,
            index
        );

        vault::deposit<ManagerCap<Config>, TOKEN>(
            mut_vault,
            coin,
            amount,
            rolling,
            ctx
        );

    }

    public entry fun unsubscribe<TOKEN>(
        vault_registry: &mut Registry<ManagerCap<Config>, Config>,
        index: u64,
        ctx: &mut TxContext
    ){
        let mut_vault = get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
            vault_registry,
            index
        );
        vault::unsubscribe<ManagerCap<Config>, TOKEN>(
            mut_vault, ctx
        );
    }

    public entry fun withdraw<TOKEN: store>(
        vault_registry: &mut Registry<ManagerCap<Config>, Config>,
        index: u64,
        amount: u64,
        ctx: &mut TxContext
    ){
        let rolling = false;

        let mut_vault = get_mut_vault<ManagerCap<Config>, TOKEN, Config>(
            vault_registry,
            index
        );

        vault::withdraw<ManagerCap<Config>, TOKEN>(
            mut_vault,
            option::some(amount),
            rolling,
            ctx
        );
    }

    const E_VAULT_NOT_EXPIRED_YET: u64 = 777;

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