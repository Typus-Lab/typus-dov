module typus_framework::asset {
    struct Asset has store, drop, copy {
        name: vector<u8>,
    }

    public fun new_asset(name: vector<u8>): Asset{
        Asset {
            name,
        }
    }

    public fun get_asset_name(asset: &Asset): vector<u8> {
        asset.name
    }
}