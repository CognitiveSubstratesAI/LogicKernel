# UPSTREAM: swipl-devel src/pl-arith.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-arith.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-incl.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-inline.h @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-os.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-arith.h, pl-inline.h, pl-arith.c (also the backports 1582e8b3 and a8e64f93, already ported): cell-tag access behind pl-data.h macros, no change of value, order, error or side effect. Also re-cited: pl-incl.h: access-only (d755bdc4) ported; ATOM_RESERVE_BATCH is pl-incl.jl:460 (commit 5); the PLFLAG_EPILOG comma is no value.
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
#     have nothing to do for the memory: Julia's GC frees a `BigInt`. The rounding mode is the hardware's
#     (`fegetround`/`fesetround`, src/pl-gmp.jl), held ONLY for the duration of one evaluation:
#     `evalExpression_cells` sets the mode `float_rounding` names, `roundtoward/2` sets another inside it,
#     and a `finally` puts the mode found at the entry back (upstream leaves the mode it set after an
#     error in `roundtoward/2`'s first argument and after `set_prolog_flag(float_rounding, M)`: swipl's
#     hardware mode is the process's, here it would be the Julia runtime's). Float operations outside an
#     evaluation (reading and printing floats, the VM's own arithmetic) run to nearest.
#   * The flags: `LD->arith.f.flags` at upstream's default (`float_overflow`, `float_zero_div` and
#     `float_undefined` = error, `float_underflow` = ignore); `prefer_rationals` and `iso` are bits of
#     the mask (`truePrologFlag`), false, as their defaults. Nothing sets a flag yet (no
#     `set_prolog_flag/2` until R2 F1b); since R2 F1a `current_prolog_flag/2` reads them (`is_arith_flag`,
#     `get_arith_flag` below).

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

# PORT: pl-arith.h moveNumber
# DIVERGES: the "structure copy" is a copy of the fields (`cpNumber`'s), the values shared
# (immutable): there is no GMP ownership to transfer.
"""
Shallow copy of number `from` to `to` (pl-arith.h `moveNumber`): for a small integer or a float only
its value and type; otherwise the whole number.
"""
function moveNumber(to::number, from::number)::Nothing
    t = from.type
    if t === V_INTEGER
        to.i = from.i
    elseif t === V_FLOAT
        to.f = from.f
    else
        cpNumber(to, from)                      # *to = *from (structure copy)
        return nothing
    end
    to.type = t
    return nothing
end

