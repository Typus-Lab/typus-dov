module typus_framework::linked_table {
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::{TxContext};

    struct LinkedTable<K: copy + drop + store, V: store> has store {
        first: Option<K>,
        last: Option<K>,
        nodes: Table<K, Node<K, V>>
    }

    struct Node<K: copy + drop + store, V: store> has store {
        value: V,
        prev: Option<K>,
        next: Option<K>,
    }

    public fun new<K: copy + drop + store, V: store>(ctx: &mut TxContext): LinkedTable<K, V> {
        LinkedTable<K, V> {
            first: option::none(),
            last: option::none(),
            nodes: table::new<K, Node<K, V>>(ctx)
        }
    }

    public fun first<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>): Option<K> {
        linked_table.first
    }

    public fun last<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>): Option<K> {
        linked_table.last
    }

    public fun length<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>): u64 {
        table::length(&linked_table.nodes)
    }

    public fun is_empty<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>): bool {
        option::is_none(&linked_table.first)
    }

    public fun push_back<K: copy + drop + store, V: store>(linked_table: &mut LinkedTable<K, V>, key: K, value: V) {
        if (option::is_none(&linked_table.first)) {
            linked_table.first = option::some(key);
        };

        let prev = option::none();
        if (option::is_some(&linked_table.last)) {
            prev = linked_table.last;

            let prev_node = table::borrow_mut(&mut linked_table.nodes, *option::borrow<K>(&prev));
            prev_node.next = option::some(key);
        };

        let node = Node<K, V> {
            value,
            prev,
            next: option::none(),
        };
        linked_table.last = option::some(key);
        table::add(&mut linked_table.nodes, key, node);
    }

    public fun push_front<K: copy + drop + store, V: store>(linked_table: &mut LinkedTable<K, V>, key: K, value: V) {
        if (option::is_none(&linked_table.last)) {
            linked_table.last = option::some(key);
        };

        let next = option::none();
        if (option::is_some(&linked_table.first)) {
            next = linked_table.first;

            let next_node = table::borrow_mut(&mut linked_table.nodes, *option::borrow<K>(&next));
            next_node.prev = option::some(key);
        };

        let node = Node<K, V> {
            value,
            prev: option::none(),
            next,
        };
        linked_table.first = option::some(key);
        table::add(&mut linked_table.nodes, key, node);
    }

    public fun pop_back<K: copy + drop + store, V: store>(linked_table: &mut LinkedTable<K, V>): V {
        let key = option::borrow(&linked_table.last);
        remove(linked_table, *key)
    }

    public fun pop_front<K: copy + drop + store, V: store>(linked_table: &mut LinkedTable<K, V>): V {
        let key = option::borrow(&linked_table.first);
        remove(linked_table, *key)
    }

    public fun remove<K: copy + drop + store, V: store>(linked_table: &mut LinkedTable<K, V>, key: K): V {
        let Node {value, prev, next} = table::remove(&mut linked_table.nodes, key);

        if (option::is_none(&prev)) {
            linked_table.first = next;
        } else {
            let prev_node = table::borrow_mut(&mut linked_table.nodes, *option::borrow<K>(&prev));
            prev_node.next = next;
        };

        if (option::is_none(&next)) {
            linked_table.last = prev;
        } else {
            let next_node = table::borrow_mut(&mut linked_table.nodes, *option::borrow<K>(&next));
            next_node.prev = prev;
        };

        value
    }

    public fun contains<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>, key: K): bool {
        table::contains(&linked_table.nodes, key)
    }

    public fun borrow<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>, key: K): &V {
        let Node {
            value,
            prev: _,
            next: _,
        } = table::borrow(&linked_table.nodes, key);

        value
    }

    public fun borrow_mut<K: copy + drop + store, V: store>(linked_table: &mut LinkedTable<K, V>, key: K): &mut V {
        let Node {
            value,
            prev: _,
            next: _,
        } = table::borrow_mut(&mut linked_table.nodes, key);

        value
    }

    public fun prev<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>, key: K): Option<K> {
        let Node {
            value: _,
            prev,
            next: _,
        } = table::borrow(&linked_table.nodes, key);

        *prev
    }

    public fun next<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>, key: K): Option<K> {
        let Node {
            value: _,
            prev: _,
            next,
        } = table::borrow(&linked_table.nodes, key);

        *next
    }

    #[test_only]
    public fun print_list<K: copy + drop + store, V: store>(linked_table: &LinkedTable<K, V>) {
        use std::debug;
        if (option::is_some(&linked_table.first)) {
            let prev_node = table::borrow(&linked_table.nodes, *option::borrow<K>(&linked_table.first));
            debug::print(prev_node);
            while (option::is_some(&prev_node.next)) {
                let node = table::borrow(&linked_table.nodes, *option::borrow<K>(&prev_node.next));
                debug::print(node);
                prev_node = node;
            }
        };
    }
}



#[test_only]
module typus_framework::test_linked_table {
    use sui::test_scenario;
    use typus_framework::linked_table::{Self, LinkedTable};

    #[test]
    fun test(): LinkedTable<address, u64>{

        let admin = @0x1;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let linked_table = linked_table::new<address, u64>(test_scenario::ctx(scenario));

        linked_table::push_back(&mut linked_table, @0x3, 3);
        linked_table::push_back(&mut linked_table, @0x5, 5);
        linked_table::push_front(&mut linked_table, @0x2, 2);
        linked_table::push_front(&mut linked_table, @0x4, 4);
        linked_table::push_back(&mut linked_table, @0x7, 7);

        // linked_table::print_list(&linked_table);
        // 4, 2, 3, 5, 7

        linked_table::remove(&mut linked_table, @0x5);
        linked_table::remove(&mut linked_table, @0x4);
        linked_table::remove(&mut linked_table, @0x7);

        // linked_table::print_list(&linked_table);
        // 2, 3

        test_scenario::end(scenario_val);
        linked_table
    }
}