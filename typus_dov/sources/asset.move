module typus_dov::asset{
    // use sui::tx_context::TxContext;
    use std::string;
    // use sui::transfer;
    // use sui::object::{Self, UID};

    // ======== Structs =========
    struct Asset has key, store, drop {
        // id: UID,
        name: string::String,
        price: u64,
        price_decimal: u64
    }

    public fun new_asset(name: &string::String, price: u64, price_decimal: u64): Asset{
        // , ctx: &mut TxContext) {
        Asset {
            // id: object::new(ctx),
            name: *name,
            price: price,
            price_decimal: price_decimal
        }
        // transfer::share_object(asset);
    }

    public fun get_asset_name(asset: &Asset): string::String {
        asset.name
    }

    public fun set_asset_price(asset: &mut Asset, price: u64) {
        asset.price = price;
    }
}