# ── float checks (pl-arith.c) ────────────────────────────────────────────────────────────────────
# PORT: pl-arith.h FLT_ROUND_NEAREST
"Round to nearest (pl-arith.h), the default."
const FLT_ROUND_NEAREST = UInt32(0x0001)
# PORT: pl-arith.h FLT_ROUND_TO_POS
"Round toward positive infinity (pl-arith.h)."
const FLT_ROUND_TO_POS = UInt32(0x0002)
# PORT: pl-arith.h FLT_ROUND_TO_NEG
"Round toward negative infinity (pl-arith.h)."
const FLT_ROUND_TO_NEG = UInt32(0x0003)
# PORT: pl-arith.h FLT_ROUND_TO_ZERO
"Round toward zero (pl-arith.h)."
const FLT_ROUND_TO_ZERO = UInt32(0x0004)
# PORT: pl-arith.h FLT_ROUND_MASK
"The rounding mode's bits in `arith.f.flags` (pl-arith.h)."
const FLT_ROUND_MASK = UInt32(0x000f)
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
# kernel takes LP64's `long`, an `Int64`, where that check can never fire, and drops it. A negative
# amount is negated as C does (`-LONG_MIN` stays `LONG_MIN`: two's complement wraps) and then READ AS
# UNSIGNED where upstream's `size_t`/`uint64_t`/`mp_bitcnt_t` arithmetic does (`reinterpret`, not
# `UInt64(shift)`, which throws an InexactError for a negative: `1 >> -9223372036854775808` — group F's
# fuzzer, 2026-10-23; swipl answers resource_error(stack)). Otherwise as
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
            bits = reinterpret(UInt64, shift) + UInt64(
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
            r.i =                                           # `shift >= sizeof(int64_t)*8`: unsigned
                reinterpret(UInt64, shift) >= 64 ? (n1.i >= 0 ? 0 : -1) : n1.i >> shift
        end
        r.type = V_INTEGER
        return true
    end
    @label mpz
    r.type = V_MPZ
    if dir < 0                                              # shift left (<<)
        msb = UInt64(ndigits(n1.mpz; base=2)) + reinterpret(UInt64, shift)
        check_int_bits(ld, msb) || return false
        r.mpz = n1.mpz << shift                             # mpz_mul_2exp
    else
        r.mpz = n1.mpz >> reinterpret(UInt64, shift)        # mpz_fdiv_q_2exp: floor (a `mp_bitcnt_t`)
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
# The flags `ar_divide` and `ar_pow` read are `truePrologFlag(ld, PLFLAG_ISO)` and
# `truePrologFlag(ld, PLFLAG_RATIONAL)`, bits of the local data's mask (src/pl-incl.jl; since R2
# F1a — until then both were constants, false, the flags' defaults).

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
    if !truePrologFlag(ld, PLFLAG_ISO)
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
            if truePrologFlag(ld, PLFLAG_RATIONAL)
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
            truePrologFlag(ld, PLFLAG_RATIONAL) && return ar_rdiv_mpz(n1, n2, r)
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
# default, so `cr_sin` & co. are the libm call in FE_TONEAREST mode, rounded outwards by `nexttoward` as
# the rounding mode says: `CR_FUNC` and its kin below).
# Julia's own `sin`, `exp`, `^`, ... are other implementations and differ from glibc's in the last
# digit for about 1 argument in 100 (measured), and its `sqrt`, `asin`, ... throw where C returns a
# NaN, so each is called through `ccall`.
# DIVERGES: the library is named `libm.so.6`, glibc's soname: the kernel runs on Linux (CI: ubuntu).
"The C math library the evaluable functions call (glibc's soname)."
const LIBM = "libm.so.6"

# The raw libm calls the `cr_*` functions wrap (`sin(in)` inside upstream's macro, in FE_TONEAREST mode).
_c_sin(x::Float64)::Float64 = ccall((:sin, LIBM), Float64, (Float64,), x)
_c_cos(x::Float64)::Float64 = ccall((:cos, LIBM), Float64, (Float64,), x)
_c_tan(x::Float64)::Float64 = ccall((:tan, LIBM), Float64, (Float64,), x)
_c_asin(x::Float64)::Float64 = ccall((:asin, LIBM), Float64, (Float64,), x)
_c_acos(x::Float64)::Float64 = ccall((:acos, LIBM), Float64, (Float64,), x)
_c_atan(x::Float64)::Float64 = ccall((:atan, LIBM), Float64, (Float64,), x)
_c_atan2(y::Float64, x::Float64)::Float64 =
    ccall((:atan2, LIBM), Float64, (Float64, Float64), y, x)
_c_exp(x::Float64)::Float64 = ccall((:exp, LIBM), Float64, (Float64,), x)
_c_log(x::Float64)::Float64 = ccall((:log, LIBM), Float64, (Float64,), x)
_c_pow(b::Float64, e::Float64)::Float64 =
    ccall((:pow, LIBM), Float64, (Float64, Float64), b, e)
_c_sinh(x::Float64)::Float64 = ccall((:sinh, LIBM), Float64, (Float64,), x)
_c_cosh(x::Float64)::Float64 = ccall((:cosh, LIBM), Float64, (Float64,), x)
_c_tanh(x::Float64)::Float64 = ccall((:tanh, LIBM), Float64, (Float64,), x)
_c_erf(x::Float64)::Float64 = ccall((:erf, LIBM), Float64, (Float64,), x)
_c_log10(x::Float64)::Float64 = ccall((:log10, LIBM), Float64, (Float64,), x)
# `lgamma` keeps the sign in the global `signgam`, which nothing reads here
_c_lgamma(x::Float64)::Float64 = ccall((:lgamma, LIBM), Float64, (Float64,), x)

# PORT: pl-arith.c CR_FUNC
# DIVERGES: the macro's body as a function of the libm call `f` (a function value, specialised), for `log`, `log10`,
# `tan`, `asin`, `acos`, `atan`, `sinh` and `lgamma` — `cr_log` & co. are `_libm_log` & co.
"The `cr_` function of `f` with no limit on its result (pl-arith.c `CR_FUNC`): `f` to nearest, then one neighbour outwards."
function CR_FUNC(f::F, x::Float64)::Float64 where {F}
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = f(x)
    if isfinite(result)
        if roundMode == FE_UPWARD
            result = nexttoward(result, Inf)
        elseif roundMode == FE_DOWNWARD
            result = nexttoward(result, -Inf)
        elseif roundMode == FE_TOWARDZERO
            result = nexttoward(result, 0.0)
        end
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end

# PORT: pl-arith.c CR_FUNC_1
# DIVERGES: as `CR_FUNC`, for `sin`, `cos` and `tanh`: the result is bounded by 1.0 in absolute value.
"The `cr_` function of `f` with `abs(result) =< 1.0` (pl-arith.c `CR_FUNC_1`)."
function CR_FUNC_1(f::F, x::Float64)::Float64 where {F}
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = f(x)
    if isfinite(result)
        if roundMode == FE_UPWARD
            result = (result < 1.0) ? nexttoward(result, Inf) : 1.0
        elseif roundMode == FE_DOWNWARD
            result = (result > -1.0) ? nexttoward(result, -Inf) : -1.0
        elseif roundMode == FE_TOWARDZERO
            result = nexttoward(result, 0.0)
        end
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end

# PORT: pl-arith.c CR_FUNC as _libm_log
"`log(x)` of the C library (pl-arith.c `cr_log`)."
_libm_log(x::Float64)::Float64 = CR_FUNC(_c_log, x)
# PORT: pl-arith.c CR_FUNC as _libm_log10
"`log10(x)` of the C library (pl-arith.c `cr_log10`)."
_libm_log10(x::Float64)::Float64 = CR_FUNC(_c_log10, x)
# PORT: pl-arith.c CR_FUNC_1 as _libm_sin
"`sin(x)` of the C library (pl-arith.c `cr_sin`)."
_libm_sin(x::Float64)::Float64 = CR_FUNC_1(_c_sin, x)
# PORT: pl-arith.c CR_FUNC_1 as _libm_cos
"`cos(x)` of the C library (pl-arith.c `cr_cos`)."
_libm_cos(x::Float64)::Float64 = CR_FUNC_1(_c_cos, x)
# PORT: pl-arith.c CR_FUNC as _libm_tan
"`tan(x)` of the C library (pl-arith.c `cr_tan`)."
_libm_tan(x::Float64)::Float64 = CR_FUNC(_c_tan, x)
# PORT: pl-arith.c CR_FUNC as _libm_asin
"`asin(x)` of the C library (pl-arith.c `cr_asin`)."
_libm_asin(x::Float64)::Float64 = CR_FUNC(_c_asin, x)
# PORT: pl-arith.c CR_FUNC as _libm_acos
"`acos(x)` of the C library (pl-arith.c `cr_acos`)."
_libm_acos(x::Float64)::Float64 = CR_FUNC(_c_acos, x)
# PORT: pl-arith.c CR_FUNC as _libm_atan
"`atan(x)` of the C library (pl-arith.c `cr_atan`)."
_libm_atan(x::Float64)::Float64 = CR_FUNC(_c_atan, x)
# PORT: pl-arith.c cr_atan2 as _libm_atan2
"`atan2(y, x)` of the C library (pl-arith.c `cr_atan2`): one neighbour outwards, the result finite (|result| =< pi)."
function _libm_atan2(y::Float64, x::Float64)::Float64
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = _c_atan2(y, x)                                 # abs(result) =< pi
    if roundMode == FE_UPWARD
        result = nexttoward(result, Inf)
    elseif roundMode == FE_DOWNWARD
        result = nexttoward(result, -Inf)
    elseif roundMode == FE_TOWARDZERO
        result = nexttoward(result, 0.0)
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end
# PORT: pl-arith.c cr_exp as _libm_exp
"`exp(x)` of the C library (pl-arith.c `cr_exp`): the lower limit of the result is 0.0."
function _libm_exp(x::Float64)::Float64
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = _c_exp(x)
    if roundMode == FE_UPWARD
        if x != -Inf
            result = nexttoward(result, Inf)
        end
    elseif roundMode == FE_DOWNWARD || roundMode == FE_TOWARDZERO
        if result != Inf
            result = nexttoward(result, 0.0)
        end
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end
# PORT: pl-arith.c cr_pow as _libm_pow
"`pow(b, e)` of the C library (pl-arith.c `cr_pow`): the lower limit of the result is 0.0."
function _libm_pow(b::Float64, e::Float64)::Float64
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = _c_pow(b, e)
    if !isnan(result)
        if roundMode == FE_UPWARD
            result = (e == -Inf) ? 0.0 : nexttoward(result, Inf)
        elseif roundMode == FE_DOWNWARD
            result = (e == -Inf) ? 0.0 : nexttoward(result, -Inf)
        elseif roundMode == FE_TOWARDZERO
            if result != Inf
                result = nexttoward(result, 0.0)
            end
        end
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end
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
"`pi/0` (pl-arith.c `ar_pi`): `M_PI`, the next float up when rounding upward."
function ar_pi(r::number)::Bool
    r.f = (fegetround() == FE_UPWARD) ? nexttoward(Float64(π), Inf) : Float64(π)    # M_PI
    r.type = V_FLOAT
    return true
end

# PORT: pl-arith.c ar_e
"`e/0` (pl-arith.c `ar_e`): `M_E`, the next float up when rounding upward."
function ar_e(r::number)::Bool
    r.f = (fegetround() == FE_UPWARD) ? nexttoward(Float64(ℯ), Inf) : Float64(ℯ)    # M_E
    r.type = V_FLOAT
    return true
end

# `CpuTime` is src/os/pl-os.jl's (pl-os.c), since Y1: it was here, as a `clock_gettime` of its own.
# PORT: pl-arith.c ar_cputime
"`cputime/0` (pl-arith.c `ar_cputime`): the CPU seconds the process has used."
function ar_cputime(r::number)::Bool
    r.f = CpuTime(CPU_USER)
    r.type = V_FLOAT
    return true
end

# The random source: upstream's `LD->arith.random` is a GMP `gmp_randstate_t`, the Mersenne twister
# (`gmp_randinit_mt`, GMP's randmt.c: `randseed_mt`, `__gmp_mt_recalc_buffer`, `__gmp_mt_getnext`,
# `randget_mt`) that `init_random` makes and `seed_random` seeds. Here the state is `ld.random_state`,
# a `Vector{UInt32}` of the generator's struct (`mt[624]`, then `mti`; empty until `init_random`), and
# the GMP generator is written out as named pieces, so that a seed gives swipl's stream and
# `random_property(state(S))` shows swipl's state number (the struct's bytes as one integer, the same
# 20032 bits).
# DIVERGES: the struct is a `Vector{UInt32}`, not GMP's allocation; the state integer's padding word
# above `mti` is zero.

const MT_N = 624
const MT_M = 397
const MT_MATRIX_A = 0x9908b0df
const MT_WARM_UP = 2000                                     # randmt.c WARM_UP
const MT_LIMBS = 313                                        # the struct's size in 64-bit limbs

# GMP source (not swipl-devel): randmt.c mangle_seed
# One reduction step of GMP's `mangle_seed`: `r` modulo 2^19937 - 20023, as upstream's inner loop.
function _mt_reduce(r::BigInt)::BigInt
    while true
        t = r >> 19937                                      # mpz_tdiv_q_2exp(t, r, 19937)
        iszero(t) && return r
        r = (r & ((BigInt(1) << 19937) - 1)) + t * 20023    # mpz_tdiv_r_2exp, mpz_addmul_ui
    end
end

# GMP source (not swipl-devel): randmt.c mangle_seed
"`b^1074888996` modulo 2^19937 - 20023, GMP's mangling of a seed (randmt.c `mangle_seed`)."
function _mt_mangle_seed(b::BigInt)::BigInt
    r = b
    e = UInt64(0x40118124)
    bit = UInt64(0x20000000)
    while true
        r = _mt_reduce(r * r)
        while (e & bit) != 0
            e ⊻= bit
            r = _mt_reduce(r * b)
        end
        bit >>= 1
        bit == 0 && return r
    end
end

# GMP source (not swipl-devel): randmt.c __gmp_mt_recalc_buffer
"Refill the twister's 624 words (`__gmp_mt_recalc_buffer`); `mt` is 1-based here."
function _mt_recalc_buffer!(mt::Vector{UInt32})::Nothing
    for kk in 0:(MT_N - MT_M - 1)
        y = (mt[kk + 1] & 0x80000000) | (mt[kk + 2] & 0x7fffffff)
        mt[kk + 1] = mt[kk + MT_M + 1] ⊻ (y >> 1) ⊻ ((y & 1) != 0 ? MT_MATRIX_A : UInt32(0))
    end
    for kk in (MT_N - MT_M):(MT_N - 2)
        y = (mt[kk + 1] & 0x80000000) | (mt[kk + 2] & 0x7fffffff)
        mt[kk + 1] =
            mt[kk + (MT_M - MT_N) + 1] ⊻ (y >> 1) ⊻
            ((y & 1) != 0 ? MT_MATRIX_A : UInt32(0))
    end
    y = (mt[MT_N] & 0x80000000) | (mt[1] & 0x7fffffff)
    mt[MT_N] = mt[MT_M] ⊻ (y >> 1) ⊻ ((y & 1) != 0 ? MT_MATRIX_A : UInt32(0))
    return nothing
end

# GMP source (not swipl-devel): randmt.c randseed_mt
"`gmp_randseed` on the twister (randmt.c `randseed_mt`): `mt` is reseeded from the integer `seed`."
function _mt_randseed!(mt::Vector{UInt32}, seed::BigInt)::Nothing
    length(mt) == MT_N + 1 || resize!(mt, MT_N + 1)
    modulus = (BigInt(1) << 19937) - 20027                  # mpz_setbit(mod, 19937); mpz_sub_ui
    seed1 = mod(seed, modulus) + 2                          # mpz_mod, mpz_add_ui
    seed1 = _mt_mangle_seed(seed1)
    if ((seed1 >> 19936) & 1) != 0                          # the last bit goes to bit 31 of mt[0]
        mt[1] = 0x80000000
        seed1 -= BigInt(1) << 19936                         # mpz_clrbit
    else
        mt[1] = UInt32(0)
    end
    for i in 1:(MT_N - 1)                                   # mpz_export into mt[1..N-1], zero filled
        mt[i + 1] = UInt32(seed1 & 0xffffffff)
        seed1 >>= 32
    end
    for _ in 1:(MT_WARM_UP ÷ MT_N)
        _mt_recalc_buffer!(mt)
    end
    mt[MT_N + 1] = UInt32(MT_WARM_UP % MT_N)                # p->mti
    return nothing
end

# GMP source (not swipl-devel): randmt.c __gmp_mt_getnext
"The next tempered 32 bits of the twister (`__gmp_mt_getnext`)."
function _mt_getnext!(mt::Vector{UInt32})::UInt32
    if mt[MT_N + 1] >= MT_N
        _mt_recalc_buffer!(mt)
        mt[MT_N + 1] = 0
    end
    y = mt[Int(mt[MT_N + 1]) + 1]
    mt[MT_N + 1] += 1
    y ⊻= y >> 11
    y ⊻= (y << 7) & 0x9d2c5680
    y ⊻= (y << 15) & 0xefc60000
    y ⊻= y >> 18
    return y
end

# GMP source (not swipl-devel): randmt.c randget_mt
"`nbits` random bits as an integer (GMP `_gmp_rand` on the twister: whole limbs as two words, low word first; a partial limb keeps its low bits)."
function _mt_randget!(mt::Vector{UInt32}, nbits::Int)::BigInt
    nlimbs, rbits = divrem(nbits, 64)
    limbs = Vector{UInt64}(undef, nlimbs)
    for i in 1:nlimbs
        lo = UInt64(_mt_getnext!(mt))
        limbs[i] = lo | (UInt64(_mt_getnext!(mt)) << 32)
    end
    top = UInt64(0)
    if rbits != 0
        if rbits < 32
            top = UInt64(_mt_getnext!(mt)) & ((UInt64(1) << rbits) - 1)
        else
            lo = UInt64(_mt_getnext!(mt))
            hi = UInt64(_mt_getnext!(mt)) & ((UInt64(1) << (rbits - 32)) - 1)
            top = lo | (hi << 32)
        end
    end
    # the limbs were drawn low limb first, the partial limb last (GMP fills dest[0..] upwards)
    x = BigInt(top)
    for i in nlimbs:-1:1
        x = (x << 64) | BigInt(limbs[i])
    end
    return x
end

# ORIGINAL: GMP `gmp_randseed_ui`'s seed integer
# (the seed of `set_random(seed(N))` for a small integer is an `unsigned long`)
"The `unsigned long` `i` as seed integer (`(unsigned long)n.value.i`)."
_ulong_seed(i::Int64)::BigInt = BigInt(reinterpret(UInt64, i))

# PORT: pl-arith.c seed_from_dev
# DIVERGES: the read is `readbytes!` up to 128 bytes (it returns at 128 bytes or at the end of the file), where upstream's loop reads
# until 16 bytes are in and takes whatever the last `read` returned (up to 128): on a device that hands out fewer than 128 bytes per
# read the seed is longer here, and a device that blocks after 16 bytes blocks here (`/dev/urandom`, `/dev/random` of a current kernel
# give 128 at once). An error from `open` (`SystemError`) is a false return, as `open() == -1`.
"Seed the generator from a character device (`/dev/urandom`, `/dev/random`): true when 16 bytes or more were read."
function seed_from_dev(ld::PL_local_data, dev::String)::Bool
    io = try
        open(dev, "r")                                      # open(dev, O_RDONLY)
    catch e
        (e isa SystemError || e isa Base.IOError) || rethrow()
        return false
    end
    done = false
    try
        if Base.Filesystem.ischardev(stat(io))              # fstat, S_ISCHR
            buf = Vector{UInt8}(undef, 128)                 # RAND_SEED_LEN
            rd = readbytes!(io, buf, 128)
            if rd >= 16                                     # MIN_RAND_SEED_LEN
                seed = BigInt(0)                            # mpz_import(seed, rd, 1, 1, 0, 0, seedarray)
                for i in 1:rd
                    seed = (seed << 8) | buf[i]
                end
                _mt_randseed!(ld.random_state, seed)
                done = true
            end
        end
    finally
        close(io)
    end
    return done
end

# PORT: pl-arith.c seed_random
# DIVERGES: `seed_from_crypt_context` is the Windows arm (nothing here: false).
"Seed the generator from the system (pl-arith.c `seed_random`): the devices, else the wall clock."
function seed_random(ld::PL_local_data)::Nothing
    if !seed_from_dev(ld, "/dev/urandom") && !seed_from_dev(ld, "/dev/random")
        key = reinterpret(UInt64, WallTime())               # key ^= u.l[i]: one long per double
        _mt_randseed!(ld.random_state, BigInt(key))         # gmp_randseed_ui
    end
    return nothing
end

# PORT: pl-arith.c init_random
"Make the generator on first use (pl-arith.c `init_random`): `gmp_randinit_mt` (seed 5489), then `seed_random`."
function init_random(ld::PL_local_data)::Nothing
    if isempty(ld.random_state)
        resize!(ld.random_state, MT_N + 1)
        _mt_randseed!(ld.random_state, BigInt(5489))        # gmp_randinit_mt: gmp_randseed_ui(5489)
        seed_random(ld)
    end
    return nothing
end

# GMP source (not swipl-devel): mpz/urandomm.c mpz_urandomm
"A random integer in `[0, n)` for `n > 0` (GMP `mpz_urandomm`): `nbits` random bits until below `n`, 80 tries at most."
function _mpz_urandomm(ld::PL_local_data, n::BigInt)::BigInt
    pow2 = count_ones(n) == 1                               # POW2_P of the limbs
    nbits = ndigits(n; base=2) - (pow2 ? 1 : 0)
    nbits == 0 && return BigInt(0)                          # n == 1
    count = 80                                              # MAX_URANDOMM_ITER
    while true
        rp = _mt_randget!(ld.random_state, nbits)
        rp < n && return rp
        count -= 1
        count == 0 && return rp - n                         # too many iterations: result mod n
    end
end

# PORT: pl-arith.c ar_random
# DIVERGES: the pin's `#if O_BF` arm (a libbf build: it draws with `mt_rand_u32`) is not this one: the kernel ports the arm of the
# pin's own build (GMP, `mpz_urandomm`), whose stream test_arith_random_swipl.out pins.
# DIVERGES: the argument is not promoted in place (`promoteToMPZNumber(n1)`): a `V_INTEGER` takes the
# `V_MPZ` branch with its value as a `BigInt`; the result is `V_MPZ` as upstream's.
"`random/1` (pl-arith.c `ar_random`): a random integer in `[0, n)`."
function ar_random(ld::PL_local_data{T}, n1::number, r::number)::Bool where {T}
    toIntegerNumber(ld, n1, TOINT_CONVERT_FLOAT) ||
        return PL_error(ld, "random", 1, "", ERR_AR_TYPE, mk_sym(T, :integer), n1)
    ar_sign_i(n1) <= 0 && return mustBePositive(ld, "random", 1, n1)
    init_random(ld)
    n = n1.type === V_INTEGER ? BigInt(n1.i) : n1.mpz       # promoteToMPZNumber(n1)
    r.type = V_MPZ
    r.mpz = _mpz_urandomm(ld, n)                            # mpz_urandomm
    return true
end

# ORIGINAL: upstream's `PL_get_number` answers `V_MPZ` for an integer beyond the tagged range
# (`max_tagged_integer`, 2^56-1 at the pin); the kernel's term layer holds every `Int64` as `V_INTEGER`
# (`get_rational`). `set_random/1` takes the two as upstream takes the `V_MPZ`.
"Whether `n` is a `V_INTEGER` past the tagged range (an upstream `V_MPZ`)."
_is_big_int64(n::number)::Bool =
    n.type === V_INTEGER && !(PLMINTAGGEDINT <= n.i <= PLMAXTAGGEDINT)

# ORIGINAL: the value of an integer `number` as a `BigInt`
"The value of the integer `n` (`V_INTEGER` or `V_MPZ`) as a `BigInt`."
_number_bigint(n::number)::BigInt = n.type === V_INTEGER ? BigInt(n.i) : n.mpz

# PORT: pl-arith.c set_random as pl_set_random1_va
# DIVERGES: a `V_INTEGER` past the tagged range takes the `V_MPZ` arms (see `_is_big_int64`); a state (`state(S)`) is copied into the struct as `mpz_set` into the seed limbs does,
# but a number of more than 313 limbs is a `domain_error(random_state, S)` (GMP would reallocate the
# seed under the generator's struct); the struct has no padding word to copy into.
# (PRED_IMPL("set_random", 1, set_random, 0))
"`set_random/1` (pl-arith.c): `seed(random)`, `seed(Int)` or `state(Int)` of the random generator."
function pl_set_random1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    init_random(ld)
    na = PL_get_name_arity(ld, A1)
    if na !== nothing && na[2] == 1
        name = na[1]
        arg = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, A1, arg)
        if sym_key(name) == sym_key(mk_sym(T, :seed))
            a = PL_get_atom(ld, arg)
            if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :random))
                seed_random(ld)
                return FTRUE
            end
            n = _number_alloc!(ld)
            if !PL_get_number(ld, arg, n)
                _number_free!(ld, 1)
                return if PL_error(
                    ld, "", 0, "integer or 'random'", ERR_TYPE, mk_sym(T, :seed), arg
                )
                    FTRUE
                else
                    FFALSE
                end
            end
            rc = if n.type === V_INTEGER && PLMINTAGGEDINT <= n.i <= PLMAXTAGGEDINT
                _mt_randseed!(ld.random_state, _ulong_seed(n.i))    # gmp_randseed_ui
                true
            elseif n.type === V_INTEGER || n.type === V_MPZ
                _mt_randseed!(ld.random_state, _number_bigint(n))   # gmp_randseed
                true
            else
                PL_error(ld, ERR_TYPE, mk_sym(T, :seed), arg)
            end
            _number_free!(ld, 1)
            return rc ? FTRUE : FFALSE
        elseif sym_key(name) == sym_key(mk_sym(T, :state))
            n = _number_alloc!(ld)
            if !PL_get_number(ld, arg, n) || !(n.type === V_MPZ || _is_big_int64(n))
                _number_free!(ld, 1)
                return PL_error(ld, ERR_TYPE, mk_sym(T, :state), arg) ? FTRUE : FFALSE
            end
            rc = _mt_set_state!(ld.random_state, _number_bigint(n))  # mpz_set(state[0]._mp_seed, n)
            _number_free!(ld, 1)                                    # clearNumber(&n)
            return rc || PL_domain_error(ld, "random_state", arg) ? FTRUE : FFALSE
        else
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :random_option), A1) ? FTRUE : FFALSE
        end
    else
        return PL_error(ld, ERR_TYPE, mk_sym(T, :random_option), A1) ? FTRUE : FFALSE
    end
