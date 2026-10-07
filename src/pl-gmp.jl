# UPSTREAM: swipl-devel src/pl-gmp.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-gmp.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-inline.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2005-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# The number core of SWI-Prolog's arithmetic (pl-gmp.c), V6c: a term read as a `number`
# (src/pl-incl.jl) and a `number` written as a term; promotion between the number types; comparison.
#
# DIVERGES (file-wide):
#   * GMP's `mpz_t`/`mpq_t` are Julia's `BigInt` and `Rational{BigInt}`, computed BY VALUE: Julia's
#     GMP operations return a new number where GMP writes into an initialised one, so
#     `mpz_init`/`clearNumber` have nothing to do.
#   * A term is read through the term interface (`number_kind` and the typed getters), never by its
#     tag, and written with `mk_gnd`; the V_INTEGER/V_MPZ split is `Int64`, where upstream's is the
#     tagged range (±2^56). That changes the storage only: the values, and every operation on them,
#     are the same.
#   * The rounding mode is always to nearest: nothing sets another (`roundtoward/2` is not ported),
#     so only `FE_TONEAREST`'s branch of a `fegetround()` switch is kept.

# ── reading a term (pl-gmp.h, pl-gmp.c) ──────────────────────────────────────────────────────────
# PORT: pl-gmp.h get_rational
"Read the integer or rational `w` (dereferenced) into `n` (pl-gmp.h `get_rational`)."
function get_rational(w, n::number)::Nothing
    if number_kind(w) === NUM_INTEGER
        if integer_is_int64(w)                              # isTaggedInt(w)
            n.i = int64_value(w)
            n.type = V_INTEGER
        else
            n.mpz = bigint_value(w)                         # get_rational_no_int: V_MPZ
            n.type = V_MPZ
        end
    else
        n.mpq = rational_value(w)                           # get_rational_no_int: V_MPQ
        n.type = V_MPQ
    end
    return nothing
end

# PORT: pl-gmp.c get_number
"Read the number `w` (dereferenced) into `n` (pl-gmp.c `get_number`)."
function get_number(w, n::number)::Nothing
    if isRational(w)
        get_rational(w, n)
    else
        n.type = V_FLOAT
        n.f = float_value(w)
    end
    return nothing
end

# ── writing a term (pl-gmp.c) ────────────────────────────────────────────────────────────────────
# PORT: pl-gmp.c put_mpz
# DIVERGES: returns the term (upstream writes it through `at`); see `put_number`.
"`mpz` as a term in its most compact form (pl-gmp.c): an `Int64` when it fits."
function put_mpz(::Type{T}, mpz::BigInt)::T where {T}
    if typemin(Int64) <= mpz <= typemax(Int64)              # MPZ_MIN_TAGGED..MPZ_MAX_TAGGED
        return mk_gnd(T, Int64(mpz))                        # *at = consInt(v)
    end
    return _put_big(T, mpz)                                 # globalMPZ(at, mpz)
end

# Whether term type `T` can hold a value of type `X`: an implementation other than `Term` holds any
# payload (AltTerm does); `Term{G}` answers for itself (src/default_term.jl).
_holds_payload(::Type, ::Type) = true

# DIVERGES (interim, until T1): a result the term type cannot hold. `T`'s payload is asked at
# compile time (`_holds_payload`); one without `BigInt`/`Rational{BigInt}` (`DefaultTerm` today)
# raises a Julia `ArgumentError` — loud, never a wrong value — where swipl, unbounded, returns the
# big number. T1 gives `DefaultTerm` the payload, as decided since Q-AR1.
function _put_big(::Type{T}, v::Union{BigInt, Rational{BigInt}})::T where {T}
    if _holds_payload(T, typeof(v))
        return mk_gnd(T, v)
    end
    throw(
        ArgumentError(
            string(
                "put_number: ", v, " does not fit the term type ", T,
                " (no BigInt/Rational{BigInt} payload until plan step T1)"
            )
        )
    )
end

# PORT: pl-gmp.h clearNumber
# DIVERGES: nothing to free (a `number`'s big integer and rational are Julia's GC's); kept so the
# callers read as upstream's.
"Release a number's GMP storage (pl-gmp.h): nothing, here."
clearNumber(n::number)::Nothing = nothing

