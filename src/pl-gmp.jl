# UPSTREAM: swipl-devel src/pl-gmp.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-gmp.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-inline.h @ 8609e216cab9
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
# DIVERGES: on the WORDS (L1d; the workspace's L1_plan/stageL1d_design.md §3e): `t` dereferenced
# with `_deref_loc`; an unbound cell is bound to `consInt` when the integer fits a tagged word
# (`varBindConst`), else to `put_number`'s value as a value-table word (upstream's indirect,
# `bindConst`) — trailed on the CELL (`_bind_const!`, the word trail), no variable term read; a tagged
# integer is compared by `valInt`, a value-table word by its stored number, an atom or a compound
# fails. The boundary (a slot's side value, a keyed variable) is decided on its term
# (`_unify_number_term`), counted in `cold_pairs`. No attributed variable lives in a cell yet, so
# `bindConst`'s wakeup has nothing to do here (the keyed variables take the term path).
"Unify term reference `t` with the number `n` (pl-gmp.c): bind a variable, else compare by value."
function PL_unify_number(ld::PL_local_data{T}, t::term_t, n::number)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # deRef(p)
    if k == DU_CELL                                         # isVar(*p)
        if n.type === V_INTEGER && PLMINTAGGEDINT <= n.i <= PLMAXTAGGEDINT &&
            _holds_payload(T, Int64)                        # valInt(w=consInt(i)) == i
            _bind_const!(ld, p, consInt(n.i))               # varBindConst(p, w)
        else
            c = _gnd_word!(ld, put_number(T, n))            # put_number(&w, n)
            _bind_const!(ld, p, c)                          # bindConst(p, w)
        end
        return true
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return _unify_number_term(ld, deRef(ld, _loc_term(ld, k, w, p)), n)
    elseif k == DU_WORD                                     # an atom or a compound: no number
        return false
    end
    isTaggedIntW(w) || return _unify_number_term(ld, ld.vtable[valPtr(w)], n)
    nt = n.type
    nt === V_INTEGER && return valInt(w) == n.i             # isTaggedInt(*p)
    (nt === V_MPZ || nt === V_MPQ) || return false          # V_FLOAT: isFloat(*p) is false
    n2 = _number_alloc!(ld)                                 # FALLTHROUGH: isInteger(*p)
    n2.i = valInt(w)                                        # get_integer(*p, &n2)
    n2.type = V_INTEGER
    rc = cmpNumbers(ld, n, n2) == CMPEX_EQUAL
    _number_free!(ld, 1)                                    # clearNumber(&n2)
    return rc
end

# PORT: pl-gmp.c PL_unify_number as _unify_number_term
# TRANSITIONAL (L1d §3e, until L1f): PL_unify_number on a dereferenced TERM `p` — the boundary of the
# word version (a keyed variable is bound through its key) and a value-table entry's stored value.
"Unify the dereferenced term `p` with the number `n` (pl-gmp.c): bind a variable, else compare by value."
function _unify_number_term(ld::PL_local_data{T}, p::T, n::number)::Bool where {T}
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
# `mpz_get_d` truncates; past the double range (more than 1024 bits) it returns ±Inf (GMP on IEEE), which
# `mpz_to_double`'s overflow check (`isinf(d)`) relies on. The kernel DECIDES that range itself and only then
# converts (exact truncation within range, public API) — `Float64(a, RoundToZero)` alone gives ±Inf on Julia
# 1.13.1 and ±floatmax on 1.13.2 (JuliaLang/julia#63525; batch 3's CI, audits D-0025/D-0026).
function _mpz_get_d(a::BigInt)::Float64
    ndigits(a; base=2) > 1024 && return signbit(a) ? -Inf : Inf    # exponent too big: ±Inf
    return Float64(a, RoundToZero)
end
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

# PORT: pl-gmp.c mpq_set_double
# DIVERGES: returns the rational (`Rational{BigInt}` is by value) where upstream writes `r`; the
# continued fraction is run on `BigInt`s, `mpz_fdiv_qr` (floor) as `fldmod`; `mpq_set_d` is the exact
# `Rational{BigInt}(f)` (as in `promoteToMPQNumber`). `f` is finite (the callers check).
"The nice rational of the finite float `f` (pl-gmp.c `mpq_set_double`): continued fractions until it converts back to `f`."
function mpq_set_double(f::Float64)::Rational{BigInt}
    m = BigInt(1)                                           # (m,n) = (1,0)
    n = BigInt(0)
    p = BigInt(0)                                           # (p,q) = (0,1)
    q = BigInt(1)
    r = Rational{BigInt}(f)                                 # mpq_set_d
    v = numerator(r)                                        # (v,w) == (r.num, r.den)
    w = denominator(r)
    fp = reinterpret(UInt64, f)
    while true
        d, u = fldmod(v, w)                                 # mpz_fdiv_qr
        p += d * m                                          # mpz_addmul
        q += d * n
        rp = mpz_fdiv(p, q)
        if reinterpret(UInt64, rp) == fp || iszero(u)       # terminating conditions
            return p // q                                   # final answer, p & q are co-prime
        end
        v = w
        w = u
        m, p = p, m                                         # mpz_swap
        n, q = q, n
    end
