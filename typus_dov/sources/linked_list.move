module typus_dov::linked_list {
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::{TxContext};

    struct LinkedList<K: copy + drop + store, V: store> has store { 
        first: Option<K>,
        last: Option<K>,
        nodes: Table<K, Node<K, V>>
    }

    struct Node<K: copy + drop + store, V: store> has store { 
        value: V,
        prev: Option<K>,
        next: Option<K>,
    }

    public fun new<K: copy + drop + store, V: store>(ctx: &mut TxContext): LinkedList<K, V> {
        LinkedList<K, V> {
            first: option::none(),
            last: option::none(),
            nodes: table::new<K, Node<K, V>>(ctx)
        }
    }

    public fun first<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>): Option<K> {
        linked_list.first
    }

    public fun last<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>): Option<K> {
        linked_list.last
    }

    public fun length<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>): u64 {
        table::length(&linked_list.nodes)
    }

    public fun is_empty<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>): bool {
        option::is_none(&linked_list.first)
    }

    public fun push_back<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K, value: V) {
        if (option::is_none(&linked_list.first)) {
            linked_list.first = option::some(key);
        };

        let prev = option::none();
        if (option::is_some(&linked_list.last)) {
            prev = linked_list.last;

            let prev_node = table::borrow_mut(&mut linked_list.nodes, *option::borrow<K>(&prev));
            prev_node.next = option::some(key);
        };
    
        let node = Node<K, V> {
            value,
            prev,
            next: option::none(),
        };
        linked_list.last = option::some(key);
        table::add(&mut linked_list.nodes, key, node);
    }

    public fun push_front<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K, value: V) {
        if (option::is_none(&linked_list.last)) {
            linked_list.last = option::some(key);
        };

        let next = option::none();
        if (option::is_some(&linked_list.first)) {
            next = linked_list.first;

            let next_node = table::borrow_mut(&mut linked_list.nodes, *option::borrow<K>(&next));
            next_node.prev = option::some(key);
        };

        let node = Node<K, V> {
            value,
            prev: option::none(),
            next,
        };
        linked_list.first = option::some(key);
        table::add(&mut linked_list.nodes, key, node);
    }

    public fun pop_back<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>): V {
        let key = option::borrow(&linked_list.last);
        remove(linked_list, *key)
    }

    public fun pop_front<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>): V {
        let key = option::borrow(&linked_list.first);
        remove(linked_list, *key)
    }

    public fun remove<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K): V {
        let Node {value, prev, next} = table::remove(&mut linked_list.nodes, key);

        if (option::is_none(&prev)) {
            linked_list.first = next;
        } else {
            let prev_node = table::borrow_mut(&mut linked_list.nodes, *option::borrow<K>(&prev));
            prev_node.next = next;
        };

        if (option::is_none(&next)) {
            linked_list.last = prev;
        } else {
            let next_node = table::borrow_mut(&mut linked_list.nodes, *option::borrow<K>(&next));
            next_node.prev = prev;
        };

        value
    }

    public fun contains<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>, key: K): bool {
        table::contains(&linked_list.nodes, key)
    }

    public fun borrow<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>, key: K): &V {
        let Node {
            value,
            prev: _,
            next: _,
        } = table::borrow(&linked_list.nodes, key);

        value
    }

    public fun borrow_mut<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K): &mut V {
        let Node {
            value,
            prev: _,
            next: _,
        } = table::borrow_mut(&mut linked_list.nodes, key);

        value
    }

    public fun prev<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>, key: K): Option<K> {
        let Node {
            value: _,
            prev,
            next: _,
        } = table::borrow(&linked_list.nodes, key);

        *prev
    }

    public fun next<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>, key: K): Option<K> {
        let Node {
            value: _,
            prev: _,
            next,
        } = table::borrow(&linked_list.nodes, key);

        *next
    }

    #[test_only]
    public fun print_list<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>) {
        use std::debug;
        if (option::is_some(&linked_list.first)) {
            let prev_node = table::borrow(&linked_list.nodes, *option::borrow<K>(&linked_list.first));
            debug::print(prev_node);
            while (option::is_some(&prev_node.next)) {
                let node = table::borrow(&linked_list.nodes, *option::borrow<K>(&prev_node.next));
                debug::print(node);
                prev_node = node;
            }
        };
    }
}



#[test_only]
module typus_dov::test_linked_list {
    use sui::test_scenario;
    use typus_dov::linked_list::{Self, LinkedList};

    #[test]
    fun test(): LinkedList<address, u64>{

        let admin = @0x1;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let linked_list = linked_list::new<address, u64>(test_scenario::ctx(scenario));

        linked_list::push_back(&mut linked_list, @0x3, 3);
        linked_list::push_back(&mut linked_list, @0x5, 5);
        linked_list::push_front(&mut linked_list, @0x2, 2);
        linked_list::push_front(&mut linked_list, @0x4, 4);
        linked_list::push_back(&mut linked_list, @0x7, 7);

        // linked_list::print_list(&linked_list);
        // 4, 2, 3, 5, 7

        linked_list::remove(&mut linked_list, @0x5);
        linked_list::remove(&mut linked_list, @0x4);
        linked_list::remove(&mut linked_list, @0x7);

        // linked_list::print_list(&linked_list);
        // 2, 3

        test_scenario::end(scenario_val);
        linked_list
    }
}