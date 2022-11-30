module typus_dov::asset {
    use std::string;

    struct Asset has store, drop {
        name: string::String,
        price: u64,
        price_decimal: u64
    }

    public fun new_asset(name: string::String, price: u64, price_decimal: u64): Asset{
        Asset {
            name: name,
            price: price,
            price_decimal: price_decimal
        }
    }

    public fun get_asset_name(asset: &Asset): string::String {
        asset.name
    }

    public fun set_asset_price(asset: &mut Asset, price: u64) {
        asset.price = price;
    }

    public fun set_asset_price_decimal(asset: &mut Asset, price_decimal: u64) {
        asset.price_decimal = price_decimal;
    }
}