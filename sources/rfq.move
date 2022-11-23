// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::rfq {
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use std::vector;
    use sui::coin::{Self, Coin};

    const E_BID_NOT_EXISTS: u64 = 0;

    struct Rfq<phantom Token> has store {
        index: u64,
        bids: Table<u64, Bid<Token>>,
        ownerships: Table<address, vector<u64>>
    }

    struct Bid<phantom Token> has store {
        price: u64,
        size: u64,
        coin: Coin<Token>,
        owner: address,
    }

    public fun new<Token>(ctx: &mut TxContext): Rfq<Token> {
        Rfq {
            index: 0,
            bids: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    public fun new_bid<Token>(
        rfq: &mut Rfq<Token>,
        price: u64,
        size: u64,
        owner: address,
        coin: &mut Coin<Token>,
        ctx: &mut TxContext,
    ) {
        let index = rfq.index;
        table::add(
            &mut rfq.bids,
            index,
            Bid {
                price,
                size,
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
    ): Bid<Token> {
        let ownership = table::borrow_mut(&mut rfq.ownerships, owner);
        let (bid_exist, index) = vector::index_of(ownership, &bid_index);
        assert!(bid_exist, E_BID_NOT_EXISTS);
        vector::swap_remove(ownership, index);
        table::remove(&mut rfq.bids, bid_index)
    }

    #[test]
    fun test_rfq_new_bid(): Rfq<sui::sui::SUI> {
        use std::vector;
        use sui::coin;
        use sui::sui::SUI;
        use sui::table;
        use sui::test_scenario;

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        let admin_scenario = test_scenario::begin(admin);
        let rfq = new(test_scenario::ctx(&mut admin_scenario));
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut admin_scenario));

        /*
            bids[0] => bid{100, 1, user1}
            ownerships[user1] => [0]
        */
        new_bid(&mut rfq, 100, 1, user1, &mut coin, test_scenario::ctx(&mut admin_scenario));
        assert!(rfq.index == 1, 1);
        let bid = table::borrow(&rfq.bids, 0);
        assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 2);
        let ownership = table::borrow(&rfq.ownerships, user1);
        assert!(vector::length(ownership) == 1, 3);
        let bid_index = vector::borrow(ownership, 0);
        assert!(*bid_index == 0, 4);

        /*
            bids[1] => bid{200, 2, user2}
            ownerships[user2] => [1]
        */
        new_bid(&mut rfq, 200, 2, user2, &mut coin, test_scenario::ctx(&mut admin_scenario));
        assert!(rfq.index == 2, 5);
        let bid = table::borrow(&rfq.bids, 0);
        assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 6);
        let ownership = table::borrow(&rfq.ownerships, user2);
        assert!(vector::length(ownership) == 1, 7);
        let bid_index = vector::borrow(ownership, 0);
        assert!(*bid_index == 1, 8);

        /*
            bids[2] => bid{300, 3, user1}
            ownerships[user1] => [0, 2]
        */
        new_bid(&mut rfq, 300, 3, user1, &mut coin, test_scenario::ctx(&mut admin_scenario));
        assert!(rfq.index == 3, 9);
        let bid = table::borrow(&rfq.bids, 0);
        assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 10);
        let ownership = table::borrow(&rfq.ownerships, user1);
        assert!(vector::length(ownership) == 2, 11);
        let bid_index = vector::borrow(ownership, 0);
        assert!(*bid_index == 0, 12);
        let bid_index = vector::borrow(ownership, 1);
        assert!(*bid_index == 2, 13);


        /*
            bids[1] => bid{400, 4, user2}
            ownerships[user2] => [1, 3]
        */
        new_bid(&mut rfq, 400, 4, user2, &mut coin, test_scenario::ctx(&mut admin_scenario));
        assert!(rfq.index == 4, 14);
        let bid = table::borrow(&rfq.bids, 0);
        assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 15);
        let ownership = table::borrow(&rfq.ownerships, user2);
        assert!(vector::length(ownership) == 2, 16);
        let bid_index = vector::borrow(ownership, 0);
        assert!(*bid_index == 1, 17);
        let bid_index = vector::borrow(ownership, 1);
        assert!(*bid_index == 3, 18);

        coin::destroy_for_testing(coin);
        test_scenario::end(admin_scenario);
        rfq
    }

    #[test]
    fun test_rfq_remove_bid_success(): (Rfq<sui::sui::SUI>, vector<Bid<sui::sui::SUI>>) {
        let rfq = test_rfq_new_bid();
        let bids = vector::empty();

        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        vector::push_back(&mut bids, remove_bid(&mut rfq, user1, 0));
        vector::push_back(&mut bids, remove_bid(&mut rfq, user1, 2));
        vector::push_back(&mut bids, remove_bid(&mut rfq, user2, 1));
        vector::push_back(&mut bids, remove_bid(&mut rfq, user2, 3));

        (rfq, bids)
    }

    #[test]
    #[expected_failure]
    fun test_rfq_remove_bid_failure(): (Rfq<sui::sui::SUI>, vector<Bid<sui::sui::SUI>>) {
        let rfq = test_rfq_new_bid();
        let bids = vector::empty();

        let monkey = @0x8787;
        vector::push_back(&mut bids, remove_bid(&mut rfq, monkey, 0));

        (rfq, bids)
    }
}
