module typus_dov::dutch {
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    const E_ZERO_SIZE: u64 = 0;
    const E_BID_NOT_EXISTS: u64 = 1;

    struct Auction<phantom Token> has key {
        id: UID,
        price: u64,
        index: u64,
        bids: Table<u64, Bid>,
        funds: Table<u64, Fund<Token>>,
        ownerships: Table<address, vector<u64>>
    }

    struct Bid has copy, drop, store {
        size: u64,
        epoch: u64,
    }

    struct Fund<phantom Token> has store {
        coin: Coin<Token>,
        owner: address,
    }

    struct Winner has store {
        owner: address,
        size: u64,
    }

    public fun new<Token>(price: u64, ctx: &mut TxContext): Auction<Token> {
        Auction {
            id: object::new(ctx),
            price,
            index: 0,
            bids: table::new(ctx),
            funds: table::new(ctx),
            ownerships: table::new(ctx),
        }
    }

    public fun new_bid<Token>(
        auction: &mut Auction<Token>,
        size: u64,
        coin: &mut Coin<Token>,
        ctx: &mut TxContext,
    ) {
        assert!(size != 0, E_ZERO_SIZE);
        let index = auction.index;
        let owner = tx_context::sender(ctx);
        table::add(
            &mut auction.bids,
            index,
            Bid {
                size,
                epoch: tx_context::epoch(ctx),
            }
        );
        table::add(
            &mut auction.funds,
            index,
            Fund {
                coin: coin::split(coin, auction.price * size, ctx),
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
        transfer::transfer(coin, owner);
    }

    public fun get_bid_by_index<Token>(auction: &Auction<Token>, index: u64): &Bid {
        table::borrow(&auction.bids, index)
    }

    public fun get_bids_index_by_address<Token>(auction: &Auction<Token>, owner: address): &vector<u64> {
        table::borrow(&auction.ownerships, owner)
    }

    public fun delivery<Token>(auction: &mut Auction<Token>, price: u64, size: u64, balance: &mut Balance<Token>): vector<Winner> {
        let winners = vector::empty();
        let index = 0;
        while (!table::is_empty(&auction.bids)) {
            // get market maker bid and fund
            let bid = table::remove(&mut auction.bids, index);
            let Fund {
                coin,
                owner
            } = table::remove(&mut auction.funds, index);
            if (size > 0) {
                balance::join(balance, balance::split(coin::balance_mut(&mut coin), price * bid.size));
                // filled
                if (bid.size <= size) {
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
            index = index + 1;
        };

        winners
    }
}