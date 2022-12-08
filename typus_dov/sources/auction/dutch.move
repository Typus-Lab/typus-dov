module typus_dov::dutch {
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    use typus_oracle::unix_time::{Self, Time};

    // ======== Errors ========

    const E_ZERO_SIZE: u64 = 0;
    const E_BID_NOT_EXISTS: u64 = 1;
    const E_AUCTION_NOT_YET_STARTED: u64 = 2;
    const E_AUCTION_CLOSED: u64 = 3;

    // ======== Structs ========

    struct Auction<phantom MANAGER, phantom TOKEN> has store {
        start_ts_ms: u64,
        end_ts_ms: u64,
        price_config: PriceConfig,
        index: u64,
        bids: Table<u64, Bid>,
        funds: Table<u64, Fund<TOKEN>>,
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

    struct Fund<phantom TOKEN> has store {
        coin: Coin<TOKEN>,
        owner: address,
    }

    // ======== Public Functions ========

    public fun new<MANAGER, TOKEN>(
        start_ts_ms: u64,
        end_ts_ms: u64,
        decay_speed: u64,
        initial_price: u64,
        final_price: u64,
        ctx: &mut TxContext,
    ): Auction<MANAGER, TOKEN> {
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

    public fun new_bid<MANAGER, TOKEN>(
        auction: &mut Auction<MANAGER, TOKEN>,
        size: u64,
        coin: &mut Coin<TOKEN>,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        assert!(unix_time::get_ts_ms(time) >= auction.start_ts_ms, E_AUCTION_NOT_YET_STARTED);
        assert!(unix_time::get_ts_ms(time) <= auction.end_ts_ms, E_AUCTION_CLOSED);
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
                ts_ms: unix_time::get_ts_ms(time),
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

    public fun remove_bid<MANAGER, TOKEN>(
        auction: &mut Auction<MANAGER, TOKEN>,
        bid_index: u64,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        assert!(unix_time::get_ts_ms(time) >= auction.start_ts_ms, E_AUCTION_NOT_YET_STARTED);
        assert!(unix_time::get_ts_ms(time) <= auction.end_ts_ms, E_AUCTION_CLOSED);

        let owner = tx_context::sender(ctx);
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

    public fun get_decayed_price<MANAGER, TOKEN>(
        auction: &Auction<MANAGER, TOKEN>,
        time: &Time
    ): u64 {
        decay_formula(
            auction.price_config.initial_price,
            auction.price_config.final_price,
            auction.price_config.decay_speed,
            auction.start_ts_ms,
            auction.end_ts_ms,
            unix_time::get_ts_ms(time),
        )
    }

    public fun delivery<MANAGER, TOKEN>(
        _manager_cap: &MANAGER,
        auction: &mut Auction<MANAGER, TOKEN>,
        size: u64,
    ): (Balance<TOKEN>, VecMap<address, u64>) {
        let balance = balance::zero();
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
        let winners = vec_map::empty();
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
                        balance::join(&mut balance, balance::split(coin::balance_mut(&mut coin), delivery_price * bid.size));
                        size = size - bid.size;
                        vec_map::insert(
                            &mut winners,
                            owner,
                            bid.size,
                        );
                    }
                    // partially filled
                    else {
                        balance::join(&mut balance, balance::split(coin::balance_mut(&mut coin), delivery_price * size));
                        vec_map::insert(
                            &mut winners,
                            owner,
                            size,
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

        (balance, winners)
    }

    // ======== Private Functions ========

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

    #[test_only]
    struct TestManagerCap { }

    #[test]
    fun test_decay_formula() {
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
        assert!(price == 4937500, 1);
    }

    #[test]
    fun test_auction_new_auction(): Auction<TestManagerCap, sui::sui::SUI> {
        use sui::test_scenario;

        let admin = @0xFFFF;
        let admin_scenario = test_scenario::begin(admin);

        ////////////////////////////////////////////////////////////////////////////////////
        //   New Dutch Auction
        ////////////////////////////////////////////////////////////////////////////////////
        let start_ts_ms = 1669338020;
        let end_ts_ms = 1669338020 + 60*60*24*2;
        let decay_speed = 10;
        let initial_price = 10000;
        let final_price = 100;
        
        let auction = new(start_ts_ms, end_ts_ms, decay_speed, initial_price, final_price, test_scenario::ctx(&mut admin_scenario));
        assert!(auction.start_ts_ms == start_ts_ms, 1);
        assert!(auction.index == 0, 1);

        test_scenario::end(admin_scenario);
        auction
    }

    #[test]
    fun test_auction_new_bid(): Auction<TestManagerCap, sui::sui::SUI> {
        use sui::test_scenario;
        use typus_oracle::unix_time::{Self, Time, Key};
        use sui::coin;
        use sui::sui::SUI;
        use sui::table;
        // use std::debug;

        let auction = test_auction_new_auction();

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        let scenario = test_scenario::begin(admin);

        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));

        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);
     
        // update time
        unix_time::update(&mut time, &key, auction.start_ts_ms + 60, test_scenario::ctx(&mut scenario)) ;

        ///////////////////////////////////////////////
        // new bid with user 1 
        // size: 1, owner: user1
        /////////////////////////////////////////////
        test_scenario::next_tx(&mut scenario, user1);
        new_bid(
            &mut auction,
            1,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
        let bid = table::borrow(&auction.bids, 0);
        assert!(auction.index == 1, 1);
        assert!(bid.size == 1, 1);
        assert!(bid.price == 10000, 1);
        // debug::print(&bid.price);

        // update time
        unix_time::update(&mut time, &key, auction.start_ts_ms + 60*60*10, test_scenario::ctx(&mut scenario)) ;

        ///////////////////////////////////////////////
        // new bid with user 2
        // size: 2, owner: user2
        /////////////////////////////////////////////
        test_scenario::next_tx(&mut scenario, user2);
        new_bid(
            &mut auction,
            2,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
        let bid = table::borrow(&auction.bids, 1);
        assert!(auction.index == 2, 1);
        assert!(bid.size == 2, 1);
        assert!(bid.price == 10000, 1);
        // debug::print(&bid.price);

        test_scenario::next_tx(&mut scenario, admin);
        coin::destroy_for_testing(coin);
        test_scenario::return_to_sender(&scenario, key); 
        test_scenario::return_shared(time); 
        test_scenario::end(scenario);

        auction
    }

    // #[test]
    // fun test_auction_remove_bid_success(): Auction<TestManagerCap, sui::sui::SUI> {
    //     use typus_oracle::unix_time::{Self, Time, Key};

    //     let auction = test_auction_new_bid();
    //     let user1 = @0xBABE1;
    //     let user2 = @0xBABE2;
    //     remove_bid(&mut auction, user1, 0);
    //     // remove_bid(&mut auction, user1, 2);
    //     remove_bid(&mut auction, user2, 1);
    //     // remove_bid(&mut auction, user2, 3);

    //     auction
    // }

    // #[test]
    // #[expected_failure]
    // fun test_auction_remove_bid_fail_on_wrong_owner(): Auction<TestManagerCap, sui::sui::SUI> {
    //     use typus_oracle::unix_time::{Self, Time, Key};

    //     let auction = test_auction_new_bid();
    //     let monkey = @0x8787;
    //     remove_bid(&mut auction, monkey, 0);

    //     auction
    // }
}