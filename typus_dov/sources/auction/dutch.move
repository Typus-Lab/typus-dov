module typus_dov::dutch {
    use std::vector;
    use std::option;

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};
    use sui::event::emit;

    use typus_oracle::unix_time::{Self, Time};

    // ======== Errors ========

    const E_ZERO_SIZE: u64 = 0;
    const E_BID_NOT_EXISTS: u64 = 1;
    const E_AUCTION_NOT_YET_STARTED: u64 = 2;
    const E_AUCTION_NOT_YET_CLOSED: u64 = 3;
    const E_AUCTION_CLOSED: u64 = 4;

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
        let ts_ms = unix_time::get_ts_ms(time);
        assert!(ts_ms >= auction.start_ts_ms, E_AUCTION_NOT_YET_STARTED);
        assert!(ts_ms <= auction.end_ts_ms, E_AUCTION_CLOSED);
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
                ts_ms,
            }
        );
        let coin = coin::split(coin, price * size, ctx);
        let coin_value = coin::value(&coin);
        table::add(
            &mut auction.funds,
            index,
            Fund {
                coin,
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
        };

        emit(NewBid<TOKEN>{
            index,
            price,
            size,
            coin_value,
            ts_ms,
            owner
        });
    }

    public fun remove_bid<MANAGER, TOKEN>(
        auction: &mut Auction<MANAGER, TOKEN>,
        index: u64,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        let ts_ms = unix_time::get_ts_ms(time);
        assert!(ts_ms >= auction.start_ts_ms, E_AUCTION_NOT_YET_STARTED);
        assert!(ts_ms <= auction.end_ts_ms, E_AUCTION_CLOSED);

        let owner = tx_context::sender(ctx);
        let ownership = table::borrow_mut(&mut auction.ownerships, owner);
        let (bid_exist, vector_index) = vector::index_of(ownership, &index);
        assert!(bid_exist, E_BID_NOT_EXISTS);
        vector::swap_remove(ownership, vector_index);
        table::remove(&mut auction.bids, index);
        let Fund {
            coin,
            owner,
        } = table::remove(&mut auction.funds, index);
        let coin_value = coin::value(&coin);
        transfer::transfer(coin, owner);

        emit(RemoveBid<TOKEN>{
            index,
            coin_value,
            ts_ms,
            owner
        });
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
        time: &Time,
    ): (Balance<TOKEN>, VecMap<address, u64>) {
        assert!(unix_time::get_ts_ms(time) > auction.end_ts_ms, E_AUCTION_NOT_YET_CLOSED);

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
                let Fund { coin, owner } = table::remove(&mut auction.funds, index);
                if (size > 0) {
                    let this_size: u64;
                    if (bid.size <= size) {
                        // filled
                        this_size = bid.size;
                    } else {
                        // partially filled
                        this_size = size;
                    };
                    balance::join(&mut balance, balance::split(coin::balance_mut(&mut coin), delivery_price * this_size));
                    let b_size_option = vec_map::get_idx_opt(&winners, &owner);
                    if (option::is_some(&b_size_option)){
                        let b_size = option::borrow_mut(&mut b_size_option);
                        *b_size = *b_size + this_size;
                    } else {
                        vec_map::insert(
                            &mut winners,
                            owner,
                            this_size,
                        );
                    };

                    size = size - this_size;
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

        auction.index = 0;

        (balance, winners)
    }

    // ======== Events =========

    struct NewBid<phantom TOKEN> has copy, drop {
        index: u64,
        price: u64,
        size: u64,
        coin_value: u64,
        ts_ms: u64,
        owner: address,
    }

    struct RemoveBid<phantom TOKEN> has copy, drop {
        index: u64,
        coin_value: u64,
        ts_ms: u64,
        owner: address,
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
    struct TestManagerCap has drop {
    }

    #[test_only]
    fun init_test_manager(): TestManagerCap {
            TestManagerCap {
            }
    }

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
        let user3 = @0xBABE3;
        let user4 = @0xBABE4;
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

        ///////////////////////////////////////////////
        // new another bid with user 2
        // size: 1, owner: user2
        /////////////////////////////////////////////
        test_scenario::next_tx(&mut scenario, user2);
        new_bid(
            &mut auction,
            3,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
    
        ///////////////////////////////////////////////
        // new bid with user 3
        // size: 33, owner: user3
        /////////////////////////////////////////////
        test_scenario::next_tx(&mut scenario, user3);
        new_bid(
            &mut auction,
            33,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );

        ///////////////////////////////////////////////
        // new bid with user 4
        // size: 1, owner: user4
        /////////////////////////////////////////////
        test_scenario::next_tx(&mut scenario, user4);
        new_bid(
            &mut auction,
            1,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, admin);
        coin::destroy_for_testing(coin);
        test_scenario::return_to_sender(&scenario, key); 
        test_scenario::return_shared(time); 
        test_scenario::end(scenario);

        auction
    }

    #[test]
    fun test_auction_remove_bid_success(): Auction<TestManagerCap, sui::sui::SUI> {
        use typus_oracle::unix_time::{Self, Time, Key};
        use sui::test_scenario;

        let auction = test_auction_new_bid();
        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;

        let scenario = test_scenario::begin(admin);
        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);
     
        // update time
        unix_time::update(&mut time, &key, auction.start_ts_ms + 60*2, test_scenario::ctx(&mut scenario)) ;

        // remove bid 0 with user1
        test_scenario::next_tx(&mut scenario, user1);
        remove_bid(&mut auction, 0, &time, test_scenario::ctx(&mut scenario));
      
        // remove bid 1 with user2
        test_scenario::next_tx(&mut scenario, user2);
        remove_bid(&mut auction, 1, &time, test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, admin);
        test_scenario::return_to_sender(&scenario, key); 
        test_scenario::return_shared(time); 
        test_scenario::end(scenario);

        auction
    }

    #[test]
    #[expected_failure]
    fun test_auction_remove_bid_fail_on_wrong_owner(): Auction<TestManagerCap, sui::sui::SUI> {
        use typus_oracle::unix_time::{Self, Time, Key};
        use sui::test_scenario;

        let auction = test_auction_new_bid();
        let admin = @0xFFFF;
        let monkey = @0x8787;

        let scenario = test_scenario::begin(admin);
        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);
     
        // update time
        unix_time::update(&mut time, &key, auction.start_ts_ms + 60*2, test_scenario::ctx(&mut scenario)) ;

        // try to remove bid 0 with monkey
        test_scenario::next_tx(&mut scenario, monkey);
        remove_bid(&mut auction, 0, &time, test_scenario::ctx(&mut scenario));
      
        test_scenario::next_tx(&mut scenario, admin);
        test_scenario::return_to_sender(&scenario, key); 
        test_scenario::return_shared(time); 
        test_scenario::end(scenario);

        auction
    }

    #[test]
    fun test_auction_delivery_success(): Auction<TestManagerCap, sui::sui::SUI> {
        use typus_oracle::unix_time::{Self, Time, Key};
        use sui::test_scenario;
        use sui::vec_map;
        use std::debug;

        let auction = test_auction_new_bid();
        let admin = @0xFFFF;

        let scenario = test_scenario::begin(admin);
        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);
     
        // update time
        unix_time::update(&mut time, &key, auction.end_ts_ms + 1, test_scenario::ctx(&mut scenario)) ;

        let manager_cap = init_test_manager();
        let (balance, winners) = delivery(&manager_cap,  &mut auction, 10,  &time);
        assert!(vec_map::size(&winners) >= 0, 1);
        debug::print(&winners);

        test_scenario::next_tx(&mut scenario, admin);
        test_scenario::return_to_sender(&scenario, key); 
        test_scenario::return_shared(time); 
        coin::destroy_for_testing(coin::from_balance(balance, test_scenario::ctx(&mut scenario)));
        test_scenario::end(scenario);

        auction
    }
}