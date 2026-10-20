# UPSTREAM: swipl-devel src/pl-arith.c @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-arith.h @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-incl.h @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-inline.h @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/os/pl-os.c @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SWI-Prolog's arithmetic (pl-arith.c), V6c: evaluating an expression (`valueExpression`,
# `evalExpression`) into a `number` (src/pl-incl.jl; the number core is src/pl-gmp.jl), the
# functions the programs reach (`+ - *`, unary `-` and `+`, and arith-a's: `/ // mod rem div`,
# `abs sign min max copysign`, `gcd msb`, `/\ \/ xor \`, `integer round truncate float floor ceil
# ceiling float_integer_part float_fractional_part`; and arith-b's: `** ^ sqrt exp log sin cos tan asin
# acos atan atan/2 atan2 pi e random cputime`; and arith-c's: `rational numerator denominator
# rationalize rdiv cmpr maxr minr lcm random_float nexttoward sinh cosh tanh asinh acosh atanh lgamma
# erf erfc log10 epsilon inf nan lsb popcount getbit powm eval`; arith_funcs_design.md), comparing
# (`compareNumbers`), and the built-ins `is/2`, `</2`, `>/2`, `=</2`, `>=/2`, `=\=/2`, `=:=/2`.
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

# DIVERGES: a constant, where upstream's `initArith` sets it from `nan15()`, `str_number` reading
# "1.5NaN" (src/pl-read.jl, since R1c), which a module constant cannot call (no local data at
# load): the same value, the quiet NaN 0x7ff8000000000000 (Julia's `NaN`). test_read_swipl.jl
# checks that `str_number` gives exactly these bits.
"The NaN `float_undefined=nan` gives (pl-arith.c `const_nan`)."
const const_nan = NaN

# PORT: pl-arith.c PL_nan
"SWI-Prolog's canonical NaN, `1.5NaN` (pl-arith.c): every NaN stored in a term is this one."
PL_nan()::Float64 = const_nan

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
# (L1f f2: the global stack's overflow, as upstream — `outOfStack(global, STACK_OVERFLOW_RAISE)`)
"An integer too big to create (pl-arith.c `int_too_big`): the global stack's resource error; false."
function int_too_big(ld::PL_local_data{T})::Bool where {T}
    outOfStack!(ld, STACK_OVERFLOW_RAISE, :global)
    return false
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

# PORT: pl-arith.c ar_rdiv_mpz
"`n1 / n2` of two big integers as an exact number (pl-arith.c): an integer if it divides, else a rational."
function ar_rdiv_mpz(n1::number, n2::number, r::number)::Bool
    if rem(n1.mpz, n2.mpz) == 0                         # mpz_divisible_p
        r.type = V_MPZ
        r.mpz = div(n1.mpz, n2.mpz)                     # mpz_divexact
    else
        r.type = V_MPQ
        r.mpq = n1.mpz // n2.mpz                        # mpq_canonicalize
        return check_mpq(r)
    end
    return true
end

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

# ── arith-a: division, sign and order, integer, bitwise, rounding and conversion (pl-arith.c) ─────
# The flags `ar_divide` reads (`truePrologFlag`): `iso` and `prefer_rationals`, both false in the
# kernel (nothing sets a flag; see the file header). The branches they guard are ported as upstream's,
# on these constants.
# PORT: pl-incl.h PLFLAG_ISO
"The `iso` Prolog flag (pl-incl.h `PLFLAG_ISO`): false, as its default."
const PLFLAG_ISO = false
# PORT: pl-incl.h PLFLAG_RATIONAL
"The `prefer_rationals` Prolog flag (pl-incl.h `PLFLAG_RATIONAL`): false, as its default."
const PLFLAG_RATIONAL = false

# PORT: pl-arith.c sign_f
"The sign of the double `f` (pl-arith.c): -1, 0 or 1; a NaN is 0."
sign_f(f::Float64)::Int =
    if f < 0
        -1
    elseif f > 0
        1
    else
        0
    end

# PORT: pl-arith.c check_zero_div
"A division by zero (pl-arith.c): a NaN or an infinity if the float flags say so, else `evaluation_error(zero_divisor)`."
function check_zero_div(
    ld::PL_local_data, sign_n::Int, r::number, func::String, arity::Int
)::Bool
    if sign_n == 0
        if (ld.arith_f_flags & FLT_UNDEFINED) != 0
            r.type = V_FLOAT
            r.f = const_nan
            return true
        end
    elseif (ld.arith_f_flags & FLT_ZERO_DIV) != 0
        r.type = V_FLOAT
        r.f = copysign(Inf, sign_n)                         # const_inf
        return true
    end
    return PL_error(ld, func, arity, "", ERR_DIV_BY_ZERO)
end