end

# ORIGINAL: `mpz_set(LD->arith.random.state[0]._mp_seed, n)` of set_random/1's `state(S)`
"Copy the limbs of `n` over the start of the generator's struct (as `mpz_set`); false when `n` has more than 313 limbs."
function _mt_set_state!(mt::Vector{UInt32}, n::BigInt)::Bool
    m = abs(n)
    nlimbs = cld(ndigits(m; base=2), 64)
    nlimbs > MT_LIMBS && return false
    for i in 0:(min(2 * nlimbs, MT_N + 1) - 1)              # the struct's words; the padding word is not kept
        mt[i + 1] = UInt32((m >> (32 * i)) & 0xffffffff)
    end
    return true
end

# ORIGINAL: the struct's bytes as one integer, `random_property(state(S))`'s `mpz_set(seed, _mp_seed)`
"The generator's struct as one integer: `mt[0]` the lowest word, `mti` above `mt[623]`, a zero padding word."
function _mt_get_state(mt::Vector{UInt32})::BigInt
    x = BigInt(0)
    for i in (MT_N + 1):-1:1
        x = (x << 32) | BigInt(mt[i])
    end
    return x
end

# PORT: pl-arith.c random_property as pl_random_property1_va
# (PRED_IMPL("random_property", 1, random_property, 0))
"`random_property/1` (pl-arith.c): `state(S)`, the generator's state as an integer."
function pl_random_property1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    init_random(ld)
    na = PL_get_name_arity(ld, A1)
    if na !== nothing && na[2] == 1
        arg = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, A1, arg)
        if sym_key(na[1]) == sym_key(mk_sym(T, :state))
            seed = _number_alloc!(ld)
            seed.type = V_MPZ
            seed.mpz = _mt_get_state(ld.random_state)
            rc = PL_unify_number(ld, arg, seed)
            _number_free!(ld, 1)                            # clearNumber(&seed)
            return rc ? FTRUE : FFALSE
        end
    end
    return FFALSE
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
# "Difficult to keep rounding modes straight": `pow` switches between monotonic increasing and decreasing with the
# signs of the base and the exponent, and the float of the exponent and `pow` round independently — `roundMode1`
# is the mode of `pow`, `roundMode2` the mode of the conversion of the exponent.
function _ar_pow_doreal_mpq(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    roundMode = fegetround()
    neg_res = n1.f < 0.0 && isodd(numerator(n2.mpq))        # mpz_get_ui(numer) & 1
    roundMode1 = roundMode
    if neg_res                                              # pow monotonic increasing or decreasing
        if roundMode == FE_UPWARD
            roundMode1 = FE_DOWNWARD
        elseif roundMode == FE_DOWNWARD
            roundMode1 = FE_UPWARD
        end
    end
    n1.f = abs(n1.f)
    roundMode2 = roundMode1
    if n1.f < 1.0                                           # pow monotonic increasing or decreasing
        if roundMode1 == FE_UPWARD
            roundMode2 = FE_DOWNWARD
        elseif roundMode1 == FE_DOWNWARD
            roundMode2 = FE_UPWARD
        end
    end
    fesetround(roundMode2)
    promoteToFloatNumber(ld, n2) || return false            # using roundMode as set
    roundMode1 != roundMode2 && fesetround(roundMode1)
    r.f = _libm_pow(n1.f, n2.f)                             # using roundMode1
    if neg_res
        r.f = -r.f
    end
    roundMode1 != roundMode && fesetround(roundMode)
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
# exponent as given); the directed rounding modes are the arms of `_ar_pow_doreal_mpq` and the `cr_*` functions; `prefer_rationals` is the
# mask bit `PLFLAG_RATIONAL` (since R2 F1a; a constant, false, before). The size checks raise `int_too_big` as everywhere (the interim).
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
            if truePrologFlag(ld, PLFLAG_RATIONAL)
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
# The last entries of `ar_funcdefs[]` (`roundtoward/2` among them, last). The C
# library functions are called through `ccall`, as arith-b's.
# PORT: pl-arith.c CR_FUNC as _libm_sinh
"`sinh(x)` of the C library (pl-arith.c `cr_sinh`)."
_libm_sinh(x::Float64)::Float64 = CR_FUNC(_c_sinh, x)
# PORT: pl-arith.c cr_cosh as _libm_cosh
"`cosh(x)` of the C library (pl-arith.c `cr_cosh`): the lower limit of the result is 1.0."
function _libm_cosh(x::Float64)::Float64
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = _c_cosh(x)
    if !isnan(result)
        if roundMode == FE_UPWARD
            result = nexttoward(result, Inf)
        elseif roundMode == FE_DOWNWARD || roundMode == FE_TOWARDZERO
            if result != Inf
                result = (result > 1.0) ? nexttoward(result, 0.0) : 1.0
            end
        end
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end
# PORT: pl-arith.c CR_FUNC_1 as _libm_tanh
"`tanh(x)` of the C library (pl-arith.c `cr_tanh`)."
_libm_tanh(x::Float64)::Float64 = CR_FUNC_1(_c_tanh, x)
# `asinh`, `acosh` and `atanh` are not redefined by `O_ROUND_UP_DOWN`: C's own
"`asinh(x)` of the C library (pl-arith.c `ar_asinh`, C's own: the same as Julia's but for the last digit)."
_libm_asinh(x::Float64)::Float64 = ccall((:asinh, LIBM), Float64, (Float64,), x)
"`acosh(x)` of the C library: a NaN below 1 (Julia's `acosh` throws)."
_libm_acosh(x::Float64)::Float64 = ccall((:acosh, LIBM), Float64, (Float64,), x)
"`atanh(x)` of the C library: a NaN beyond ±1 (Julia's `atanh` throws)."
_libm_atanh(x::Float64)::Float64 = ccall((:atanh, LIBM), Float64, (Float64,), x)
# PORT: pl-arith.c cr_erf as _libm_erf
"`erf(x)` of the C library (pl-arith.c `cr_erf`): bounded by +/- 1.0."
function _libm_erf(x::Float64)::Float64
    roundMode = fegetround()
    roundMode != FE_TONEAREST && fesetround(FE_TONEAREST)
    result = _c_erf(x)                                      # abs(result) =< 1.0
    if !isnan(result) && !isinf(x)
        if roundMode == FE_UPWARD
            result = (result < 1.0) ? nexttoward(result, Inf) : 1.0
        elseif roundMode == FE_DOWNWARD
            result = (result > -1.0) ? nexttoward(result, -Inf) : -1.0
        elseif roundMode == FE_TOWARDZERO
            result = nexttoward(result, 0.0)
        end
    end
    roundMode != FE_TONEAREST && fesetround(roundMode)
    return result
end
# PORT: pl-arith.c cr_erfc as _libm_erfc
# The build without CORE-MATH, the pin's: `return 1.0 - cr_erf(in)` — not the C library's erfc, so a large
# argument loses its low bits and erfc(6.0) is 0.0, as swipl's (the oracle's rows).
"`erfc(x)` as upstream computes it without CORE-MATH (pl-arith.c `cr_erfc`): `1.0 - erf(x)`."
_libm_erfc(x::Float64)::Float64 = 1.0 - _libm_erf(x)
# PORT: pl-arith.c CR_FUNC as _libm_lgamma
"`lgamma(x)` of the C library (pl-arith.c `cr_lgamma`)."
_libm_lgamma(x::Float64)::Float64 = CR_FUNC(_c_lgamma, x)

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
# The pin cbf4e189 plus upstream fix 1582e8b37 (BP2, a named backport): the three type checks return their error.
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
# DIVERGES: `mpf_urandomb(rop, state, 64)` is the 64 random bits as the fraction `x * 2^-64`, and
# `mpf_get_d` truncates it to 53 significant bits (computed here on the integer), as the O_GMP arm.
"`random_float/0` (pl-arith.c `ar_random_float`): a random float in the open interval (0.0, 1.0)."
function ar_random_float(ld::PL_local_data, r::number)::Bool
    init_random(ld)
    while true
        x = UInt64(_mt_randget!(ld.random_state, 64))       # mpf_urandomb(rop, state, 64)
        bl = 64 - leading_zeros(x)
        if bl > 53
            x = (x >> (bl - 53)) << (bl - 53)               # mpf_get_d truncates
        end
        r.f = ldexp(Float64(x), -64)
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
# the earlier (hotter) ones as soon as before. `roundtoward/2` is the last entry, as upstream's: its
# second argument (the mode) is read by `set_roundtoward` in the walk of `evalExpression_cells`, the
# function `ar_roundtoward` puts the mode found there back (see the file header).
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
    (:popcount, 1), (:getbit, 2), (:powm, 3), (:eval, 1), (:roundtoward, 2)
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
    f === :roundtoward && return ar_roundtoward(ld, a0, a1, r)
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

# ── virtual machine support (pl-arith.c, `#if O_COMPILE_ARITH`) ──────────────────────────────────
# PORT: pl-arith.c indexArithFunction
# DIVERGES: the function is `name/arity` (the name's key and the arity), as `isCurrentArithFunction`'s;
# the index is the 0-based position in `ar_funcdefs` (what the code word of `A_FUNC0` .. `A_FUNC` holds),
# -1 when there is no such function, as upstream's.
"The index of the arithmetic function `name/arity` in `ar_funcdefs`, 0-based, -1 for none (pl-arith.c)."
function indexArithFunction(::Type{T}, name::UInt64, arity::Int)::Int where {T}
    return isCurrentArithFunction(T, name, arity) - 1
end

# PORT: pl-arith.c functorArithFunction
# DIVERGES: the functor is `(name, arity)` (the kernel has no functor table), the entry at the 0-based
# index `i` of `ar_funcdefs` (`fetchFunctorArray(i)->functor` upstream).
"The functor `(name, arity)` of the arithmetic function at 0-based index `i` (pl-arith.c)."
function functorArithFunction(i::Int)::Tuple{Symbol, Int}
    return ar_funcdefs[i + 1]
end

# PORT: pl-arith.c FunctionFromIndex
# DIVERGES: upstream returns the function pointer `GD->arith.functions[index]`; here the entry's 1-based
# position in `ar_funcdefs`, which `_ar_call0` .. `_ar_call3` call by the entry's name.
"The `ar_funcdefs` entry of the 0-based function index `index` (pl-arith.c)."
function FunctionFromIndex(index::Int)::Int
    return index + 1
end

# PORT: pl-arith.c ar_func_n
# DIVERGES: the arithmetic stack is the local data's pool of numbers (`_number_alloc!`; the arguments
# are the top `argc` of it, the LAST one pushed is the first argument: `a0 = arith_numbers[arith_top]`
# as `_evalExpression_walk`'s). The result is computed in a pool record above the arguments, then moved
# to the place of the first one (`popArgvArithStack`, `pushArithStack`). `sysError` is a Julia `error`.
# `clearNumber` has nothing to clear: the values are immutable.
"`A_FUNC0` .. `A_FUNC`: run function `findex` on the top `argc` numbers of the arithmetic stack, push the result (pl-arith.c)."
function ar_func_n(ld::PL_local_data, findex::Int, argc::Int)::Bool
    k = FunctionFromIndex(findex)
    r = _number_alloc!(ld)                                  # number result
    top = ld.arith_top - 1                                  # the last argument pushed
    rval = false
    if argc > 0
        a0 = ld.arith_numbers[top]
        if argc == 1
            rval = _ar_call1(ld, k, a0, r)
        elseif argc == 2
            rval = _ar_call2(ld, k, a0, ld.arith_numbers[top - 1], r)
        elseif argc == 3
            rval = _ar_call3(
                ld, k, a0, ld.arith_numbers[top - 1], ld.arith_numbers[top - 2], r
            )
        else
            error("Too many arguments to arithmetic function")    # sysError
        end
    else
        rval = _ar_call0(ld, k, r)
    end
    ld.arith_top -= argc + 1                                # popArgvArithStack(argc), and `result`
    if rval
        dst = _number_alloc!(ld)                            # pushArithStack(&result)
        dst === r || moveNumber(dst, r)
    end
    return rval
end

# ── characters (pl-arith.c) ──────────────────────────────────────────────────────────────────────
# PORT: pl-arith.c getCharExpression
# DIVERGES: the `TAG_STRING` branch, on a value-table string's stored value `p` (its one caller,
# `evalExpression_cells`); the `TAG_COMPOUND` branch, `[X]`, is `getCharExpression_cells`.
"A one-character string as its character code in `r` (pl-arith.c); false after raising."
function getCharExpression(ld::PL_local_data{T}, p::T, r::number)::Bool where {T}
    s = string_value(p)                                     # TAG_STRING
    if length(s) == 1
        r.i = Int64(s[1])
        r.type = V_INTEGER
        return true
    end
    return _len_not_one(ld, p)
end

# getCharExpression's `len_not_one:`.
function _len_not_one(ld::PL_local_data{T}, p::T)::Bool where {T}
    a = new_term_ref(ld)
    setSlotValue!(ld, a + 1, p)
    PL_error(ld, "", 0, "\"x\" must hold one character", ERR_TYPE, mk_sym(T, :character), a)
    return false
end

# getCharExpression's `len_not_one:` on the cells (f3b-4): `PL_error(NULL, 0, "\"x\" must hold one
# character", ERR_TYPE, ATOM_character, pushWordAsTermRef(p)); popTermRef()`.
function _len_not_one_cells(
    ld::PL_local_data{T}, loc::Tuple{UInt8, word, Int}
)::Bool where {T}
    PL_error(
        ld, "", 0, "\"x\" must hold one character", ERR_TYPE, mk_sym(T, :character),
        pushWordAsTermRef(ld, loc)
    )
    popTermRef(ld)
    return false
end

# PORT: pl-arith.c arithChar as arithChar_cells
# DIVERGES: on a LOCATION (`_deref_loc`, the workspace's L1_plan/stageL1d_design.md §3e): a tagged
# integer by `valInt`, an atom word by its symbol's `charCode` — no term read; the culprit of the
# type error is its word (`pushWordAsTermRef`, f3b-4).
"The character code location `l` stands for in `[X]` (pl-arith.c `arithChar`); -1 after raising."
function arithChar_cells(ld::PL_local_data{T}, l::Int)::Int where {T}
    k, w, p = _deref_loc(ld, l)                             # deRef(p)
    if k == DU_VALUE && isTaggedIntW(w)                     # isTaggedInt(*p)
        chr = valInt(w)
        0 <= chr <= 0x10ffff && return Int(chr)             # VALID_CODE_POINT(chr)
    elseif k == DU_WORD && isAtomW(w)                       # isAtom(*p)
        chr = charCode(_atom_value(ld, w))
        chr >= 0 && return chr
    end
    _ar_type_error_cells(ld, :character, (k, w, p))         # ERR_TYPE, ATOM_character
    return -1                                               # EOF
end

# PORT: pl-arith.c getCharExpression as getCharExpression_cells
# DIVERGES: the `TAG_COMPOUND` branch on the CELLS of the `'[|]'/2` compound at global position `c`
# (its arguments at `c + 1`, `c + 2`); `len_not_one`'s culprit is the list's word (f3b-4). A string
# is a value-table entry: the term-level `getCharExpression` reads it (no export).
"`[X]` at global position `c` as its character code in `r` (pl-arith.c); false after raising."
function getCharExpression_cells(ld::PL_local_data{T}, c::Int, r::number)::Bool where {T}
    chr = arithChar_cells(ld, c + 1)                        # argTermP(w, 0)
    chr == -1 && return false
    k, w, _ = _deref_loc(ld, c + 2)                         # argTermP(w, 1)
    (k == DU_WORD && w == ld.atom_nil_w) ||                 # isNil(*a)
        return _len_not_one_cells(ld, (DU_WORD, consPtr(c, TAG_COMPOUND | STG_GLOBAL), 0))
    r.i = Int64(chr)
    r.type = V_INTEGER
    return true
end

# `PL_error(NULL, 0, NULL, ERR_TYPE, ATOM_<expected>, pushWordAsTermRef(p))` on the cells (f3b-4):
# the culprit is the dereferenced location `(k, w, p)`; `popTermRef()` as upstream.
function _ar_type_error_cells(
    ld::PL_local_data{T}, expected::Symbol, loc::Tuple{UInt8, word, Int}
)::Bool where {T}
    rc = PL_error(ld, ERR_TYPE, mk_sym(T, expected), pushWordAsTermRef(ld, loc))
    popTermRef(ld)
    return rc
end

# PORT: pl-arith.c set_roundtoward
# DIVERGES: the mode cell is a LOCATION (`c`, the compound's argument cell), dereferenced by `_deref_loc`;
# `ERR_PTR_DOMAIN`/`ERR_PTR_TYPE` are `ERR_DOMAIN`/`ERR_TYPE` on the word (`pushWordAsTermRef`). The atom
# is compared by its key (`sym_key`), where upstream compares atom handles.
"Set the rounding mode the atom in the argument cell `c` names; the mode in force before goes to `old` (pl-arith.c)."
function set_roundtoward(ld::PL_local_data{T}, c::Int, old::number)::Bool where {T}
    loc = _deref_loc(ld, c)                                 # deRef(p)
    old.type = V_INTEGER
    old.i = Int64(fegetround())
    k, w, _ = loc
    if k == DU_WORD && isAtomW(w)
        key = sym_key(_atom_value(ld, w))
        if key == sym_key(mk_sym(T, :to_nearest))
            fesetround(FE_TONEAREST)
        elseif key == sym_key(mk_sym(T, :to_positive))
            fesetround(FE_UPWARD)
        elseif key == sym_key(mk_sym(T, :to_negative))
            fesetround(FE_DOWNWARD)
        elseif key == sym_key(mk_sym(T, :to_zero))
            fesetround(FE_TOWARDZERO)
        else                                                # isAtom(*p): ERR_PTR_DOMAIN, ATOM_round
            rc = PL_error(ld, ERR_DOMAIN, mk_sym(T, :round), pushWordAsTermRef(ld, loc))
            popTermRef(ld)
            return rc
        end
        return true
    end
    return _ar_type_error_cells(ld, :atom, loc)             # ERR_PTR_TYPE, ATOM_atom
end

# PORT: pl-arith.c ar_roundtoward
"`roundtoward/2` (pl-arith.c): the value of its first argument; the mode found by `set_roundtoward` (`n2`) goes back."
function ar_roundtoward(ld::PL_local_data, n1::number, n2::number, r::number)::Bool
    cpNumber(r, n1)
    @assert n2.type === V_INTEGER
    fesetround(Int(n2.i))
    return true
end

# The WORD walk of pl-arith.c `evalExpression` (`evalExpression_cells` below carries the PORT marker).
# DIVERGES (L1d; the workspace's L1_plan/stageL1d_design.md §3e): upstream's WORD walk on LOCATIONS
# (`_deref_loc`'s: a global position, or `-i` for slot `i`) — `term_stack` holds them with the
# `walk_ref` bit (`(loc << 1) | wr`, `ld.arith_cells`); a compound is pushed and the walk goes to its
# LAST argument cell (`c + arity`), and after a leaf it steps back (`p -= 1`) while the cell is a
# FUNCTOR word, applying it to the pooled numbers (`ld.arith_numbers`, upstream's `arg_stack`). A
# leaf is read on its word: a tagged integer by `valInt`, a value-table word by its stored number (a
# string through `getCharExpression`), an atom by its symbol — no export; an export is made only for
# an error's culprit. Not ported: signals; the ported functions only
# (`isCurrentArithFunction`, by the name's key). A kernel-only `$expr/n` compound (Q-AR5) is
# evaluated as the term walk evaluates it — its arguments after the head (argument 1), the last
# first, each on the cells, then `'$expr'/(n-1)` is not evaluable (f3b-4: no export). An error's
# culprit is its word (`pushWordAsTermRef`, f3b-4). `roundtoward(Expr, Mode)`: `set_roundtoward`
# reads the mode (the second argument) when the compound is entered and pushes the mode found,
# `ar_roundtoward` puts it back after `Expr` (upstream's `FUNCTOR_roundtoward2` arm, as written).
"Evaluate the expression `expr` refers to into `result` on the CELLS (pl-arith.c `evalExpression`); false after raising."
function _evalExpression_walk(
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
            v = _indirect_value(ld, w)                      # (a side word's too, f3-1)
            nk = number_kind(v)
            if nk === NUM_INTEGER || nk === NUM_RATIONAL    # TAG_INTEGER
                get_rational(v, n)
            elseif nk === NUM_FLOAT                         # TAG_FLOAT
                n.f = float_value(v)
                n.type = V_FLOAT
            elseif nk === NUM_STRING                        # TAG_STRING
                getCharExpression(ld, v, n) || @goto error
            else                                            # NUM_OTHER: a non-text blob (Q-AR5)
                _ar_type_error_cells(ld, :evaluable, (k, w, p))
                @goto error
            end
        end
    elseif k == DU_CELL                                     # TAG_VAR
        PL_error(ld, ERR_INSTANTIATION)
        @goto error
    elseif k == DU_ATTVAR                                   # default: (TAG_ATTVAR, AV1b)
        # PL_error(…, ERR_PTR_TYPE, ATOM_number, p): ERR_TYPE on the word (pl-error.c),
        # whose `PL_is_variable(actual)` (canBind) makes it an instantiation error
        _ar_type_error_cells(ld, :number, (k, w, p))
        @goto error
    elseif isAtomW(w)                                       # TAG_ATOM
        a = _atom_value(ld, w)
        f0 = isCurrentArithFunction(T, sym_key(a), 0)       # lookupFunctorDef(word2atom(*p), 0)
        if f0 != 0
            _ar_call0(ld, f0, n) || @goto error
        else
            if isTextAtom(a)
                PL_error(ld, ERR_NOT_EVALUABLE, (a, 0))
            else
                _ar_type_error_cells(ld, :evaluable, (k, w, p))
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
                _ar_type_error_cells(ld, :evaluable, (k, w, p))
                @goto error
            end
        elseif nameFunctor(ld.functors, f) == ld.atom_dexpr # Q-AR5 (kernel-only): as the term walk,
            a = PL_new_term_ref(ld)                         # its arguments after the head (argument
            for i in arity:-1:2                             # 1), the last first, then not evaluable
                _slot_link_loc!(ld, a + 1, _deref_loc(ld, c + i))
                _evalExpression_walk(ld, a, _number_alloc!(ld)) || @goto error
            end
            PL_error(ld, ERR_NOT_EVALUABLE, (mk_sym(T, Symbol("\$expr")), arity - 1))
            @goto error
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
            if arity == 2 &&
                sym_first_byte(_atom_value(ld, nameFunctor(ld.functors, f))) == 0x72 &&
                sym_text(_atom_value(ld, nameFunctor(ld.functors, f))) == "roundtoward"
                crnd = _number_alloc!(ld)                   # number crnd, pushed on arg_stack
                set_roundtoward(ld, c + 2, crnd) || @goto error
                p = c + 1                                   # p = &term->arguments[0]
            else
                p = c + arity                               # p = &term->arguments[arity-1]
            end
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
        moveNumber(a0, n_tmp)                               # moveNumber(a0, n)
    elseif arity == 2
        a1 = ld.arith_numbers[top - 1]
        _ar_call2(ld, fi, a0, a1, n_tmp) || @goto error
        ld.arith_top = top - 1                              # popTopOfSegStack
        moveNumber(a1, n_tmp)                               # moveNumber(n1, n)
    else                                                    # arity 3: powm/3
        a1 = ld.arith_numbers[top - 1]
        a2 = ld.arith_numbers[top - 2]
        _ar_call3(ld, fi, a0, a1, a2, n_tmp) || @goto error
        ld.arith_top = top - 2                              # popTopOfSegStack, twice
        moveNumber(a2, n_tmp)                               # moveNumber(n2, n)
    end
    e = pop!(stack)                                         # popForMark(&term_stack, &p, &walk_ref)
    p, walk_ref = e >> 1, (e & 1) != 0
    if p == start
        moveNumber(result, n_tmp)                           # moveNumber(result, n)
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

# PORT: pl-arith.c evalExpression as evalExpression_cells
# DIVERGES: the rounding mode is scoped to ONE evaluation (see the file header): the mode the
# `float_rounding` flag names is set for the walk, and the mode found at the entry is put back in a
# `finally`, also after an error (upstream leaves the hardware mode set by `roundtoward/2` after an
# error in its first argument: measured at the pin, a later `Y is 1/3.0` answers 0.33333333333333337
# for the rest of the process). The scope is here, not in `valueExpression`: pl-wam.jl calls this
# function directly.
"Evaluate the expression `expr` refers to into `result` on the CELLS (pl-arith.c `evalExpression`); false after raising."
function evalExpression_cells(
    ld::PL_local_data{T}, expr::term_t, result::number
)::Bool where {T}
    entry = fegetround()
    mode = Int(ld.arith_f_flags & FLT_ROUND_MASK)
    mode != Int(FLT_ROUND_NEAREST) && set_rounding(mode)
    try
        return _evalExpression_walk(ld, expr, result)
    finally
        fegetround() != entry && fesetround(entry)
    end
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
        v = _indirect_value(ld, w)
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

# PORT: pl-arith.c between as pl_between3_va
# DIVERGES: the state is a record of the local data's pool (`ld.between_states`, design D3), its
# index the `REDO_PTR` context (`PL_retry_address`); the first call's numbers are the local data's
# pooled ones (`_number_alloc!`), where upstream's are C locals. `clearInteger` has nothing to free
# (a `BigInt` is Julia's GC's).
# (PRED_IMPL("between", 3, between, PL_FA_NONDETERMINISTIC))
"`between/3` (pl-arith.c): `N` is `Low`, `Low+1`, … up to `High`, or without end for `inf`."
function pl_between3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    low, high, n = PL__t0, PL__t0 + 1, PL__t0 + 2
    rc = true

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        l = _number_alloc!(ld)
        h = _number_alloc!(ld)
        i = _number_alloc!(ld)
        hinf = false

        if !PL_get_number(ld, low, l) || !intNumber(l)
            _number_free!(ld, 3)
            return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), low) ? FTRUE : FFALSE
        end
        if !PL_get_number(ld, high, h) || !intNumber(h)
            if PL_is_inf(ld, high)
                h.type = V_INTEGER                      # make clearInteger() safe
                hinf = true
            else
                _number_free!(ld, 3)
                return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), high) ? FTRUE : FFALSE
            end
        end

        # between(+,+,+)
        if PL_get_number(ld, n, i) && intNumber(i)
            if hinf
                rc = cmpNumbers(ld, i, l) >= 0
            else
                rc = cmpNumbers(ld, i, l) >= 0 && cmpNumbers(ld, i, h) <= 0
            end
            _number_free!(ld, 3)
            return rc ? FTRUE : FFALSE
        end

        # between(+,+,-)
        if !PL_is_variable(ld, n)
            _number_free!(ld, 3)
            return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), n) ? FTRUE : FFALSE
        end
        if !hinf && cmpNumbers(ld, h, l) < 0
            _number_free!(ld, 3)
            return FFALSE
        end

        if !PL_unify(ld, n, low)
            _number_free!(ld, 3)
            return FFALSE
        end
        if !hinf && cmpNumbers(ld, l, h) == 0
            _number_free!(ld, 3)
            return FTRUE
        end

        k = alloc_foreign_state!(ld.between_states)    # allocForeignState(sizeof(*state))
        state = ld.between_states.states[k]
        cpNumber(state.low, l)
        cpNumber(state.high, h)
        state.hinf = hinf
        _number_free!(ld, 3)
        return PL_retry_address(k)                      # ForeignRedoPtr(state)
    elseif ctl == FRG_REDO
        k = PL_foreign_context_address(PL__ctx)         # state = CTX_PTR
        state = ld.between_states.states[k]

        if !ar_add_si(ld, state.low, 1) || !PL_unify_number(ld, n, state.low)
            free_foreign_state!(ld.between_states, k)   # rc = false; goto cleanup
            return FFALSE
        end
        if !state.hinf
            if state.high.type === V_INTEGER && state.low.type === V_INTEGER
                if state.low.i == state.high.i
                    free_foreign_state!(ld.between_states, k)   # goto cleanup
                    return FTRUE
                end
            elseif cmpNumbers(ld, state.low, state.high) == CMPEX_EQUAL
                free_foreign_state!(ld.between_states, k)       # goto cleanup
                return FTRUE
            end
        end
        return PL_retry_address(k)                      # ForeignRedoPtr(state)
    elseif ctl == FRG_CUTTED
        free_foreign_state!(ld.between_states, PL_foreign_context_address(PL__ctx))
    end
    return rc ? FTRUE : FFALSE
