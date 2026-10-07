# UPSTREAM: swipl-devel src/os/pl-ctype.c @ bae881a2
# UPSTREAM: swipl-devel src/os/pl-ctype.h @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# The character types of ASCII (since R1c): `_PL_char_types`, the reader's table for code points
# below 0x80, and the `is*` macros over it; `isBlankW`, which answers for every code point through
# the Unicode map's classes (src/pl-umap.jl). NOT PORTED: `code_type/2`, `char_type/2` and the
# rest of pl-ctype.c (their own step); `initEncoding` (a text stream is UTF-8, src/os/pl-stream.jl).

# PORT: pl-ctype.h CT
"Control character (pl-ctype.h)."
const CT = 0
# PORT: pl-ctype.h SP
"Space (pl-ctype.h)."
const SP = 1
# PORT: pl-ctype.h SO
"Solo character (pl-ctype.h)."
const SO = 2
# PORT: pl-ctype.h SY
"Symbol character (pl-ctype.h)."
const SY = 3
# PORT: pl-ctype.h PU
"Punctuation character (pl-ctype.h)."
const PU = 4
# PORT: pl-ctype.h DQ
"Double quote (pl-ctype.h)."
const DQ = 5
# PORT: pl-ctype.h SQ
"Single quote (pl-ctype.h)."
const SQ = 6
# PORT: pl-ctype.h BQ
"Back quote (pl-ctype.h)."
const BQ = 7
# PORT: pl-ctype.h UC
"Uppercase character (pl-ctype.h)."
const UC = 8
# PORT: pl-ctype.h LC
"Lowercase character (pl-ctype.h)."
const LC = 9
# PORT: pl-ctype.h DI
"Digit (pl-ctype.h)."
const DI = 10

# PORT: pl-ctype.c _PL_char_types
# DIVERGES: a tuple (frozen: no module-level mutable state), 1-based: the type of code c is
# `_PL_char_types[c + 1]`.
"The character type of each ASCII code, 0..127 (pl-ctype.c)."
const _PL_char_types = (
    #= ^@  ^A  ^B  ^C  ^D  ^E  ^F  ^G  ^H  ^I  ^J  ^K  ^L  ^M  ^N  ^O    0-15 =#
    CT, CT, CT, CT, CT, CT, CT, CT, CT, SP, SP, SP, SP, SP, CT, CT,
    #= ^P  ^Q  ^R  ^S  ^T  ^U  ^V  ^W  ^X  ^Y  ^Z  ^[  ^\  ^]  ^^  ^_   16-31 =#
    CT, CT, CT, CT, CT, CT, CT, CT, CT, CT, CT, CT, CT, CT, CT, CT,
    #= sp   !   "   #   $   %   &   '   (   )   *   +   ,   -   .   /   32-47 =#
    SP, SO, DQ, SY, SY, SO, SY, SQ, PU, PU, SY, SY, PU, SY, SY, SY,
    #=  0   1   2   3   4   5   6   7   8   9   :   ;   <   =   >   ?   48-63 =#
    DI, DI, DI, DI, DI, DI, DI, DI, DI, DI, SY, SO, SY, SY, SY, SY,
    #=  @   A   B   C   D   E   F   G   H   I   J   K   L   M   N   O   64-79 =#
    SY, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC,
    #=  P   Q   R   S   T   U   V   W   X   Y   Z   [   \   ]   ^   _   80-95 =#
    UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, UC, PU, SY, PU, SY, UC,
    #=  `   a   b   c   d   e   f   g   h   i   j   k   l   m   n   o   96-111 =#
    BQ, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC,
    #=  p   q   r   s   t   u   v   w   x   y   z   {   |   }   ~  ^?   112-127 =#
    LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, LC, PU, PU, PU, SY, CT
)

# The type of an ASCII code `c` (`_PL_char_types[(unsigned)(c)]`); -1 for any other code.
@inline _char_type(c::Int)::Int = (c % UInt32) < 0x80 ? Int(_PL_char_types[c + 1]) : -1

