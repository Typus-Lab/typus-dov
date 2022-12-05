module typus_dov::dutch {
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use typus_oracle::unix_time::{Self, Time};

    const E_ZERO_SIZE: u64 = 0;
    const E_BID_NOT_EXISTS: u64 = 1;

    struct Auction<phantom T> has store {
        start_ts_ms: u64,
        end_ts_ms: u64,
        price_config: PriceConfig,
        index: u64,
        bids: Table<u64, Bid>,
        funds: Table<u64, Fund<T>>,
        ownerships: Table<address, vector<u64>>
    }

    struct PriceConfig has store {
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
    }

    struct Bid has copy, drop, store {
        price: u64,
        size: u64,
        ts_ms: u64,
    }

    struct Fund<phantom T> has store {
        coin: Coin<T>,
        owner: address,
    }

    struct Winner has store {
        owner: address,
        size: u64,
    }

    public fun new<T>(
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        ctx: &mut TxContext,
    ): Auction<T> {
        Auction {
            start_ts_ms,
            end_ts_ms,
            price_config: PriceConfig {
                decay_speed,
                initial_price,
                final_price,
            },
            index: 0,
            bids: table::new(ctx),
            funds: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    public fun new_bid<T>(
        auction: &mut Auction<T>,
        size: u64,
        coin: &mut Coin<T>,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        assert!(size != 0, E_ZERO_SIZE);
        let index = auction.index;
        let owner = tx_context::sender(ctx);
        let price = get_decayed_price(auction, time);
        table::add(
            &mut auction.bids,
            index,
            Bid {
                price,
                size,
                ts_ms: unix_time::get_unix_ms(time),
            }
        );
        table::add(
            &mut auction.funds,
            index,
            Fund {
                coin: coin::split(coin, price * size, ctx),
                owner,
            }
        );
        auction.index = index + 1;
        if (table::contains(&auction.ownerships, owner)) {
            let ownership = table::borrow_mut(&mut auction.ownerships, owner);
            vector::push_back(ownership, index);
        }
        else {
            let ownership = vector::empty();
            vector::push_back(&mut ownership, index);
            table::add(
                &mut auction.ownerships,
                owner,
                ownership,
            )
        }
    }

    public fun remove_bid<T>(
        auction: &mut Auction<T>,
        owner: address,
        bid_index: u64,
    ) {
        let ownership = table::borrow_mut(&mut auction.ownerships, owner);
        let (bid_exist, index) = vector::index_of(ownership, &bid_index);
        assert!(bid_exist, E_BID_NOT_EXISTS);
        vector::swap_remove(ownership, index);
        table::remove(&mut auction.bids, bid_index);
        let Fund {
            coin,
            owner,
        } = table::remove(&mut auction.funds, bid_index);
        transfer::transfer(coin, owner);
    }

    public fun get_bid_by_index<T>(auction: &Auction<T>, index: u64): &Bid {
        table::borrow(&auction.bids, index)
    }

    public fun get_bids_index_by_address<T>(auction: &Auction<T>, owner: address): &vector<u64> {
        table::borrow(&auction.ownerships, owner)
    }

    public fun get_decayed_price<T>(auction: &Auction<T>, time: &Time): u64 {
        decay_formula(
            auction.price_config.initial_price,
            auction.price_config.final_price,
            auction.price_config.decay_speed,
            auction.start_ts_ms,
            auction.end_ts_ms,
            unix_time::get_unix_ms(time) / 1000,
        )
    }

    /// decayed_price = 
    ///     initial_price -
    ///         (initial_price - final_price) *
    ///             (1 - remaining_time / auction_duration) ^ decay_speed
    fun decay_formula(
        initial_price: u64,
        final_price: u64,
        decay_speed: u64,
        start_ts_ms: u64,
        end_ts_ms: u64,
        current_ts_ms: u64,
    ): u64 {
        let price_diff = initial_price - final_price;
        // 1 - remaining_time / auction_duration => 1 - (end - current) / (end - start) => (current - start) / (end - start)
        let numerator = current_ts_ms - start_ts_ms;
        let denominator = end_ts_ms - start_ts_ms;

        while (decay_speed > 0) {
            price_diff  = price_diff * numerator / denominator;
            decay_speed = decay_speed - 1;
        };
        
        initial_price - price_diff
    }

    public fun delivery<T>(auction: &mut Auction<T>, size: u64, balance: &mut Balance<T>): vector<Winner> {
        // calculate decayed price
        let delivery_price = auction.price_config.initial_price;
        let index = 0;
        let sum = 0;
        while (sum < size && index < auction.index) {
            if (table::contains(&auction.bids, index)) {
                let bid = table::borrow(&auction.bids, index);
                sum = sum + bid.size;
                delivery_price = bid.price;
            };
            index = index + 1;
        };

        // delivery
        let winners = vector::empty();
        let index = 0;
        while (!table::is_empty(&auction.bids)) {
            if (table::contains(&auction.bids, index)) {
                // get market maker bid and fund
                let bid = table::remove(&mut auction.bids, index);
                let Fund {
                    coin,
                    owner
                } = table::remove(&mut auction.funds, index);
                if (size > 0) {
                    // filled
                    if (bid.size <= size) {
                        balance::join(balance, balance::split(coin::balance_mut(&mut coin), delivery_price * bid.size));
                        size = size - bid.size;
                        vector::push_back(
                            &mut winners,
                            Winner {
                                owner,
                                size: bid.size,
                            },
                        );
                    }
                    // partially filled
                    else {
                        balance::join(balance, balance::split(coin::balance_mut(&mut coin), delivery_price * size));
                        vector::push_back(
                            &mut winners,
                            Winner {
                                owner,
                                size,
                            },
                        );
                        size = 0;
                    };

                };
                if (coin::value(&coin) != 0) {
                    transfer::transfer(coin, owner);
                }
                else {
                    coin::destroy_zero(coin);
                };
            };
            index = index + 1;
        };

        winners
    }

    #[test]
    fun test_decay_formula() {
        use std::debug;

        let initial_price = 5000000;
        let final_price = 3000000;
        let decay_speed = 5;
        let start_ts_ms = 1669680000;
        let end_ts_ms = 1669708800;
        let current_ts_ms = 1669694400;

        let price = decay_formula(
            initial_price,
            final_price,
            decay_speed,
            start_ts_ms,
            end_ts_ms,
            current_ts_ms,
        );
        debug::print(&price);
    }
}