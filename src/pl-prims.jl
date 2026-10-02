# UPSTREAM: swipl-devel src/pl-prims.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE STANDARD ORDER OF TERMS — SWI-Prolog's `compareStandard` and the chain under it, under the
# same names: compareStandard → compare_std → compare_fast → do_compare → compare_primitives /
# compare_functors, and the leaf comparisons compareAtoms, compareStrings, compare_neq_floats,
# compare_mixed_float_rational. Upstream's order (pl-prims.c, `compare_std` comment and the tag
# values in pl-data.h):
#
#     Var @< AttVar @< Number @< String @< Atom @< Compound
#     numbers by value (on a float/integer tie the float first), atoms and strings by character
#     codes, compounds by arity, then name, then arguments left to right.
#
# Terms are reached ONLY through the term interface (src/term_interface.jl), so this works for any
# implementation. Where the interface model differs from SWI's cells, the function says DIVERGES.
#
# NOT PORTED, deliberately: CMP_MODE_PARTIAL (`partial_compare/3`), attributed-variable ordering, and
# the cyclic-term machinery (`linkTermsCyclic`, `compare_descend`, CMP_INCOMPARABLE) — interface
# terms are finite trees.

# ── results and modes (pl-incl.h `cmp_t`/`cmpex_t`, pl-prims.c `cmp_mode`) ───────────────────────
"Standard-order result: the first term sorts before the second (pl-incl.h `CMP_LESS`)."
const CMP_LESS = -1
"Standard-order result: the terms are identical (pl-incl.h `CMP_EQUAL`)."
const CMP_EQUAL = 0
"Standard-order result: the first term sorts after the second (pl-incl.h `CMP_GREATER`)."
const CMP_GREATER = 1
"Equality-mode result: the terms differ, order not computed (pl-incl.h `CMP_NOTEQ`)."
const CMP_NOTEQ = 2
"`compare_primitives` result: both terms are compound — descend (pl-incl.h `CMP_COMPOUND`)."
const CMP_COMPOUND = -3
"Mode: only decide equal / not equal (`==/2`) — pl-prims.c `CMP_MODE_EQUAL`."
const CMP_MODE_EQUAL = 0
"Mode: the full standard order (`compare/3`, `@</2`) — pl-prims.c `CMP_MODE_ORDER`."
const CMP_MODE_ORDER = 1

_sign(x::Integer)::Int =
    if x < 0
        CMP_LESS
    elseif x > 0
        CMP_GREATER
    else
        CMP_EQUAL
    end

# ── leaf comparisons ─────────────────────────────────────────────────────────────────────────────

# PORT: pl-prims.c compareAtoms
"""
    compareAtoms(a::Symbol, b::Symbol) -> Int

Atoms by their text: byte-wise, then shorter first (pl-prims.c `compareAtoms`, the text-blob
branch). `Base.cmp` on two `Symbol`s is `strcmp`, which is exactly that order for text without NUL
— and a Julia `Symbol` cannot contain NUL, so an upstream atom with an embedded NUL (test_bips.pl
`zero_codes`) has no counterpart in the reference type.
"""
compareAtoms(a::Symbol, b::Symbol)::Int = a === b ? CMP_EQUAL : _sign(cmp(a, b))

# PORT: pl-prims.c compareStrings
"""
    compareStrings(a::AbstractString, b::AbstractString) -> Int

Strings by character codes (pl-prims.c `compareStrings`).
"""
compareStrings(a::AbstractString, b::AbstractString)::Int = _sign(cmp(a, b))

"The NaN payload (significand bits) — upstream `NaN_value`."
_nan_value(f::Base.IEEEFloat)::UInt64 =
    UInt64(reinterpret(Unsigned, f) & Base.significand_mask(typeof(f)))
_nan_value(::AbstractFloat)::UInt64 = UInt64(0)

# PORT: pl-prims.c compare_neq_floats
"""
    compare_neq_floats(f1, f2) -> Int

Two floats already known not to be bit-identical, which therefore may not compare equal
(pl-prims.c `compare_neq_floats`): NaN sorts before every number, two NaNs by payload and then
sign, otherwise by value, and on a numeric tie (only `-0.0` vs `0.0`) the negative zero first.
"""
function compare_neq_floats(f1::AbstractFloat, f2::AbstractFloat)::Int
    if isnan(f1)
        if isnan(f2)
            n1, n2 = _nan_value(f1), _nan_value(f2)
            n1 < n2 && return CMP_LESS
            n1 > n2 && return CMP_GREATER
            signbit(f1) != signbit(f2) && return signbit(f1) ? CMP_LESS : CMP_GREATER
            return CMP_EQUAL
        end
        return CMP_LESS
    elseif isnan(f2)
        return CMP_GREATER
    end
    f1 < f2 && return CMP_LESS
    f1 > f2 && return CMP_GREATER
    return signbit(f1) ? CMP_LESS : CMP_GREATER
end

# PORT: pl-prims.c compare_mixed_float_rational
"""
    compare_mixed_float_rational(x::Real, y::Real) -> Int

A float against an integer or rational (pl-prims.c `compare_mixed_float_rational`): a NaN float
sorts first, otherwise by value, and on a tie THE FLOAT FIRST — so `1.0` sorts before `1`.
"""
function compare_mixed_float_rational(x::Real, y::Real)::Int
    rc = if x isa AbstractFloat && isnan(x)
        CMP_LESS
    elseif y isa AbstractFloat && isnan(y)
        CMP_GREATER
    else
        if x < y
            CMP_LESS
        elseif x > y
            CMP_GREATER
        else
            CMP_EQUAL
        end
    end
    rc == CMP_EQUAL && (rc = x isa AbstractFloat ? CMP_LESS : CMP_GREATER)
    return rc
