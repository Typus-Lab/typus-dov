// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::rfq {
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    use sui::object::{Self, UID};
    use std::debug;

    const E_ZERO_PRICE: u64 = 0;
    const E_ZERO_SIZE: u64 = 1;
    const E_BID_NOT_EXISTS: u64 = 2;
    const E_AUCTION_CLOSED: u64 = 3;
    const E_AUCTION_NOT_CLOSED: u64 = 4;
    const E_REVEAL_CLOSED: u64 = 5;
    const E_REVEAL_NOT_CLOSED: u64 = 6;
    const E_OWNER_MISMATCH: u64 = 7;
    const E_BID_COMMITMENT_MISMATCH: u64 = 8;

    /// Rfq which is First Price Sealed-Bid Auction style
    struct Rfq<phantom Token> has key, store {
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
        bids: Table<u64, Bid<Token>>,
        /// bidders info
        ownerships: Table<address, vector<u64>>
    }

    struct Bid<phantom Token> has store {
        index: u64,
        /// encrypted (price+size+blinding_factor) with zk proof function
        /// ==> or just using a hash function? or RSA function?
        commitment: vector<u8>,
        /// real price after revealing
        price: Option<u64>,
        /// real size after revealing
        size: Option<u64>,
        /// blinding_factor after revealing
        blinding_factor: Option<u64>,
        coin: Option<Coin<Token>>,
        owner: address,
    }

    /// create a new RFQ for auction
    public fun new<Token>(
        min_deposit: u64,
        bid_closing_time: u64,
        reveal_closing_time: u64,
        ctx: &mut TxContext
    ): Rfq<Token> {
        Rfq {
            id: object::new(ctx),
            min_deposit,
            bid_closing_time,
            reveal_closing_time,
            index: 0,
            bids: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    /// submit a bid for auction - for bidders to call
    public fun new_bid<Token>(
        rfq: &mut Rfq<Token>,
        commitment: vector<u8>,
        owner: address,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::epoch(ctx) < rfq.bid_closing_time, E_AUCTION_CLOSED);
        let index = rfq.index;
        // todo - transfer deposit to vault
        table::add(
            &mut rfq.bids,
            index,
            Bid {
                index,
                commitment,
                price: option::none(),
                size: option::none(),
                blinding_factor: option::none(),
                coin: option::none(), // transfer coin only after revealing the bid
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

    /// reveal a bid
    public fun reveal_bid<Token>(
        rfq: &mut Rfq<Token>,
        bid_index: u64,
        price: u64,
        size: u64,
        blinding_factor: u64,
        coin: &mut Coin<Token>,
        _owner: address,
        ctx: &mut TxContext,
    ) {
        // assert!(tx_context::epoch(ctx) >= rfq.bid_closing_time, E_AUCTION_NOT_CLOSED);
        assert!(tx_context::epoch(ctx) < rfq.reveal_closing_time, E_REVEAL_CLOSED);

        assert!(bid_index < rfq.index, E_BID_NOT_EXISTS);
        let bid = table::borrow_mut(&mut rfq.bids, bid_index);
        // let sender = tx_context::sender(ctx);
        // assert!(bid.owner == sender, E_OWNER_MISMATCH);

        // transfer quote coins
        option::fill(&mut bid.coin, coin::split(coin, price * size, ctx));

        debug::print(&price);
        debug::print(&size);
        debug::print(&blinding_factor);
        debug::print(&bid.commitment);

        assert!(verify_bid_commitment(&bid.commitment, price, size, blinding_factor), E_BID_COMMITMENT_MISMATCH);
        assert!(price != 0, E_ZERO_PRICE);
        assert!(size != 0, E_ZERO_SIZE);
        // TODO: remove bid if price=0 || size = 0
        
        bid.price = option::some(price);
        bid.size = option::some(size);
        bid.blinding_factor = option::some(blinding_factor);

       // TODO: sorting the bids
        
    }

    /// auction winners to pay - anyone can call?
    public fun finalize_auction<Token>(
        rfq: &mut Rfq<Token>,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::epoch(ctx) >= rfq.reveal_closing_time, E_REVEAL_NOT_CLOSED);
        // TODO: 
        // transfer winners' tokens (check if bidded size available - MIN(base_available, bid_size)) 
        // to vault and send Items(amount = MIN(base_available, bid_size)) to winners    
      
        // refund losing bidder's tokens 
        // refund honest bidders' deposits
        // punish malicious bidders by taking their deposits
    }

    /// TODO
    fun verify_bid_commitment(
        _commitment: &vector<u8>,
        _price: u64,
        _size: u64,
        _blinding_factor: u64
    ): bool {
        true
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
        let Bid {
            index: _,
            commitment: _,
            price: _,
            size: _,
            blinding_factor: _,
            coin,
            owner,
        } = table::remove(&mut rfq.bids, bid_index);
        transfer::transfer(option::destroy_some(coin), owner)
    }

    fun sort<Token>(bids: &mut vector<Bid<Token>>) {
        let length = vector::length(bids);
        sort_(bids, 0, length - 1);
    }

    fun sort_<Token>(bids: &mut vector<Bid<Token>>, l: u64, r: u64) {
        if (l >= r) {
            return
        };

        let pivot_price = *option::borrow(&vector::borrow(bids, l).price);
        let left = l;
        let right = r + 1;
        loop {
            while (left < r && *option::borrow(&vector::borrow(bids, left + 1).price) <= pivot_price) {
                left = left + 1;
            };
            while (right > l && *option::borrow(&vector::borrow(bids, right - 1).price) >= pivot_price) {
                right = right - 1;
            };
            if (left < right) {
                vector::swap(bids, left, right);
            }
            else {
                break
            }
        };
        vector::swap(bids, l, right);

        sort_(bids, l, right - 1);
        sort_(bids, left, r);
    }
    
    fun selection_sort<Token>(bids: &mut vector<Bid<Token>>) {
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

    #[test]
    fun test_rfq_new_bid(): Rfq<sui::sui::SUI> {
        // use std::vector;
        use sui::coin;
        use sui::sui::SUI;
        // use sui::table;
        use sui::test_scenario;
        use std::debug;

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        // let user2 = @0xBABE2;
        let admin_scenario = test_scenario::begin(admin);
        // 1669338020
        // 1669343354
        // 1669346954
        let rfq = new(100, 20, 1669338020, 1669346954, test_scenario::ctx(&mut admin_scenario));
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut admin_scenario));

        // /*
        //     bids[0] => bid{100, 1, user1}
        //     ownerships[user1] => [0]
        // */

        new_bid(&mut rfq, b"i am user1, my sealed bid is (x,y) with blinding_factor z", user1, test_scenario::ctx(&mut admin_scenario));
        assert!(rfq.index == 1, 1);
        let bid = table::borrow(&rfq.bids, 0);
        debug::print(bid);
        debug::print(&tx_context::epoch(test_scenario::ctx(&mut admin_scenario)));
        // rfq: &mut Rfq<Token>,
        // bid_index: u64,
        // price: u64,
        // size: u64,
        // blinding_factor: u64,
        // coin: &mut Coin<Token>,
        // _owner: address,
        // ctx: &mut TxContext,

        reveal_bid(
            &mut rfq,
            0,
            99,
            1,
            12384,
            &mut coin,
            user1,
            test_scenario::ctx(&mut admin_scenario)
        );

        // assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 2);
        // let ownership = table::borrow(&rfq.ownerships, user1);
        // assert!(vector::length(ownership) == 1, 3);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 0, 4);

        // /*
        //     bids[1] => bid{200, 2, user2}
        //     ownerships[user2] => [1]
        // */
        // new_bid(&mut rfq, 200, 2, user2, &mut coin, test_scenario::ctx(&mut admin_scenario));
        // assert!(rfq.index == 2, 5);
        // let bid = table::borrow(&rfq.bids, 0);
        // assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 6);
        // let ownership = table::borrow(&rfq.ownerships, user2);
        // assert!(vector::length(ownership) == 1, 7);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 1, 8);

        // /*
        //     bids[2] => bid{300, 3, user1}
        //     ownerships[user1] => [0, 2]
        // */
        // new_bid(&mut rfq, 300, 3, user1, &mut coin, test_scenario::ctx(&mut admin_scenario));
        // assert!(rfq.index == 3, 9);
        // let bid = table::borrow(&rfq.bids, 0);
        // assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 10);
        // let ownership = table::borrow(&rfq.ownerships, user1);
        // assert!(vector::length(ownership) == 2, 11);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 0, 12);
        // let bid_index = vector::borrow(ownership, 1);
        // assert!(*bid_index == 2, 13);


        // /*
        //     bids[1] => bid{400, 4, user2}
        //     ownerships[user2] => [1, 3]
        // */
        // new_bid(&mut rfq, 400, 4, user2, &mut coin, test_scenario::ctx(&mut admin_scenario));
        // assert!(rfq.index == 4, 14);
        // let bid = table::borrow(&rfq.bids, 0);
        // assert!(bid.price == 100 && bid.size == 1 && bid.owner == user1, 15);
        // let ownership = table::borrow(&rfq.ownerships, user2);
        // assert!(vector::length(ownership) == 2, 16);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 1, 17);
        // let bid_index = vector::borrow(ownership, 1);
        // assert!(*bid_index == 3, 18);

        coin::destroy_for_testing(coin);
        test_scenario::end(admin_scenario);
        rfq
    }

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