end

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

# cmpReals() compares two real numbers of any type and is mathematically correct: floats and 64 bit
# integers without extended arithmetic, the rest by the bignum library's compare. Upstream's large 4x4
# switch calls a targeted function per pair; a negated result is right for every pair but those with a
# float (-CMP_NOTEQ is wrong).
# PORT: pl-gmp.c cmp_i_i
"Compare two `int64_t` (pl-gmp.c): -1, 0 or 1."
cmp_i_i(i1::Int64, i2::Int64)::Int = Int(i1 > i2) - Int(i1 < i2)     # SCALAR_TO_CMP

# PORT: pl-gmp.c cmp_f_f
"Compare two doubles (pl-gmp.c): -1, 0 or 1, `CMP_NOTEQ` if either is a NaN."
function cmp_f_f(d1::Float64, d2::Float64)::Int
    (isnan(d1) || isnan(d2)) && return CMP_NOTEQ
    return Int(d1 > d2) - Int(d1 < d2)                      # SCALAR_TO_CMP
end

# PORT: pl-gmp.c cmp_i_f
# See https://stackoverflow.com/questions/58734034/ : the integer as the sum of two doubles, each exact.
"Compare an `int64_t` with a double, exactly (pl-gmp.c): -1, 0 or 1, `CMP_NOTEQ` for a NaN."
function cmp_i_f(i1::Int64, d2::Float64)::Int
    isnan(d2) && return CMP_NOTEQ
    if i1 >= 0
        d1_lo = Float64(i1 & Int64(0x00000000FFFFFFFF))     # TOD(i1 & 0x00000000FFFFFFFF)
        d1_hi = Float64(i1 & Int64(-4294967296))            # TOD(i1 & 0xFFFFFFFF00000000)
    else
        d1_lo = Float64(i1 | Int64(-4294967296))            # TOD(i1 | 0xFFFFFFFF00000000)
        d1_hi = Float64(i1 | Int64(0x00000000FFFFFFFF)) + 1.0
    end
    x = d2 - d1_hi
    return Int(d1_lo > x) - Int(d1_lo < x)                  # SCALAR_TO_CMP(d1_lo, d2-d1_hi)
end

# PORT: pl-gmp.c cmp_z_z
"Compare two big integers (pl-gmp.c): -1, 0 or 1."
cmp_z_z(z1::BigInt, z2::BigInt)::Int = Int(sign(cmp(z1, z2)))        # mpz_cmp

# PORT: pl-gmp.c cmp_q_q
"Compare two rationals (pl-gmp.c): -1, 0 or 1."
cmp_q_q(q1::Rational{BigInt}, q2::Rational{BigInt})::Int =
    Int(sign(cmp(q1, q2)))                                  # mpq_cmp

# PORT: pl-gmp.c cmp_z_i
"Compare a big integer with an `int64_t` (pl-gmp.c): -1, 0 or 1."
cmp_z_i(z1::BigInt, i2::Int64)::Int = Int(sign(cmp(z1, i2)))         # mpz_cmp_si

# PORT: pl-gmp.c cmp_q_i
# `mpq_cmp_si(q1, i2, 1)` is a cross multiplication, written out (a denominator is > 0).
"Compare a rational with an `int64_t` (pl-gmp.c): -1, 0 or 1."
cmp_q_i(q1::Rational{BigInt}, i2::Int64)::Int =
    Int(sign(cmp(numerator(q1), BigInt(i2) * denominator(q1))))

# PORT: pl-gmp.c cmp_z_f
"Compare a big integer with a double (pl-gmp.c): exact, an infinity compares correctly; NaN is `CMP_NOTEQ`."
function cmp_z_f(z1::BigInt, d2::Float64)::Int
    isnan(d2) && return CMP_NOTEQ
    return Int(z1 > d2) - Int(z1 < d2)                      # mpz_cmp_d handles infinities
end

# PORT: pl-gmp.c cmp_f_q
"Compare a double with a rational (pl-gmp.c): the double is made an exact rational first."
function cmp_f_q(d1::Float64, q2::Rational{BigInt})::Int
    isnan(d1) && return CMP_NOTEQ
    d1 == Inf && return CMPEX_GREATER
    d1 == -Inf && return CMPEX_LESS
    return cmp_q_q(Rational{BigInt}(d1), q2)                # mpq_set_d: exact
end

