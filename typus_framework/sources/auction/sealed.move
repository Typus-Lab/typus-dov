// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_framework::sealed {
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    use sui::bcs;
    use std::hash;
    use typus_oracle::unix_time::{Self, Time};
    use sui::event::emit;
    use sui::vec_map::{Self, VecMap};

    const E_ZERO_PRICE: u64 = 0;
    const E_ZERO_SIZE: u64 = 1;
    const E_BID_NOT_EXISTS: u64 = 2;
    const E_AUCTION_CLOSED: u64 = 3;
    const E_AUCTION_NOT_CLOSED: u64 = 4;
    const E_REVEAL_CLOSED: u64 = 5;
    const E_REVEAL_NOT_CLOSED: u64 = 6;
    const E_OWNER_MISMATCH: u64 = 7;
    const E_BID_COMMITMENT_MISMATCH: u64 = 8;
    const E_BID_NOT_REVEALED: u64 = 9;

    struct Auction<phantom Token> has key {
        id: UID,
        /// minimum deposit for participating the auction
        min_deposit: u64,
        /// bidders can submit bids only before bid_closing_time
        bid_closing_time: u64,
        /// bidders can reveal their own bids info only between bid_closing_time and reveal_closing_time
        reveal_closing_time: u64,
        /// next bid index
        index: u64,
        /// all submitted bids
        bids: Table<u64, Bid>,
        /// user's funds for trade
        funds: Table<u64, Fund<Token>>,
        /// bidders info
        ownerships: Table<address, vector<u64>>

    }

    struct Bid has copy, drop, store {
        index: u64,
        /// encrypted (price+size+blinding_factor) with zk proof function
        /// ==> or just using a hash function? or RSA function?
        /// hash of the bid
        bid_hash: vector<u8>,
        /// encrypted bid info
        encrypted_bid: vector<u8>,
        /// real price after revealing
        price: Option<u64>,
        /// real size after revealing
        size: Option<u64>,
        /// blinding_factor after revealing
        blinding_factor: Option<u64>,
        owner: address,
    }

    struct Fund<phantom Token> has store {
        coin: Coin<Token>,
        owner: address,
    }

    /// create a new Sealed-Bid Auction
    public fun new<Token>(
        min_deposit: u64,
        bid_closing_time: u64,
        reveal_closing_time: u64,
        ctx: &mut TxContext
    ): Auction<Token> {
        Auction {
            id: object::new(ctx),
            min_deposit,
            bid_closing_time,
            reveal_closing_time,
            index: 0,
            bids: table::new(ctx),
            funds: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    /// submit a bid for auction - for bidders to call
    public fun new_bid<Token>(
        auction: &mut Auction<Token>,
        bid_hash: vector<u8>,
        encrypted_bid: vector<u8>,
        coin: &mut Coin<Token>,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        let current_timestamp = unix_time::get_ts_ms(time);
        assert!(current_timestamp < auction.bid_closing_time, E_AUCTION_CLOSED);
        let index = auction.index;
        let owner = tx_context::sender(ctx);
        table::add(
            &mut auction.bids,
            index,
            Bid {
                index,
                bid_hash,
                encrypted_bid,
                price: option::none(),
                size: option::none(),
                blinding_factor: option::none(),
                owner,
            }
        );

        // transfer deposit
        table::add(
            &mut auction.funds,
            index,
            Fund {
                coin: coin::split(coin, auction.min_deposit, ctx),
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

        emit(
            SealedBidCreated{
                bid_index: index,
                owner,
                deposit: auction.min_deposit,
                timestamp: current_timestamp
            }
        )
    }

    /// reveal a bid
    public fun reveal_bid<Token>(
        auction: &mut Auction<Token>,
        bid_index: u64,
        price: u64,
        size: u64,
        blinding_factor: u64,
        coin: &mut Coin<Token>,
        time: &Time,
        ctx: &mut TxContext,
    ) {
        let current_timestamp = unix_time::get_ts_ms(time);
        assert!(current_timestamp >= auction.bid_closing_time, E_AUCTION_NOT_CLOSED);
        assert!(current_timestamp < auction.reveal_closing_time, E_REVEAL_CLOSED);
        assert!(bid_index < auction.index, E_BID_NOT_EXISTS);
        let bid = table::borrow_mut(&mut auction.bids, bid_index);
        let owner = tx_context::sender(ctx);
        assert!(bid.owner == owner, E_OWNER_MISMATCH);

        // transfer quote coins
        let transfer_amount = 0u64;
        if (price * size > auction.min_deposit) {
            transfer_amount = price * size - auction.min_deposit
        };
        let user_fund = table::borrow_mut(&mut auction.funds, bid_index);

        // transfer quote coins for the trade
        coin::join(&mut user_fund.coin, coin::split(coin, transfer_amount, ctx));

        assert!(verify_bid_hash(&bid.bid_hash, price, size, blinding_factor), E_BID_COMMITMENT_MISMATCH);
        assert!(price != 0, E_ZERO_PRICE);
        assert!(size != 0, E_ZERO_SIZE);

        bid.price = option::some(price);
        bid.size = option::some(size);
        bid.blinding_factor = option::some(blinding_factor);

        emit(
            SealedBidRevealed{
                bid_index,
                owner,
                price,
                size,
                blinding_factor,
                coin_transferred: transfer_amount,
                timestamp: current_timestamp,
            }
        )
    }

    public fun serialize_bid_info(
        price: u64,
        size: u64,
        blinding_factor: u64,
    ): vector<u8> {
        let serialized_bid_info = vector::empty();
        let price_vec = bcs::to_bytes(&price);
        let size_vec =  bcs::to_bytes(&size);
        let blinding_factor_vec =  bcs::to_bytes(&blinding_factor);
        vector::append(&mut serialized_bid_info, price_vec);
        vector::append(&mut serialized_bid_info, size_vec);
        vector::append(&mut serialized_bid_info, blinding_factor_vec);

        // vector::destroy_empty(contents);
        // compare::cmp_bcs_bytes(&hash_to_verify, hash) == 0

        serialized_bid_info
    }

    fun verify_bid_hash(
        hash: &vector<u8>,
        price: u64,
        size: u64,
        blinding_factor: u64,
    ): bool {
        // serialize bid info
        let serialize_bid_info = serialize_bid_info(price, size, blinding_factor);
        // compare with previous hash
        let hash_to_verify = hash::sha3_256(serialize_bid_info);
        hash_to_verify == *hash
    }

    public fun remove_bid<Token>(
        auction: &mut Auction<Token>,
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
        let coin_returned = coin::value(&coin);
        transfer::transfer(coin, owner);

        emit(
            SealedBidRemoved{
                bid_index,
                owner,
                coin_returned: coin_returned,
            }
        )
    }

    public fun get_bid_by_index<Token>(auction: &Auction<Token>, index: u64): &Bid {
        table::borrow(&auction.bids, index)
    }

    public fun get_bids_index_by_address<Token>(auction: &Auction<Token>, owner: address): &vector<u64> {
        table::borrow(&auction.ownerships, owner)
    }

    public fun delivery<MANAGER, Token>(
        _manager_cap: &MANAGER,
        auction: &mut Auction<Token>,
        price: u64,
        size: u64,
        time: &Time,
    ): (Balance<Token>, VecMap<address, u64>) {
        let current_timestamp = unix_time::get_ts_ms(time);
        assert!( current_timestamp >= auction.reveal_closing_time, E_REVEAL_NOT_CLOSED);
        let balance = balance::zero();
        let winners = vec_map::empty();

        // find valid bids and unvealed bids
        let bids = vector::empty();
        let unrevealed_bids = vector::empty();
        let index = auction.index;

        while (index > 0) {
            if (table::contains(&auction.bids, index - 1)) {
                let bid = table::borrow(&mut auction.bids, index - 1);
                if (option::is_some(&bid.price) && option::is_some(&bid.size) && option::is_some(&bid.blinding_factor)) {
                    vector::push_back(&mut bids, *bid);
                } else {
                    vector::push_back(&mut unrevealed_bids, *bid);
                };
                index = index - 1;
            }
        };

        // sort the bids
        selection_sort<Token>(&mut bids);

        // matching
        while (!vector::is_empty(&bids)) {
            // get market maker bid and fund
            let bid = vector::pop_back(&mut bids);
            let Fund {
                coin,
                owner
            } = table::remove(&mut auction.funds, bid.index);
            let bid_price= *option::borrow<u64>(&bid.price);
            let bid_size= *option::borrow<u64>(&bid.size);
            if (bid_price >= price && size > 0) {
                let this_size: u64;
                if (bid_size <= size) {
                    // filled
                    this_size = bid_size;
                } else {
                    // partially filled
                    this_size = size;
                };
                size = size - this_size;

                balance::join(&mut balance, balance::split(coin::balance_mut(&mut coin), bid_price * this_size));
                let coin_returned = coin::value(&coin);
                if (coin_returned != 0) {
                    transfer::transfer(coin, owner);
                }
                else {
                    coin::destroy_zero(coin);
                };

                emit(
                    SealedBidDelivered {
                        bid_index: bid.index,
                        owner,
                        price: bid_price,
                        delivered_size: this_size,
                        coin_returned,
                    }
                );

                if (vec_map::contains(&winners, &owner)){
                    let b_size = vec_map::get_mut(&mut winners, &owner);
                    *b_size = *b_size + this_size;
                } else {
                    vec_map::insert(
                        &mut winners,
                        owner,
                        this_size,
                    );
                };
            }
            else {
                let balance = coin::value(&coin);
                transfer::transfer(coin, owner);
                emit(
                    SealedBidIgnored {
                        bid_index: bid.index,
                        owner,
                        price: bid_price,
                        delivered_size: 0,
                        coin_returned: balance,
                    }
                )
            };
        };

        // punish bidders with unrevealed bid
        while (!vector::is_empty(&unrevealed_bids)) {
            let bid = vector::pop_back(&mut unrevealed_bids);
            let Fund {
                coin,
                owner,
            } = table::remove(&mut auction.funds, bid.index);
            let forfeited_amount = coin::value(&coin);
            balance::join(&mut balance, coin::into_balance(coin));
            emit(
                DepositForfeited {
                    bid_index: bid.index,
                    owner,
                    forfeited_amount,
                    timestamp: current_timestamp,
                }
            )
        };

        (balance, winners)
    }

    ////////////////////////////////////////////
    /// Events
    ///////////////////////////////////////////

    struct SealedBidCreated has copy, drop {
        bid_index: u64,
        owner: address,
        deposit: u64,
        timestamp: u64
    }

    struct SealedBidRemoved has copy, drop {
        bid_index: u64,
        owner: address,
        coin_returned: u64,
    }

    struct SealedBidRevealed has copy, drop {
        bid_index: u64,
        owner: address,
        price: u64,
        size: u64,
        blinding_factor: u64,
        coin_transferred: u64,
        timestamp: u64,
    }

    struct SealedBidDelivered has copy, drop {
        bid_index: u64,
        owner: address,
        price: u64,
        delivered_size: u64,
        coin_returned: u64,
    }

    struct SealedBidIgnored has copy, drop {
        bid_index: u64,
        owner: address,
        price: u64,
        delivered_size: u64,
        coin_returned: u64,
    }

    struct DepositForfeited has copy, drop {
        bid_index: u64,
        owner: address,
        forfeited_amount: u64,
        timestamp: u64,
    }

    fun selection_sort<Token>(bids: &mut vector<Bid>) {
        let length = vector::length(bids);
        let i = 0;
        while (i < length) {
            let min_price = option::borrow<u64>(&(vector::borrow(bids, i).price));
            let min_index = vector::borrow(bids, i).index;
            let min_at = i;
            let j = i + 1;
            while (j < length) {
                let price = option::borrow<u64>(&(vector::borrow(bids, j).price));
                let index = vector::borrow(bids, j).index;
                if(*price < *min_price || (*price == *min_price && index > min_index)) {
                    min_price = price;
                    min_index = index;
                    min_at = j;
                };
                j = j + 1;
            };
            vector::swap(bids, i, min_at);
            i = i + 1;
        }
    }

    ////////////////////////////////////////////
    // Tests
    ///////////////////////////////////////////

    #[test_only]
    struct TestManagerCap has drop {
    }

    #[test_only]
    fun init_test_manager(): TestManagerCap {
            TestManagerCap {
            }
    }

    #[test]
    fun test_auction_new_bid(): Auction<sui::sui::SUI> {
        // use std::vector;
        use sui::coin;
        use sui::sui::SUI;
        // use sui::table;
        use sui::test_scenario;
        use typus_oracle::unix_time::{Self, Time, Key};
        use std::option;

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        let user3 = @0xBABE3;
        let scenario = test_scenario::begin(admin);

        ////////////////////////////////////////////////////////////////////////////////////
        //   New Sealed Bid Auction
        ////////////////////////////////////////////////////////////////////////////////////
        let bid_closing_time =  1669338020;
        let reveal_closing_time = bid_closing_time + 60*60*24;
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));
        let auction = new(20, bid_closing_time, reveal_closing_time, test_scenario::ctx(&mut scenario));

        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        test_scenario::next_tx(&mut scenario, admin);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);

        ////////////////////////////////////////////////////////////////////////////////////
        //   New Bids
        ////////////////////////////////////////////////////////////////////////////////////

        // update time
        unix_time::update(&mut time, &key, bid_closing_time - 60*60*12, test_scenario::ctx(&mut scenario)) ;
        // new bid 1 with user 1
        test_scenario::next_tx(&mut scenario, user1);
        let serialize_bid_info = serialize_bid_info(12, 1, 11111111);
        let bid_hash = hash::sha3_256(serialize_bid_info);
        // the encryption should be done in sdk
        let encrypted_bid = b"encrypted - i am user1, my sealed bid is (x,y) with blinding_factor z";
        new_bid(
            &mut auction,
            bid_hash,
            encrypted_bid,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
        let bid = table::borrow(&auction.bids, 0);
        assert!(bid.index == 0, 1);
        assert!(auction.index == 1, 1);

        // new bid 2 with user 2
        test_scenario::next_tx(&mut scenario, user2);
        let serialize_bid_info = serialize_bid_info(12, 3, 22222222);
        let bid_hash = hash::sha3_256(serialize_bid_info);
        // the encryption should be done in sdk
        let encrypted_bid = b"encrypted - i am user2, my sealed bid is (x,y) with blinding_factor z";
        new_bid(
            &mut auction,
            bid_hash,
            encrypted_bid,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
        let bid = table::borrow(&auction.bids, 1);
        assert!(bid.index == 1, 1);
        assert!(auction.index == 2, 1);

        // new bid 3 with user 2
        test_scenario::next_tx(&mut scenario, user2);
        let serialize_bid_info = serialize_bid_info(11, 8, 22222222);
        let bid_hash = hash::sha3_256(serialize_bid_info);
        // the encryption should be done in sdk
        let encrypted_bid = b"encrypted - i am user2, my sealed bid is (x,y) with blinding_factor z";
        new_bid(
            &mut auction,
            bid_hash,
            encrypted_bid,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
        let bid = table::borrow(&auction.bids, 2);
        assert!(bid.index == 2, 1);
        assert!(auction.index == 3, 1);

        // new bid 4 with user 3
        test_scenario::next_tx(&mut scenario, user3);
        let serialize_bid_info = serialize_bid_info(18, 6, 33333333);
        let bid_hash = hash::sha3_256(serialize_bid_info);
        // the encryption should be done in sdk
        let encrypted_bid = b"encrypted - i am user3, my sealed bid is (x,y) with blinding_factor z";
        new_bid(
            &mut auction,
            bid_hash,
            encrypted_bid,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );
        let bid = table::borrow(&auction.bids, 3);
        assert!(bid.index == 3, 1);
        assert!(auction.index == 4, 1);

        ////////////////////////////////////////////////////////////////////////////////////
        //     Reveal Bids
        ////////////////////////////////////////////////////////////////////////////////////

        // update time
        unix_time::update(&mut time, &key, bid_closing_time + 60, test_scenario::ctx(&mut scenario)) ;

        // reveal bid 1 with user 1
        test_scenario::next_tx(&mut scenario, user1);
        reveal_bid(
            &mut auction,
            0,
            12,
            1,
            11111111,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );

        // reveal bid 2 with user 2
        test_scenario::next_tx(&mut scenario, user2);
        reveal_bid(
            &mut auction,
            1,
            12,
            3,
            22222222,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );

        // reveal bid 3 with user 2
        test_scenario::next_tx(&mut scenario, user2);
        reveal_bid(
            &mut auction,
            2,
            11,
            8,
            22222222,
            &mut coin,
            &time,
            test_scenario::ctx(&mut scenario)
        );

        let bid = table::borrow(&auction.bids, 0);
        assert!(option::is_some(&bid.price), 1);

        test_scenario::next_tx(&mut scenario, admin);
        coin::destroy_for_testing(coin);
        test_scenario::return_to_sender(&scenario, key);
        test_scenario::return_shared(time);
        test_scenario::end(scenario);
        auction
    }

    #[test]
    fun test_auction_remove_bid_success(): Auction<sui::sui::SUI> {
        let auction = test_auction_new_bid();

        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        remove_bid(&mut auction, user1, 0);
        // remove_bid(&mut auction, user1, 2);
        remove_bid(&mut auction, user2, 1);
        // remove_bid(&mut auction, user2, 3);

        auction
    }

    #[test]
    #[expected_failure]
    fun test_auction_remove_bid_failure(): Auction<sui::sui::SUI> {
        let auction = test_auction_new_bid();

        let monkey = @0x8787;
        remove_bid(&mut auction, monkey, 0);

        auction
    }

    #[test]
    #[expected_failure]
    fun test_auction_reveal_bid_fail_on_wrong_bid_info(): Auction<sui::sui::SUI> {
        use sui::coin;
        use sui::sui::SUI;
        use sui::test_scenario;
        use typus_oracle::unix_time::{Self, Time, Key};

        let auction = test_auction_new_bid();

        let admin = @0xFFFF;
        let user2 = @0xBABE2;
        let scenario = test_scenario::begin(admin);

        ////////////////////////////////////////////////////////////////////////////////////
        //   New Sealed Bid Auction
        ////////////////////////////////////////////////////////////////////////////////////
        let bid_closing_time =  1669338020;
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));

        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        test_scenario::next_tx(&mut scenario, admin);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);

        // update time
        unix_time::update(&mut time, &key, bid_closing_time + 60, test_scenario::ctx(&mut scenario)) ;

        // reveal bid with wrong bid info - wrong price 10. it should be 12
        test_scenario::next_tx(&mut scenario, user2);
        reveal_bid(
            &mut auction,
            1,
            10,
            3,
            11112222,
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
    #[expected_failure]
    fun test_auction_reveal_bid_fail_on_wrong_owner(): Auction<sui::sui::SUI> {
        use sui::coin;
        use sui::sui::SUI;
        use sui::test_scenario;
        use typus_oracle::unix_time::{Self, Time, Key};

        let auction = test_auction_new_bid();

        let admin = @0xFFFF;
        let monkey = @0x8787;
        let scenario = test_scenario::begin(admin);

        ////////////////////////////////////////////////////////////////////////////////////
        //   New Sealed Bid Auction
        ////////////////////////////////////////////////////////////////////////////////////
        let bid_closing_time =  1669338020;
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut scenario));

        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        test_scenario::next_tx(&mut scenario, admin);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);

        // update time
        unix_time::update(&mut time, &key, bid_closing_time + 60, test_scenario::ctx(&mut scenario)) ;

        // try to reveal bid 2 with user monkey
        test_scenario::next_tx(&mut scenario, monkey);
        reveal_bid(
            &mut auction,
            1,
            12,
            3,
            11112222,
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
    fun test_auction_delivery_success(): Auction<sui::sui::SUI> {
        use typus_oracle::unix_time::{Self, Time, Key};
        use sui::test_scenario;
        use sui::vec_map;

        let auction = test_auction_new_bid();
        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        // let user3 = @0xBABE3;

        let scenario = test_scenario::begin(admin);
        unix_time::new_time(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, admin);
        let time = test_scenario::take_shared<Time>(&scenario);
        let key = test_scenario::take_from_address<Key>(&scenario, admin);

        // update time
        unix_time::update(&mut time, &key, auction.reveal_closing_time + 1, test_scenario::ctx(&mut scenario)) ;

        let manager_cap = init_test_manager();
        let (balance, winners) = delivery(&manager_cap,  &mut auction, 10, 10, &time);

        assert!(vec_map::size(&winners) == 2, 1);
        assert!(*vec_map::get(&winners, &user1) == 1, 1);
        assert!(*vec_map::get(&winners, &user2) == 9, 1);
        // assert!(*vec_map::get(&winners, &user3) == 4, 1);

        // user1: got 1 at price 12
        // user2: got 1 at price 12, 6 at price 11, and got 2*11 refund
        // user3: deposit 20 forfeited
        assert!(balance::value(&balance) == 12*1 + 12*3 + 11*6 + 20, 1);


        test_scenario::next_tx(&mut scenario, admin);
        test_scenario::return_to_sender(&scenario, key);
        test_scenario::return_shared(time);
        coin::destroy_for_testing(coin::from_balance(balance, test_scenario::ctx(&mut scenario)));
        test_scenario::end(scenario);

        auction
    }

    // #[test]
    // fun test_auction_sorting(): vector<Bid<sui::sui::SUI>> {
    //     use sui::test_scenario;
    //     use sui::sui::SUI;
    //     use sui::coin;
    //     use std::debug;

    //     let admin = @0xFFFF;
    //     let admin_scenario = test_scenario::begin(admin);
    //     let coin = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut admin_scenario));

    //     let bids = vector::empty();
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 0,
    //             price: 123,
    //             size: 1,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 1,
    //             price: 42,
    //             size: 2,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 2,
    //             price: 435,
    //             size: 3,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 3,
    //             price: 33,
    //             size: 4,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 4,
    //             price: 123,
    //             size: 5,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 5,
    //             price: 33,
    //             size: 6,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 6,
    //             price: 435,
    //             size: 7,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     vector::push_back(
    //         &mut bids,
    //         Bid<SUI> {
    //             index: 7,
    //             price: 42,
    //             size: 8,
    //             coin: coin::split(&mut coin, 100, test_scenario::ctx(&mut admin_scenario)),
    //             owner: admin,
    //         }
    //     );
    //     selection_sort(&mut bids);

    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 0).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 0).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 1).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 1).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 2).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 2).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 3).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 3).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 4).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 4).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 5).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 5).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 6).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 6).price);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 7).index);
    //     debug::print(&vector::borrow<Bid<SUI>>(&bids, 7).price);

    //     coin::destroy_for_testing(coin);
    //     test_scenario::end(admin_scenario);
    //     bids
    // }
}