end

# ── succ/2, plus/3, bounded_number/3 and the bignum built-ins (pl-arith.c) ───────────────────────
# PORT: pl-arith.c succ as pl_succ2_va
# DIVERGES: "tagged" is `PLMINTAGGEDINT..PLMAXTAGGEDINT` of the kernel; the numbers are the local
# data's pooled ones (`_number_alloc!`). As upstream, an integer first argument beyond the tagged
# range falls through to the second argument's branch, which finds the number just unified.
# (PRED_IMPL("succ", 2, succ, 0))
"`succ/2` (pl-arith.c): `A2` is `A1+1`, both non-negative integers; at least one is bound."
function pl_succ2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    i1 = _number_alloc!(ld)
    i2 = _number_alloc!(ld)
    one = _number_alloc!(ld)
    rc = _succ_body(ld, A1, A2, i1, i2, one)
    _number_free!(ld, 3)                                    # clearInteger(&i1, &i2, &one)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-arith.c succ as _succ_body
# DIVERGES: the body of upstream's `succ`, so the pooled numbers are released once, by the caller.
"The body of `succ/2` on the numbers `i1`, `i2`, `one` of the caller (pl-arith.c)."
function _succ_body(
    ld::PL_local_data{T}, A1::term_t, A2::term_t, i1::number, i2::number, one::number
)::Bool where {T}
    one.type = V_INTEGER
    one.i = 1
    rc = false

    if PL_get_number(ld, A1, i1) && intNumber(i1)           # isInteger(*p1)
        if i1.type === V_INTEGER && 0 <= i1.i <= PLMAXTAGGEDINT    # isTaggedInt: v >= 0 && ++v >= 0
            return PL_unify_int64(ld, A2, i1.i + 1)
        end
        if ar_sign_i(i1) < 0
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), A1)
        end
        rc = pl_ar_add(ld, i1, one, i2) && PL_unify_number(ld, A2, i2)
    elseif !PL_is_variable(ld, A1)                          # !canBind(*p1)
        return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), A1)
    end

    if PL_get_number(ld, A2, i2) && intNumber(i2)           # isInteger(*p2)
        if i2.type === V_INTEGER && PLMINTAGGEDINT <= i2.i <= PLMAXTAGGEDINT    # isTaggedInt(*p2)
            i2.i > 0 && return PL_unify_int64(ld, A1, i2.i - 1)
            i2.i == 0 && return false
        end
        sgn = ar_sign_i(i2)
        if sgn == 1
            rc = ar_minus(ld, i2, one, i1) && PL_unify_number(ld, A1, i1)
        elseif sgn == 0
            return false
        else
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), A2)
        end
    elseif !PL_is_variable(ld, A2)                          # !canBind(*p2)
        return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), A2)
    else
        return PL_error(ld, ERR_INSTANTIATION)
    end

    return rc
