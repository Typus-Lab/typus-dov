// Copyright (c) Typus Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module typus_dov::sealed {
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    use sui::ecdsa::{Self};
    // use std::debug;

    const E_ZERO_PRICE: u64 = 0;
    const E_ZERO_SIZE: u64 = 1;
    const E_BID_NOT_EXISTS: u64 = 2;
    const E_AUCTION_CLOSED: u64 = 3;
    const E_AUCTION_NOT_CLOSED: u64 = 4;
    const E_REVEAL_CLOSED: u64 = 5;
    const E_REVEAL_NOT_CLOSED: u64 = 6;
    const E_OWNER_MISMATCH: u64 = 7;
    const E_BID_COMMITMENT_MISMATCH: u64 = 8;

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
        commitment: vector<u8>,
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

    fun init(
        ctx: &mut TxContext
    ) {
        transfer::share_object(new<sui::sui::SUI>(
            1000,
            tx_context::epoch(ctx) + 60*60*24, // t+1
            tx_context::epoch(ctx) + 60*60*24*2, // t+2
            ctx
        ));
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
    public entry fun new_bid<Token>(
        auction: &mut Auction<Token>,
        commitment: vector<u8>,
        coin: &mut Coin<Token>, 
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::epoch(ctx) < auction.bid_closing_time, E_AUCTION_CLOSED);
        let index = auction.index;
        let owner = tx_context::sender(ctx);
        table::add(
            &mut auction.bids,
            index,
            Bid {
                index,
                commitment,
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
        }
    }

    /// reveal a bid
    public fun reveal_bid<Token>(
        auction: &mut Auction<Token>,
        bid_index: u64,
        price: u64,
        size: u64,
        blinding_factor: u64,
        coin: &mut Coin<Token>,
        ctx: &mut TxContext,
    ) {
        // assert!(tx_context::epoch(ctx) >= rfq.bid_closing_time, E_AUCTION_NOT_CLOSED);
        assert!(tx_context::epoch(ctx) < auction.reveal_closing_time, E_REVEAL_CLOSED);

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

        // debug::print(&price);
        // debug::print(&size);
        // debug::print(&blinding_factor);
        // debug::print(&bid.commitment);

        assert!(verify_bid_commitment(&bid.commitment, price, size, blinding_factor), E_BID_COMMITMENT_MISMATCH);
        assert!(price != 0, E_ZERO_PRICE);
        assert!(size != 0, E_ZERO_SIZE);
        
        bid.price = option::some(price);
        bid.size = option::some(size);
        bid.blinding_factor = option::some(blinding_factor);

       // TODO: sorting the bids
        
    }
    
    fun verify_bid_commitment(
        commitment: &vector<u8>,
        price: u64,
        size: u64,
        blinding_factor: u64,
    ): bool {
        let msg_to_verify = vector::empty();
        let price_vec = u64_to_u8_vector(price);
        let size_vec = u64_to_u8_vector(size);
        let blinding_factor_vec = u64_to_u8_vector(blinding_factor);
        
        let i = 0;
        let price_vec_len = vector::length(&price_vec);
        while (i < price_vec_len) {
            let elem: u8 = *vector::borrow(&price_vec, i);
            vector::push_back(&mut msg_to_verify, elem);
            i = i + 1;
        };

        let j = 0;
        let size_vec_len = vector::length(&size_vec);
        while (j < size_vec_len) {
            let elem: u8 = *vector::borrow(&size_vec, j);
            vector::push_back(&mut msg_to_verify, elem);
            j = j + 1;
        };

        let k = 0;
        let blinding_factor_vec_len = vector::length(&blinding_factor_vec);
        while (k < blinding_factor_vec_len) {
            let elem: u8 = *vector::borrow(&blinding_factor_vec, k);
            vector::push_back(&mut msg_to_verify, elem);
            k = k + 1;
        };

        // vector::destroy_empty(contents);

        // recover pubkey from signature
        let pubkey = ecdsa::ecrecover(commitment, &msg_to_verify);
        ecdsa::secp256k1_verify(commitment, &pubkey, &msg_to_verify)

        // compare::cmp_bcs_bytes(&hash_to_verify, hash) == 0
    }

    fun u64_to_u8_vector(num: u64): vector<u8> {
        let v1 = vector::empty();

        while (num/10 > 0){
            let rem = num%10;
            vector::push_back(&mut v1, (rem+48 as u8));
            num = num/10;
        };

        vector::push_back(&mut v1, (num+48 as u8));
        vector::reverse(&mut v1);

        v1
    }

    #[test]
    public fun test_u64_to_u8_vector() {
        use std::debug;
        let res = u64_to_u8_vector(99);
        debug::print(&res);
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
        let Bid {
            index: _,
            commitment: _,
            price: _,
            size: _,
            blinding_factor: _,
            owner: _,
        } = table::remove(&mut auction.bids, bid_index);
    }

    public fun get_bid_by_index<Token>(auction: &Auction<Token>, index: u64): &Bid {
        table::borrow(&auction.bids, index)
    }

    public fun get_bids_index_by_address<Token>(auction: &Auction<Token>, owner: address): &vector<u64> {
        table::borrow(&auction.ownerships, owner)
    }

    public fun delivery<Token>(auction: &mut Auction<Token>, price: u64, size: u64, balance: &mut Balance<Token>, ctx: &mut TxContext) {
        assert!(tx_context::epoch(ctx) >= auction.reveal_closing_time, E_REVEAL_NOT_CLOSED);
        
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
                // filled
                if (bid_size <= size) {
                    balance::join(balance, coin::into_balance(coin));
                    size = size - bid_size;
                }
                // partially filled
                else {
                    balance::join(balance, balance::split(coin::balance_mut(&mut coin), bid_price * bid_size));
                    transfer::transfer(coin, owner);
                    size = 0;
                };
            }
            else {
                transfer::transfer(coin, owner);
            };
        };

        // punish bidders with unrevealed bid
        let sender = tx_context::sender(ctx);
        while (!vector::is_empty(&unrevealed_bids)) {
            let bid = vector::pop_back(&mut unrevealed_bids);
            let Fund {
                coin,
                owner: _,
            } = table::remove(&mut auction.funds, bid.index);
            transfer::transfer(coin, sender);
        }
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

    #[test]
    fun test_auction_new_bid(): Auction<sui::sui::SUI> {
        // use std::vector;
        use sui::coin;
        use sui::sui::SUI;
        use sui::table;
        use sui::test_scenario;
        use std::debug;

        let admin = @0xFFFF;
        let user1 = @0xBABE1;
        let user2 = @0xBABE2;
        let admin_scenario = test_scenario::begin(admin);
        let user1_scenario = test_scenario::begin(user1);
        let user2_scenario = test_scenario::begin(user2);

        // 1669338020
        // 1669343354
        // 1669346954
        let coin = coin::mint_for_testing<SUI>(1000000, test_scenario::ctx(&mut admin_scenario));
        let auction = new(20, 1669338020, 1669346954, test_scenario::ctx(&mut admin_scenario));

        new_bid(
            &mut auction,
            b"i am user1, my sealed bid is (x,y) with blinding_factor z",
            &mut coin,
            test_scenario::ctx(&mut user1_scenario)
        );
        assert!(auction.index == 1, 1);
        let bid = table::borrow(&auction.bids, 0);
        debug::print(bid);

        // reveal_bid(
        //     &mut auction,
        //     0,
        //     99,
        //     1,
        //     12384,
        //     &mut coin,
        //     test_scenario::ctx(&mut user1_scenario)
        // );


        // /*
        //     bids[0] => bid{100, 1, user1}
        //     ownerships[user1] => [0]
        // */
        // new_bid(&mut auction, 100, 1, &mut coin, test_scenario::ctx(&mut user1_scenario));
        // assert!(auction.index == 1, 1);
        // let bid = table::borrow(&auction.bids, 0);
        // let fund = table::borrow(&auction.funds, 0);
        // assert!(bid.price == 100 && bid.size == 1 && fund.owner == user1, 2);
        // let ownership = table::borrow(&auction.ownerships, user1);
        // assert!(vector::length(ownership) == 1, 3);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 0, 4);

        // /*
        //     bids[1] => bid{200, 2, user2}
        //     ownerships[user2] => [1]
        // */
        // new_bid(&mut auction, 200, 2, &mut coin, test_scenario::ctx(&mut user2_scenario));
        // assert!(auction.index == 2, 5);
        // let bid = table::borrow(&auction.bids, 1);
        // let fund = table::borrow(&auction.funds, 1);
        // assert!(bid.price == 200 && bid.size == 2 && fund.owner == user2, 6);
        // let ownership = table::borrow(&auction.ownerships, user2);
        // assert!(vector::length(ownership) == 1, 7);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 1, 8);

        // /*
        //     bids[2] => bid{300, 3, user1}
        //     ownerships[user1] => [0, 2]
        // */
        // new_bid(&mut auction, 300, 3, &mut coin, test_scenario::ctx(&mut user1_scenario));
        // assert!(auction.index == 3, 9);
        // let bid = table::borrow(&auction.bids, 2);
        // let fund = table::borrow(&auction.funds, 2);
        // assert!(bid.price == 300 && bid.size == 3 && fund.owner == user1, 10);
        // let ownership = table::borrow(&auction.ownerships, user1);
        // assert!(vector::length(ownership) == 2, 11);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 0, 12);
        // let bid_index = vector::borrow(ownership, 1);
        // assert!(*bid_index == 2, 13);


        // /*
        //     bids[1] => bid{400, 4, user2}
        //     ownerships[user2] => [1, 3]
        // */
        // new_bid(&mut auction, 400, 4, &mut coin, test_scenario::ctx(&mut user2_scenario));
        // assert!(auction.index == 4, 14);
        // let bid = table::borrow(&auction.bids, 3);
        // let fund = table::borrow(&auction.funds, 3);
        // assert!(bid.price == 400 && bid.size == 4 && fund.owner == user2, 15);
        // let ownership = table::borrow(&auction.ownerships, user2);
        // assert!(vector::length(ownership) == 2, 16);
        // let bid_index = vector::borrow(ownership, 0);
        // assert!(*bid_index == 1, 17);
        // let bid_index = vector::borrow(ownership, 1);
        // assert!(*bid_index == 3, 18);

        coin::destroy_for_testing(coin);
        test_scenario::end(admin_scenario);
        test_scenario::end(user1_scenario);
        test_scenario::end(user2_scenario);
        auction
    }

    // #[test]
    // fun test_auction_remove_bid_success(): Auction<sui::sui::SUI> {
    //     let auction = test_auction_new_bid();

    //     let user1 = @0xBABE1;
    //     let user2 = @0xBABE2;
    //     remove_bid(&mut auction, user1, 0);
    //     remove_bid(&mut auction, user1, 2);
    //     remove_bid(&mut auction, user2, 1);
    //     remove_bid(&mut auction, user2, 3);

    //     auction
    // }

    // #[test]
    // #[expected_failure]
    // fun test_auction_remove_bid_failure(): Auction<sui::sui::SUI> {
    //     let auction = test_auction_new_bid();

    //     let monkey = @0x8787;
    //     remove_bid(&mut auction, monkey, 0);

    //     auction
    // }

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
