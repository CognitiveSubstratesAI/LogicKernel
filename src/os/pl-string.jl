# UPSTREAM: swipl-devel src/os/pl-string.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2012, University of Amsterdam
#
# String helpers (since R1c): `digitValue`, the value of a digit in a base, which the reader's
# number scanner reads digits with. NOT PORTED: the rest of pl-string.c (its first reader each).

# PORT: pl-string.c digitValue
"""
The value of character code `c` as a digit of base `b` (pl-string.c): -1 if it is not one. Base 0
is `0'c` (the code itself). As upstream, a code below `'0'` in a base up to 10 gives a negative
value, not -1 (`c - '0'`); its callers test `>= 0`.
"""
function digitValue(b::Int, c::Int)::Int
    b == 0 && return c                      # 0'c
    b == 1 && return -1
    if b <= 10
        v = c - Int('0')
        v < b && return v
        return -1
    end
    c <= Int('9') && return c - Int('0')
    isUpper(c) && (c = c + Int('a') - Int('A'))     # toLower(c)
    c = c - Int('a') + 10
    (c < b && c >= 10) && return c
    return -1
end