end

# PORT: pl-arith.c var_or_integer
# DIVERGES: returns the new mask, or -1 after the type error (upstream: a `bool` and `*mask`).
"Read `t` into `n` if it is an integer, ored into `mask` as `which`; a variable is kept (pl-arith.c)."
function var_or_integer(
    ld::PL_local_data{T}, t::term_t, n::number, which::Int, mask::Int
)::Int where {T}
    if PL_get_number(ld, t, n) && intNumber(n)              # isInteger(*p): get_integer(*p, n)
        return mask | which
    end
    PL_is_variable(ld, t) && return mask                    # canBind(*p)
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
    return -1
end

# PORT: pl-arith.c plus as pl_plus3_va
# DIVERGES: the numbers are the local data's pooled ones.
# (PRED_IMPL("plus", 3, plus, 0))
"`plus/3` (pl-arith.c): `A3` is `A1+A2`, any two of the three being integers."
function pl_plus3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    m = _number_alloc!(ld)
    n = _number_alloc!(ld)
    o = _number_alloc!(ld)
    mask = 0

    mask = var_or_integer(ld, A1, m, 1, mask)
    mask >= 0 && (mask = var_or_integer(ld, A2, n, 2, mask))
    mask >= 0 && (mask = var_or_integer(ld, A3, o, 4, mask))
    if mask < 0
        _number_free!(ld, 3)
        return FFALSE
    end

    if mask == 7 || mask == 3                              # +, +, + and +, +, -
        pl_ar_add(ld, m, n, o)
        rc = PL_unify_number(ld, A3, o)
    elseif mask == 5                                        # +, -, +
        ar_minus(ld, o, m, n)
        rc = PL_unify_number(ld, A2, n)
    elseif mask == 6                                        # -, +, +
        ar_minus(ld, o, n, m)
        rc = PL_unify_number(ld, A1, m)
    else
        _number_free!(ld, 3)
        return PL_error(ld, ERR_INSTANTIATION) ? FTRUE : FFALSE
    end

    _number_free!(ld, 3)                                    # clearInteger(&m, &n, &o)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-arith.c bounded_number as pl_bounded_number3_va
