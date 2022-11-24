module typus_dov::convert{
    use std::string::{Self, String};
    use std::vector;

    public fun u8_to_string(value: u8): String {
        let result = string::utf8(vector::empty());
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            string::insert(&mut result, 0, string::utf8(vector::singleton(ascii_byte)));
            value = value / 10;
        };

        result
    }

    public fun u16_to_string(value: u16): String {
        let result = string::utf8(vector::empty());
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            string::insert(&mut result, 0, string::utf8(vector::singleton(ascii_byte)));
            value = value / 10;
        };

        result
    }

    public fun u32_to_string(value: u32): String {
        let result = string::utf8(vector::empty());
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            string::insert(&mut result, 0, string::utf8(vector::singleton(ascii_byte)));
            value = value / 10;
        };

        result
    }

    public fun u64_to_string(value: u64): String {
        let result = string::utf8(vector::empty());
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            string::insert(&mut result, 0, string::utf8(vector::singleton(ascii_byte)));
            value = value / 10;
        };

        result
    }

    public fun u128_to_string(value: u128): String {
        let result = string::utf8(vector::empty());
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            string::insert(&mut result, 0, string::utf8(vector::singleton(ascii_byte)));
            value = value / 10;
        };

        result
    }
}