/// Utilities for comparing two vector<u8>.
module typus_dov::compare {
    use std::vector;

    const EQUAL: u8 = 0;
    const LESS_THAN: u8 = 1;
    const GREATER_THAN: u8 = 2;

    /// compare vectors `v1` and `v2` using (1) vector contents from right to left and then
    /// (2) vector length to break ties.
    /// Returns either `EQUAL` (0u8), `LESS_THAN` (1u8), or `GREATER_THAN` (2u8).
    public fun cmp_bcs_bytes(v1: &vector<u8>, v2: &vector<u8>): u8 {
        let i1 = vector::length(v1);
        let i2 = vector::length(v2);
        let len_cmp = cmp_u64(i1, i2);

        // BCS uses little endian encoding for all integer types, so we choose to compare from left
        // to right. Going right to left would make the behavior of compare::cmp diverge from the
        // bytecode operators < and > on integer values (which would be confusing).
        while (i1 > 0 && i2 > 0) {
            i1 = i1 - 1;
            i2 = i2 - 1;
            let elem_cmp = cmp_u8(*vector::borrow(v1, i1), *vector::borrow(v2, i2));
            if (elem_cmp != 0) return elem_cmp
            // else, compare next element
        };
        // all compared elements equal; use length comparion to break the tie
        len_cmp
    }

    /// Compare two `u8`'s
    fun cmp_u8(i1: u8, i2: u8): u8 {
        if (i1 == i2) EQUAL
        else if (i1 < i2) LESS_THAN
        else GREATER_THAN
    }

    /// Compare two `u64`'s
    fun cmp_u64(i1: u64, i2: u64): u8 {
        if (i1 == i2) EQUAL
        else if (i1 < i2) LESS_THAN
        else GREATER_THAN
    }

}