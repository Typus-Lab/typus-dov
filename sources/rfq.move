// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::rfq {
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use std::vector;

    const E_BID_NOT_EXISTS: u64 = 0;

    struct Rfq has store {
        index: u64,
        bids: Table<u64, Bid>,
        ownerships: Table<address, vector<u64>>
    }

    struct Bid has drop, store {
        price: u64,
        size: u64,
        owner: address,
    }

    public fun new(ctx: &mut TxContext): Rfq {
        Rfq {
            index: 0,
            bids: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    public fun new_bid(
        rfq: &mut Rfq,
        price: u64,
        size: u64,
        owner: address,
    ) {
        let index = rfq.index;
        table::add(
            &mut rfq.bids,
            index,
            Bid {
                price,
                size,
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

    public fun remove_bid(
        rfq: &mut Rfq,
        owner: address,
        bid_index: u64,
    ): Bid {
        let ownership = table::borrow_mut(&mut rfq.ownerships, owner);
        let (bid_exist, index) = vector::index_of(ownership, &bid_index);
        assert!(bid_exist, E_BID_NOT_EXISTS);
        vector::swap_remove(ownership, index);
        table::remove(&mut rfq.bids, bid_index)
    }

    #[test]
    fun test_rfq_new_bid(): Rfq {
        use std::vector;
        use sui::table;
        use sui::test_scenario;

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        let admin_scenario = test_scenario::begin(admin);
        let rfq = new(test_scenario::ctx(&mut admin_scenario));

        /*
            bids[0] => bid{100, 1, user1}
            ownerships[user1] => [0]
        */
        new_bid(&mut rfq, 100, 1, user1);
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
        new_bid(&mut rfq, 200, 2, user2);
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
        new_bid(&mut rfq, 300, 3, user1);
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
        new_bid(&mut rfq, 400, 4, user2);
        assert!(rfq.index == 4, 14);
        let bid = table::borrow(&rfq.bids, 0);
        assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 15);
        let ownership = table::borrow(&rfq.ownerships, user2);
        assert!(vector::length(ownership) == 2, 16);
        let bid_index = vector::borrow(ownership, 0);
        assert!(*bid_index == 1, 17);
        let bid_index = vector::borrow(ownership, 1);
        assert!(*bid_index == 3, 18);

        test_scenario::end(admin_scenario);
        rfq
    }

    #[test]
    fun test_rfq_remove_bid_success(): Rfq {
        let rfq = test_rfq_new_bid();

        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        remove_bid(&mut rfq, user1, 0);
        remove_bid(&mut rfq, user1, 2);
        remove_bid(&mut rfq, user2, 1);
        remove_bid(&mut rfq, user2, 3);

        rfq
    }

    #[test]
    #[expected_failure]
    fun test_rfq_remove_bid_failure(): Rfq {
        let rfq = test_rfq_new_bid();

        let monkey = @0x8787;
        remove_bid(&mut rfq, monkey, 0);

        rfq
    }
}