# PORT: pl-gmp.c put_number
# DIVERGES: returns the term (upstream writes it through `at`, with room ensured for `bindConst`:
# no global stack here). `put_int64`'s overflow branch cannot be taken: every `Int64` is one value.
"`n` as a term in its most compact form (pl-gmp.c `put_number`)."
function put_number(::Type{T}, n::number)::T where {T}
    t = n.type
    if t === V_INTEGER
        return mk_gnd(T, n.i)                               # consInt / put_int64
    elseif t === V_MPZ
        return put_mpz(T, n.mpz)
    elseif t === V_MPQ
        if denominator(n.mpq) == 1                          # mpz_cmp_ui(mpq_denref(...), 1) == 0
            return put_mpz(T, numerator(n.mpq))
        end
        return _put_big(T, n.mpq)                           # globalMPQ(at, n->value.mpq)
    end
    f = n.f
    isnan(f) && (f = PL_nan())                              # put_double: canonical 1.5NaN
    return mk_gnd(T, f)                                     # put_double(at, n->value.f)
end

# PORT: pl-gmp.c PL_unify_number
"Unify term reference `t` with the number `n` (pl-gmp.c): bind a variable, else compare by value."
function PL_unify_number(ld::PL_local_data{T}, t::term_t, n::number)::Bool where {T}
    p = deRef(ld, ld.slots[t + 1])
    if canBind(p)                                           # isVar(*p) && …: varBindConst
        Trail!(ld, var_key(p), put_number(T, n))            # bindConst(p, w)
        return true
    end
    nt = n.type
    if nt === V_INTEGER || nt === V_MPZ
        if nt === V_INTEGER && integer_is_int64(p) && number_kind(p) === NUM_INTEGER
            return int64_value(p) == n.i                    # isTaggedInt(*p): valInt(*p) == …
        end
        if isInteger(p)                                     # FALLTHROUGH: V_MPZ
            n2 = _number_alloc!(ld)
            get_rational(p, n2)                             # get_integer(*p, &n2)
            rc = cmpNumbers(ld, n, n2) == CMPEX_EQUAL
            _number_free!(ld, 1)                             # clearNumber(&n2)
            return rc
        end
    elseif nt === V_MPQ
        if isRational(p)
            n2 = _number_alloc!(ld)
            get_rational(p, n2)
            rc = cmpNumbers(ld, n, n2) == CMPEX_EQUAL
            _number_free!(ld, 1)
            return rc
        end
    elseif isFloat(p)                                       # V_FLOAT
        return reinterpret(UInt64, float_value(p)) == reinterpret(UInt64, n.f)   # memcmp
    end
    return false
end

# ── promotion (pl-gmp.c, pl-inline.h) ───────────────────────────────────────────────────────────
# PORT: pl-gmp.c promoteToMPZNumber
"Promote `n` to `V_MPZ` in place (pl-gmp.c); a rational truncates, a float converts."
function promoteToMPZNumber(n::number)::Bool
    t = n.type
    if t === V_INTEGER
        n.mpz = BigInt(n.i)                                 # mpz_init_set_si64
        n.type = V_MPZ
    elseif t === V_MPQ
        n.mpz = div(numerator(n.mpq), denominator(n.mpq))   # mpz_tdiv_q: truncating
        n.type = V_MPZ
    elseif t === V_FLOAT
        n.mpz = BigInt(trunc(n.f))                          # mpz_init_set_d: truncating
        n.type = V_MPZ
    end
    return true
end

# PORT: pl-gmp.c promoteToMPQNumber
"Promote `n` to `V_MPQ` in place (pl-gmp.c); a NaN or infinite float is an evaluation error."
function promoteToMPQNumber(ld::PL_local_data, n::number)::Bool
    t = n.type
    if t === V_INTEGER || t === V_MPZ
        t === V_INTEGER && promoteToMPZNumber(n)            # FALLTHROUGH
        n.mpq = Rational{BigInt}(n.mpz, BigInt(1))          # mpq_numref = mpz; denref = 1
        n.type = V_MPQ
    elseif t === V_FLOAT
        v = n.f
        isnan(v) && return PL_error(ld, ERR_AR_UNDEF)
        isinf(v) && return PL_error(ld, ERR_AR_RAT_OVERFLOW)
        n.mpq = Rational{BigInt}(v)                         # mpq_set_d: exact
        n.type = V_MPQ
    end
    return true
end

# PORT: pl-gmp.c promoteToFloatNumber
"Promote `n` to `V_FLOAT` in place (pl-gmp.c), then `check_float`."
function promoteToFloatNumber(ld::PL_local_data, n::number)::Bool
    t = n.type
    if t === V_INTEGER
        n.f = Float64(n.i)                                  # (double)n->value.i
        n.type = V_FLOAT
    elseif t === V_MPZ
        n.f = mpz_to_double(n.mpz)
        n.type = V_FLOAT
    elseif t === V_MPQ
        n.f = mpq_to_double(n.mpq)
        n.type = V_FLOAT
    else
        return true                                         # V_FLOAT
    end
    return check_float(ld, n)
