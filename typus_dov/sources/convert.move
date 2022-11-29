module typus_dov::convert{
    use std::string::{Self, String};
    use std::vector;

    const E_NON_NUMBER_CHARACTER: u64 = 0;

    public fun u8_to_bytes(value: u8): vector<u8> {
        let bytes = vector::empty();
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            vector::push_back(&mut bytes, ascii_byte);
            value = value / 10;
        };
        vector::reverse(&mut bytes);

        bytes
    }

    public fun u16_to_bytes(value: u16): vector<u8> {
        let bytes = vector::empty();
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            vector::push_back(&mut bytes, ascii_byte);
            value = value / 10;
        };
        vector::reverse(&mut bytes);

        bytes
    }

    public fun u32_to_bytes(value: u32): vector<u8> {
        let bytes = vector::empty();
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            vector::push_back(&mut bytes, ascii_byte);
            value = value / 10;
        };
        vector::reverse(&mut bytes);

        bytes
    }

    public fun u64_to_bytes(value: u64): vector<u8> {
        let bytes = vector::empty();
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            vector::push_back(&mut bytes, ascii_byte);
            value = value / 10;
        };
        vector::reverse(&mut bytes);

        bytes
    }

    public fun u128_to_bytes(value: u128): vector<u8> {
        let bytes = vector::empty();
        while (value > 0) {
            let ascii_byte = ((value % 10 + 48) as u8);
            vector::push_back(&mut bytes, ascii_byte);
            value = value / 10;
        };
        vector::reverse(&mut bytes);

        bytes
    }

    public fun u8_to_string(value: u8): String {
        let bytes = u8_to_bytes(value);

        string::utf8(bytes)
    }

    public fun u16_to_string(value: u16): String {
        let bytes = u16_to_bytes(value);

        string::utf8(bytes)
    }

    public fun u32_to_string(value: u32): String {
        let bytes = u32_to_bytes(value);

        string::utf8(bytes)
    }

    public fun u64_to_string(value: u64): String {
        let bytes = u64_to_bytes(value);

        string::utf8(bytes)
    }

    public fun u128_to_string(value: u128): String {
        let bytes = u128_to_bytes(value);

        string::utf8(bytes)
    }

    public fun string_to_u8(value: String): u8 {
        let result = 0;
        let bytes = string::bytes(&value);
        let index = 0;
        let length = vector::length(bytes);
        while (index < length) {
            let digit = (*vector::borrow(bytes, index) as u8);
            assert!(digit >= 48 && digit <= 57, 0);
            result = result * 10 + (digit - 48);
            index = index + 1;
        };

        result
    }

    public fun string_to_u16(value: String): u16 {
        let result = 0;
        let bytes = string::bytes(&value);
        let index = 0;
        let length = vector::length(bytes);
        while (index < length) {
            let digit = (*vector::borrow(bytes, index) as u16);
            assert!(digit >= 48 && digit <= 57, 0);
            result = result * 10 + (digit - 48);
            index = index + 1;
        };

        result
    }

    public fun string_to_u32(value: String): u32 {
        let result = 0;
        let bytes = string::bytes(&value);
        let index = 0;
        let length = vector::length(bytes);
        while (index < length) {
            let digit = (*vector::borrow(bytes, index) as u32);
            assert!(digit >= 48 && digit <= 57, 0);
            result = result * 10 + (digit - 48);
            index = index + 1;
        };

        result
    }

    public fun string_to_u64(value: String): u64 {
        let result = 0;
        let bytes = string::bytes(&value);
        let index = 0;
        let length = vector::length(bytes);
        while (index < length) {
            let digit = (*vector::borrow(bytes, index) as u64);
            assert!(digit >= 48 && digit <= 57, 0);
            result = result * 10 + (digit - 48);
            index = index + 1;
        };

        result
    }

    public fun string_to_u128(value: String): u128 {
        let result = 0;
        let bytes = string::bytes(&value);
        let index = 0;
        let length = vector::length(bytes);
        while (index < length) {
            let digit = (*vector::borrow(bytes, index) as u128);
            assert!(digit >= 48 && digit <= 57, 0);
            result = result * 10 + (digit - 48);
            index = index + 1;
        };

        result
    }

    #[test]
    fun test_string_number_string_convert() {
        use std::debug;
        use std::string;

        let max = string::utf8(b"u8 max: ");
        string::append(&mut max, u8_to_string(string_to_u8(string::utf8(b"255"))));
        debug::print(&max);
        let max = string::utf8(b"u16 max: ");
        string::append(&mut max, u16_to_string(string_to_u16(string::utf8(b"65535"))));
        debug::print(&max);
        let max = string::utf8(b"u32 max: ");
        string::append(&mut max, u32_to_string(string_to_u32(string::utf8(b"4294967295"))));
        debug::print(&max);
        let max = string::utf8(b"u64 max: ");
        string::append(&mut max, u64_to_string(string_to_u64(string::utf8(b"18446744073709551615"))));
        debug::print(&max);
        let max = string::utf8(b"u128 max: ");
        string::append(&mut max, u128_to_string(string_to_u128(string::utf8(b"340282366920938463463374607431768211455"))));
        debug::print(&max);
    }
}