# PORT: pl-arith.c ar_divide
# DIVERGES: `n1 % n2` of `INT64_MIN` and -1 is undefined in C (a trap on x86); the pin's build
# answers 2^63 as a big integer (probed: `X is -9223372036854775808 / -1`), which is what the
# kernel gives. Julia's `rem` is 0 there, so `n1 % n2 == 0` holds, and the quotient is made a `V_MPZ`.
"`//2` (pl-arith.c `ar_divide`): `r = n1 / n2`: an integer when it divides, else a float."
function ar_divide(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    if n2.type === V_FLOAT && isinf(n2.f)                   # X/inf
        if n1.type === V_FLOAT                              # float --> signed 0.0 or NaN
            r.type = V_FLOAT
            r.f = isfinite(n1.f) ? 0.0 * sign_f(n1.f) * sign_f(n2.f) : const_nan
            return check_float(ld, r)
        else                                                # non-float --> 0
            r.type = V_INTEGER
            r.i = 0
            return true
        end
    end
    if !PLFLAG_ISO
        same_type_numbers(ld, n1, n2) || return false
        t = n1.type
        if t === V_INTEGER
            n2.i == 0 && return check_zero_div(ld, ar_sign_i(n1), r, "/", 2)
            if n1.i % n2.i == 0
                if n2.i == -1 && n1.i == typemin(Int64)     # INT64_MIN / -1: see DIVERGES
                    r.type = V_MPZ
                    r.mpz = -BigInt(n1.i)
                    return true
                end
                r.i = n1.i ÷ n2.i
                r.type = V_INTEGER
                return true
            end
            if PLFLAG_RATIONAL
                promoteToMPZNumber(n1)
                promoteToMPZNumber(n2)
                return ar_rdiv_mpz(n1, n2, r)
            end
        elseif t === V_MPZ
            iszero(n2.mpz) && return check_zero_div(ld, ar_sign_i(n1), r, "/", 2)
            if rem(n1.mpz, n2.mpz) == 0                     # mpz_divisible_p
                r.type = V_MPZ
                r.mpz = div(n1.mpz, n2.mpz)                 # mpz_divexact
                return true
            end
            PLFLAG_RATIONAL && return ar_rdiv_mpz(n1, n2, r)
        elseif t === V_MPQ
            iszero(numerator(n2.mpq)) && return check_zero_div(ld, ar_sign_i(n1), r, "/", 2)
            r.type = V_MPQ
            r.mpq = n1.mpq / n2.mpq                         # mpq_div
            return check_mpq(r)
        end                                                 # V_FLOAT: break
    end
    # TBD: How to handle Q?
    (promoteToFloatNumber(ld, n1) && promoteToFloatNumber(ld, n2)) || return false
    # separate zero-div case from general overflow, Note: sign_f(nan)=0
    if n2.f == 0.0 && sign_f(n1.f) != 0
        return check_zero_div(ld, signbit(n1.f) == signbit(n2.f) ? 1 : -1, r, "/", 2)
    end
    r.f = n1.f / n2.f
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c mod as mod_int64
"`x mod y` of two `int64_t` (pl-arith.c `mod`): the sign of `y`; `y` is not 0."
function mod_int64(x::Int64, y::Int64)::Int64
    r = x % y
    if r != 0 && (r < 0) != (y < 0)
        r += y
    end
    return r
end

# PORT: pl-arith.c ar_mod
"`mod/2` (pl-arith.c `ar_mod`): `r = n1 mod n2`, the sign of `n2`."
function ar_mod(ld::PL_local_data{T}, n1::number, n2::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "mod", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "mod", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    same_type_numbers(ld, n1, n2) || return false
    if n1.type === V_INTEGER
        n2.i == 0 && return PL_error(ld, "mod", 2, "", ERR_DIV_BY_ZERO)
        if n2.i != -1 || n1.i != typemin(Int64)             # INT64_MIN
            r.i = mod_int64(n1.i, n2.i)
        else
            r.i = 0
        end
        r.type = V_INTEGER
    else                                                    # V_MPZ
        iszero(n2.mpz) && return PL_error(ld, "mod", 2, "", ERR_DIV_BY_ZERO)
        r.type = V_MPZ
        r.mpz = mod(n1.mpz, n2.mpz)                         # mpz_fdiv_r
    end
    return true
end

# PORT: pl-arith.c ar_rem
"`rem/2` (pl-arith.c `ar_rem`): `r = n1 rem n2`, the sign of `n1`."
function ar_rem(ld::PL_local_data{T}, n1::number, n2::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "rem", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "rem", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    same_type_numbers(ld, n1, n2) || return false
    if n1.type === V_INTEGER
        n2.i == 0 && return PL_error(ld, "rem", 2, "", ERR_DIV_BY_ZERO)
        if n2.i != -1 || n1.i != typemin(Int64)             # INT64_MIN
            r.i = n1.i % n2.i
        else
            r.i = 0
        end
        r.type = V_INTEGER
    else                                                    # V_MPZ
        iszero(n2.mpz) && return PL_error(ld, "rem", 2, "", ERR_DIV_BY_ZERO)
        r.type = V_MPZ
        r.mpz = rem(n1.mpz, n2.mpz)                         # mpz_tdiv_r
    end
    return true
end

# PORT: pl-arith.c ar_tdiv
# DIVERGES: C99's `(-3 / 2) == -1` is true, so upstream's `mpz_fdiv_q` branch is dead and only
# `mpz_tdiv_q` (Julia's `div` on a `BigInt`) is written.
"`///2` (pl-arith.c `ar_tdiv`): integer division, truncating toward zero."
function ar_tdiv(ld::PL_local_data{T}, n1::number, n2::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "//", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "//", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    if n1.type === V_INTEGER && n2.type === V_INTEGER
        n2.i == 0 && return PL_error(ld, "//", 2, "", ERR_DIV_BY_ZERO)
        if !(n2.i == -1 && n1.i == typemin(Int64))          # PLMININT
            r.i = n1.i ÷ n2.i
            r.type = V_INTEGER
            return true
        end
    end
    promoteToMPZNumber(n1)
    promoteToMPZNumber(n2)
    iszero(n2.mpz) && return PL_error(ld, "//", 2, "", ERR_DIV_BY_ZERO)
    r.type = V_MPZ
    r.mpz = div(n1.mpz, n2.mpz)                             # mpz_tdiv_q
    return true
end

# PORT: pl-arith.c ar_div
"`div/2` (pl-arith.c `ar_div`): integer division, rounding toward negative infinity."
function ar_div(ld::PL_local_data{T}, n1::number, n2::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "div", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "div", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    if n1.type === V_INTEGER && n2.type === V_INTEGER
        n2.i == 0 && return PL_error(ld, "div", 2, "", ERR_DIV_BY_ZERO)
        if !(n2.i == -1 && n1.i == typemin(Int64))          # PLMININT
            r.i = n1.i ÷ n2.i
            if (n1.i > 0) != (n2.i > 0) && n1.i % n2.i != 0
                r.i -= 1
            end
            r.type = V_INTEGER
            return true
        end
    end
    promoteToMPZNumber(n1)
    promoteToMPZNumber(n2)
    iszero(n2.mpz) && return PL_error(ld, "div", 2, "", ERR_DIV_BY_ZERO)
    r.type = V_MPZ
    r.mpz = fld(n1.mpz, n2.mpz)                             # mpz_fdiv_q
    return true
end

# PORT: pl-arith.c ar_signbit
"The sign bit of `n` (pl-arith.c): -1 if it is set (a negative number, `-0.0`), else 1."
function ar_signbit(n::number)::Int
    t = n.type
    t === V_INTEGER && return n.i < 0 ? -1 : 1
    t === V_MPZ && return sign(cmp(n.mpz, 0)) < 0 ? -1 : 1  # mpz_sgn
    t === V_MPQ && return sign(cmp(numerator(n.mpq), 0)) < 0 ? -1 : 1  # mpq_sgn
    return signbit(n.f) ? -1 : 1                            # V_FLOAT
end

# PORT: pl-arith.c ar_sign
"`sign/1` (pl-arith.c `ar_sign`): -1, 0 or 1 of the argument's type; a NaN stays one."
function ar_sign(n1::number, r::number)::Bool
    if n1.type === V_FLOAT
        r.f = isnan(n1.f) ? const_nan : (
            if n1.f < 0
                -1.0
            elseif n1.f > 0.0
                1.0
            else
                0.0
            end
        )
        r.type = V_FLOAT
    else
        r.i = ar_sign_i(n1)
        r.type = V_INTEGER
    end
    return true
end

# PORT: pl-arith.c ar_copysign
"`copysign/2` (pl-arith.c `ar_copysign`): the magnitude of `n1` with the sign of `n2`."
function ar_copysign(n1::number, n2::number, r::number)::Bool
    if n1.type === V_FLOAT && n2.type === V_FLOAT
        if isnan(n1.f)
            r.f = const_nan
        else
            r.f = copysign(n1.f, n2.f)
        end
        r.type = V_FLOAT
    else
        if ar_signbit(n1) != ar_signbit(n2)
            return ar_u_minus(n1, r)
        else
            cpNumber(r, n1)
        end
    end
    return true
end

# PORT: pl-arith.c is_min_zero
"Whether `n` is the float -0.0 (pl-arith.c)."
is_min_zero(n::number)::Bool = n.type === V_FLOAT && n.f == 0.0 && signbit(n.f)

# PORT: pl-arith.c ar_max
"`max/2` (pl-arith.c `ar_max`): a NaN argument gives a NaN, and -0.0 < 0.0."
function ar_max(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    diff = cmpNumbers(ld, n1, n2)
    if diff == CMP_NOTEQ                                    # one or both nan
        r.f = const_nan
        r.type = V_FLOAT
    elseif diff == CMPEX_EQUAL
        if is_min_zero(n1)
            cpNumber(r, n2)
        elseif is_min_zero(n2)
            cpNumber(r, n1)
        else
            make_same_type_numbers(ld, n1, n2) || return false
            cpNumber(r, n1)
        end
    elseif diff > 0
        cpNumber(r, n1)
    else
        cpNumber(r, n2)
    end
    return true
end

# PORT: pl-arith.c ar_min
"`min/2` (pl-arith.c `ar_min`): a NaN argument gives a NaN, and -0.0 < 0.0."
function ar_min(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    diff = cmpNumbers(ld, n1, n2)
    if diff == CMP_NOTEQ                                    # if one or both nan's
        r.f = const_nan
        r.type = V_FLOAT
    elseif diff == CMPEX_EQUAL
        if is_min_zero(n1)
            cpNumber(r, n1)
        elseif is_min_zero(n2)
            cpNumber(r, n2)
        else
            make_same_type_numbers(ld, n1, n2) || return false
            cpNumber(r, n1)
        end
    elseif diff < 0
        cpNumber(r, n1)
    else
        cpNumber(r, n2)
    end
    return true
end

# PORT: pl-arith.c same_positive_ints
"The integer arguments of `gcd/2` made absolute and of one type (pl-arith.c): a type error, or false after raising."
function same_positive_ints(
    ld::PL_local_data{T}, fname::String, n1::number, n2::number
)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, fname, 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, fname, 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    same_type_numbers(ld, n1, n2) || return false
    if n1.type === V_INTEGER
        a = n1.i
        b = n2.i
        promote = false
        if a < 0
            a = -a                                          # -(uint64_t)a: wraps for INT64_MIN
            promote = a < 0
        end
        if !promote && b < 0
            b = -b
            promote = b < 0
        end
        if promote
            promoteToMPZNumber(n1)
            promoteToMPZNumber(n2)
            return true                                     # goto case_gmp: the GMP functions ignore the sign
        end
        n1.i = a
        n2.i = b
    end                                                     # V_MPZ: nothing to make absolute
    return true
end

# PORT: pl-arith.c i64_gcd
"The greatest common divisor of two non-negative `int64_t` (pl-arith.c)."
function i64_gcd(a::Int64, b::Int64)::Int64
    a == 0 && return b
    b == 0 && return a
    while b != 0
        t = b
        b = a % b
        a = t
    end
    return a
end

# PORT: pl-arith.c ar_gcd
"`gcd/2` (pl-arith.c `ar_gcd`): the greatest common divisor of two integers."
function ar_gcd(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    same_positive_ints(ld, "gcd", n1, n2) || return false
    if n1.type === V_INTEGER
        r.type = V_INTEGER
        r.i = i64_gcd(n1.i, n2.i)
    else                                                    # V_MPZ
        r.type = V_MPZ
        r.mpz = gcd(n1.mpz, n2.mpz)                         # mpz_gcd
    end
    return true
end

# PORT: pl-arith.c ar_disjunct
"`\\//2` (pl-arith.c `ar_disjunct`, BINAIRY_INT_FUNCTION): bitwise or."
function ar_disjunct(
    ld::PL_local_data{T}, n1::number, n2::number, r::number
)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "\\/", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "\\/", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    same_type_numbers(ld, n1, n2) || return false
    if n1.type === V_INTEGER
        r.i = n1.i | n2.i
        r.type = V_INTEGER
    else                                                    # V_MPZ
        r.type = V_MPZ
        r.mpz = n1.mpz | n2.mpz                             # mpz_ior
    end
    return true
end

# PORT: pl-arith.c ar_conjunct
"`/\\/2` (pl-arith.c `ar_conjunct`, BINAIRY_INT_FUNCTION): bitwise and."
function ar_conjunct(
    ld::PL_local_data{T}, n1::number, n2::number, r::number
)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "/\\", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "/\\", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    same_type_numbers(ld, n1, n2) || return false
    if n1.type === V_INTEGER
        r.i = n1.i & n2.i
        r.type = V_INTEGER
    else                                                    # V_MPZ
        r.type = V_MPZ
        r.mpz = n1.mpz & n2.mpz                             # mpz_and
    end
    return true
end

# PORT: pl-arith.c ar_xor
"`xor/2` (pl-arith.c `ar_xor`, BINAIRY_INT_FUNCTION): bitwise exclusive or."
function ar_xor(ld::PL_local_data{T}, n1::number, n2::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "xor", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    toIntegerNumber(ld, n2, 0) ||
        return PL_error(ld, "xor", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), n2)
    same_type_numbers(ld, n1, n2) || return false
    if n1.type === V_INTEGER
        r.i = xor(n1.i, n2.i)
        r.type = V_INTEGER
    else                                                    # V_MPZ
        r.type = V_MPZ
        r.mpz = xor(n1.mpz, n2.mpz)                         # mpz_xor
    end
    return true
end

# PORT: pl-arith.c ar_negation
"`\\/1` (pl-arith.c `ar_negation`): bitwise negation."
function ar_negation(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "\\", 1, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    if n1.type === V_INTEGER
        r.i = ~n1.i
        r.type = V_INTEGER
    else                                                    # V_MPZ
        r.type = V_MPZ
        r.mpz = ~n1.mpz                                     # mpz_com
    end
    return true
end

# PORT: pl-arith.c mustBePositive
"`domain_error(not_less_than_one, N)` for the function `f/a` (pl-arith.c)."
function mustBePositive(ld::PL_local_data{T}, f::String, a::Int, n::number)::Bool where {T}
    return PL_error(ld, f, a, "", ERR_AR_DOMAIN, mk_sym(T, :not_less_than_one), n)
end

# PORT: pl-arith.c ar_msb
"`msb/1` (pl-arith.c `ar_msb`): the index of the most significant bit of a positive integer."
function ar_msb(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "msb", 1, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    if n1.type === V_INTEGER
        n1.i <= 0 && return mustBePositive(ld, "msb", 1, n1)
        r.i = MSB64(n1.i)
        r.type = V_INTEGER
        return true
    end
    ar_sign_i(n1) <= 0 && return mustBePositive(ld, "msb", 1, n1)    # V_MPZ: mpz_sgn
    r.i = ndigits(n1.mpz; base=2) - 1                       # mpz_sizeinbase(…, 2) - 1
    r.type = V_INTEGER
    return true
end

# PORT: pl-arith.c ar_abs
"`abs/1` (pl-arith.c `ar_abs`): the absolute value; that of the most negative integer is a bigint."
function ar_abs(n1::number, r::number)::Bool
    t = n1.type
    if t === V_INTEGER
        if n1.i == typemin(Int64)                           # PLMININT
            promoteToMPZNumber(n1)
            r.type = V_MPZ
            t = V_MPZ                                       # FALLTHROUGH
        else
            r.i = abs(n1.i)                                 # llabs
            r.type = V_INTEGER
            return true
        end
    end
    if t === V_MPZ
        r.type = V_MPZ
        r.mpz = abs(n1.mpz)                                 # mpz_abs
    elseif t === V_MPQ
        r.type = V_MPQ
        r.mpq = abs(n1.mpq)                                 # mpq_abs
    else                                                    # V_FLOAT
        if signbit(n1.f)
            r.f = -n1.f
        else
            r.f = n1.f
        end
        r.type = V_FLOAT
    end
    return true
end

# PORT: pl-arith.c ar_integer
# DIVERGES: `lround` of the doubles up to and including 2^63 (the test is against `(float)PLMAXINT`,
# which is 2^63): the double 2^63 is out of range, glibc on x86-64 answers `LONG_MIN`, which the
# sign check below turns into `PLMAXINT` (probed: `integer(9223372036854775808.0)` is
# 9223372036854775807). Julia's `round(Int64, …)` throws there, so the rounded double is converted
# in range and 2^63 is given `typemin`. `mpq_t`s and `mpz_set_q` (truncation toward zero) are
# `Rational`s and `div` on the parts.
"`integer/1` and `round/1` (pl-arith.c `ar_integer`): round to the nearest integer, halves away from zero."
function ar_integer(n1::number, r::number)::Bool
    t = n1.type
    if t === V_INTEGER || t === V_MPZ
        cpNumber(r, n1)
        return true
    elseif t === V_MPQ
        half = Rational{BigInt}(1, 2)
        q = ar_sign_i(n1) > 0 ? n1.mpq + half : n1.mpq - half
        r.type = V_MPZ
        r.mpz = div(numerator(q), denominator(q))           # mpz_set_q
        return true
    end
    f = n1.f                                                # V_FLOAT
    if isnan(f) || isinf(f)
        cpNumber(r, n1)
        return true
    end
    if f <= Float64(Float32(typemax(Int64))) && f >= Float64(Float32(typemin(Int64)))
        rf = round(f, RoundNearestTiesAway)                 # lround
        r.i = rf >= 9.223372036854775808e18 ? typemin(Int64) : trunc(Int64, rf)
        if f > 0 && r.i < 0
            r.i = typemax(Int64)                            # PLMAXINT
        elseif f < 0 && r.i > 0
            r.i = typemin(Int64)                            # PLMININT
        end
        r.type = V_INTEGER
        return true
    end
    r.type = V_MPZ
    r.mpz = BigInt(f)                                       # mpz_init_set_d
    return true
end

# PORT: pl-arith.c ar_float
"`float/1` (pl-arith.c `ar_float`): the argument as a float."
function ar_float(ld::PL_local_data, n1::number, r::number)::Bool
    cpNumber(r, n1)
    return promoteToFloatNumber(ld, r)
end

# PORT: pl-arith.c ar_floor
# DIVERGES: only the `HAVE_FLOOR` branch is written (the pin's build has it), and
# `mpz_set_q` is `div` on the parts, truncating.
"`floor/1` (pl-arith.c `ar_floor`): the largest integer not above the argument."
function ar_floor(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    t = n1.type
    if t === V_INTEGER || t === V_MPZ
        cpNumber(r, n1)
        return true
    elseif t === V_MPQ
        r.type = V_MPZ
        r.mpz = div(numerator(n1.mpq), denominator(n1.mpq)) # mpz_set_q
        if ar_sign_i(n1) < 0 && denominator(n1.mpq) != 1
            r.mpz = r.mpz - 1                               # mpz_sub_ui
        end
        return true
    end
    if isnan(n1.f) || isinf(n1.f)                           # V_FLOAT
        cpNumber(r, n1)
        return true
    end
    r.type = V_FLOAT
    r.f = floor(n1.f)
    if !toIntegerNumber(ld, r, TOINT_CONVERT_FLOAT | TOINT_TRUNCATE)
        return PL_error(ld, "floor", 1, "", ERR_EVALUATION, mk_sym(T, :int_overflow))
    end
    return true
end

# PORT: pl-arith.c ar_ceil
# DIVERGES: as `ar_floor`: the `HAVE_CEIL` branch only.
"`ceiling/1` and `ceil/1` (pl-arith.c `ar_ceil`): the smallest integer not below the argument."
function ar_ceil(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    t = n1.type
    if t === V_INTEGER || t === V_MPZ
        cpNumber(r, n1)
        return true
    elseif t === V_MPQ
        r.type = V_MPZ
        r.mpz = div(numerator(n1.mpq), denominator(n1.mpq)) # mpz_set_q
        if ar_sign_i(n1) > 0 && denominator(n1.mpq) != 1
            r.mpz = r.mpz + 1                               # mpz_add_ui
        end
        return true
    end
    if isnan(n1.f) || isinf(n1.f)                           # V_FLOAT
        cpNumber(r, n1)
        return true
    end
    r.type = V_FLOAT
    r.f = ceil(n1.f)
    if !toIntegerNumber(ld, r, TOINT_CONVERT_FLOAT | TOINT_TRUNCATE)
        return PL_error(ld, "ceil", 1, "", ERR_EVALUATION, mk_sym(T, :int_overflow))
    end
    return true
end

# PORT: pl-arith.c ar_float_fractional_part
# DIVERGES: C's `modf` and `copysign(modf(...), f)` (for -0.0) as Julia's `modf`, whose
# fractional part is `x - trunc(x)` and whose infinity case is 0.0: `copysign` restores the sign.
"`float_fractional_part/1` (pl-arith.c): `X - truncate(X)`, a rational for a rational."
function ar_float_fractional_part(ld::PL_local_data, n1::number, r::number)::Bool
    t = n1.type
    if t === V_INTEGER || t === V_MPZ
        r.i = 0
        r.type = V_INTEGER
        return true
    elseif t === V_MPQ
        r.type = V_MPQ
        ip = div(numerator(n1.mpq), denominator(n1.mpq))    # mpz_tdiv_q
        r.mpq = n1.mpq - Rational{BigInt}(ip, BigInt(1))    # mpq_sub
        return true
    end
    r.f = copysign(modf(n1.f)[1], n1.f)                     # V_FLOAT
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_float_integer_part
"`float_integer_part/1` (pl-arith.c): `truncate(X)`, a float for a float."
function ar_float_integer_part(ld::PL_local_data, n1::number, r::number)::Bool
    t = n1.type
    if t === V_INTEGER || t === V_MPZ
        cpNumber(r, n1)
        return true
    elseif t === V_MPQ
        r.type = V_MPZ
        r.mpz = div(numerator(n1.mpq), denominator(n1.mpq)) # mpz_tdiv_q
        return true
    end
    r.f = modf(n1.f)[2]                                     # V_FLOAT
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_truncate
"`truncate/1` (pl-arith.c `ar_truncate`): the integer part, toward zero."
function ar_truncate(ld::PL_local_data, n1::number, r::number)::Bool
    t = n1.type
    if t === V_MPQ
        return ar_sign_i(n1) >= 0 ? ar_floor(ld, n1, r) : ar_ceil(ld, n1, r)
    elseif t === V_FLOAT
        if isnan(n1.f) || isinf(n1.f)
            cpNumber(r, n1)
            return true
        end
        return n1.f >= 0.0 ? ar_floor(ld, n1, r) : ar_ceil(ld, n1, r)
    end
    cpNumber(r, n1)
    return true
end

# ── arith-b: powers, transcendental functions, constants and system (pl-arith.c) ──────────────────
# The C library functions, from glibc's libm — the library `swipl` calls (`USE_CRMATH` is off by
# default, so `cr_sin` & co. are plain libm calls in FE_TONEAREST mode, the only mode the kernel has).
# Julia's own `sin`, `exp`, `^`, ... are other implementations and differ from glibc's in the last
# digit for about 1 argument in 100 (measured), and its `sqrt`, `asin`, ... throw where C returns a
# NaN, so each is called through `ccall`.
# DIVERGES: the library is named `libm.so.6`, glibc's soname: the kernel runs on Linux (CI: ubuntu).
"The C math library the evaluable functions call (glibc's soname)."
const LIBM = "libm.so.6"

# `cr_sin` of pl-arith.c
"`sin(x)` of the C library (pl-arith.c `cr_sin`, FE_TONEAREST)."
_libm_sin(x::Float64)::Float64 = ccall((:sin, LIBM), Float64, (Float64,), x)
# `cr_cos` of pl-arith.c
"`cos(x)` of the C library (pl-arith.c `cr_cos`, FE_TONEAREST)."
_libm_cos(x::Float64)::Float64 = ccall((:cos, LIBM), Float64, (Float64,), x)
# `cr_tan` of pl-arith.c
"`tan(x)` of the C library (pl-arith.c `cr_tan`, FE_TONEAREST)."
_libm_tan(x::Float64)::Float64 = ccall((:tan, LIBM), Float64, (Float64,), x)
# `cr_asin` of pl-arith.c
"`asin(x)` of the C library (pl-arith.c `cr_asin`, FE_TONEAREST)."
_libm_asin(x::Float64)::Float64 = ccall((:asin, LIBM), Float64, (Float64,), x)
# `cr_acos` of pl-arith.c
"`acos(x)` of the C library (pl-arith.c `cr_acos`, FE_TONEAREST)."
_libm_acos(x::Float64)::Float64 = ccall((:acos, LIBM), Float64, (Float64,), x)
# `cr_atan` of pl-arith.c
"`atan(x)` of the C library (pl-arith.c `cr_atan`, FE_TONEAREST)."
_libm_atan(x::Float64)::Float64 = ccall((:atan, LIBM), Float64, (Float64,), x)
# `cr_atan2` of pl-arith.c
"`atan2(y, x)` of the C library (pl-arith.c `cr_atan2`, FE_TONEAREST)."
_libm_atan2(y::Float64, x::Float64)::Float64 =
    ccall((:atan2, LIBM), Float64, (Float64, Float64), y, x)
# `cr_exp` of pl-arith.c
"`exp(x)` of the C library (pl-arith.c `cr_exp`, FE_TONEAREST)."
_libm_exp(x::Float64)::Float64 = ccall((:exp, LIBM), Float64, (Float64,), x)
# `cr_log` of pl-arith.c
"`log(x)` of the C library (pl-arith.c `cr_log`, FE_TONEAREST)."
_libm_log(x::Float64)::Float64 = ccall((:log, LIBM), Float64, (Float64,), x)
# `cr_pow` of pl-arith.c
"`pow(b, e)` of the C library (pl-arith.c `cr_pow`, FE_TONEAREST)."
_libm_pow(b::Float64, e::Float64)::Float64 =
    ccall((:pow, LIBM), Float64, (Float64, Float64), b, e)
# `sqrt` is not redefined by `O_ROUND_UP_DOWN`: C's own, correctly rounded by IEEE.
"`sqrt(x)` of the C library: a NaN for a negative argument (Julia's `sqrt` throws)."
_libm_sqrt(x::Float64)::Float64 = ccall((:sqrt, LIBM), Float64, (Float64,), x)

# PORT: pl-arith.c ar_sin
"`sin/1` (pl-arith.c `ar_sin`, UNAIRY_FLOAT_FUNCTION)."
function ar_sin(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_sin(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_cos
"`cos/1` (pl-arith.c `ar_cos`, UNAIRY_FLOAT_FUNCTION)."
function ar_cos(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_cos(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_tan
"`tan/1` (pl-arith.c `ar_tan`, UNAIRY_FLOAT_FUNCTION)."
function ar_tan(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_tan(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_atan
"`atan/1` (pl-arith.c `ar_atan`, UNAIRY_FLOAT_FUNCTION)."
function ar_atan(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_atan(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_exp
"`exp/1` (pl-arith.c `ar_exp`, UNAIRY_FLOAT_FUNCTION)."
function ar_exp(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_exp(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_atan2
"`atan/2` and `atan2/2` (pl-arith.c `ar_atan2`, BINAIRY_FLOAT_FUNCTION): the angle of the point `(n2, n1)`."
function ar_atan2(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    (promoteToFloatNumber(ld, n1) && promoteToFloatNumber(ld, n2)) || return false
    r.f = _libm_atan2(n1.f, n2.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_sqrt
"`sqrt/1` (pl-arith.c `ar_sqrt`)."
function ar_sqrt(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_sqrt(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_asin
"`asin/1` (pl-arith.c `ar_asin`)."
function ar_asin(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_asin(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_acos
"`acos/1` (pl-arith.c `ar_acos`)."
function ar_acos(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_acos(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_log
"`log/1` (pl-arith.c `ar_log`)."
function ar_log(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_log(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_pi
# DIVERGES: round to nearest only, so `fegetround() == FE_UPWARD` never holds.
"`pi/0` (pl-arith.c `ar_pi`): `M_PI`."
function ar_pi(r::number)::Bool
    r.f = Float64(π)                                        # M_PI
    r.type = V_FLOAT
    return true
end

# PORT: pl-arith.c ar_e
# DIVERGES: round to nearest only, as `ar_pi`.
"`e/0` (pl-arith.c `ar_e`): `M_E`."
function ar_e(r::number)::Bool
    r.f = Float64(ℯ)                                        # M_E
    r.type = V_FLOAT
    return true
end

# PORT: pl-os.c CpuTime
# DIVERGES: the `CLOCK_PROCESS_CPUTIME_ID` (2) branch of `CpuTime`, the one Linux takes; the spectre
# jitter (`mitigate_spectre`) is off, its default. 0.0 where `clock_gettime` fails, as upstream.
"The CPU time the process has used, in seconds (os/pl-os.c `CpuTime(CPU_USER)`)."
function CpuTime()::Float64
    ts = Ref((Int64(0), Int64(0)))                          # struct timespec
    rc = ccall(:clock_gettime, Cint, (Cint, Ptr{Tuple{Int64, Int64}}), 2, ts)
    rc == 0 || return 0.0
    sec, nsec = ts[]
    return Float64(sec) + Float64(nsec) / 1000000000.0      # timespec_to_double
end

# PORT: pl-arith.c ar_cputime
"`cputime/0` (pl-arith.c `ar_cputime`): the CPU seconds the process has used."
function ar_cputime(r::number)::Bool
    r.f = CpuTime()
    r.type = V_FLOAT
    return true
end

# The random source: upstream seeds a GMP `gmp_randstate_t` (a Mersenne twister, `init_random`) in the
# LOCAL DATA on first use (`LD->arith.random`); here SplitMix64 on `ld.random_state`, seeded on first use.
# A seed (`set_random/1`, `random_property/1`) is a later step, so the stream is not comparable to
# swipl's under any seed: the tests check the range and the errors.
# DIVERGES: the generator (above).

# `init_random` and `mt_rand_u32` of pl-arith.c, in one
"The next 64 random bits (`init_random` on first use, then `mt_rand_u32` twice)."
function _random_u64(ld::PL_local_data)::UInt64
    if ld.random_state == 0                                 # init_random()
        ld.random_state =
            (UInt64(time_ns()) ⊻ (UInt64(Libc.getpid()) << 40) ⊻ 0x853c49e6748fea9b) | 1
    end
    z = ld.random_state += 0x9e3779b97f4a7c15
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

# GMP's `mpz_urandomm` by rejection: `nbits` random bits until the number is below `n`.
"A random integer in `[0, n)` for `n > 0` (GMP `mpz_urandomm`)."
function _mpz_urandomm(ld::PL_local_data, n::BigInt)::BigInt
    nbits = ndigits(n; base=2)
    nwords = cld(nbits, 32)
    while true
        x = BigInt(0)
        for _ in 1:nwords
            x = (x << 32) | BigInt(UInt32(_random_u64(ld) >> 32))
        end
        x >>= nwords * 32 - nbits
        x < n && return x
    end
end

# PORT: pl-arith.c ar_random
# DIVERGES: the generator (see `_random_u64`); `V_INTEGER` takes upstream's `O_BF` branch (a mask of
# `msb(n)+1` bits, redrawn while not below `n`), which answers a small integer, where the GMP branch
# promotes to `V_MPZ` and answers the same value.
"`random/1` (pl-arith.c `ar_random`): a random integer in `[0, n)`."
function ar_random(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, TOINT_CONVERT_FLOAT) ||
        return PL_error(ld, "random", 1, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    ar_sign_i(n1) <= 0 && return mustBePositive(ld, "random", 1, n1)
    if n1.type === V_INTEGER
        msb = MSB64(n1.i)
        mask = (UInt64(1) << (msb + 1)) - 1
        rnd = UInt64(0)
        while true
            rnd = _random_u64(ld) >> 32                     # mt_rand_u32
            if msb > 32
                rnd |= (_random_u64(ld) >> 32) << 32
            end
            rnd &= mask
            rnd >= UInt64(n1.i) || break
        end
        r.type = V_INTEGER
        r.i = Int64(rnd)
        return true
    end
    r.type = V_MPZ                                          # V_MPZ
    r.mpz = _mpz_urandomm(ld, n1.mpz)
    return true
end

# ── ** and ^ (pl-arith.c ar_pow) ─────────────────────────────────────────────────────────────────
# PORT: pl-incl.h intNumber
"Whether `n` is an integer, small or big (pl-arith.h `intNumber`)."
intNumber(n::number)::Bool = n.type === V_INTEGER || n.type === V_MPZ

# PORT: pl-arith.c ar_even
"Whether the integer `i` is even (pl-arith.c)."
ar_even(i::number)::Bool = i.type === V_INTEGER ? i.i % 2 == 0 : iseven(i.mpz)

# PORT: pl-arith.c bn_pow_ui
# DIVERGES: returns `(status, result)`, where upstream writes `r` and returns the status (0, or -1 on
# overflow); an exponent above `INT64_MAX` is an overflow here: `mul64` there takes it as a negative
# `int64_t`, and `mpz_pow_ui` is then asked for a result past GMP's size.
"`base^exp` of big integers (pl-arith.c `bn_pow_ui`): `(0, base^exp)`, or `(-1, 0)` if it is too big."
function bn_pow_ui(ld::PL_local_data, base::BigInt, exp::UInt64)::Tuple{Int, BigInt}
    iszero(base) && return (0, BigInt(0))
    isone(base) && return (0, BigInt(1))
    exp == 0 && return (0, BigInt(1))
    base_bits = ndigits(base; base=2)                       # mpz_sizeinbase(base, 2)
    exp > UInt64(typemax(Int64)) && return (-1, BigInt(0))
    r_bits, overflow = mul64(Int64(base_bits), Int64(exp))
    (overflow || !int_bits_ok(ld, UInt64(r_bits))) && return (-1, BigInt(0))
    return (0, base^Int(exp))
end

# PORT: pl-arith.c get_int_exponent
# DIVERGES: returns `(true, |n|)`; `int_too_big` raises (the interim, see there), so `false` is never
# returned.
"The absolute value of the integer exponent `n` (pl-arith.c `get_int_exponent`): `int_too_big` if it is past an `int64_t`."
function get_int_exponent(ld::PL_local_data, n::number)::Tuple{Bool, UInt64}
    i = Int64(0)
    if n.type === V_INTEGER
        i = n.i
    else                                                    # V_MPZ
        fits, v = mpz_to_int64(n.mpz)
        fits || return (int_too_big(ld), UInt64(0))
        i = v
    end
    if i < 0
        i = -i
        i < 0 && return (int_too_big(ld), UInt64(0))        # INT64_MIN
    end
    return (true, UInt64(i))                                # FITS_ULONG(i): always on LP64
end

# PORT: pl-arith.c ar_smallint
# DIVERGES: returns `(is_small, value)`.
"Whether the integer `n` is -1, 0 or 1 (pl-arith.c `ar_smallint`), and which."
function ar_smallint(n::number)::Tuple{Bool, Int}
    if n.type === V_INTEGER
        -1 <= n.i <= 1 && return (true, Int(n.i))
        return (false, 0)
    end
    -1 <= n.mpz <= 1 && return (true, Int(n.mpz))           # V_MPZ
    return (false, 0)
end

# PORT: pl-arith.c pow64
# DIVERGES: returns `(ok, m^n)`.
"`m^n` of `int64_t`s by repeated squaring (pl-arith.c `pow64`): `(false, 0)` on overflow."
function pow64(m::Int64, n::Int64)::Tuple{Bool, Int64}
    res = Int64(1)
    while n != 0
        if (n & 1) != 0
            v, overflow = mul64(res, m)
            overflow && return (false, Int64(0))
            res = v
        end
        n >>= 1
        if n != 0
            v, overflow = mul64(m, m)
            overflow && return (false, Int64(0))
            m = v
        end
    end
    return (true, res)
end

# DIVERGES: `LD->arith.rat.max_rational_size_action`, nonzero (`ATOM_error`) by default: an inexact
# rational power is then computed as a float (`maybe_real_mpq`); zero would raise `int_too_big`.
"Whether `max_rational_size_action` is set (pl-arith.c): `error`, its default."
const MAX_RATIONAL_SIZE_ACTION = true

# ar_pow's `doreal_mpq:` — a float base to a rational power (the branch also takes the other bases
# once `maybe_real_mpq` made them floats): `|n1| ** n2` as floats, negated when `n1` is negative and
# the numerator of `n2` odd. `n2` is the exponent as given (upstream negates a negative numerator for
# the root searches and restores it here).
# DIVERGES: `fegetround()` is always FE_TONEAREST, so `roundMode1` and `roundMode2` are that mode and
# the `fesetround` calls have nothing to do.
function _ar_pow_doreal_mpq(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    neg_res = n1.f < 0.0 && isodd(numerator(n2.mpq))        # mpz_get_ui(numer) & 1
    n1.f = abs(n1.f)
    promoteToFloatNumber(ld, n2) || return false
    r.f = _libm_pow(n1.f, n2.f)
    if neg_res
        r.f = -r.f
    end
    r.type = V_FLOAT
    return check_float(ld, r)
end

# ar_pow's `maybe_real_mpq:` — the rational power is not computed exactly.
function _ar_pow_maybe_real_mpq(
    ld::PL_local_data, n1::number, n2::number, r::number
)::Bool
    if MAX_RATIONAL_SIZE_ACTION
        promoteToFloatNumber(ld, n1) || return false        # float overflow
        return _ar_pow_doreal_mpq(ld, n1, n2, r)
    end
    return int_too_big(ld)                                  # stack overflow
end

# ar_pow's `doreal:` — the general case, as floats.
function _ar_pow_doreal(
    ld::PL_local_data, n1::number, n2::number, exp_sign::Int, r::number
)::Bool
    # `signbit(n1->value.f)` of upstream reads a float where one is the zero base this matters for
    zero_div_sign =
        if (n2.type === V_INTEGER && !ar_even(n2) && n1.type === V_FLOAT && signbit(n1.f))
            -1
        else
            1
        end
    (promoteToFloatNumber(ld, n1) && promoteToFloatNumber(ld, n2)) || return false
    if n1.f == 0.0 && exp_sign == -1
        return check_zero_div(ld, zero_div_sign, r, "**", 2)
    end
    if n1.f == 1.0
        r.f = 1.0                                           # broken on e.g., mipsel
    else
        r.f = _libm_pow(n1.f, n2.f)
    end
    r.type = V_FLOAT
    return check_float(ld, r)
end

# ar_pow's `int_pow_neg_int:` and the `MPQ ^ int` branch: `n1` (a rational) to the integer power
# `exp` (an absolute value; `exp_sign` is the exponent's sign), as the numerator's and denominator's
# powers.
function _ar_pow_mpq_int(
    ld::PL_local_data, n1::number, exp::UInt64, exp_sign::Int, r::number
)::Bool
    nexp = _number_alloc!(ld)
    nr = _number_alloc!(ld)
    nd = _number_alloc!(ld)
    nrp = _number_alloc!(ld)
    ndp = _number_alloc!(ld)
    nexp.type = V_INTEGER
    nexp.i = Int64(exp)
    nr.type = V_MPZ
    nr.mpz = numerator(n1.mpq)
    nd.type = V_MPZ
    nd.mpz = denominator(n1.mpq)
    rc = false
    if ar_pow(ld, nr, nexp, nrp) && ar_pow(ld, nd, nexp, ndp)
        pr = nrp.type === V_INTEGER ? BigInt(nrp.i) : nrp.mpz       # mpz_set_num
        pd = ndp.type === V_INTEGER ? BigInt(ndp.i) : ndp.mpz
        r.type = V_MPQ
        r.mpq = exp_sign > 0 ? pr // pd : pd // pr          # mpq_canonicalize
        rc = check_mpq(r)
    end
    _number_free!(ld, 5)
    return rc
end

# PORT: pl-arith.c ar_pow
# DIVERGES: the `gotos` are the helpers `_ar_pow_*`; `n2` is not negated in place for a negative
# rational exponent (the root searches use its absolute numerator, and `_ar_pow_doreal_mpq` the
# exponent as given); the rounding modes are FE_TONEAREST only (see there); `prefer_rationals` is the
# constant `PLFLAG_RATIONAL`. The size checks raise `int_too_big` as everywhere (the interim).
"`**/2` and `^/2` (pl-arith.c `ar_pow`): `n1` to the power `n2`; an integer for integers, else a float or a rational."
function ar_pow(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    exp_nan = false
    exp_sign = 0
    if n2.type === V_FLOAT
        exp_nan = isnan(n2.f)
        exp_sign = sign_f(n2.f)
    else
        exp_sign = ar_sign_i(n2)
    end
    r.type = V_INTEGER                                      # for all special cases

    if exp_sign == 0 && !exp_nan                            # test for X**0
        r.i = 1
        return true
    end

    if intNumber(n1)
        is_small, n1_val = ar_smallint(n1)
        if is_small
            if n1_val == 1                                  # 1**X => 1
                r.i = 1
                return true
            end
            if n1_val == 0 && !exp_nan                      # n1==0, non-zero(n2)
                if exp_sign > 0
                    r.i = 0                                 # positive exp => 0
                    return true
                end
                return check_zero_div(ld, 1, r, "**", 2)    # negative exp => zero_div
            end
            if n1_val == -1 && intNumber(n2)                # check n1 == -1
                r.i = ar_even(n2) ? 1 : -1
                return true
            end
        end
    end

    if intNumber(n1) && intNumber(n2)
        ok, exp = get_int_exponent(ld, n2)
        ok || return false
        if exp_sign < 0
            if PLFLAG_RATIONAL
                promoteToMPQNumber(ld, n1)
                return _ar_pow_mpq_int(ld, n1, exp, exp_sign, r)    # goto int_pow_neg_int
            end
            return _ar_pow_doreal(ld, n1, n2, exp_sign, r)  # goto doreal
        end
        op1_bits = 0
        if n1.type === V_INTEGER
            v = n1.i
            if v < 0
                v = -v
            end
            op1_bits = MSB64(v) + 1                         # # bits, as mpz_sizeinbase()
        else
            op1_bits = ndigits(n1.mpz; base=2)              # V_MPZ
        end
        r_bits, overflow = mul64(Int64(op1_bits), Int64(exp))   # bit estimate for result
        overflow && return int_too_big(ld)
        check_int_bits(ld, UInt64(r_bits)) || return false
        if n1.type === V_INTEGER && r_bits < 63             # try using small integers
            fits, res = pow64(n1.i, Int64(exp))
            if fits
                r.type = V_INTEGER
                r.i = res
                return true
            end
        end
        r.type = V_MPZ
        if n1.type === V_INTEGER
            r.mpz = BigInt(n1.i)^Int(exp)                   # mpz_ui_pow_ui, or promote and mpz_pow_ui
        else
            r.mpz = n1.mpz^Int(exp)                         # mpz_pow_ui
        end
        return true
    end

    if n1.type === V_MPQ && intNumber(n2)
        if exp_sign == 0
            r.type = V_INTEGER
            r.i = 1
            return true
        end
        ok, exp = get_int_exponent(ld, n2)
        ok || return false
        return _ar_pow_mpq_int(ld, n1, exp, exp_sign, r)    # MPQ^int
    end

    if n2.type === V_MPQ                                    # X ^ rat
        num = exp_sign == -1 ? -numerator(n2.mpq) : numerator(n2.mpq)   # mpz_neg for a negative one
        status, r_den = mpz_to_uint64(denominator(n2.mpq))
        status != 0 && return _ar_pow_maybe_real_mpq(ld, n1, n2, r)     # !FITS_ULONG: always fits
        t = n1.type
        if t === V_INTEGER || t === V_MPZ
            base = t === V_INTEGER ? BigInt(n1.i) : n1.mpz
            r.type = V_MPZ                                  # int ^ rat
            if base < 0 && iseven(r_den)                    # neg ^ int/even is undefined
                r.type = V_FLOAT
                r.f = const_nan
                return check_float(ld, r)
            end
            root, exact = mpz_root(base, r_den)
            exact || return _ar_pow_maybe_real_mpq(ld, n1, n2, r)       # root inexact
            status, r_num = mpz_to_uint64(num)
            status != 0 && return _ar_pow_maybe_real_mpq(ld, n1, n2, r)
            rc, pw = bn_pow_ui(ld, root, r_num)
            rc != 0 && return _ar_pow_maybe_real_mpq(ld, n1, n2, r)
            r.mpz = pw
            if exp_sign == -1                               # create mpq=1/r->value
                r.type = V_MPQ
                r.mpq = BigInt(1) // pw                     # mpq_set_z, mpq_inv
                return check_mpq(r)
            end
            return true
        elseif t === V_MPQ
            q = n1.mpq
            if numerator(q) < 0 && iseven(r_den)            # neg ^ int / even
                r.type = V_FLOAT
                r.f = const_nan
                return check_float(ld, r)
            end
            rn, exact_n = mpz_root(numerator(q), r_den)
            rd, exact_d = exact_n ? mpz_root(denominator(q), r_den) : (BigInt(0), false)
            exact_n && exact_d || return _ar_pow_maybe_real_mpq(ld, n1, n2, r)
            status, r_num = mpz_to_uint64(num)
            status != 0 && return _ar_pow_maybe_real_mpq(ld, n1, n2, r)
            rc1, pn = bn_pow_ui(ld, rn, r_num)
            rc1 != 0 && return _ar_pow_maybe_real_mpq(ld, n1, n2, r)
            rc2, pd = bn_pow_ui(ld, rd, r_num)
            rc2 != 0 && return _ar_pow_maybe_real_mpq(ld, n1, n2, r)
            r.type = V_MPQ
            r.mpq = exp_sign == -1 ? pd // pn : pn // pd    # mpq_inv
            return check_mpq(r)
        end
        if n1.f == 0.0                                      # V_FLOAT: general case of 0.0**X
            return _ar_pow_doreal(ld, n1, n2, exp_sign, r)
        end
        if n1.f < 0 && iseven(r_den)
            r.f = const_nan                                 # negative base, even denominator
        else
            return _ar_pow_doreal_mpq(ld, n1, n2, r)
        end
        r.type = V_FLOAT
        return check_float(ld, r)
    end
    return _ar_pow_doreal(ld, n1, n2, exp_sign, r)
end

# ── arith-c: rationals, the order of reals, bits, the remaining float functions (pl-arith.c) ──────
# The last entries of `ar_funcdefs[]` but `roundtoward/2` (NOT PORTED, see `ar_funcdefs`). The C
# library functions are called through `ccall`, as arith-b's.
# `sinh` & co. of the C library (`cr_sinh` & co. of pl-arith.c, FE_TONEAREST)
"`sinh(x)` of the C library (pl-arith.c `cr_sinh`, FE_TONEAREST)."
_libm_sinh(x::Float64)::Float64 = ccall((:sinh, LIBM), Float64, (Float64,), x)
"`cosh(x)` of the C library (pl-arith.c `cr_cosh`, FE_TONEAREST)."
_libm_cosh(x::Float64)::Float64 = ccall((:cosh, LIBM), Float64, (Float64,), x)
"`tanh(x)` of the C library (pl-arith.c `cr_tanh`, FE_TONEAREST)."
_libm_tanh(x::Float64)::Float64 = ccall((:tanh, LIBM), Float64, (Float64,), x)
# `asinh`, `acosh` and `atanh` are not redefined by `O_ROUND_UP_DOWN`: C's own
"`asinh(x)` of the C library (pl-arith.c `ar_asinh`, C's own: the same as Julia's but for the last digit)."
_libm_asinh(x::Float64)::Float64 = ccall((:asinh, LIBM), Float64, (Float64,), x)
"`acosh(x)` of the C library: a NaN below 1 (Julia's `acosh` throws)."
_libm_acosh(x::Float64)::Float64 = ccall((:acosh, LIBM), Float64, (Float64,), x)
"`atanh(x)` of the C library: a NaN beyond ±1 (Julia's `atanh` throws)."
_libm_atanh(x::Float64)::Float64 = ccall((:atanh, LIBM), Float64, (Float64,), x)
"`erf(x)` of the C library (pl-arith.c `cr_erf`, FE_TONEAREST)."
_libm_erf(x::Float64)::Float64 = ccall((:erf, LIBM), Float64, (Float64,), x)
# PORT: pl-arith.c cr_erfc as _libm_erfc
# The build without CORE-MATH, the pin's: `return 1.0 - cr_erf(in)` — not the C library's erfc, so a large
# argument loses its low bits and erfc(6.0) is 0.0, as swipl's (the oracle's rows).
"`erfc(x)` as upstream computes it without CORE-MATH (pl-arith.c `cr_erfc`): `1.0 - erf(x)`."
_libm_erfc(x::Float64)::Float64 = 1.0 - _libm_erf(x)
"`log10(x)` of the C library (pl-arith.c `cr_log10`, FE_TONEAREST)."
_libm_log10(x::Float64)::Float64 = ccall((:log10, LIBM), Float64, (Float64,), x)
# `lgamma` keeps the sign in the global `signgam`, which nothing reads here
"`lgamma(x)` of the C library (pl-arith.c `cr_lgamma`, FE_TONEAREST)."
_libm_lgamma(x::Float64)::Float64 = ccall((:lgamma, LIBM), Float64, (Float64,), x)

# PORT: pl-arith.c ar_sinh
"`sinh/1` (pl-arith.c `ar_sinh`, UNAIRY_FLOAT_FUNCTION)."
function ar_sinh(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_sinh(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_cosh
"`cosh/1` (pl-arith.c `ar_cosh`, UNAIRY_FLOAT_FUNCTION)."
function ar_cosh(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_cosh(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_tanh
"`tanh/1` (pl-arith.c `ar_tanh`, UNAIRY_FLOAT_FUNCTION)."
function ar_tanh(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_tanh(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_asinh
"`asinh/1` (pl-arith.c `ar_asinh`, UNAIRY_FLOAT_FUNCTION)."
function ar_asinh(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_asinh(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_acosh
"`acosh/1` (pl-arith.c `ar_acosh`, UNAIRY_FLOAT_FUNCTION)."
function ar_acosh(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_acosh(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_atanh
"`atanh/1` (pl-arith.c `ar_atanh`, UNAIRY_FLOAT_FUNCTION)."
function ar_atanh(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_atanh(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_erf
"`erf/1` (pl-arith.c `ar_erf`, UNAIRY_FLOAT_FUNCTION)."
function ar_erf(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_erf(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_erfc
"`erfc/1` (pl-arith.c `ar_erfc`, UNAIRY_FLOAT_FUNCTION)."
function ar_erfc(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_erfc(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_log10
"`log10/1` (pl-arith.c `ar_log10`)."
function ar_log10(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = _libm_log10(n1.f)
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_lgamma
"`lgamma/1` (pl-arith.c `ar_lgamma`): `log(abs(gamma(X)))`, a positive infinity (an overflow) for `X =< 0`."
function ar_lgamma(ld::PL_local_data, n1::number, r::number)::Bool
    promoteToFloatNumber(ld, n1) || return false
    r.f = (n1.f <= 0.0) ? Inf : _libm_lgamma(n1.f)          # INFINITY
    r.type = V_FLOAT
    return check_float(ld, r)
end

# PORT: pl-arith.c ar_nexttoward
# DIVERGES: C's `nexttoward(x, y)` (its second argument a `long double`, here the double `y`) as
# `nextfloat`/`prevfloat`: `y` when `x == y`, a NaN when either is one, else the neighbour of `x`
# towards `y`.
"`nexttoward/2` (pl-arith.c `ar_nexttoward`): the float next to the first argument in the direction of the second."
function ar_nexttoward(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    if promoteToFloatNumber(ld, n1) && promoteToFloatNumber(ld, n2)
        if n1.type === V_FLOAT && n2.type === V_FLOAT
            x = n1.f
            y = n2.f
            r.f = if isnan(x) || isnan(y)
                x + y
            elseif x == y
                y
            elseif y > x
                nextfloat(x)
            else
                prevfloat(x)
            end
            r.type = V_FLOAT
            return check_float(ld, r)
        end
    end
    return false
end

# PORT: pl-arith.c ar_rational
"`rational/1` (pl-arith.c `ar_rational`): the argument as an exact rational, a float converted exactly."
function ar_rational(ld::PL_local_data, n1::number, r::number)::Bool
    cpNumber(r, n1)
    return promoteToMPQNumber(ld, r)
end

# PORT: pl-arith.c ar_numerator
"`numerator/1` (pl-arith.c `ar_numerator`): the numerator of a rational, an integer is its own."
function ar_numerator(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    if intNumber(n1)
        cpNumber(r, n1)
        return true
    end
    if n1.type === V_MPQ
        r.type = V_MPZ
        r.mpz = numerator(n1.mpq)                           # mpz_set(…, mpq_numref(…))
        return true
    end
    return PL_error(ld, "numerator", 1, "", ERR_AR_TYPE, mk_sym(T, :rational), n1)
end

# PORT: pl-arith.c ar_denominator
"`denominator/1` (pl-arith.c `ar_denominator`): the denominator of a rational, 1 for an integer."
function ar_denominator(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    if intNumber(n1)
        r.type = V_INTEGER
        r.i = 1
        return true
    end
    if n1.type === V_MPQ
        r.type = V_MPZ
        r.mpz = denominator(n1.mpq)                         # mpz_set(…, mpq_denref(…))
        return true
    end
    return PL_error(ld, "denominator", 1, "", ERR_AR_TYPE, mk_sym(T, :rational), n1)
end

# PORT: pl-arith.c ar_rationalize
# DIVERGES: `mpq_set_double` returns the rational (see src/pl-gmp.jl).
"`rationalize/1` (pl-arith.c `ar_rationalize`): the simplest rational that converts back to the float."
function ar_rationalize(ld::PL_local_data, n1::number, r::number)::Bool
    t = n1.type
    if t === V_INTEGER || t === V_MPZ || t === V_MPQ
        cpNumber(r, n1)
        return true
    end
    f = n1.f                                                # V_FLOAT
    isnan(f) && return PL_error(ld, ERR_AR_UNDEF)           # FP_NAN
    isinf(f) && return PL_error(ld, ERR_AR_RAT_OVERFLOW)    # FP_INFINITE
    r.mpq = mpq_set_double(f)
    r.type = V_MPQ
    return check_mpq(r)
end

# PORT: pl-incl.h ratNumber
"Whether `n` is a rational, an integer included (pl-incl.h `ratNumber`)."
ratNumber(n::number)::Bool = n.type !== V_FLOAT

# PORT: pl-arith.c ar_rdiv
"`rdiv/2` (pl-arith.c `ar_rdiv`): the exact quotient of two rationals, an integer if it divides."
function ar_rdiv(ld::PL_local_data{T}, n1::number, n2::number, r::number)::Bool where {T}
    if toIntegerNumber(ld, n1, 0) && toIntegerNumber(ld, n2, 0)
        promoteToMPZNumber(n1)
        promoteToMPZNumber(n2)
        iszero(n2.mpz) && return PL_error(ld, "/", 2, "", ERR_DIV_BY_ZERO)
        return ar_rdiv_mpz(n1, n2, r)
    elseif ratNumber(n1) && ratNumber(n2)
        promoteToMPQNumber(ld, n1)
        promoteToMPQNumber(ld, n2)
        iszero(numerator(n2.mpq)) && return PL_error(ld, "/", 2, "", ERR_DIV_BY_ZERO)
        r.type = V_MPQ
        r.mpq = n1.mpq / n2.mpq                             # mpq_div
        return check_mpq(r)
    elseif !ratNumber(n1)
        return PL_error(ld, "rdiv", 2, "", ERR_AR_TYPE, mk_sym(T, :rational), n1)
    end
    return PL_error(ld, "rdiv", 2, "", ERR_AR_TYPE, mk_sym(T, :rational), n2)
end

# PORT: pl-arith.c ar_cmpr
# Compare real numbers: any numeric value is a point on the real number line, compared by
# `cmpReals`: -1, 0 or 1. Comparing with a NaN is a NaN or an error, as the flag `float_undefined`.
"`cmpr/2` (pl-arith.c `ar_cmpr`): -1, 0 or 1 by the mathematical order of the two reals."
function ar_cmpr(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    r.type = V_INTEGER
    r.i = cmpReals(n1, n2)
    if r.i == CMP_NOTEQ                                     # non-number
        if (ld.arith_f_flags & FLT_UNDEFINED) != 0          # check float_undefined flag
            r.type = V_FLOAT                                # return NaN
            r.f = const_nan
        else
            return PL_error(ld, ERR_AR_UNDEF)               # error
        end
    end
    return true
end

# PORT: pl-arith.c ar_maxr
# `maxr` and `minr` are `max` and `min` with three differences: the mathematically correct
# comparison (`cmpReals`); of equal values a rational is preferred to a float (no loss of
# precision); and a NaN argument gives the other. The `default: assert(0)` of the switch cannot be
# reached: `cmpReals` answers one of the four.
"`maxr/2` (pl-arith.c `ar_maxr`): the larger of two reals, a rational preferred when equal."
function ar_maxr(n1::number, n2::number, r::number)::Bool
    c = cmpReals(n1, n2)
    if c == CMPEX_LESS
        cpNumber(r, n2)
    elseif c == CMPEX_EQUAL
        if n1.type !== V_FLOAT                              # preference to rational
            cpNumber(r, n1)
        elseif n2.type !== V_FLOAT
            cpNumber(r, n2)
        elseif is_min_zero(n1)                              # both floats, special case -0.0 < 0.0
            cpNumber(r, n2)
        else
            cpNumber(r, n1)
        end
    elseif c == CMPEX_GREATER
        cpNumber(r, n1)
    else                                                    # CMP_NOTEQ: one or both nan
        if n1.type === V_FLOAT && isnan(n1.f)
            cpNumber(r, n2)
        else
            cpNumber(r, n1)
        end
    end
    return true
end

# PORT: pl-arith.c ar_minr
"`minr/2` (pl-arith.c `ar_minr`): the smaller of two reals, a rational preferred when equal."
function ar_minr(n1::number, n2::number, r::number)::Bool
    c = cmpReals(n1, n2)
    if c == CMPEX_LESS
        cpNumber(r, n1)
    elseif c == CMPEX_EQUAL
        if n1.type !== V_FLOAT                              # preference to rational
            cpNumber(r, n1)
        elseif n2.type !== V_FLOAT
            cpNumber(r, n2)
        elseif is_min_zero(n2)                              # both floats, special case -0.0 < 0.0
            cpNumber(r, n2)
        else
            cpNumber(r, n1)
        end
    elseif c == CMPEX_GREATER
        cpNumber(r, n2)
    else                                                    # CMP_NOTEQ: one or both nan
        if n1.type === V_FLOAT && isnan(n1.f)
            cpNumber(r, n2)
        else
            cpNumber(r, n1)
        end
    end
    return true
end

# PORT: pl-arith.c ar_lcm
# `lcm/2` is bounded by `n1*n2`, so the big case checks the size (gcd/2 needs none).
"`lcm/2` (pl-arith.c `ar_lcm`): the least common multiple of two integers, never negative."
function ar_lcm(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    same_positive_ints(ld, "lcm", n1, n2) || return false
    if n1.type === V_INTEGER
        prod, overflow = mul64(n1.i, n2.i)
        if !overflow
            r.type = V_INTEGER
            r.i = prod != 0 ? prod ÷ i64_gcd(n1.i, n2.i) : 0
            return true
        end
        promoteToMPZNumber(n1)                              # FALLTHROUGH
        promoteToMPZNumber(n2)
    end
    bits = UInt64(ndigits(n1.mpz; base=2)) + UInt64(ndigits(n2.mpz; base=2))   # mpz_sizeinbase
    check_int_bits(ld, bits) || return false
    r.type = V_MPZ
    r.mpz = lcm(n1.mpz, n2.mpz)                             # mpz_lcm
    return true
end

# PORT: pl-arith.c notLessThanZero
"`domain_error(not_less_than_zero, N)` for the function `f/a` (pl-arith.c)."
function notLessThanZero(ld::PL_local_data{T}, f::String, a::Int, n::number)::Bool where {T}
    return PL_error(ld, f, a, "", ERR_AR_DOMAIN, mk_sym(T, :not_less_than_zero), n)
end

# PORT: pl-arith.c lsb64
"The index of the least significant set bit of the positive `int64_t` `i` (pl-arith.c)."
function lsb64(i::Int64)::Int
    j = 0
    i == 0 && return 0
    if (i & 0xffffffff) == 0
        i >>= 32
        j += 32
    end
    if (i & 0xffff) == 0
        i >>= 16
        j += 16
    end
    if (i & 0xff) == 0
        i >>= 8
        j += 8
    end
    if (i & 0xf) == 0
        i >>= 4
        j += 4
    end
    if (i & 0x3) == 0
        i >>= 2
        j += 2
    end
    (i & 0x1) == 0 && (j += 1)
    return j
end

# PORT: pl-arith.c ar_lsb
"`lsb/1` (pl-arith.c `ar_lsb`): the index of the least significant set bit of a positive integer."
function ar_lsb(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "lsb", 1, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    if n1.type === V_INTEGER
        n1.i <= 0 && return mustBePositive(ld, "lsb", 1, n1)
        r.i = lsb64(n1.i)
        r.type = V_INTEGER
        return true
    end
    ar_sign_i(n1) <= 0 && return mustBePositive(ld, "lsb", 1, n1)    # V_MPZ: mpz_sgn
    r.i = trailing_zeros(n1.mpz)                            # mpz_scan1(…, 0)
    r.type = V_INTEGER
    return true
end

# PORT: pl-arith.c my_popcount64
# my_: avoids a NetBSD name conflict
"The number of set bits of `i` (pl-arith.c; `__builtin_popcountll`)."
my_popcount64(i::Int64)::Int = count_ones(i)

# PORT: pl-arith.c ar_popcount
"`popcount/1` (pl-arith.c `ar_popcount`): the number of set bits of a non-negative integer."
function ar_popcount(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, 0) ||
        return PL_error(ld, "popcount", 1, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    if n1.type === V_INTEGER
        n1.i < 0 && return notLessThanZero(ld, "popcount", 1, n1)
        r.i = my_popcount64(n1.i)
        r.type = V_INTEGER
        return true
    end
    ar_sign_i(n1) < 0 && return notLessThanZero(ld, "popcount", 1, n1)   # V_MPZ: mpz_sgn
    r.i = count_ones(n1.mpz)                                # mpz_popcount
    r.type = V_INTEGER
    return true
end

# PORT: pl-arith.c ar_getbit
# `bit(I,K)` is the K-th bit of I; a bit past the end of a non-negative integer is 0. A `mp_bitcnt_t`
# is 64 bits wide, so `K` fits it up to `LONG_MAX`; the 32-bit branch (`sizeof(mp_bitcnt_t) < 8`) is
# not written.
"`getbit/2` (pl-arith.c `ar_getbit`): the K-th bit of the non-negative integer I, 0 or 1."
function ar_getbit(
    ld::PL_local_data{T}, I::number, K::number, r::number
)::Bool where {T}
    toIntegerNumber(ld, I, 0) ||
        return PL_error(ld, "bit", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), I)
    toIntegerNumber(ld, K, 0) ||
        return PL_error(ld, "bit", 2, "", ERR_AR_TYPE, mk_sym(T, :integer), K)
    bit = 0
    if K.type === V_INTEGER
        K.i < 0 && return notLessThanZero(ld, "bit", 2, K)
        bit = K.i
    else                                                    # V_MPZ
        ar_sign_i(K) < 0 && return notLessThanZero(ld, "bit", 2, K)    # mpz_sgn
        K.mpz > typemax(Int64) && @goto too_large           # mpz_cmp_ui(…, LONG_MAX) > 0
        bit = Int(K.mpz)                                    # mpz_get_ui
    end
    if I.type === V_INTEGER
        I.i < 0 && return notLessThanZero(ld, "bit", 2, I)
        bit >= 64 && @goto too_large                        # 8*sizeof(I->value.i)
        r.i = (I.i & (Int64(1) << bit)) != 0 ? 1 : 0
        r.type = V_INTEGER
        return true
    end
    ar_sign_i(I) < 0 && return notLessThanZero(ld, "bit", 2, I)    # V_MPZ: mpz_sgn
    r.i = _mpz_tstbit(I.mpz, bit) ? 1 : 0                   # mpz_tstbit
    r.type = V_INTEGER
    return true
    @label too_large
    r.i = 0
    r.type = V_INTEGER
    return true
end

# PORT: pl-arith.c ar_powm
# DIVERGES: the three type checks return their error (internal record Q5).
"`powm/3` (pl-arith.c `ar_powm`): `base ^ exp mod mod` of three integers, `base` and `exp` non-negative."
function ar_powm(
    ld::PL_local_data{T}, base::number, exp::number, mod::number, r::number
)::Bool where {T}
    intNumber(base) ||
        return PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), base)
    intNumber(exp) ||
        return PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), exp)
    intNumber(mod) ||
        return PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), mod)
    promoteToMPZNumber(base)
    promoteToMPZNumber(exp)
    promoteToMPZNumber(mod)
    ar_sign_i(base) < 0 && return notLessThanZero(ld, "powm", 3, base)
    ar_sign_i(exp) < 0 && return notLessThanZero(ld, "powm", 3, exp)
    ar_sign_i(mod) <= 0 && return mustBePositive(ld, "powm", 3, mod)
    r.type = V_MPZ
    r.mpz = powermod(base.mpz, exp.mpz, mod.mpz)            # mpz_powm
    return true
end

# PORT: pl-arith.c ar_eval
"`eval/1` (pl-arith.c `ar_eval`): the value of its argument, already evaluated."
function ar_eval(n1::number, r::number)::Bool
    cpNumber(r, n1)
    return true
end

# PORT: pl-arith.c ar_random_float
# DIVERGES: the generator (see `_random_u64`): 64 random bits as the fraction `mpf_urandomb`
# returns, truncated to a double by `mpf_get_d` (53 bits), redrawn while 0.0.
"`random_float/0` (pl-arith.c `ar_random_float`): a random float in the open interval (0.0, 1.0)."
function ar_random_float(ld::PL_local_data, r::number)::Bool
    while true
        i = _random_u64(ld)                                 # mpf_urandomb(rop, state, 64)
        r.f = Float64(i >> 11) * 0x1.0p-53                  # mpf_get_d: truncates
        r.f == 0.0 || break
    end
    r.type = V_FLOAT
    return true
end

# PORT: pl-arith.c ar_epsilon
"`epsilon/0` (pl-arith.c `ar_epsilon`): the difference between 1.0 and the next float, `DBL_EPSILON`."
function ar_epsilon(r::number)::Bool
    r.f = eps(Float64)                                      # DBL_EPSILON
    r.type = V_FLOAT
    return true
end

# PORT: pl-arith.c ar_inf
# DIVERGES: not cached in a static `number`: the constant is the positive infinity, `const_inf`.
"`inf/0` (pl-arith.c `ar_inf`): positive infinity."
function ar_inf(r::number)::Bool
    r.f = Inf                                               # const_inf
    r.type = V_FLOAT
    return true
end

# PORT: pl-arith.c ar_nan
# DIVERGES: not cached in a static `number`, as `ar_inf`.
"`nan/0` (pl-arith.c `ar_nan`): the canonical NaN."
function ar_nan(r::number)::Bool
    r.f = const_nan
    r.type = V_FLOAT
    return true
end

# PORT: pl-arith.c ar_funcdefs
# DIVERGES: the entries ported, `(name, arity)`; see the file header. arith-a's and arith-b's keep
# upstream's relative order; arith-c's are APPENDED, so the scan of `isCurrentArithFunction` reaches
# the earlier (hotter) ones as soon as before. `roundtoward/2` is the one upstream entry NOT PORTED:
# it sets the hardware rounding mode (`fesetround`) around the evaluation of its first argument,
# which `evalExpression` handles on its own (`set_roundtoward`), and the kernel has no other mode
# than to nearest (see the file header) — a call is `type_error(evaluable, roundtoward/2)`, where
# swipl evaluates it.
# `integer` and `round` share `ar_integer`, `ceil` and `ceiling` share `ar_ceil`, `atan/2` and
# `atan2/2` share `ar_atan2` and `^` and `**` share `ar_pow`, as upstream's.
"pl-arith.c's `ar_funcdefs[]`: the arithmetic functions, the ported entries."
const ar_funcdefs = (
    (:+, 2), (:-, 2), (:*, 2), (:/, 2), (:-, 1), (:+, 1), (:abs, 1), (:max, 2), (:min, 2),
    (:mod, 2), (:rem, 2), (:div, 2), (:(//), 2), (:gcd, 2), (:sign, 1),
    (Symbol("/\\"), 2), (Symbol("\\/"), 2), (:>>, 2), (:<<, 2), (:xor, 2),
    (Symbol("\\"), 1), (:random, 1),
    (:integer, 1), (:round, 1), (:truncate, 1), (:float, 1), (:floor, 1), (:ceil, 1),
    (:ceiling, 1), (:float_fractional_part, 1), (:float_integer_part, 1), (:copysign, 2),
    (:sqrt, 1), (:sin, 1), (:cos, 1), (:tan, 1), (:asin, 1), (:acos, 1), (:atan, 1),
    (:atan, 2), (:atan2, 2), (:log, 1), (:exp, 1), (:^, 2), (Symbol("**"), 2), (:pi, 0),
    (:e, 0),
    (:cputime, 0), (:msb, 1),
    # arith-c
    (:rational, 1), (:numerator, 1), (:denominator, 1), (:rationalize, 1), (:rdiv, 2),
    (:cmpr, 2), (:maxr, 2), (:minr, 2), (:lcm, 2), (:random_float, 0), (:nexttoward, 2),
    (:sinh, 1), (:cosh, 1), (:tanh, 1), (:asinh, 1), (:acosh, 1), (:atanh, 1), (:lgamma, 1),
    (:erf, 1), (:erfc, 1), (:log10, 1), (:epsilon, 0), (:inf, 0), (:nan, 0), (:lsb, 1),
    (:popcount, 1), (:getbit, 2), (:powm, 3), (:eval, 1)
)

# The names of `ar_funcdefs` that are not Julia syntax, as symbols compared in `_ar_call2`/`_ar_call1`.
const _AR_AND = Symbol("/\\")
const _AR_OR = Symbol("\\/")
const _AR_NEG = Symbol("\\")
const _AR_POW = Symbol("**")

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

# The call of `ar_funcdefs` entry `k` (upstream's `(*(ArithF2)f)(a0, a1, n)` and arity 1, 0 and 3), by
# the entry's name.
function _ar_call2(ld::PL_local_data, k::Int, a0::number, a1::number, r::number)::Bool
    f = ar_funcdefs[k][1]
    f === :+ && return pl_ar_add(ld, a0, a1, r)
    f === :- && return ar_minus(ld, a0, a1, r)
    f === :* && return ar_mul(ld, a0, a1, r)
    f === :/ && return ar_divide(ld, a0, a1, r)
    f === :max && return ar_max(ld, a0, a1, r)
    f === :min && return ar_min(ld, a0, a1, r)
    f === :mod && return ar_mod(ld, a0, a1, r)
    f === :rem && return ar_rem(ld, a0, a1, r)
    f === :div && return ar_div(ld, a0, a1, r)
    f === :(//) && return ar_tdiv(ld, a0, a1, r)
    f === :gcd && return ar_gcd(ld, a0, a1, r)
    f === _AR_AND && return ar_conjunct(ld, a0, a1, r)
    f === _AR_OR && return ar_disjunct(ld, a0, a1, r)
    f === :>> && return ar_shift_right(ld, a0, a1, r)
    f === :<< && return ar_shift_left(ld, a0, a1, r)
    f === :xor && return ar_xor(ld, a0, a1, r)
    (f === :^ || f === _AR_POW) && return ar_pow(ld, a0, a1, r)
    (f === :atan || f === :atan2) && return ar_atan2(ld, a0, a1, r)
    f === :copysign && return ar_copysign(a0, a1, r)
    f === :rdiv && return ar_rdiv(ld, a0, a1, r)                # arith-c
    f === :cmpr && return ar_cmpr(ld, a0, a1, r)
    f === :maxr && return ar_maxr(a0, a1, r)
    f === :minr && return ar_minr(a0, a1, r)
    f === :lcm && return ar_lcm(ld, a0, a1, r)
    f === :nexttoward && return ar_nexttoward(ld, a0, a1, r)
    return ar_getbit(ld, a0, a1, r)                         # :getbit
end
function _ar_call1(ld::PL_local_data, k::Int, a0::number, r::number)::Bool
    f = ar_funcdefs[k][1]
    f === :- && return ar_u_minus(a0, r)
    f === :+ && return ar_u_plus(a0, r)
    f === :abs && return ar_abs(a0, r)
    f === :sign && return ar_sign(a0, r)
    f === _AR_NEG && return ar_negation(ld, a0, r)
    (f === :integer || f === :round) && return ar_integer(a0, r)
    f === :truncate && return ar_truncate(ld, a0, r)
    f === :float && return ar_float(ld, a0, r)
    f === :floor && return ar_floor(ld, a0, r)
    (f === :ceil || f === :ceiling) && return ar_ceil(ld, a0, r)
    f === :float_fractional_part && return ar_float_fractional_part(ld, a0, r)
    f === :float_integer_part && return ar_float_integer_part(ld, a0, r)
    f === :random && return ar_random(ld, a0, r)
    f === :sqrt && return ar_sqrt(ld, a0, r)
    f === :sin && return ar_sin(ld, a0, r)
    f === :cos && return ar_cos(ld, a0, r)
    f === :tan && return ar_tan(ld, a0, r)
    f === :asin && return ar_asin(ld, a0, r)
    f === :acos && return ar_acos(ld, a0, r)
    f === :atan && return ar_atan(ld, a0, r)
    f === :log && return ar_log(ld, a0, r)
    f === :exp && return ar_exp(ld, a0, r)
    f === :msb && return ar_msb(ld, a0, r)
    f === :rational && return ar_rational(ld, a0, r)            # arith-c
    f === :numerator && return ar_numerator(ld, a0, r)
    f === :denominator && return ar_denominator(ld, a0, r)
    f === :rationalize && return ar_rationalize(ld, a0, r)
    f === :sinh && return ar_sinh(ld, a0, r)
    f === :cosh && return ar_cosh(ld, a0, r)
    f === :tanh && return ar_tanh(ld, a0, r)
    f === :asinh && return ar_asinh(ld, a0, r)
    f === :acosh && return ar_acosh(ld, a0, r)
    f === :atanh && return ar_atanh(ld, a0, r)
    f === :lgamma && return ar_lgamma(ld, a0, r)
    f === :erf && return ar_erf(ld, a0, r)
    f === :erfc && return ar_erfc(ld, a0, r)
    f === :log10 && return ar_log10(ld, a0, r)
    f === :lsb && return ar_lsb(ld, a0, r)
    f === :popcount && return ar_popcount(ld, a0, r)
    return ar_eval(a0, r)                                   # :eval
end
# The call of the arity-0 `ar_funcdefs` entry `k` (upstream's `(*(ArithF0)f)(n)`), by the entry's name.
function _ar_call0(ld::PL_local_data, k::Int, r::number)::Bool
    f = ar_funcdefs[k][1]
    f === :pi && return ar_pi(r)
    f === :e && return ar_e(r)
    f === :epsilon && return ar_epsilon(r)
    f === :inf && return ar_inf(r)
    f === :nan && return ar_nan(r)
    f === :random_float && return ar_random_float(ld, r)
    return ar_cputime(r)                                    # :cputime
end
# The call of the arity-3 `ar_funcdefs` entry `k` (upstream's `(*(ArithF3)f)(a0, a1, a2, n)`): `powm/3`.
function _ar_call3(
    ld::PL_local_data, k::Int, a0::number, a1::number, a2::number, r::number
)::Bool
    return ar_powm(ld, a0, a1, a2, r)
end

# ── characters (pl-arith.c) ──────────────────────────────────────────────────────────────────────
# PORT: pl-arith.c arithChar
"The character code `p` stands for in `[X]` (pl-arith.c): a code point, or a one-character atom's code; -1 after raising."
function arithChar(ld::PL_local_data{T}, p::T)::Int where {T}
    p = deRef(ld, p)
    if number_kind(p) === NUM_INTEGER && integer_is_int64(p)    # isTaggedInt(*p)
        chr = int64_value(p)
        0 <= chr <= 0x10ffff && return Int(chr)             # VALID_CODE_POINT(chr)
    elseif kind(p) === SYM                                  # isAtom(*p)
        chr = charCode(p)
        chr >= 0 && return chr
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
    setSlotValue!(ld, a + 1, p)
    PL_error(ld, "", 0, "\"x\" must hold one character", ERR_TYPE, mk_sym(T, :character), a)
    return false
end

# PORT: pl-arith.c arithChar as arithChar_cells
# DIVERGES: on a LOCATION (`_deref_loc`, the workspace's L1_plan/stageL1d_design.md §3e): a tagged
# integer by `valInt`, an atom word by its symbol's `charCode` — no term read; the culprit of the
# type error is exported only on that error path (`_loc_term`, counted). The boundary (a slot's side
# value, a keyed variable) is decided by the term-level `arithChar`, counted in `cold_pairs`.
"The character code location `l` stands for in `[X]` (pl-arith.c `arithChar`); -1 after raising."
function arithChar_cells(ld::PL_local_data{T}, l::Int)::Int where {T}
    k, w, p = _deref_loc(ld, l)                             # deRef(p)
    if k == DU_VALUE && isTaggedIntW(w)                     # isTaggedInt(*p)
        chr = valInt(w)
        0 <= chr <= 0x10ffff && return Int(chr)             # VALID_CODE_POINT(chr)
    elseif k == DU_WORD && isAtomW(w)                       # isAtom(*p)
        chr = charCode(_atom_value(ld, w))
        chr >= 0 && return chr
    elseif k == DU_TERM
        ld.cold_pairs += 1
        return arithChar(ld, _loc_term(ld, k, w, p))
    end
    _ar_type_error(ld, :character, _loc_term(ld, k, w, p))  # ERR_TYPE, ATOM_character
    return -1                                               # EOF
end

# PORT: pl-arith.c getCharExpression as getCharExpression_cells
# DIVERGES: the `TAG_COMPOUND` branch on the CELLS of the `'[|]'/2` compound at global position `c`
# (its arguments at `c + 1`, `c + 2`); the list is exported only for `len_not_one`'s error. A string
# is a value-table entry: the term-level `getCharExpression` reads it (no export).
"`[X]` at global position `c` as its character code in `r` (pl-arith.c); false after raising."
function getCharExpression_cells(ld::PL_local_data{T}, c::Int, r::number)::Bool where {T}
    chr = arithChar_cells(ld, c + 1)                        # argTermP(w, 0)
    chr == -1 && return false
    k, w, _ = _deref_loc(ld, c + 2)                         # argTermP(w, 1)
    (k == DU_WORD && w == ld.atom_nil_w) || return _len_not_one(ld, _compound_term(ld, c))  # isNil(*a)
    r.i = Int64(chr)
    r.type = V_INTEGER
    return true
end

# ── evaluation (pl-arith.c) ──────────────────────────────────────────────────────────────────────
# PORT: pl-arith.c evalExpression
# TRANSITIONAL (L1d, the workspace's L1_plan/stageL1d_design.md §3e): the TERM walk, kept for the
# boundary of `evalExpression_cells` (a slot's side value, a keyed variable, a `$expr/n` compound)
# and a caller holding a term; it goes when the stamp does (L1f).
"Evaluate the expression term reference `expr` refers to, as a TERM, into `result` (pl-arith.c); false after raising."
evalExpression(ld::PL_local_data{T}, expr::term_t, result::number) where {T} =
    _evalExpression_term(ld, deRef(ld, slotValue(ld, expr + 1)), expr, result)

# PORT: pl-arith.c evalExpression as _evalExpression_term
# DIVERGES: an AGENDA of compounds and the argument being evaluated (`ld.arith_frames`) where
# upstream walks the argument cells by address (`*--p` back to the functor word) — in upstream's
# order, LAST argument first, which decides which error a bad expression raises; every child is
# dereferenced through the bindings. The evaluated arguments are on the pooled stack, the FIRST
# argument on top (upstream's `topsOfSegStack`), and a function's result replaces them. No signals
# and no `TAG_REFERENCE` walk (no cells); `roundtoward/2` is not ported. Kernel-only terms (Q-AR5,
# `# DIVERGES`): a grounded value of no SWI type takes the non-text-atom branch,
# `type_error(evaluable, V)`; a compound whose head is not a symbol (`$expr/n`) evaluates its
# arguments and then is not evaluable, `'$expr'/n`. The walk starts at the dereferenced term `start`;
# `expr` is the reference the cyclic-term error names.
"Evaluate the dereferenced term `start` (of reference `expr`) into `result` (pl-arith.c); false after raising."
function _evalExpression_term(
    ld::PL_local_data{T}, start::T, expr::term_t, result::number
)::Bool where {T}
    frames = ld.arith_frames
    fbase = length(frames)
    mark = ld.arith_top
    n_tmp = _number_alloc!(ld)                              # number n_tmp
    n = result                                              # number *n = result
    pushed = 0
    known_acyclic = false
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
    elseif k === SYM                                        # TAG_ATOM
        f0 = isCurrentArithFunction(T, sym_key(p), 0)       # lookupFunctorDef(word2atom(*p), 0)
        if f0 != 0
            _ar_call0(ld, f0, n) || @goto error
        else
            if isTextAtom(p)
                PL_error(ld, ERR_NOT_EVALUABLE, (p, 0))
            else
                _ar_type_error(ld, :evaluable, p)
            end
            @goto error
        end
    else                                                    # TAG_COMPOUND
        arity = nchildren(p) - 1
        if is_pair(p)                                       # FUNCTOR_dot2
            getCharExpression(ld, p, n) || @goto error
        elseif arity == 0                                   # arity0: `pi()`, else not a text atom
            h0 = child(p, 1)
            f0 = kind(h0) === SYM ? isCurrentArithFunction(T, sym_key(h0), 0) : 0
            if f0 != 0
                _ar_call0(ld, f0, n) || @goto error
            else
                _ar_type_error(ld, :evaluable, p)
                @goto error
            end
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
        _ar_call1(ld, f, a0, n_tmp) || @goto error
        cpNumber(a0, n_tmp)                                 # *a0 = *n
    elseif arity == 2
        a1 = ld.arith_numbers[top - 1]
        _ar_call2(ld, f, a0, a1, n_tmp) || @goto error
        ld.arith_top = top - 1                              # popTopOfSegStack
        cpNumber(a1, n_tmp)                                 # *n1 = *n
    else                                                    # arity 3: powm/3
        a1 = ld.arith_numbers[top - 1]
        a2 = ld.arith_numbers[top - 2]
        _ar_call3(ld, f, a0, a1, a2, n_tmp) || @goto error
        ld.arith_top = top - 2                              # popTopOfSegStack, twice
        cpNumber(a2, n_tmp)                                 # *n2 = *n
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
    setSlotValue!(ld, a + 1, p)
    return PL_error(ld, ERR_TYPE, mk_sym(T, expected), a)
end

# PORT: pl-arith.c evalExpression as evalExpression_cells
# DIVERGES (L1d; the workspace's L1_plan/stageL1d_design.md §3e): upstream's WORD walk on LOCATIONS
# (`_deref_loc`'s: a global position, or `-i` for slot `i`) — `term_stack` holds them with the
# `walk_ref` bit (`(loc << 1) | wr`, `ld.arith_cells`); a compound is pushed and the walk goes to its
# LAST argument cell (`c + arity`), and after a leaf it steps back (`p -= 1`) while the cell is a
# FUNCTOR word, applying it to the pooled numbers (`ld.arith_numbers`, upstream's `arg_stack`). A
# leaf is read on its word: a tagged integer by `valInt`, a value-table word by its stored number (a
# string through `getCharExpression`), an atom by its symbol — no export; an export is made only for
# an error's culprit. Not ported: `roundtoward/2` and signals; the ported functions only
# (`isCurrentArithFunction`, by the name's key). THE BOUNDARY — a slot's side value or a keyed
# variable (`DU_TERM`) — is evaluated by the term walk (`_evalExpression_term`), counted in
# `cold_pairs`; a kernel-only `$expr/n` compound (Q-AR5) too, on its (counted) export: the term walk
# evaluates its arguments and then raises `'$expr'/n`, as before. TRANSITIONAL until L1f.
"Evaluate the expression `expr` refers to into `result` on the CELLS (pl-arith.c `evalExpression`); false after raising."
function evalExpression_cells(
    ld::PL_local_data{T}, expr::term_t, result::number
)::Bool where {T}
    stack = ld.arith_cells                                  # term_stack
    sbase = length(stack)
    mark = ld.arith_top
    n_tmp = _number_alloc!(ld)                              # number n_tmp
    n = result                                              # number *n = result
    walk_ref = false
    known_acyclic = false
    pushed = 0
    k, w, p = _deref_loc(ld, -(expr + 1))                   # p = valTermRef(expr); deRef(p)
    p == 0 && (p = -(expr + 1))                             # a word in the slot itself
    start = p
    @label next_term                                        # switch(tag(*p)), p dereferenced
    if k == DU_VALUE
        if isTaggedIntW(w)                                  # TAG_INTEGER, inline
            n.i = valInt(w)
            n.type = V_INTEGER
        else                                                # an indirect: the stored value
            v = ld.vtable[valPtr(w)]
            nk = number_kind(v)
            if nk === NUM_INTEGER || nk === NUM_RATIONAL    # TAG_INTEGER
                get_rational(v, n)
            elseif nk === NUM_FLOAT                         # TAG_FLOAT
                n.f = float_value(v)
                n.type = V_FLOAT
            elseif nk === NUM_STRING                        # TAG_STRING
                getCharExpression(ld, v, n) || @goto error
            else                                            # NUM_OTHER: a non-text blob (Q-AR5)
                _ar_type_error(ld, :evaluable, v)
                @goto error
            end
        end
    elseif k == DU_CELL                                     # TAG_VAR
        PL_error(ld, ERR_INSTANTIATION)
        @goto error
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        _evalExpression_term(ld, deRef(ld, _loc_term(ld, k, w, p)), expr, n) || @goto error
    elseif isAtomW(w)                                       # TAG_ATOM
        a = _atom_value(ld, w)
        f0 = isCurrentArithFunction(T, sym_key(a), 0)       # lookupFunctorDef(word2atom(*p), 0)
        if f0 != 0
            _ar_call0(ld, f0, n) || @goto error
        else
            if isTextAtom(a)
                PL_error(ld, ERR_NOT_EVALUABLE, (a, 0))
            else
                _ar_type_error(ld, :evaluable, a)
            end
            @goto error
        end
    else                                                    # TAG_COMPOUND
        c = valPtr(w)
        f = ld.gstack[c]                                    # term->definition
        arity = arityFunctor(ld.functors, f)
        if f == ld.functor_dot2                             # FUNCTOR_dot2
            getCharExpression_cells(ld, c, n) || @goto error
        elseif arity == 0                                   # arity0: `pi()`, else not a text atom
            h0 = _atom_value(ld, nameFunctor(ld.functors, f))
            f0 = isCurrentArithFunction(T, sym_key(h0), 0)
            if f0 != 0
                _ar_call0(ld, f0, n) || @goto error
            else
                _ar_type_error(ld, :evaluable, _compound_term(ld, c))
                @goto error
            end
        elseif nameFunctor(ld.functors, f) == ld.atom_dexpr # Q-AR5: on its export, the term walk
            _evalExpression_term(ld, _compound_term(ld, c), expr, n) || @goto error
        else
            push!(stack, (p << 1) | Int(walk_ref))          # pushForMark(&term_stack, p, walk_ref)
            pushed += 1
            if pushed % 1024 == 0 && pushed > 1000 && !known_acyclic
                if is_acyclic_cells(ld, start)
                    known_acyclic = true
                else
                    PL_error(
                        ld, "", 0, "cyclic term", ERR_TYPE, mk_sym(T, :expression), expr
                    )
                    @goto error
                end
            end
            p = c + arity                                   # p = &term->arguments[arity-1]
            walk_ref = false
            n = n_tmp
            @goto read_p
        end
    end
    p == start && @goto done                                # a leaf: n == result
    if walk_ref                                             # popForMark(&term_stack, &p, &walk_ref)
        e = pop!(stack)
        p, walk_ref = e >> 1, (e & 1) != 0
    end
    cpNumber(_number_alloc!(ld), n_tmp)                     # pushSegStack(&arg_stack, n_tmp)
    @label step_back
    p -= 1
    f = ld.gstack[p]
    isFunctor(f) || @goto read_p                            # tagex(*--p) == (TAG_ATOM|STG_GLOBAL)
    arity = arityFunctor(ld.functors, f)                    # the functor: apply it
    name = _atom_value(ld, nameFunctor(ld.functors, f))
    fi = isCurrentArithFunction(T, sym_key(name), arity)
    if fi == 0
        PL_error(ld, ERR_NOT_EVALUABLE, (name, arity))
        @goto error
    end
    top = ld.arith_top
    a0 = ld.arith_numbers[top]                              # a[0], the first argument
    if arity == 1
        _ar_call1(ld, fi, a0, n_tmp) || @goto error
        cpNumber(a0, n_tmp)                                 # *a0 = *n
    elseif arity == 2
        a1 = ld.arith_numbers[top - 1]
        _ar_call2(ld, fi, a0, a1, n_tmp) || @goto error
        ld.arith_top = top - 1                              # popTopOfSegStack
        cpNumber(a1, n_tmp)                                 # *n1 = *n
    else                                                    # arity 3: powm/3
        a1 = ld.arith_numbers[top - 1]
        a2 = ld.arith_numbers[top - 2]
        _ar_call3(ld, fi, a0, a1, a2, n_tmp) || @goto error
        ld.arith_top = top - 2                              # popTopOfSegStack, twice
        cpNumber(a2, n_tmp)                                 # *n2 = *n
    end
    e = pop!(stack)                                         # popForMark(&term_stack, &p, &walk_ref)
    p, walk_ref = e >> 1, (e & 1) != 0
    if p == start
        cpNumber(result, n_tmp)                             # *result = *n
        @goto done
    end
    if walk_ref
        e = pop!(stack)
        p, walk_ref = e >> 1, (e & 1) != 0
    end
    @goto step_back
    @label read_p                                           # an argument cell, not dereferenced
    if isRef(ld.gstack[p])                                  # TAG_REFERENCE
        push!(stack, (p << 1) | Int(walk_ref))              # pushForMark(&term_stack, p, walk_ref)
        walk_ref = true
    end
    k, w, p = _deref_loc(ld, p)                             # deRef(p)
    @goto next_term
    @label done
    resize!(stack, sbase)
    ld.arith_top = mark
    return true
    @label error
    resize!(stack, sbase)                                   # clearSegStack(&term_stack)
    ld.arith_top = mark                                     # popSegStack(&arg_stack, …)
    return false
end

# PORT: pl-arith.c valueExpression
# DIVERGES: on the WORD (L1d step 4; §3e): `expr` dereferenced to a tagged integer gives `valInt`,
# to a value-table float its value — no term read; else `evalExpression_cells`. `EXCEPTION_GUARDED`
# has nothing to guard — no `longjmp`.
"Evaluate the expression `expr` refers to into `n` (pl-arith.c): the fast paths, else `evalExpression_cells`."
function valueExpression(ld::PL_local_data{T}, expr::term_t, n::number)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(expr + 1))                   # deRef(p)
    if k == DU_VALUE
        if isTaggedIntW(w)                                  # (TAG_INTEGER|STG_INLINE)
            n.i = valInt(w)
            n.type = V_INTEGER
            return true
        end
        v = ld.vtable[valPtr(w)]
        if number_kind(v) === NUM_FLOAT                     # tag(*p) == TAG_FLOAT
            n.f = float_value(v)
            n.type = V_FLOAT
            return true
        end
    end
    return evalExpression_cells(ld, expr, n)
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
