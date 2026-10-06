# UPSTREAM: swipl-devel src/pl-arith.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-arith.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-inline.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SWI-Prolog's arithmetic (pl-arith.c), V6c: evaluating an expression (`valueExpression`,
# `evalExpression`) into a `number` (src/pl-incl.jl; the number core is src/pl-gmp.jl), the
# functions the programs reach (`+`, `-`, `*`, unary `-` and `+`), comparing (`compareNumbers`), and
# the built-ins `is/2`, `</2`, `>/2`, `=</2`, `>=/2`, `=\=/2`, `=:=/2`.
#
# DIVERGES (file-wide):
#   * The functions are the PORTED entries of upstream's table (`ar_funcdefs`), found by their
#     name's key and arity (`isCurrentArithFunction`), where upstream indexes a table in GD by the
#     functor table's index — the kernel has no functor table, and a built-in gets only `ld`. They
#     are called through a branch on the entry, where upstream holds a function pointer.
#   * Upstream's `number`s are C locals and segstacks; here they are records POOLED in the local data
#     (`_number_alloc!`, `_number_free!`, a stack discipline), so the Int64 path allocates nothing
#     but its result term.
#   * `AR_CTX`/`AR_BEGIN`/`AR_END`/`AR_CLEANUP` (GMP memory tracking and the float rounding mode)
#     have nothing to do: Julia's GC frees a `BigInt`, and only `roundtoward/2`, not ported, sets the
#     rounding mode.
#   * The flags: `LD->arith.f.flags` at upstream's default (`float_overflow`, `float_zero_div` and
#     `float_undefined` = error, `float_underflow` = ignore); `prefer_rationals` and `iso` are false,
#     as their defaults — nothing sets a flag (no `set_prolog_flag/2` yet).

# ── the pooled numbers (the kernel's C stack) ────────────────────────────────────────────────────
# A number from the local data's pool, above those in use; `_number_free!` releases the newest `k`.
function _number_alloc!(ld::PL_local_data)::number
    ld.arith_top += 1
    if ld.arith_top > length(ld.arith_numbers)
        push!(ld.arith_numbers, number())
    end
    return ld.arith_numbers[ld.arith_top]
end

function _number_free!(ld::PL_local_data, k::Int)::Nothing
    ld.arith_top -= k
    return nothing
end

# PORT: pl-arith.c cpNumber
"Copy number `from` into `to` (pl-arith.c `cpNumber`): the fields, the values shared (immutable)."
function cpNumber(to::number, from::number)::Nothing
    to.type = from.type
    to.i = from.i
    to.f = from.f
    to.mpz = from.mpz
    to.mpq = from.mpq
    return nothing
end

# ── float checks (pl-arith.c) ────────────────────────────────────────────────────────────────────
# PORT: pl-arith.h FLT_ROUND_NEAREST
"Round to nearest (pl-arith.h), the rounding the kernel has."
const FLT_ROUND_NEAREST = UInt32(0x0001)
# PORT: pl-arith.h FLT_OVERFLOW
"`float_overflow=infinity` (pl-arith.h)."
const FLT_OVERFLOW = UInt32(0x0010)
# PORT: pl-arith.h FLT_ZERO_DIV
"`float_zero_div=infinity` (pl-arith.h)."
const FLT_ZERO_DIV = UInt32(0x0020)
# PORT: pl-arith.h FLT_UNDEFINED
"`float_undefined=nan` (pl-arith.h)."
const FLT_UNDEFINED = UInt32(0x0040)
# PORT: pl-arith.h FLT_UNDERFLOW
"`float_underflow=ignore` (pl-arith.h)."
const FLT_UNDERFLOW = UInt32(0x0080)

# DIVERGES: `nan15()` reads "1.5NaN" with the number reader, which the kernel does not have yet
# (R1); that is the quiet NaN, 0x7ff8000000000000 — Julia's `NaN`.
"The NaN `float_undefined=nan` gives (pl-arith.c `const_nan`)."
const const_nan = NaN

