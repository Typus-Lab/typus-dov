module typus_dov::doubly_linked_list {
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::{TxContext};

    struct LinkedList<K: copy + drop + store, V: store> has store { 
        first: Option<K>,
        last: Option<K>,
        table: Table<K, LinkedNode<K, V>>
    }

    struct LinkedNode<K: copy + drop + store, V: store> has store { 
        value: V,
        prev: Option<K>,
        next: Option<K>,
    }

    public fun new<K: copy + drop + store, V: store>(ctx: &mut TxContext): LinkedList<K, V> {
        LinkedList<K, V> {
            first: option::none(),
            last: option::none(),
            table: table::new<K, LinkedNode<K, V>>(ctx)
        }
    }

    public fun push_back<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K, value: V) {
        if (option::is_none(&linked_list.first)) {
            linked_list.first = option::some(key);
        };

        let prev = option::none();
        if (option::is_some(&linked_list.last)) {
            prev = linked_list.last;

            let prev_node = table::borrow_mut(&mut linked_list.table, *option::borrow<K>(&prev));
            prev_node.next = option::some(key);
        };
    
        let node = LinkedNode<K, V> {
            value,
            prev,
            next: option::none(),
        };
        linked_list.last = option::some(key);
        table::add(&mut linked_list.table, key, node);
    }

    public fun push_front<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K, value: V) {
        if (option::is_none(&linked_list.last)) {
            linked_list.last = option::some(key);
        };

        let next = option::none();
        if (option::is_some(&linked_list.first)) {
            next = linked_list.first;

            let next_node = table::borrow_mut(&mut linked_list.table, *option::borrow<K>(&next));
            next_node.prev = option::some(key);
        };

        let node = LinkedNode<K, V> {
            value,
            prev: option::none(),
            next,
        };
        linked_list.first = option::some(key);
        table::add(&mut linked_list.table, key, node);
    }

    public fun remove<K: copy + drop + store, V: store>(linked_list: &mut LinkedList<K, V>, key: K): V {
        let LinkedNode {value, prev, next} = table::remove(&mut linked_list.table, key);

        if (option::is_none(&prev)) {
            linked_list.first = next;
        } else {
            let prev_node = table::borrow_mut(&mut linked_list.table, *option::borrow<K>(&prev));
            prev_node.next = next;
        };

        if (option::is_none(&next)) {
            linked_list.last = prev;
        } else {
            let next_node = table::borrow_mut(&mut linked_list.table, *option::borrow<K>(&next));
            next_node.prev = prev;
        };

        value
    }

    #[test_only]
    public fun print_list<K: copy + drop + store, V: store>(linked_list: &LinkedList<K, V>) {
        use std::debug;
        if (option::is_some(&linked_list.first)) {
            let prev_node = table::borrow(&linked_list.table, *option::borrow<K>(&linked_list.first));
            debug::print(prev_node);
            while (option::is_some(&prev_node.next)) {
                let node = table::borrow(&linked_list.table, *option::borrow<K>(&prev_node.next));
                debug::print(node);
                prev_node = node;
            }
        };
    }
}



#[test_only]
module typus_dov::test_linked_list {
    use sui::test_scenario;
    use typus_dov::doubly_linked_list::{Self, LinkedList};

    #[test]
    fun test(): LinkedList<address, u64>{

        let admin = @0x1;
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let linked_list = doubly_linked_list::new<address, u64>(test_scenario::ctx(scenario));

        doubly_linked_list::push_back(&mut linked_list, @0x3, 3);
        doubly_linked_list::push_back(&mut linked_list, @0x5, 5);
        doubly_linked_list::push_front(&mut linked_list, @0x2, 2);
        doubly_linked_list::push_front(&mut linked_list, @0x4, 4);
        doubly_linked_list::push_back(&mut linked_list, @0x7, 7);

        doubly_linked_list::print_list(&linked_list); 
        // 4, 2, 3, 5, 7

        doubly_linked_list::remove(&mut linked_list, @0x5);
        doubly_linked_list::remove(&mut linked_list, @0x4);
        doubly_linked_list::remove(&mut linked_list, @0x7);

        doubly_linked_list::print_list(&linked_list);
        // 2, 3

        test_scenario::end(scenario_val);
        linked_list
    }
}