# DIVERGES: the numbers are the local data's pooled ones; `nexttoward(x, ±INFINITY)` is
# `nextfloat`/`prevfloat`. The type error names `A1`, as upstream's (not the number's argument `A3`).
# (PRED_IMPL("bounded_number", 3, bounded_number, 0))
"`bounded_number/3` (pl-arith.c): `Low < Num < High`, a bound unbound taking its neighbour of `Num`."
function pl_bounded_number3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    n = _number_alloc!(ld)
    lo = _number_alloc!(ld)
    hi = _number_alloc!(ld)

    if PL_get_number(ld, A3, n)
        if n.type === V_INTEGER || n.type === V_MPZ
            cpNumber(lo, n)
            cpNumber(hi, n)
            ar_add_si(ld, lo, Int64(-1))
            ar_add_si(ld, hi, Int64(1))
        else
            n.type === V_MPQ && promoteToFloatNumber(ld, n)
            # V_FLOAT
            if isfinite(n.f)
                lo.type = V_FLOAT
                lo.f = prevfloat(n.f)                       # nexttoward(f, -INFINITY)
                hi.type = V_FLOAT
                hi.f = nextfloat(n.f)                       # nexttoward(f, INFINITY)
            else
                _number_free!(ld, 3)
                return FFALSE
            end
        end

        rc =
            (
                if PL_get_number(ld, A1, lo)
                    cmpNumbers(ld, lo, n) == CMPEX_LESS
                else
                    PL_unify_number(ld, A1, lo)
                end
            ) && (
                if PL_get_number(ld, A2, hi)
                    cmpNumbers(ld, n, hi) == CMPEX_LESS
                else
                    PL_unify_number(ld, A2, hi)
                end
            )
    else
        rc = PL_error(ld, ERR_TYPE, mk_sym(T, :number), A1)
    end
    _number_free!(ld, 3)                                    # clearNumber(&n, &lo, &hi)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-arith.c get_mpz
"Read the integer `t` holds into `n` as a `V_MPZ`; `type_error(integer, T)` otherwise (pl-arith.c)."
function get_mpz(ld::PL_local_data{T}, t::term_t, n::number)::Bool where {T}
    if PL_get_number(ld, t, n) && intNumber(n)              # isInteger(*p): get_integer(*p, n)
        promoteToMPZNumber(n)
        return true
    end
    return PL_type_error(ld, "integer", t)
end