# PORT: pl-arith.c check_float
"Check a float result against the float flags (pl-arith.c): NaN, subnormal, infinite."
function check_float(ld::PL_local_data, n::number)::Bool
    code = if issubnormal(n.f)
        ERR_AR_UNDERFLOW
    elseif isnan(n.f)
        ERR_AR_UNDEF
    elseif isinf(n.f)
        ERR_AR_OVERFLOW
    else
        nothing
    end
    code === nothing && return true
    if code === ERR_AR_OVERFLOW
        (ld.arith_f_flags & FLT_OVERFLOW) != 0 && return true
    elseif code === ERR_AR_UNDERFLOW
        (ld.arith_f_flags & FLT_UNDERFLOW) != 0 && return true
    else                                                    # ERR_AR_UNDEF
        n.f = const_nan
        (ld.arith_f_flags & FLT_UNDEFINED) != 0 && return true
    end
    return PL_error(ld, code)
end

# PORT: pl-arith.c check_mpq
# DIVERGES: `max_rational_size` is unlimited (its default), so there is nothing to check.
"Check a rational result against `max_rational_size` (pl-arith.c): unlimited."
check_mpq(n::number)::Bool = true

# PORT: pl-arith.c int_too_big
# NOT PORTED: the global stack's resource error (`outOfStack`), until G1, as decided since Q-C: the
# kernel has no global stack, and G1 accounts the binding store and trail against `stack_limit`.
# Here a `NotPortedError` — loud: the query closes (decision 1) — never GMP's `abort()`.
"An integer too big to create (pl-arith.c `int_too_big`): see above."
function int_too_big(ld::PL_local_data{T})::Bool where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :int_too_big),
            "the resource error of an integer too big (int_too_big)",
            "G1"
        )
    )
end

# PORT: pl-arith.c int_bits_ok
"Whether an integer of `bits` bits (an upper bound) may be created (pl-arith.c): GMP aborts on one too big."
int_bits_ok(ld::PL_local_data, bits::UInt64)::Bool =
    bits <= 10000 || bits ÷ 8 <= maxBigIntSize(ld)

# PORT: pl-arith.c check_int_bits
"`int_bits_ok`, else `int_too_big` (pl-arith.c)."
check_int_bits(ld::PL_local_data, bits::UInt64)::Bool =
    int_bits_ok(ld, bits) ? true : int_too_big(ld)

# ── the functions (pl-arith.c) ──────────────────────────────────────────────────────────────────
# PORT: pl-arith.c promoteIntNumber
"Promote a `V_INTEGER` to more capacity (pl-arith.c; O_BIGNUM: `V_MPZ`)."
promoteIntNumber(n::number)::Bool = promoteToMPZNumber(n)

# PORT: pl-arith.c ar_add_si
"`n += add` in place (pl-arith.c `ar_add_si`): A_ADD_FC's slow path."
function ar_add_si(ld::PL_local_data, n::number, add::Int64)::Bool
    t = n.type
    if t === V_INTEGER
        r, overflow = Base.Checked.add_with_overflow(n.i, add)   # __builtin_saddll_overflow
        if !overflow
            n.i = r
            return true
        end
        promoteIntNumber(n) || return false
        t = V_MPZ                                           # FALLTHROUGH
    end
    if t === V_MPZ
        n.mpz = n.mpz + add                                 # mpz_add_si
        return true
    elseif t === V_MPQ                                      # mpz_addmul_ui / mpz_submul_ui
        n.mpq = Rational{BigInt}(
            numerator(n.mpq) + denominator(n.mpq) * add, denominator(n.mpq)
        )
        return check_mpq(n)
    end
    n.f += Float64(add)                                     # V_FLOAT
    return check_float(ld, n)
end