end

# PORT: pl-gmp.c promoteNumber
"Promote `n` to type `t` (pl-gmp.c `promoteNumber`)."
function promoteNumber(ld::PL_local_data, n::number, t::numtype)::Bool
    t === V_INTEGER && return true
    t === V_MPZ && return promoteToMPZNumber(n)
    t === V_MPQ && return promoteToMPQNumber(ld, n)
    return promoteToFloatNumber(ld, n)
end

# PORT: pl-gmp.c make_same_type_numbers
"Promote the lower of `n1`, `n2` to the other's type (pl-gmp.c): `numtype` is a total order."
function make_same_type_numbers(ld::PL_local_data, n1::number, n2::number)::Bool
    if n1.type > n2.type
        return promoteNumber(ld, n2, n1.type)
    end
    return promoteNumber(ld, n1, n2.type)
end

# PORT: pl-inline.h same_type_numbers
"`make_same_type_numbers` when the types differ (pl-inline.h)."
function same_type_numbers(ld::PL_local_data, n1::number, n2::number)::Bool
    n1.type != n2.type && return make_same_type_numbers(ld, n1, n2)
    return true
end

# ── the size of a big integer (pl-gmp.h) ─────────────────────────────────────────────────────────
# PORT: pl-gmp.h MPZ_MAX_BYTES
"The largest GMP integer, in bytes, with slack (pl-gmp.h): GMP aborts on a larger one."
const MPZ_MAX_BYTES = typemax(UInt64) ÷ 8 - 1024

# PORT: pl-gmp.h maxBigIntSize
# DIVERGES: `globalStackLimit()` is upstream's `stacks.limit` in BYTES; the kernel's `stacks_limit`
# counts positions (words), so it is multiplied by the word size.
"The largest big integer, in bytes, the kernel creates (pl-gmp.h): the stack limit or GMP's."
maxBigIntSize(ld::PL_local_data)::UInt64 = min(UInt64(ld.stacks_limit) * 8, MPZ_MAX_BYTES)

# ── to double (pl-gmp.c) ─────────────────────────────────────────────────────────────────────────
# GMP's `mpz_get_d` truncates; `mpz_tstbit` reads two's complement — Julia's `>>` on a BigInt is
# arithmetic, so `isodd(a >> i)` is that bit. `mpz_sizeinbase(a, 2)` is `ndigits(a; base=2)`,
# `mpz_scan1(a, 0)` `trailing_zeros(a)`.
_mpz_get_d(a::BigInt)::Float64 = Float64(a, RoundToZero)
_mpz_tstbit(a::BigInt, i::Integer)::Bool = isodd(a >> i)
# `sa - mpz_scan1(a, 0)` in upstream's `size_t`: for 0, `mpz_scan1` is ULONG_MAX and the difference
# WRAPS to 2 (`sa` is 1) — so a 0 takes the "representable on 53 bits" path, and gives 0.0. Julia's
# `trailing_zeros(big(0))` is a DomainError: the wrap is written out.
_sa_minus_scan1(a::BigInt, sa::Int)::Int = iszero(a) ? 2 : sa - trailing_zeros(a)

# PORT: pl-gmp.c mpz_to_double
"`a` (not 0) as the nearest double (pl-gmp.c): `mpz_get_d`'s truncation corrected."
function mpz_to_double(a::BigInt)::Float64
    d = _mpz_get_d(a)                                       # truncated, note: a != 0
    sa = ndigits(a; base=2)
    isinf(d) && return d                                    # float overflow check
    _sa_minus_scan1(a, sa) <= 53 && return d                # truncated value is accurate (0 too)
    na = trailing_zeros(a)
    bit54 = _mpz_tstbit(a, sa - 54)
    trailing = na >= sa - 54                                # trailing_zeros
    if d > 0                                                # FE_TONEAREST
        if !bit54
        elseif !trailing || _mpz_tstbit(a, sa - 53)
            d = nextfloat(d)                                # nexttoward(d, INFINITY)
        end
    else
        if bit54 && !trailing                               # d is negative
        elseif !trailing || !_mpz_tstbit(a, sa - 53)
            d = prevfloat(d)                                # nexttoward(d, -INFINITY)
        end
    end
    return d
end

