module typus_dov::token {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Supply};
    use sui::coin;


    // ======== Structs =========

    struct Registry has key{
        id: UID,
        supply: Supply<USDC>
    }

    struct USDC has drop {}

    fun init(ctx: &mut TxContext){
        let registry =  Registry {
            id: object::new(ctx),
            supply: balance::create_supply(USDC{}),
        };

        transfer::share_object(registry);
    }

    public entry fun mint(registry: &mut Registry, value: u64, ctx: &mut TxContext){

        let b = balance::increase_supply(&mut registry.supply, value);

        let c = coin::from_balance(b, ctx);

        transfer::transfer(c, tx_context::sender(ctx));
    }
}