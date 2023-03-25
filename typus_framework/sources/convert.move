module typus_framework::convert{
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

    public fun u256_to_bytes(value: u256): vector<u8> {
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

    public fun u256_to_string(value: u256): String {
        let bytes = u256_to_bytes(value);

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

    public fun string_to_u256(value: String): u256 {
        let result = 0;
        let bytes = string::bytes(&value);
        let index = 0;
        let length = vector::length(bytes);
        while (index < length) {
            let digit = (*vector::borrow(bytes, index) as u256);
            assert!(digit >= 48 && digit <= 57, 0);
            result = result * 10 + (digit - 48);
            index = index + 1;
        };

        result
    }

    #[test]
    fun test_string_number_string_convert() {
        use std::string;

        let max = string::utf8(b"u8 max: ");
        string::append(&mut max, u8_to_string(string_to_u8(string::utf8(b"255"))));
        assert!(*string::bytes(&max) == b"u8 max: 255" , 0);
        let max = string::utf8(b"u16 max: ");
        string::append(&mut max, u16_to_string(string_to_u16(string::utf8(b"65535"))));
        assert!(*string::bytes(&max) == b"u16 max: 65535" , 0);
        let max = string::utf8(b"u32 max: ");
        string::append(&mut max, u32_to_string(string_to_u32(string::utf8(b"4294967295"))));
        assert!(*string::bytes(&max) == b"u32 max: 4294967295" , 0);
        let max = string::utf8(b"u64 max: ");
        string::append(&mut max, u64_to_string(string_to_u64(string::utf8(b"18446744073709551615"))));
        assert!(*string::bytes(&max) == b"u64 max: 18446744073709551615" , 0);
        let max = string::utf8(b"u128 max: ");
        string::append(&mut max, u128_to_string(string_to_u128(string::utf8(b"340282366920938463463374607431768211455"))));
        assert!(*string::bytes(&max) == b"u128 max: 340282366920938463463374607431768211455" , 0);
        let max = string::utf8(b"u256 max: ");
        string::append(&mut max, u256_to_string(string_to_u256(string::utf8(b"115792089237316195423570985008687907853269984665640564039457584007913129639935"))));
        assert!(*string::bytes(&max) == b"u256 max: 115792089237316195423570985008687907853269984665640564039457584007913129639935" , 0);
    }
}