# PORT: pl-ctype.h isControl
"Is `c` an ASCII control character (pl-ctype.h)?"
isControl(c::Int)::Bool = _char_type(c) == CT
# PORT: pl-ctype.h isBlank
"Is `c` ASCII layout (pl-ctype.h)?"
isBlank(c::Int)::Bool = _char_type(c) == SP
# PORT: pl-ctype.h isGraph
"Is `c` a visible ASCII character (pl-ctype.h)?"
isGraph(c::Int)::Bool = _char_type(c) > SP
# PORT: pl-ctype.h isDigit
"Is `c` an ASCII digit (pl-ctype.h)?"
isDigit(c::Int)::Bool = _char_type(c) == DI
# PORT: pl-ctype.h isLower
"Is `c` an ASCII lowercase letter (pl-ctype.h)?"
isLower(c::Int)::Bool = _char_type(c) == LC
# PORT: pl-ctype.h isUpper
"Is `c` an ASCII uppercase letter or `_` (pl-ctype.h)?"
isUpper(c::Int)::Bool = _char_type(c) == UC
# PORT: pl-ctype.h isSymbol
"Is `c` an ASCII symbol character (pl-ctype.h)?"
isSymbol(c::Int)::Bool = _char_type(c) == SY
# PORT: pl-ctype.h isPunct
"Is `c` ASCII punctuation (pl-ctype.h)?"
isPunct(c::Int)::Bool = _char_type(c) == PU
# PORT: pl-ctype.h isSolo
"Is `c` an ASCII solo character (pl-ctype.h)?"
isSolo(c::Int)::Bool = _char_type(c) == SO
# PORT: pl-ctype.h isAlpha
"Is `c` an ASCII letter, digit or `_` (pl-ctype.h)?"
isAlpha(c::Int)::Bool = _char_type(c) >= UC
# PORT: pl-ctype.h isLetter
"Is `c` an ASCII letter (pl-ctype.h)?"
isLetter(c::Int)::Bool = isLower(c) || isUpper(c)
# PORT: pl-ctype.h isSign
"Is `c` a sign, `-` or `+` (pl-ctype.h)?"
isSign(c::Int)::Bool = c == Int('-') || c == Int('+')
# PORT: pl-ctype.h isDecimal
"Is `c` one of the ten digits from `zero` (pl-ctype.h)?"
isDecimal(zero::Int, c::Int)::Bool = c >= zero && c <= zero + 9

# PORT: pl-ctype.h matchingBracket
"The bracket that closes `c` (`[`, `{` or `(`), else 0 (pl-ctype.h)."
matchingBracket(c::Int)::Int =
    if c == Int('[')
        Int(']')
    elseif c == Int('{')
        Int('}')
    elseif c == Int('(')
        Int(')')
    else
        0
    end

# PORT: pl-ctype.h isBlankW
"Is `c` layout: ASCII by the table, any other code point by its Unicode class (pl-ctype.h)."
isBlankW(c::Int)::Bool =
    (c % UInt32) < 0x80 ? _char_type(c) == SP : (PL_ctype_flags(c) & PL_CTYPE_SPACE) != 0
# PORT: pl-ctype.h isDigitW
"Is `c` an ASCII digit (pl-ctype.h: deliberately ASCII only)?"
isDigitW(c::Int)::Bool = (c % UInt32) < 0x80 ? _char_type(c) == DI : false
# PORT: pl-ctype.h isSymbolW
"Is `c` an ASCII symbol character (pl-ctype.h: deliberately ASCII only)?"
isSymbolW(c::Int)::Bool = (c % UInt32) < 0x80 ? _char_type(c) == SY : false
# PORT: pl-ctype.h isPunctW
"Is `c` ASCII punctuation (pl-ctype.h: deliberately ASCII only)?"
isPunctW(c::Int)::Bool = (c % UInt32) < 0x80 ? _char_type(c) == PU : false