# PORT: pl-gmp.c cmp_q_z
# `mpq_cmp_z(q1, z2)`: a cross multiplication, written out (a denominator is > 0).
"Compare a rational with a big integer (pl-gmp.c): -1, 0 or 1."
cmp_q_z(q1::Rational{BigInt}, z2::BigInt)::Int =
    Int(sign(cmp(numerator(q1), z2 * denominator(q1))))

# PORT: pl-gmp.c cmpReals
"Compare two real numbers of any type, mathematically correctly (pl-gmp.c): `CMP_NOTEQ` if a NaN is involved."
function cmpReals(n1::number, n2::number)::Int
    t1 = n1.type
    t2 = n2.type
    if t1 === V_INTEGER
        t2 === V_INTEGER && return cmp_i_i(n1.i, n2.i)
        t2 === V_FLOAT && return cmp_i_f(n1.i, n2.f)
        t2 === V_MPZ && return -cmp_z_i(n2.mpz, n1.i)
        t2 === V_MPQ && return -cmp_q_i(n2.mpq, n1.i)
    elseif t1 === V_FLOAT
        if t2 === V_INTEGER
            rc = cmp_i_f(n2.i, n1.f)
            return rc == CMP_NOTEQ ? rc : -rc
        elseif t2 === V_FLOAT
            return cmp_f_f(n1.f, n2.f)
        elseif t2 === V_MPZ
            rc = cmp_z_f(n2.mpz, n1.f)
            return rc == CMP_NOTEQ ? rc : -rc
        elseif t2 === V_MPQ
            return cmp_f_q(n1.f, n2.mpq)
        end
    elseif t1 === V_MPZ
        t2 === V_INTEGER && return cmp_z_i(n1.mpz, n2.i)
        t2 === V_FLOAT && return cmp_z_f(n1.mpz, n2.f)
        t2 === V_MPZ && return cmp_z_z(n1.mpz, n2.mpz)
        t2 === V_MPQ && return -cmp_q_z(n2.mpq, n1.mpz)
    elseif t1 === V_MPQ
        t2 === V_INTEGER && return cmp_q_i(n1.mpq, n2.i)
        if t2 === V_FLOAT
            rc = cmp_f_q(n2.f, n1.mpq)
            return rc == CMP_NOTEQ ? rc : -rc
        end
        t2 === V_MPZ && return cmp_q_z(n1.mpq, n2.mpz)
        t2 === V_MPQ && return cmp_q_q(n1.mpq, n2.mpq)
    end
    return CMP_NOTEQ                                        # unrecognized type?, treat as nan
end

# ── big integers to machine integers, and the integer root (pl-gmp.c, GMP) ───────────────────────
# PORT: pl-gmp.c mpz_to_int64
# DIVERGES: returns `(fits, value)`, where upstream writes `*i` and returns the flag.
"The `Int64` an integer `mpz` is, if it fits (pl-gmp.c): `(true, value)`, else `(false, 0)`."
function mpz_to_int64(mpz::BigInt)::Tuple{Bool, Int64}
    if typemin(Int64) <= mpz <= typemax(Int64)              # MPZ_MIN_INT64 .. MPZ_MAX_INT64
        return (true, Int64(mpz))
    end
    return (false, Int64(0))
end

# PORT: pl-gmp.c mpz_to_uint64
# DIVERGES: returns `(status, value)`, where upstream writes `*i` and returns the status.
"The `UInt64` an integer `mpz` is (pl-gmp.c): `(0, value)`; `(-1, 0)` if negative, `(1, 0)` if too big."
function mpz_to_uint64(mpz::BigInt)::Tuple{Int, UInt64}
    mpz < 0 && return (-1, UInt64(0))
    mpz <= typemax(UInt64) && return (0, UInt64(mpz))
    return (1, UInt64(0))
end

# GMP's `mpz_root(rop, op, n)`: the truncated integer `n`th root of `op`, and whether it is exact. A
# negative `op` has a root for odd `n` only (the callers check); the root is the negative of its
# magnitude's. Newton's iteration from a power of two above the root, as GMP's does in effect.
"The truncated integer `n`th root of `x` (GMP `mpz_root`) and whether `root^n == x`."
function mpz_root(x::BigInt, n::UInt64)::Tuple{BigInt, Bool}
    iszero(x) && return (BigInt(0), true)
    if x < 0
        r, exact = mpz_root(-x, n)
        return (-r, exact)
    end
    n == 1 && return (x, true)
    nb = ndigits(x; base=2)                                 # mpz_sizeinbase(x, 2)
    n >= nb && return (BigInt(1), isone(x))                 # 1 <= x < 2^nb <= 2^n: the root is 1
    if n == 2
        s = isqrt(x)                                        # mpz_sqrt
        return (s, s * s == x)
    end
    k = Int(n)
    y = BigInt(1) << cld(nb, k)                             # >= the root
    while true
        t = ((k - 1) * y + x ÷ y^(k - 1)) ÷ k
        t >= y && break
        y = t
    end
    return (y, y^k == x)
end