# PORT: pl-arith.c divmod as pl_divmod4_va
# DIVERGES: the numbers are the local data's pooled ones; `mpz_fdiv_qr` is `fldmod` on `BigInt`.
# (PRED_IMPL("divmod", 4, divmod, 0))
"`divmod/4` (pl-arith.c): `Q` is `div(N, D)` and `R` is `mod(N, D)` of two integers."
function pl_divmod4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    N = _number_alloc!(ld)
    D = _number_alloc!(ld)
    rc = false

    if get_mpz(ld, A1, N) && get_mpz(ld, A2, D)
        if !iszero(D.mpz)                                   # mpz_sgn(D) != 0
            Q = _number_alloc!(ld)
            R = _number_alloc!(ld)
            Q.type = V_MPZ
            R.type = V_MPZ
            Q.mpz, R.mpz = fldmod(N.mpz, D.mpz)             # mpz_fdiv_qr
            rc = PL_unify_number(ld, A3, Q) && PL_unify_number(ld, A4, R)
            _number_free!(ld, 2)                            # clearNumber(&R), clearNumber(&Q)
        else
            rc = PL_error(ld, "divmod", 2, "", ERR_DIV_BY_ZERO)
        end
    end

    _number_free!(ld, 2)                                    # clearNumber(&N), clearNumber(&D)
    return rc ? FTRUE : FFALSE
end

# Ported from pl-gmp.c `mpz_rootrem` (pl-gmp.c is not one of this file's UPSTREAM files), as `_mpz_rootrem`.
# DIVERGES: GMP's `mpz_rootrem` has no Julia wrapper: the truncated `k`-th root by Newton's
# iteration on `BigInt` (the root of a negative `n` is the negated root of `-n`, GMP's sign rule),
# the remainder `n - root^k`. A `k` at least the bit length of `n` gives the root 1 (or 0) at once.
"`(root, rem)` of `mpz_rootrem(n, k)`: `root = trunc(n^(1/k))`, `rem = n - root^k`, for `k >= 1`."
function _mpz_rootrem(n::BigInt, k::Int)::Tuple{BigInt, BigInt}
    neg = n < 0
    a = neg ? -n : n
    root = if a < 2 || k == 1
        a
    else
        bits = ndigits(a; base=2)
        if k >= bits                                        # a < 2^bits <= 2^k
            BigInt(1)
        else
            x = BigInt(1) << cld(bits, k)                   # a power of two above the root
            while true
                y = div((k - 1) * x + div(a, x^(k - 1)), k)
                y >= x && break
                x = y
            end
            x
        end
    end
    neg && (root = -root)
    return root, n - root^k
end

# PORT: pl-arith.c nth_integer_root_and_remainder as pl_nth_integer_root_and_remainder4_va
# DIVERGES: the numbers are the local data's pooled ones; the root is `_mpz_rootrem`.
# (PRED_IMPL("nth_integer_root_and_remainder", 4, nth_integer_root_and_remainder, 0))
"`nth_integer_root_and_remainder/4` (pl-arith.c): the truncated `I`-th root of `N` and the rest."
function pl_nth_integer_root_and_remainder4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    N = _number_alloc!(ld)
    rc = false

    I = PL_get_long_ex(ld, A1)
    if I !== nothing && get_mpz(ld, A2, N)
        if I >= 1
            if N.mpz < 0 && I % 2 == 0
                rc = PL_error(ld, ERR_AR_UNDEF)
            else
                root = _number_alloc!(ld)
                rem = _number_alloc!(ld)
                root.type = V_MPZ
                rem.type = V_MPZ
                root.mpz, rem.mpz = _mpz_rootrem(N.mpz, I)  # mpz_rootrem
                rc = PL_unify_number(ld, A3, root) && PL_unify_number(ld, A4, rem)
                _number_free!(ld, 2)                        # clearNumber(&root), clearNumber(&rem)
            end
        else
            rc = PL_domain_error(ld, "not_less_than_one", A1)
        end
    end

    _number_free!(ld, 1)                                    # clearNumber(&N)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-arith.c rational as pl_rational3_va
# DIVERGES: on the numbers (`PL_get_number`) where upstream tests the word (`isRational`); the
# numerator and denominator are `BigInt`s of the rational.
# (PRED_IMPL("rational", 3, rational, 0))
"`rational/3` (pl-arith.c): the numerator and denominator of a rational; an integer is `N/1`."
function pl_rational3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    n = _number_alloc!(ld)
    rc = false

    if PL_get_number(ld, A1, n) && n.type !== V_FLOAT       # isRational(*p)
        if n.type === V_MPQ                                 # isMPQNum(*p)
            num = _number_alloc!(ld)
            den = _number_alloc!(ld)
            num.type = V_MPZ
            den.type = V_MPZ
            num.mpz = numerator(n.mpq)                      # mpz_set(num, mpq_numref(n))
            den.mpz = denominator(n.mpq)                    # mpz_set(den, mpq_denref(n))
            rc = PL_unify_number(ld, A2, num) && PL_unify_number(ld, A3, den)
            _number_free!(ld, 2)                            # clearNumber(&num), clearNumber(&den)
        else
            rc = PL_unify(ld, A1, A2) && PL_unify_integer(ld, A3, 1)
        end
    end

    _number_free!(ld, 1)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-arith.c float_parts as pl_float_parts4_va
# DIVERGES: `frexp` is Julia's (`frexp(Inf)` is `(Inf, 0)`, as glibc's).
# (PRED_IMPL("float_parts", 4, float_parts, 0))
"`float_parts/4` (pl-arith.c): the mantissa, the base (always 2) and the exponent of a float."
function pl_float_parts4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    d = PL_get_float_ex(ld, A1)
    if d !== nothing
        m, e = frexp(d)
        rc =
            PL_unify_float(ld, A2, m) && PL_unify_integer(ld, A3, 2) &&
            PL_unify_integer(ld, A4, Int(e))
        return rc ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-arith.c float_class as pl_float_class2_va
# DIVERGES: `fpclassify` is `isnan`, `isinf`, `iszero`, `issubnormal`.
# (PRED_IMPL("float_class", 2, float_class, 0))
"`float_class/2` (pl-arith.c): `nan`, `infinite`, `zero`, `subnormal` or `normal`, of a float."
function pl_float_class2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    n = _number_alloc!(ld)
    if PL_get_number(ld, A1, n) && n.type === V_FLOAT       # isFloat(*p)
        f = n.f
        _number_free!(ld, 1)
        a = if isnan(f)
            :nan
        elseif isinf(f)
            :infinite
        elseif iszero(f)
            :zero
        elseif issubnormal(f)
            :subnormal
        else
            :normal
        end
        return PL_unify_atom(ld, A2, mk_sym(T, a)) ? FTRUE : FFALSE
    end
    _number_free!(ld, 1)
    return PL_type_error(ld, "float", A1) ? FTRUE : FFALSE
end

# ── the arithmetic flags (pl-arith.c; R2 F1a) ───────────────────────────────────────────────────
# PORT: pl-arith.c initArith
# DIVERGES: only its Prolog flags (the rest of `initArith` — the function table, the NaN, the signal
# mask — is done where the kernel has it, or has no counterpart: see the file header); called from
# `initPrologFlags!`, which runs where `initPrologFlags` runs, so the flags are created in upstream's
# order within the group (upstream: `initArith` last, after the built-ins). `max_rational_size`,
# `max_rational_size_action` and `max_integer_size` are the limits `LD->arith.rat`/`LD->gmp` hold; the
# kernel's are their defaults (unlimited, `error`), which nothing can set before `set_prolog_flag/2`
# (R2 F1b, which refuses a SET by name).
"Define the Prolog flags of the arithmetic (pl-arith.c `initArith`)."
function initArith!(gd::PL_global_data{T})::Nothing where {T}
    setPrologFlag(gd, "max_rational_size", FT_INTEGER, -1)
    setPrologFlag(gd, "max_rational_size_action", FT_ATOM, "error")
    setPrologFlag(gd, "max_integer_size", FT_INTEGER, -1)

    setPrologFlag(gd, "float_overflow", FT_ATOM, "error")
    setPrologFlag(gd, "float_zero_div", FT_ATOM, "error")
    setPrologFlag(gd, "float_undefined", FT_ATOM, "error")
    setPrologFlag(gd, "float_underflow", FT_ATOM, "ignore")
    setPrologFlag(gd, "float_rounding", FT_ATOM, "to_nearest")
    setPrologFlag(gd, "float_min", FT_FLOAT | FF_READONLY, floatmin(Float64))
    setPrologFlag(gd, "float_max", FT_FLOAT | FF_READONLY, floatmax(Float64))
    setPrologFlag(gd, "float_max_integer", FT_FLOAT | FF_READONLY, 9007199254740992.0)
    return nothing
end

# PORT: pl-arith.c is_arith_flag
# DIVERGES: the key is the atom (`sym_text`), where upstream compares atom handles.
"Whether the atom `k` names a flag that lives in the arithmetic state (pl-arith.c)."
function is_arith_flag(k::T)::Bool where {T}
    name = sym_text(k)
    return name == "max_rational_size" ||
           name == "max_rational_size_action" ||
           name == "max_integer_size" ||
           name == "float_overflow" ||
           name == "float_zero_div" ||
           name == "float_undefined" ||
           name == "float_underflow" ||
           name == "float_rounding"
end

# PORT: pl-arith.c get_arith_flag
# DIVERGES: returns the Boolean (upstream an int). `max_rational_size` and `max_integer_size` are
# `(size_t)-1` — unlimited, the only value they have here — so they fall to the end and fail, as upstream's
# do when unlimited; `max_rational_size_action` is `error`, its only value (`LD->arith.rat`, not ported);
# `float_rounding` names the mode of `arith_f_flags`.
"Unify `val` with the value of the arithmetic flag `k` (pl-arith.c); false if the flag has no value."
function get_arith_flag(ld::PL_local_data{T}, val::term_t, k::T)::Bool where {T}
    name = sym_text(k)
    if name == "max_rational_size_action"
        return PL_unify_atom(ld, val, mk_sym(T, :error))
    end
    flags = ld.arith_f_flags
    if name == "float_overflow"
        a = (flags & FLT_OVERFLOW) != 0 ? :infinity : :error
    elseif name == "float_zero_div"
        a = (flags & FLT_ZERO_DIV) != 0 ? :infinity : :error
    elseif name == "float_undefined"
        a = (flags & FLT_UNDEFINED) != 0 ? :nan : :error
    elseif name == "float_underflow"
        a = (flags & FLT_UNDERFLOW) != 0 ? :ignore : :error
    elseif name == "float_rounding"
        mode = flags & FLT_ROUND_MASK
        if mode == FLT_ROUND_NEAREST
            a = :to_nearest
        elseif mode == FLT_ROUND_TO_POS
            a = :to_positive
        elseif mode == FLT_ROUND_TO_NEG
            a = :to_negative
        elseif mode == FLT_ROUND_TO_ZERO
            a = :to_zero
        else
            return false                    # upstream's `default: return false`
        end
    else
        return false
    end
    return PL_unify_atom(ld, val, mk_sym(T, a))
end

# PORT: pl-arith.c float_rounding_names
"The names of the rounding modes, indexed by the `FLT_ROUND_*` values (upstream's table, whose entry 0 is unused)."
const float_rounding_names = (:to_nearest, :to_positive, :to_negative, :to_zero)
# PORT: pl-arith.c rounding_mode
"The `FE_*` mode of each `FLT_ROUND_*` value (upstream's table, whose entry 0 is unused)."
const rounding_mode = (FE_TONEAREST, FE_UPWARD, FE_DOWNWARD, FE_TOWARDZERO)