# PORT: pl-gmp.c mpz_fdiv
"`a / b` as the nearest double (pl-gmp.c), from the gmp-devel list's algorithm."
function mpz_fdiv(a::BigInt, b::BigInt)::Float64
    sa = ndigits(a; base=2)
    sb = ndigits(b; base=2)
    if sa <= 53 && sb <= 53                                 # easy case
        return _mpz_get_d(a) / _mpz_get_d(b)
    end
    na = _sa_minus_scan1(a, sa)
    nb = _sa_minus_scan1(b, sb)
    if sa <= 1024 && na <= 53 && sb <= 1024 && nb <= 53
        return _mpz_get_d(a) / _mpz_get_d(b)
    end
    if sa >= sb                                             # hard case
        aa = a
        bb = b << (sa - sb)
    else
        aa = a << (sb - sa)
        bb = b
    end
    if abs(aa) >= abs(bb)                                   # q = aa/bb*2^(sa-sb)
        bb = bb << 1
        sa += 1
    end
    aa = aa << 54
    sb += 54
    aa, bb = divrem(aa, bb)                                 # mpz_tdiv_qr
    if !isodd(aa)                                           # FE_TONEAREST
    elseif !iszero(bb)
        aa = aa > 0 ? aa + 1 : aa - 1
    else                                                    # mid case: round to even
        if !_mpz_tstbit(aa, 1)
            aa = aa > 0 ? aa - 1 : aa + 1
        else
            aa = aa > 0 ? aa + 1 : aa - 1
        end
    end
    d = _mpz_get_d(aa)                                      # exact
    return ldexp(d, sa - sb)
end

# PORT: pl-gmp.c mpq_to_double
"`q` as the nearest double (pl-gmp.c)."
mpq_to_double(q::Rational{BigInt})::Float64 = mpz_fdiv(numerator(q), denominator(q))

# ── comparison (pl-gmp.c) ────────────────────────────────────────────────────────────────────────
# PORT: pl-gmp.c cmpFloatNumbers
# DIVERGES: the bit-pattern test first, as upstream's (its reason, the x87 extended register, does
# not arise here; the result is the same).
"Compare `n1`, `n2`, one of them a float, the other converted to a double (pl-gmp.c)."
function cmpFloatNumbers(n1::number, n2::number)::Int
    if n1.type === V_FLOAT
        isnan(n1.f) && return CMP_NOTEQ
        t2 = n2.type
        d2 = if t2 === V_INTEGER
            Float64(n2.i)                                   # (double)n2->value.i
        elseif t2 === V_MPZ
            mpz_to_double(n2.mpz)
        else
            mpq_to_double(n2.mpq)                           # V_MPQ
        end
        f1 = n1.f
        return if reinterpret(UInt64, f1) == reinterpret(UInt64, d2)
            CMPEX_EQUAL
        elseif f1 == d2
            CMPEX_EQUAL
        elseif f1 < d2
            CMPEX_LESS
        else
            CMPEX_GREATER
        end
    end
    @assert n2.type === V_FLOAT
    isnan(n2.f) && return CMP_NOTEQ                         # CMP_NOTEQ != -CMP_NOTEQ :(
    return -cmpFloatNumbers(n2, n1)
end

# PORT: pl-gmp.c cmpNumbers
"Compare `n1`, `n2` (pl-gmp.c): `CMPEX_LESS`/`EQUAL`/`GREATER`, or `CMP_NOTEQ` for a NaN."
function cmpNumbers(ld::PL_local_data, n1::number, n2::number)::Int
    if n1.type != n2.type
        if n1.type === V_FLOAT || n2.type === V_FLOAT
            return cmpFloatNumbers(n1, n2)
        end
        rc = make_same_type_numbers(ld, n1, n2)
        @assert rc
    end
    t = n1.type
    if t === V_INTEGER
        return cmp(n1.i, n2.i)                              # SCALAR_TO_CMP
    elseif t === V_MPZ
        return Int(sign(cmp(n1.mpz, n2.mpz)))               # SCALAR_TO_CMP(mpz_cmp(…), 0)
    elseif t === V_MPQ
        return Int(sign(cmp(n1.mpq, n2.mpq)))               # SCALAR_TO_CMP(mpq_cmp(…), 0)
    end
    n1.f == n2.f && return CMPEX_EQUAL                      # V_FLOAT
    lt = n1.f < n2.f
    gt = n1.f > n2.f
    !lt && !gt && return CMP_NOTEQ                          # either is NaN
    return Int(gt) - Int(lt)
end