end

# ── the walk ─────────────────────────────────────────────────────────────────────────────────────

"Variables, atomic terms, compounds: the order of the three groups (pl-data.h tag order)."
_tag_rank(k::Kind)::Int =
    if k === VAR
        0
    elseif k === EXPR
        2
    else
        1
    end

# PORT: pl-prims.c compare_primitives
# DIVERGES: upstream orders atomic cells by their tags itself; the interface hides payloads, so two atomic terms are ordered by the implementation's `atomic_compare`, which must follow the same ladder.
"""
    compare_primitives(t1, t2, mode::Int) -> Int

One step of the walk (pl-prims.c `compare_primitives`): variables before atomic terms before
compounds; two variables by [`var_key`](@ref); two atomic terms by [`atomic_compare`](@ref); two
compounds → `CMP_COMPOUND`, meaning "descend".
"""
function compare_primitives(t1::T, t2::T, mode::Int)::Int where {T}
    k1, k2 = kind(t1), kind(t2)
    r1, r2 = _tag_rank(k1), _tag_rank(k2)
    if r1 != r2
        mode == CMP_MODE_EQUAL && return CMP_NOTEQ
        return r1 < r2 ? CMP_LESS : CMP_GREATER
    end
    if r1 == 0
        a, b = var_key(t1), var_key(t2)
        a == b && return CMP_EQUAL
        return mode == CMP_MODE_EQUAL ? CMP_NOTEQ : (a < b ? CMP_LESS : CMP_GREATER)
    elseif r1 == 1
        c = atomic_compare(t1, t2)
        c == 0 && return CMP_EQUAL
        return mode == CMP_MODE_EQUAL ? CMP_NOTEQ : _sign(c)
    end
    return CMP_COMPOUND
end

# PORT: pl-prims.c compare_functors
# DIVERGES: a SWI functor is a name plus an arity; here the "name" is child 1 and may be a variable or a compound, so this compares the ARITY only and the head is compared by the walk as an ordinary child.
"""
    compare_functors(t1, t2, mode::Int) -> Int

Two compounds by arity (pl-prims.c `compare_functors`). `CMP_EQUAL` means "same shape — compare
the children", head first.
"""
function compare_functors(t1::T, t2::T, mode::Int)::Int where {T}
    n1, n2 = nchildren(t1), nchildren(t2)
    n1 == n2 && return CMP_EQUAL
    mode == CMP_MODE_EQUAL && return CMP_NOTEQ
    return n1 < n2 ? CMP_LESS : CMP_GREATER
end

# PORT: pl-prims.c do_compare
"""
    do_compare(t1, t2, mode::Int) -> Int

Compare two compounds of the same shape child by child, left to right, depth first, with an
explicit agenda instead of recursion (pl-prims.c `do_compare` over a `term_agendaLR`) — so a deep
term cannot overflow the stack. The first difference decides.
"""
function do_compare(t1::T, t2::T, mode::Int)::Int where {T}
    agenda = Tuple{T, T, Int}[(t1, t2, 1)]           # (left, right, next child index)
    while !isempty(agenda)
        a, b, i = agenda[end]
        if i > nchildren(a)
            pop!(agenda)
            continue
        end
        agenda[end] = (a, b, i + 1)
        c1, c2 = child(a, i), child(b, i)
        rc = compare_primitives(c1, c2, mode)
        if rc == CMP_COMPOUND
            rc = compare_functors(c1, c2, mode)
            rc == CMP_EQUAL || return rc
            push!(agenda, (c1, c2, 1))
        elseif rc != CMP_EQUAL
            return rc
        end
    end
    return CMP_EQUAL
end

# PORT: pl-prims.c compare_fast
"""
    compare_fast(t1, t2, mode::Int) -> Int

One walk over both terms (pl-prims.c `compare_fast`): decide at the top if the terms are not both
compound, otherwise compare shapes and then the children with [`do_compare`](@ref).
"""
function compare_fast(t1::T, t2::T, mode::Int)::Int where {T}
    rc = compare_primitives(t1, t2, mode)
    rc == CMP_COMPOUND || return rc
    rc = compare_functors(t1, t2, mode)
    rc == CMP_EQUAL || return rc
    return do_compare(t1, t2, mode)
end

# PORT: pl-prims.c compare_std
# DIVERGES: no cyclic-term fallback (`compare_descend`) — interface terms are finite trees, so the single fast walk is always the answer.
# Long form on purpose: in the SHORT form `f(x::T)::Int where {T} = …` the `where` binds to the
# return type, not the method, and `T` is undefined — precompilation failed on exactly that.
"""
    compare_std(t1, t2, mode::Int) -> Int

The standard-order comparison in `mode` (pl-prims.c `compare_std`).
"""
function compare_std(t1::T, t2::T, mode::Int)::Int where {T}
    return compare_fast(t1, t2, mode)
end

# PORT: pl-prims.c compareStandard
"""
    compareStandard(t1, t2, eq::Bool = false) -> Int

The standard order of terms (pl-prims.c `compareStandard`, Prolog `compare/3`): `-1`, `0` or `1`.
`0` exactly when the terms are identical — the same variables, identical atomic terms (see
[`atomic_compare`](@ref)) and the same structure. With `eq = true` it only decides equality and
returns `0` or `CMP_NOTEQ` (`2`), skipping the ordering work (`==/2`).
"""
function compareStandard(t1::T, t2::T, eq::Bool=false)::Int where {T}
    return compare_std(t1, t2, eq ? CMP_MODE_EQUAL : CMP_MODE_ORDER)
end