# PORT: pl-arith.c atom_to_rounding
# DIVERGES: returns the mode, 0 for an atom that names none (upstream: a Boolean and `int *m`); the atom
# is compared by its key.
"The `FLT_ROUND_*` value the atom `a` names, 0 if it names none (pl-arith.c)."
function atom_to_rounding(a::T)::Int where {T}
    key = sym_key(a)
    for i in 1:4
        key == sym_key(mk_sym(T, float_rounding_names[i])) && return i
    end
    return 0
end

# PORT: pl-arith.c float_rounding_name
# DIVERGES: the atom is made for the term type (`mk_sym`), upstream returns its table entry.
"The atom naming the rounding mode `i`, an `FLT_ROUND_*` value (pl-arith.c)."
function float_rounding_name(::Type{T}, i::Int)::T where {T}
    @assert 1 <= i <= 4
    return mk_sym(T, float_rounding_names[i])
end

# PORT: pl-arith.c set_rounding
"Set the hardware rounding mode to the `FLT_ROUND_*` value `mode` (pl-arith.c)."
function set_rounding(mode::Int)::Nothing
    fesetround(rounding_mode[mode])
    return nothing
end

# PORT: pl-arith.c set_restraint
# DIVERGES: returns the value or `nothing` after raising (upstream: `size_t *valp` and an int); the
# value is a `UInt64`, `typemax(UInt64)` for `infinite` (upstream's `(size_t)-1`).
"The limit `t` holds, `infinite` or a size not below `min` (pl-arith.c); `nothing` after raising."
function set_restraint(
    ld::PL_local_data{T}, t::term_t, min::Int
)::Union{Nothing, UInt64} where {T}
    inf = PL_get_atom(ld, t)
    if inf !== nothing && sym_key(inf) == sym_key(mk_sym(T, :infinite))
        return typemax(UInt64)
    end
    v = PL_get_size_ex(ld, t)
    v === nothing && return nothing
    return UInt64(max(v, min))
end

# PORT: pl-arith.c set_restraint_action
# DIVERGES: returns the atom or `nothing` after raising (upstream: `atom_t *valp` and an int).
"The action atom `t` holds for `key` (pl-arith.c): `error`, and `float` for `max_rational_size_action`; `nothing` after raising."
function set_restraint_action(
    ld::PL_local_data{T}, t::term_t, key::T
)::Union{Nothing, T} where {T}
    act = PL_get_atom_ex(ld, t)
    act === nothing && return nothing
    sym_key(act) == sym_key(mk_sym(T, :error)) && return act
    if sym_key(key) == sym_key(mk_sym(T, :max_rational_size_action)) &&
        sym_key(act) == sym_key(mk_sym(T, :float))
        return act
    end
    PL_domain_error(ld, "max_rational_size_action", t)
    return nothing
end

# The float flag `bit` of `arith_f_flags`: cleared by `error`, set by the atom `on` (set_arith_flag's `clear`/`set`);
# false for any other atom (upstream's `goto dom`).
function _set_float_flag(
    ld::PL_local_data{T}, a::T, bit::UInt32, on::Symbol
)::Bool where {T}
    key = sym_key(a)
    if key == sym_key(mk_sym(T, :error))
        ld.arith_f_flags &= ~bit
    elseif key == sym_key(mk_sym(T, on))
        ld.arith_f_flags |= bit
    else
        return false
    end
    return true
end

# PORT: pl-arith.c set_arith_flag
# DIVERGES: (1) `float_rounding` sets the bits of `arith_f_flags` and NOT the hardware (upstream's
# `set_rounding(i)`): `evalExpression_cells` applies the mode for one evaluation (see the file header).
# So every float computation outside an arithmetic evaluation (`strtod` in `atom_number/2`, `read/1` of a float) runs in
# `to_nearest` here and in the flag's mode in the pin (the pin's `set_arith_flag` calls `set_rounding`).
# (2) The three limits (`max_rational_size`, `max_rational_size_action`, `max_integer_size`) are validated as
# upstream does; the number layer is unbounded, so `infinite` and `error` (the state it has) are accepted and any
# other value is a named refusal (`NotPortedError`) — upstream keeps it in `LD->arith.rat` and `LD->gmp`.
# Pin 18168e62 src/pl-arith.c: the limit arms are set_arith_flag 5183-5194 (`max_rational_size` -> `LD->arith.rat.max_rational_size`,
# `max_rational_size_action` -> `LD->arith.rat.max_rational_size_action`, `max_integer_size` -> `LD->gmp.max_integer_size`), set_restraint
# 5110-5124 (`infinite` stores `(size_t)-1`, else PL_get_size_ex, values below `min` raised to `min`), set_restraint_action 5128-5140; the
# boot state is `(size_t)-1`, `(size_t)-1` and `error` (pl-arith.c 5022-5024, flags 5026-5028): the states this kernel has, so those
# are the no-ops. The refusal sites are listed in docs/r2_owners.tsv (owner AR1).
"Set the arithmetic flag `key` to the value of `val` (pl-arith.c); false after raising or for a key that is no arithmetic flag."
function set_arith_flag(ld::PL_local_data{T}, val::term_t, key::T)::Bool where {T}
    name = sym_text(key)
    if name == "max_rational_size" || name == "max_integer_size"
        v = set_restraint(ld, val, name == "max_integer_size" ? 1000 : 0)
        v === nothing && return false
        v == typemax(UInt64) && return true                 # unlimited: the state it has
        throw(
            NotPortedError{T}(
                key,
                "LD->arith.rat / LD->gmp.max_integer_size: a limit on the numbers",
                "AR1"
            )
        )
    end
    if name == "max_rational_size_action"
        act = set_restraint_action(ld, val, key)
        act === nothing && return false
        sym_key(act) == sym_key(mk_sym(T, :error)) && return true      # the state it has
        throw(
            NotPortedError{T}(key, "LD->arith.rat.max_rational_size_action: float", "AR1")
        )
    end
    a = PL_get_atom_ex(ld, val)
    a === nothing && return false
    if name == "float_overflow"
        _set_float_flag(ld, a, FLT_OVERFLOW, :infinity) ||
            return PL_domain_error(ld, "flag_value", val)
    elseif name == "float_zero_div"
        _set_float_flag(ld, a, FLT_ZERO_DIV, :infinity) ||
            return PL_domain_error(ld, "flag_value", val)
    elseif name == "float_undefined"
        _set_float_flag(ld, a, FLT_UNDEFINED, :nan) ||
            return PL_domain_error(ld, "flag_value", val)
    elseif name == "float_underflow"
        _set_float_flag(ld, a, FLT_UNDERFLOW, :ignore) ||
            return PL_domain_error(ld, "flag_value", val)
    elseif name == "float_rounding"
        i = atom_to_rounding(a)
        i == 0 && return PL_domain_error(ld, "flag_value", val)
        ld.arith_f_flags = (ld.arith_f_flags & ~FLT_ROUND_MASK) | UInt32(i)
    else
        return false
    end
    return true
end

# PORT: pl-arith.c current_arithmetic_function as pl_current_arithmetic_function1_va
# DIVERGES: the functor is `(name, arity)` and the table is `ar_funcdefs` (its entries are ported ones, in the
# kernel's order, where upstream's `GD->arith.functions` is indexed by the functor's index: the ORDER of the
# solutions differs, the SET is the same); `i` is the 0-based position in the table, `functorArithFunction(i)`
# is the function of that name, and `GD->arith.functions[i]` being set is every position (no empty slot). The redo
# context is `PL_retry` (`ForeignRedoInt`).
# (PRED_IMPL("current_arithmetic_function", 1, current_arithmetic_function, PL_FA_NONDETERMINISTIC))
"`current_arithmetic_function/1` (pl-arith.c): true if `Term` is evaluable; enumerates the evaluable functors for a variable."
function pl_current_arithmetic_function1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    head = PL__t0
    i = 0
    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, head)
            i = 0
        else
            fd = PL_get_functor(ld, head)
            fd === nothing &&
                return PL_error(ld, ERR_TYPE, mk_sym(T, :callable), head) ? FTRUE : FFALSE
            return isCurrentArithFunction(T, sym_key(fd[1]), fd[2]) != 0 ? FTRUE : FFALSE
        end
    elseif ctl == FRG_REDO
        i = PL_foreign_context(PL__ctx)                 # (int)CTX_INT
    else                                                # FRG_CUTTED
        return FTRUE
    end

    while i < length(ar_funcdefs)
        f, a = functorArithFunction(i)
        if PL_unify_functor(ld, head, mk_sym(T, f), a)
            return PL_retry(i + 1)                      # ForeignRedoInt(i+1)
        end
        i += 1
    end
    return FFALSE
end

# PORT: pl-arith.c PL_eval_expression_to_int64_ex
# DIVERGES: returns the value or `nothing` (upstream: `int *` result and `int64_t *val`), the error raised.
"Evaluate the expression term `t` to an `Int64` (pl-arith.c): `type_error(integer_expression, T)` for a non-integer, `int_overflow` past 64 bits."
function PL_eval_expression_to_int64_ex(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Int64} where {T}
    n = _number_alloc!(ld)
    val = nothing
    if valueExpression(ld, t, n)
        if toIntegerNumber(ld, n, 0)
            if n.type === V_INTEGER
                val = n.i
            else                                            # V_MPZ
                fits, v = mpz_to_int64(n.mpz)
                if fits
                    val = v
                else
                    PL_error(ld, "", 0, "", ERR_EVALUATION, mk_sym(T, :int_overflow))
                end
            end
        else
            PL_error(ld, ERR_TYPE, mk_sym(T, :integer_expression), t)
        end
    end
    _number_free!(ld, 1)
    return val
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
    PL_extension("=:=", 2, pl_eq2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("succ", 2, pl_succ2_va, PL_FA_VARARGS),
    PL_extension("plus", 3, pl_plus3_va, PL_FA_VARARGS),
    PL_extension("between", 3, pl_between3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("bounded_number", 3, pl_bounded_number3_va, PL_FA_VARARGS),
    PL_extension("float_class", 2, pl_float_class2_va, PL_FA_VARARGS),
    PL_extension("float_parts", 4, pl_float_parts4_va, PL_FA_VARARGS),
    PL_extension(
        "current_arithmetic_function", 1, pl_current_arithmetic_function1_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("divmod", 4, pl_divmod4_va, PL_FA_VARARGS),
    PL_extension(
        "nth_integer_root_and_remainder", 4, pl_nth_integer_root_and_remainder4_va,
        PL_FA_VARARGS
    ),
    PL_extension("rational", 3, pl_rational3_va, PL_FA_VARARGS),
    PL_extension("set_random", 1, pl_set_random1_va, PL_FA_VARARGS),
    PL_extension("random_property", 1, pl_random_property1_va, PL_FA_VARARGS)
)