# PORT: pl-arith.c pl_ar_add
"`+/2` (pl-arith.c `pl_ar_add`): `r = n1 + n2`."
function pl_ar_add(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    same_type_numbers(ld, n1, n2) || return false
    t = n1.type
    if t === V_INTEGER
        v, overflow = Base.Checked.add_with_overflow(n1.i, n2.i)   # __builtin_saddll_overflow
        if !overflow
            r.i = v
            r.type = V_INTEGER
            return true
        end
        (promoteIntNumber(n1) && promoteIntNumber(n2)) || return false
        t = V_MPZ                                           # FALLTHROUGH
    end
    if t === V_MPZ
        r.type = V_MPZ
        r.mpz = n1.mpz + n2.mpz                             # mpz_add
        return true
    elseif t === V_MPQ
        r.type = V_MPQ
        r.mpq = n1.mpq + n2.mpq                             # mpq_add
        return check_mpq(r)
    end
    r.f = n1.f + n2.f                                       # V_FLOAT
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_minus
"`-/2` (pl-arith.c `ar_minus`): `r = n1 - n2`."
function ar_minus(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    same_type_numbers(ld, n1, n2) || return false
    t = n1.type
    if t === V_INTEGER
        r.i = reinterpret(Int64, reinterpret(UInt64, n1.i) - reinterpret(UInt64, n2.i))
        if (n1.i >= 0 && n2.i < 0 && r.i <= 0) || (n1.i < 0 && n2.i > 0 && r.i >= 0)
            (promoteIntNumber(n1) && promoteIntNumber(n2)) || return false  # overflow
            t = V_MPZ                                       # FALLTHROUGH
        else
            r.type = V_INTEGER
            return true
        end
    end
    if t === V_MPZ
        r.type = V_MPZ
        r.mpz = n1.mpz - n2.mpz                             # mpz_sub
        return true
    elseif t === V_MPQ
        r.type = V_MPQ
        r.mpq = n1.mpq - n2.mpq                             # mpq_sub
        return check_mpq(r)
    end
    r.f = n1.f - n2.f                                       # V_FLOAT
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c mul64
"`x * y` into `r[]` unless it overflows (pl-arith.c; `__builtin_mul_overflow`)."
mul64(x::Int64, y::Int64)::Tuple{Int64, Bool} = Base.Checked.mul_with_overflow(x, y)

# PORT: pl-arith.c ar_mul
"`*/2` (pl-arith.c `ar_mul`): `r = n1 * n2`."
function ar_mul(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    same_type_numbers(ld, n1, n2) || return false
    t = n1.type
    if t === V_INTEGER
        v, overflow = mul64(n1.i, n2.i)
        if !overflow
            r.i = v
            r.type = V_INTEGER
            return true
        end
        promoteToMPZNumber(n1)                              # FALLTHROUGH
        promoteToMPZNumber(n2)
        t = V_MPZ
    end
    if t === V_MPZ
        bits = UInt64(ndigits(n1.mpz; base=2)) + UInt64(ndigits(n2.mpz; base=2))
        check_int_bits(ld, bits) || return false
        r.type = V_MPZ
        r.mpz = n1.mpz * n2.mpz                             # mpz_mul
        return true
    elseif t === V_MPQ
        r.type = V_MPQ
        r.mpq = n1.mpq * n2.mpq                             # mpq_mul
        return check_mpq(r)
    end
    r.f = n1.f * n2.f                                       # V_FLOAT
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_u_minus
"`-/1` (pl-arith.c `ar_u_minus`): `r = -n1`; the most negative integer becomes a bigint."
function ar_u_minus(n1::number, r::number)::Bool
    r.type = n1.type
    t = n1.type
    if t === V_INTEGER
        if n1.i == typemin(Int64)                           # PLMININT
            promoteToMPZNumber(n1)
            r.type = V_MPZ
            t = V_MPZ                                       # FALLTHROUGH
        else
            r.i = -n1.i
            return true
        end
    end
    if t === V_MPZ
        r.mpz = -n1.mpz                                     # mpz_neg
    elseif t === V_MPQ
        r.mpq = -n1.mpq                                     # mpq_neg
        return check_mpq(r)
    else
        r.f = isnan(n1.f) ? n1.f : -n1.f                    # V_FLOAT
        r.type = V_FLOAT
    end
    return true
end

# PORT: pl-arith.c ar_u_plus
"`+/1` (pl-arith.c `ar_u_plus`): `r = n1`."
function ar_u_plus(n1::number, r::number)::Bool
    cpNumber(r, n1)
    return true
end

# PORT: pl-incl.h TOINT_CONVERT_FLOAT
"`toIntegerNumber`: convert a float with no fractional part (pl-incl.h)."
const TOINT_CONVERT_FLOAT = 0x1
# PORT: pl-incl.h TOINT_TRUNCATE
"`toIntegerNumber`: truncate a float (pl-incl.h)."
const TOINT_TRUNCATE = 0x2

# PORT: pl-arith.c double_in_int64_range
"Whether the double `x` converts to an `int64_t` (pl-arith.c)."
function double_in_int64_range(x::Float64)::Bool
    y, k = frexp(x)
    k < 64 && return true
    return k == 64 && y == -0.5                             # x == INT64_MIN
end

# PORT: pl-arith.c toIntegerNumber
"Make `n` an integer in place where `flags` allow (pl-arith.c): a rational of denominator 1, a float."
function toIntegerNumber(ld::PL_local_data, n::number, flags::Integer)::Bool
    t = n.type
    (t === V_INTEGER || t === V_MPZ) && return true
    if t === V_MPQ                                          # never from stacks iff integer
        if denominator(n.mpq) == 1
            n.mpz = numerator(n.mpq)
            n.type = V_MPZ
            return true
        end
        return false
    end
    check_float(ld, n) || return false                      # V_FLOAT
    if (flags & TOINT_CONVERT_FLOAT) != 0
        if double_in_int64_range(n.f)
            l = trunc(Int64, n.f)                           # (int64_t)n->value.f: in range
            if (flags & TOINT_TRUNCATE) != 0 || Float64(l) == n.f
                n.i = l
                n.type = V_INTEGER
                return true
            end
            return false
        end
        n.mpz = BigInt(n.f)                                 # mpz_init_set_d
        n.type = V_MPZ
        return true
    end
    return false
end

# PORT: pl-arith.c ar_sign_i
"The sign of the rational `n1` (pl-arith.c): -1, 0 or 1."
function ar_sign_i(n1::number)::Int
    t = n1.type
    t === V_INTEGER && return if n1.i < 0
        -1
    elseif n1.i > 0
        1
    else
        0
    end
    # `sign` of a BigInt is a BigInt: GMP's mpz_cmp_si reads the sign without one
    t === V_MPZ && return sign(cmp(n1.mpz, 0))              # mpz_sgn
    return sign(cmp(numerator(n1.mpq), 0))                  # mpq_sgn: a denominator is > 0
end

# PORT: pl-arith.c shift_to_far
"A shift by more than a `long` (pl-arith.c): a left one is too big, a right one gives 0."
function shift_to_far(ld::PL_local_data, shift::number, r::number, dir::Int)::Bool
    ar_sign_i(shift) * dir < 0 && return int_too_big(ld)    # <<
    r.i = 0
    r.type = V_INTEGER
    return true
end

# PORT: pl-inline.h MSB64
"The index of the most significant bit of `i` > 0 (pl-inline.h)."
MSB64(i::Int64)::Int = 63 - leading_zeros(i)

# PORT: pl-arith.c ar_shift
# DIVERGES: upstream's `V_INTEGER` branch checks the amount against `LONG_MIN`/`LONG_MAX`; the
# kernel takes LP64's `long`, an `Int64`, where that check can never fire, and drops it. Otherwise as
# upstream, `O_BIGNUM_PRECHECK_ALLOCATIONS` on (pl-arith.c:84): a left shift's size is checked
# before GMP is asked. Julia's `BigInt` needs no `mpz_init`/`mpz_clear`.
"`n1 << n2` (`dir` -1) or `n1 >> n2` (`dir` 1) (pl-arith.c `ar_shift`)."
function ar_shift(
    ld::PL_local_data{T}, n1::number, n2::number, r::number, dir::Int
)::Bool where {T}
    plop = dir < 0 ? "<<" : ">>"
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, plop, 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, plop, 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    if ar_sign_i(n1) == 0                                   # shift of 0 is always 0
        r.i = 0
        r.type = V_INTEGER
        return true
    end
    if n2.type === V_INTEGER                                # amount to shift
        shift = n2.i
    else
        (n2.mpz < typemin(Int64) || n2.mpz > typemax(Int64)) &&
            return shift_to_far(ld, n2, r, dir)
        shift = Int64(n2.mpz)
    end
    if shift < 0
        shift = -shift
        dir = -dir
    end
    if n1.type === V_INTEGER
        if dir < 0                                          # shift left (<<)
            bits = UInt64(shift) + UInt64(
                if n1.i >= 0
                    MSB64(n1.i)
                elseif n1.i == typemin(Int64)
                    64
                else
                    MSB64(-n1.i)
                end
            )
            if bits >= 63                                   # sizeof(int64_t)*8-1
                promoteToMPZNumber(n1)
                @goto mpz
            end
            r.i = reinterpret(Int64, reinterpret(UInt64, n1.i) << shift)
        else                                                # shift right (>>)
            r.i = shift >= 64 ? (n1.i >= 0 ? 0 : -1) : n1.i >> shift
        end
        r.type = V_INTEGER
        return true
    end
    @label mpz
    r.type = V_MPZ
    if dir < 0                                              # shift left (<<)
        msb = UInt64(ndigits(n1.mpz; base=2)) + UInt64(shift)
        check_int_bits(ld, msb) || return false
        r.mpz = n1.mpz << shift                             # mpz_mul_2exp
    else
        r.mpz = n1.mpz >> shift                             # mpz_fdiv_q_2exp: floor
    end
    return true
end

# PORT: pl-arith.c ar_shift_left
"`<</2` (pl-arith.c)."
ar_shift_left(ld::PL_local_data, n1::number, n2::number, r::number)::Bool =
    ar_shift(ld, n1, n2, r, -1)

# PORT: pl-arith.c ar_shift_right
"`>>/2` (pl-arith.c)."
ar_shift_right(ld::PL_local_data, n1::number, n2::number, r::number)::Bool =
    ar_shift(ld, n1, n2, r, 1)

# PORT: pl-arith.c ar_funcdefs
# DIVERGES: the entries ported so far, in upstream's order, `(name, arity)`; see the file header.
"pl-arith.c's `ar_funcdefs[]`: the arithmetic functions, the ported entries."
const ar_funcdefs = ((:+, 2), (:-, 2), (:*, 2), (:-, 1), (:+, 1), (:>>, 2), (:<<, 2))

# PORT: pl-arith.c isCurrentArithFunction
# DIVERGES: the function is `ar_funcdefs`' entry for the name's key and the arity, 0 for none —
# where upstream indexes GD's table by the functor (see the file header).
"The `ar_funcdefs` entry of the function `name/arity` in term type `T`, 0 if none (pl-arith.c)."
function isCurrentArithFunction(::Type{T}, name::UInt64, arity::Int)::Int where {T}
    for k in 1:length(ar_funcdefs)
        f, a = ar_funcdefs[k]
        a == arity && name == sym_key(mk_sym(T, f)) && return k
    end
    return 0
end

# The call of `ar_funcdefs` entry `k` (upstream's `(*(ArithF2)f)(a0, a1, n)` and arity 1).
function _ar_call2(ld::PL_local_data, k::Int, a0::number, a1::number, r::number)::Bool
    k == 1 && return pl_ar_add(ld, a0, a1, r)
    k == 2 && return ar_minus(ld, a0, a1, r)
    k == 6 && return ar_shift_right(ld, a0, a1, r)
    k == 7 && return ar_shift_left(ld, a0, a1, r)
    return ar_mul(ld, a0, a1, r)                            # k == 3
end
function _ar_call1(k::Int, a0::number, r::number)::Bool
    k == 4 && return ar_u_minus(a0, r)
    return ar_u_plus(a0, r)                                 # k == 5
end

# ── characters (pl-arith.c) ──────────────────────────────────────────────────────────────────────
# PORT: pl-arith.c arithChar
# NOT PORTED: a one-character ATOM (`X is [a]`), until R1: it needs the atom's text (`charCode`),
# which the term interface gives from R1's `sym_text` on, as decided since Q-AR7. It is refused
# (`NotPortedError`), never answered wrongly. A code point is as upstream.
"The character code `p` stands for in `[X]` (pl-arith.c): a code point (an atom: refused until R1); -1 after raising."
function arithChar(ld::PL_local_data{T}, p::T)::Int where {T}
    p = deRef(ld, p)
    if number_kind(p) === NUM_INTEGER && integer_is_int64(p)    # isTaggedInt(*p)
        chr = int64_value(p)
        0 <= chr <= 0x10ffff && return Int(chr)             # VALID_CODE_POINT(chr)
    elseif kind(p) === SYM && !is_reserved_symbol(p)        # isAtom(*p): charCode(*p); `[]`: -1
        throw(
            NotPortedError{T}(
                p, "a one-character atom in [X] (charCode: no atom text)", "R1"
            )
        )
    end
    _ar_type_error(ld, :character, p)                       # ERR_TYPE, ATOM_character
    return -1                                               # EOF
end

# PORT: pl-arith.c getCharExpression
"A one-character string, or `[X]`, as its character code in `r` (pl-arith.c); false after raising."
function getCharExpression(ld::PL_local_data{T}, p::T, r::number)::Bool where {T}
    if isString(p)                                          # TAG_STRING
        s = string_value(p)
        if length(s) == 1
            r.i = Int64(s[1])
            r.type = V_INTEGER
            return true
        end
        return _len_not_one(ld, p)
    end
    chr = arithChar(ld, child(p, 2))                        # TAG_COMPOUND: argTermP(w, 0)
    chr == -1 && return false
    is_nil(deRef(ld, child(p, 3))) || return _len_not_one(ld, p)   # argTermP(w, 1)
    r.i = Int64(chr)
    r.type = V_INTEGER
    return true
end

# getCharExpression's `len_not_one:`.
function _len_not_one(ld::PL_local_data{T}, p::T)::Bool where {T}
    a = new_term_ref(ld)
    ld.slots[a + 1] = p
    PL_error(ld, "", 0, "\"x\" must hold one character", ERR_TYPE, mk_sym(T, :character), a)
    return false
end

# ── evaluation (pl-arith.c) ──────────────────────────────────────────────────────────────────────
# PORT: pl-arith.c evalExpression
# DIVERGES: an AGENDA of compounds and the argument being evaluated (`ld.arith_frames`) where
# upstream walks the argument cells by address (`*--p` back to the functor word) — in upstream's
# order, LAST argument first, which decides which error a bad expression raises; every child is
# dereferenced through the bindings. The evaluated arguments are on the pooled stack, the FIRST
# argument on top (upstream's `topsOfSegStack`), and a function's result replaces them. No signals
# and no `TAG_REFERENCE` walk (no cells); `roundtoward/2` is not ported. Kernel-only terms (Q-AR5,
# `# DIVERGES`): a grounded value of no SWI type takes the non-text-atom branch,
# `type_error(evaluable, V)`; a compound whose head is not a symbol (`$expr/n`) evaluates its
# arguments and then is not evaluable, `'$expr'/n`.
"Evaluate the expression term reference `expr` refers to into `result` (pl-arith.c); false after raising."
function evalExpression(ld::PL_local_data{T}, expr::term_t, result::number)::Bool where {T}
    frames = ld.arith_frames
    fbase = length(frames)
    mark = ld.arith_top
    n_tmp = _number_alloc!(ld)                              # number n_tmp
    n = result                                              # number *n = result
    pushed = 0
    known_acyclic = false
    start = deRef(ld, ld.slots[expr + 1])
    p = start
    @label next_term
    k = kind(p)
    if k === GND
        nk = number_kind(p)
        if nk === NUM_INTEGER || nk === NUM_RATIONAL        # TAG_INTEGER
            get_rational(p, n)
        elseif nk === NUM_FLOAT                             # TAG_FLOAT
            n.f = float_value(p)
            n.type = V_FLOAT
        elseif nk === NUM_STRING                            # TAG_STRING
            getCharExpression(ld, p, n) || @goto error
        else                                                # NUM_OTHER: a non-text blob (Q-AR5)
            _ar_type_error(ld, :evaluable, p)
            @goto error
        end
    elseif k === VAR                                        # TAG_VAR
        PL_error(ld, ERR_INSTANTIATION)
        @goto error
    elseif k === SYM                                        # TAG_ATOM: no arity-0 function is ported
        if isTextAtom(p)
            PL_error(ld, ERR_NOT_EVALUABLE, (p, 0))
        else
            _ar_type_error(ld, :evaluable, p)
        end
        @goto error
    else                                                    # TAG_COMPOUND
        arity = nchildren(p) - 1
        if is_pair(p)                                       # FUNCTOR_dot2
            getCharExpression(ld, p, n) || @goto error
        elseif arity == 0                                   # arity0: no function, not a text atom
            _ar_type_error(ld, :evaluable, p)
            @goto error
        else
            push!(frames, (p, arity))                       # pushForMark(&term_stack, p, …)
            pushed += 1
            if pushed % 1024 == 0 && pushed > 1000 && !known_acyclic
                if is_acyclic(ld, start)
                    known_acyclic = true
                else
                    PL_error(
                        ld, "", 0, "cyclic term", ERR_TYPE, mk_sym(T, :expression), expr
                    )
                    @goto error
                end
            end
            p = deRef(ld, child(p, arity + 1))              # p = &term->arguments[arity-1]
            n = n_tmp
            @goto next_term
        end
    end
    length(frames) == fbase && @goto done                   # p == start: a leaf
    cpNumber(_number_alloc!(ld), n_tmp)                     # pushSegStack(&arg_stack, n_tmp)
    @label next_arg
    c, i = frames[end]
    if i > 1                                                # *--p: the previous argument
        frames[end] = (c, i - 1)
        p = deRef(ld, child(c, i))
        @goto next_term
    end
    arity = nchildren(c) - 1                                # *--p: the functor — apply it
    h = child(c, 1)
    f = kind(h) === SYM ? isCurrentArithFunction(T, sym_key(h), arity) : 0
    if f == 0
        PL_error(
            ld,
            ERR_NOT_EVALUABLE,
            (kind(h) === SYM ? h : mk_sym(T, Symbol("\$expr")), arity)
        )
        @goto error
    end
    top = ld.arith_top
    a0 = ld.arith_numbers[top]                              # a[0], the first argument
    if arity == 1
        _ar_call1(f, a0, n_tmp) || @goto error
        cpNumber(a0, n_tmp)                                 # *a0 = *n
    else                                                    # arity 2: no arity-3 function is ported
        a1 = ld.arith_numbers[top - 1]
        _ar_call2(ld, f, a0, a1, n_tmp) || @goto error
        ld.arith_top = top - 1                              # popTopOfSegStack
        cpNumber(a1, n_tmp)                                 # *n1 = *n
    end
    pop!(frames)                                            # popForMark(&term_stack, &p, …)
    if length(frames) == fbase                              # p == start
        cpNumber(result, n_tmp)                             # *result = *n
        @goto done
    end
    @goto next_arg
    @label done
    ld.arith_top = mark
    return true
    @label error
    resize!(frames, fbase)                                  # clearSegStack(&term_stack)
    ld.arith_top = mark                                     # popSegStack(&arg_stack, …)
    return false
end

# `PL_error(NULL, 0, NULL, ERR_TYPE, ATOM_<expected>, pushWordAsTermRef(p))`.
function _ar_type_error(ld::PL_local_data{T}, expected::Symbol, p::T)::Bool where {T}
    a = new_term_ref(ld)
    ld.slots[a + 1] = p
    return PL_error(ld, ERR_TYPE, mk_sym(T, expected), a)
end

# PORT: pl-arith.c valueExpression
# DIVERGES: the fast paths are an `Int64` integer and a float (upstream's: a tagged integer and a
# float); `EXCEPTION_GUARDED` has nothing to guard — no `longjmp`.
"Evaluate the expression `expr` refers to into `n` (pl-arith.c): the fast paths, else `evalExpression`."
function valueExpression(ld::PL_local_data{T}, expr::term_t, n::number)::Bool where {T}
    p = deRef(ld, ld.slots[expr + 1])
    nk = number_kind(p)
    if nk === NUM_INTEGER && integer_is_int64(p)            # (TAG_INTEGER|STG_INLINE)
        n.i = int64_value(p)
        n.type = V_INTEGER
        return true
    elseif nk === NUM_FLOAT
        n.f = float_value(p)
        n.type = V_FLOAT
        return true
    end
    return evalExpression(ld, expr, n)
end

# ── comparison (pl-arith.c) ──────────────────────────────────────────────────────────────────────
# PORT: pl-incl.h LT
"Arithmetic comparison `<` (pl-incl.h)."
const LT = 1
# PORT: pl-incl.h GT
"Arithmetic comparison `>` (pl-incl.h)."
const GT = 2
# PORT: pl-incl.h LE
"Arithmetic comparison `=<` (pl-incl.h)."
const LE = 3
# PORT: pl-incl.h GE
"Arithmetic comparison `>=` (pl-incl.h)."
const GE = 4
# PORT: pl-incl.h NE
"Arithmetic comparison `=\\=` (pl-incl.h)."
const NE = 5
# PORT: pl-incl.h EQ
"Arithmetic comparison `=:=` (pl-incl.h)."
const EQ = 6

# PORT: pl-arith.c ar_compare
"Whether `n1` and `n2` compare as `what` (pl-arith.c): a NaN is unordered and unequal."
function ar_compare(ld::PL_local_data, n1::number, n2::number, what::Int)::Bool
    diff = cmpNumbers(ld, n1, n2)                           # nan compares CMP_NOTEQ
    if what == LT
        return diff == CMPEX_LESS
    elseif what == GT
        return diff == CMPEX_GREATER
    elseif what == LE
        return (diff == CMPEX_LESS) || (diff == CMPEX_EQUAL)
    elseif what == GE
        return (diff == CMPEX_GREATER) || (diff == CMPEX_EQUAL)
    elseif what == NE
        return diff != CMPEX_EQUAL
    end
    @assert what == EQ
    return diff == CMPEX_EQUAL
end

# PORT: pl-arith.c compareNumbers
"Evaluate `n1` and `n2` (left first) and compare them as `what` (pl-arith.c)."
function compareNumbers(
    ld::PL_local_data{T}, n1::term_t, n2::term_t, what::Int
)::Bool where {T}
    left = _number_alloc!(ld)
    right = _number_alloc!(ld)
    rc =
        valueExpression(ld, n1, left) && valueExpression(ld, n2, right) &&
        ar_compare(ld, left, right, what)
    _number_free!(ld, 2)
    return rc
end

# ── the built-ins (pl-arith.c) ──────────────────────────────────────────────────────────────────
# PORT: pl-arith.c lt as pl_lt2_va
# (PRED_IMPL("<", 2, lt, PL_FA_ISO))
"`</2` (pl-arith.c): the first expression's value is smaller."
function pl_lt2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return compareNumbers(ld, A1, A2, LT) ? FTRUE : FFALSE
end

# PORT: pl-arith.c gt as pl_gt2_va
# (PRED_IMPL(">", 2, gt, PL_FA_ISO))
"`>/2` (pl-arith.c): the first expression's value is greater."
function pl_gt2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return compareNumbers(ld, A1, A2, GT) ? FTRUE : FFALSE
end

# PORT: pl-arith.c leq as pl_leq2_va
# (PRED_IMPL("=<", 2, leq, PL_FA_ISO))
"`=</2` (pl-arith.c): the first expression's value is not greater."
function pl_leq2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return compareNumbers(ld, A1, A2, LE) ? FTRUE : FFALSE
end

# PORT: pl-arith.c geq as pl_geq2_va
# (PRED_IMPL(">=", 2, geq, PL_FA_ISO))
"`>=/2` (pl-arith.c): the first expression's value is not smaller."
function pl_geq2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return compareNumbers(ld, A1, A2, GE) ? FTRUE : FFALSE
end

# PORT: pl-arith.c neq as pl_neq2_va
# (PRED_IMPL("=\\=", 2, neq, PL_FA_ISO))
"`=\\=/2` (pl-arith.c): the expressions' values are not equal."
function pl_neq2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return compareNumbers(ld, A1, A2, NE) ? FTRUE : FFALSE
end

# PORT: pl-arith.c eq as pl_eq2_va
# (PRED_IMPL("=:=", 2, eq, PL_FA_ISO))
"`=:=/2` (pl-arith.c): the expressions' values are equal."
function pl_eq2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return compareNumbers(ld, A1, A2, EQ) ? FTRUE : FFALSE
end

# PORT: pl-arith.c is as pl_is2_va
# (PRED_IMPL("is", 2, is, PL_FA_ISO))
# DIVERGES: no `ensureGlobalSpace` (no global stack) and no `AR_*` (see the file header).
"`is/2` (pl-arith.c): unify the first argument with the second's value."
function pl_is2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    arg = _number_alloc!(ld)                                # number arg
    rc = valueExpression(ld, A2, arg) && PL_unify_number(ld, A1, arg)
    _number_free!(ld, 1)                                    # clearNumber(&arg)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-arith.c BeginPredDefs as PL_predicates_from_arith
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order
# (ar:5386-5393); `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-arith.c's registration table (`BeginPredDefs(arith)`): the ported entries."
const PL_predicates_from_arith = (
    PL_extension("is", 2, pl_is2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("<", 2, pl_lt2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension(">", 2, pl_gt2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("=<", 2, pl_leq2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension(">=", 2, pl_geq2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("=\\=", 2, pl_neq2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("=:=", 2, pl_eq2_va, PL_FA_ISO | PL_FA_VARARGS)
)
