// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::rfq {
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    const E_ZERO_PRICE: u64 = 0;
    const E_ZERO_SIZE: u64 = 1;
    const E_BID_NOT_EXISTS: u64 = 2;

    struct Rfq<phantom Token> has key {
        id: UID,
        index: u64,
        bids: Table<u64, Bid>,
        funds: Table<u64, Fund<Token>>,
        ownerships: Table<address, vector<u64>>
    }

    struct Bid has copy, drop, store {
        index: u64,
        price: u64,
        size: u64,
    }

    struct Fund<phantom Token> has store {
        coin: Coin<Token>,
        owner: address,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(new<sui::sui::SUI>(ctx));
    }

    public fun new<Token>(ctx: &mut TxContext): Rfq<Token> {
        Rfq {
            id: object::new(ctx),
            index: 0,
            bids: table::new(ctx),
            funds: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    public entry fun new_bid<Token>(
        rfq: &mut Rfq<Token>,
        price: u64,
        size: u64,
        coin: &mut Coin<Token>,
        ctx: &mut TxContext,
    ) {
        assert!(price != 0, E_ZERO_PRICE);
        assert!(size != 0, E_ZERO_SIZE);
        let index = rfq.index;
        let owner = tx_context::sender(ctx);
        table::add(
            &mut rfq.bids,
            index,
            Bid {
                index,
                price,
                size,
            }
        );
        table::add(
            &mut rfq.funds,
            index,
            Fund {
                coin: coin::split(coin, price * size, ctx),
                owner,
            }
        );
        rfq.index = index + 1;
        if (table::contains(&rfq.ownerships, owner)) {
            let ownership = table::borrow_mut(&mut rfq.ownerships, owner);
            vector::push_back(ownership, index);
        }
        else {
            let ownership = vector::empty();
            vector::push_back(&mut ownership, index);
            table::add(
                &mut rfq.ownerships,
                owner,
                ownership,
            )
        }
    }

    public fun remove_bid<Token>(
        rfq: &mut Rfq<Token>,
        owner: address,
        bid_index: u64,
    ) {
        let ownership = table::borrow_mut(&mut rfq.ownerships, owner);
        let (bid_exist, index) = vector::index_of(ownership, &bid_index);
        assert!(bid_exist, E_BID_NOT_EXISTS);
        vector::swap_remove(ownership, index);
        table::remove(&mut rfq.bids, bid_index);
        let Fund {
            coin,
            owner,
        } = table::remove(&mut rfq.funds, bid_index);
        transfer::transfer(coin, owner);
    }

    public fun get_bid_by_index<Token>(rfq: &Rfq<Token>, index: u64): &Bid {
        table::borrow(&rfq.bids, index)
    }

    public fun get_bids_index_by_address<Token>(rfq: &Rfq<Token>, owner: address): &vector<u64> {
        table::borrow(&rfq.ownerships, owner)
    }

    // public entry fun test_sorting<Token>(rfq: &mut Rfq<Token>, ctx: &mut TxContext) {
    //     use std::string;
    //     use typus_dov::convert;

    //     let result = string::utf8(vector::empty());
    //     let bids = vector::empty();
    //     let index = rfq.index;
    //     while (index > 0) {
    //         let bid = table::remove(&mut rfq.bids, index - 1);
    //         vector::push_back(&mut bids, bid);
    //         index = index - 1;
    //     };
    //     selection_sort(&mut bids);
    //     while (!vector::is_empty(&bids)) {
    //         let Bid {
    //             index: _,
    //             price,
    //             size,
    //             coin,
    //             owner: _,
    //         } = vector::pop_back(&mut bids);
    //         string::append_utf8(&mut result, b", Price: ");
    //         string::append(&mut result, convert::u64_to_string(price));
    //         string::append_utf8(&mut result, b", Size: ");
    //         string::append(&mut result, convert::u64_to_string(size));
    //         transfer::transfer(
    //             coin,
    //             sui::tx_context::sender(ctx),
    //         );
            
    //         index = index + 1;
    //     };

    //     transfer::transfer(
    //         TestResult {
    //             id: sui::object::new(ctx),
    //             result,
    //         },
    //         sui::tx_context::sender(ctx),
    //     );
    //     vector::destroy_empty(bids);
    // }

    // fun quick_sort<Token>(bids: &mut vector<Bid<Token>>) {
    //     let length = vector::length(bids);
    //     quick_sort_(bids, 0, length - 1);
    // }

    // fun quick_sort_<Token>(bids: &mut vector<Bid<Token>>, l: u64, r: u64) {
    //     if (l >= r) {
    //         return
    //     };

    //     let pivot_price = vector::borrow(bids, l).price;
    //     let left = l;
    //     let right = r + 1;
    //     loop {
    //         while (left < r && vector::borrow(bids, left + 1).price <= pivot_price) {
    //             left = left + 1;
    //         };
    //         while (right > l && vector::borrow(bids, right - 1).price >= pivot_price) {
    //             right = right - 1;
    //         };
    //         if (left < right) {
    //             vector::swap(bids, left, right);
    //         }
    //         else {
    //             break
    //         }
    //     };
    //     vector::swap(bids, l, right);

    //     quick_sort_(bids, l, right - 1);
    //     quick_sort_(bids, left, r);
    // }
    
    fun selection_sort<Token>(bids: &mut vector<Bid>) {
        let length = vector::length(bids);
        let i = 0;
        while (i < length) {
            let min_price = vector::borrow(bids, i).price;
            let min_index = vector::borrow(bids, i).index;
            let min_at = i;
            let j = i + 1;
            while (j < length) {
                let price = vector::borrow(bids, j).price;
                let index = vector::borrow(bids, j).index;
                if(price < min_price || (price == min_price && index > min_index)) {
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

    // #[test]
    // fun test_rfq_new_bid(): Rfq<sui::sui::SUI> {
    //     use std::vector;
    //     use sui::coin;
    //     use sui::sui::SUI;
    //     use sui::table;
    //     use sui::test_scenario;

    //     let admin = @0xFFFF;
    //     let user1 = @0xBABE1;
    //     let user2 = @0xBABE2;
    //     let admin_scenario = test_scenario::begin(admin);
    //     let rfq = new(test_scenario::ctx(&mut admin_scenario));
    //     let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut admin_scenario));

    //     /*
    //         bids[0] => bid{100, 1, user1}
    //         ownerships[user1] => [0]
    //     */
    //     new_bid(&mut rfq, 100, 1, user1, &mut coin, test_scenario::ctx(&mut admin_scenario));
    //     assert!(rfq.index == 1, 1);
    //     let bid = table::borrow(&rfq.bids, 0);
    //     assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 2);
    //     let ownership = table::borrow(&rfq.ownerships, user1);
    //     assert!(vector::length(ownership) == 1, 3);
    //     let bid_index = vector::borrow(ownership, 0);
    //     assert!(*bid_index == 0, 4);

    //     /*
    //         bids[1] => bid{200, 2, user2}
    //         ownerships[user2] => [1]
    //     */
    //     new_bid(&mut rfq, 200, 2, user2, &mut coin, test_scenario::ctx(&mut admin_scenario));
    //     assert!(rfq.index == 2, 5);
    //     let bid = table::borrow(&rfq.bids, 0);
    //     assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 6);
    //     let ownership = table::borrow(&rfq.ownerships, user2);
    //     assert!(vector::length(ownership) == 1, 7);
    //     let bid_index = vector::borrow(ownership, 0);
    //     assert!(*bid_index == 1, 8);

    //     /*
    //         bids[2] => bid{300, 3, user1}
    //         ownerships[user1] => [0, 2]
    //     */
    //     new_bid(&mut rfq, 300, 3, user1, &mut coin, test_scenario::ctx(&mut admin_scenario));
    //     assert!(rfq.index == 3, 9);
    //     let bid = table::borrow(&rfq.bids, 0);
    //     assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 10);
    //     let ownership = table::borrow(&rfq.ownerships, user1);
    //     assert!(vector::length(ownership) == 2, 11);
    //     let bid_index = vector::borrow(ownership, 0);
    //     assert!(*bid_index == 0, 12);
    //     let bid_index = vector::borrow(ownership, 1);
    //     assert!(*bid_index == 2, 13);


    //     /*
    //         bids[1] => bid{400, 4, user2}
    //         ownerships[user2] => [1, 3]
    //     */
    //     new_bid(&mut rfq, 400, 4, user2, &mut coin, test_scenario::ctx(&mut admin_scenario));
    //     assert!(rfq.index == 4, 14);
    //     let bid = table::borrow(&rfq.bids, 0);
    //     assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 15);
    //     let ownership = table::borrow(&rfq.ownerships, user2);
    //     assert!(vector::length(ownership) == 2, 16);
    //     let bid_index = vector::borrow(ownership, 0);
    //     assert!(*bid_index == 1, 17);
    //     let bid_index = vector::borrow(ownership, 1);
    //     assert!(*bid_index == 3, 18);

    //     coin::destroy_for_testing(coin);
    //     test_scenario::end(admin_scenario);
    //     rfq
    // }

    // #[test]
    // fun test_rfq_remove_bid_success(): Rfq<sui::sui::SUI> {
    //     let rfq = test_rfq_new_bid();

    //     let user1 = @0xBABE1;
    //     let user2 = @0xBABE2;
    //     remove_bid(&mut rfq, user1, 0);
    //     remove_bid(&mut rfq, user1, 2);
    //     remove_bid(&mut rfq, user2, 1);
    //     remove_bid(&mut rfq, user2, 3);

    //     rfq
    // }

    // #[test]
    // #[expected_failure]
    // fun test_rfq_remove_bid_failure(): Rfq<sui::sui::SUI> {
    //     let rfq = test_rfq_new_bid();

    //     let monkey = @0x8787;
    //     remove_bid(&mut rfq, monkey, 0);

    //     rfq
    // }

    // #[test]
    // fun test_rfq_sorting(): vector<Bid<sui::sui::SUI>> {
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
