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
# UNIFICATION (the second half of this file) — pl-prims.c's `do_unify` and the predicates on it: `=`,
# `\=`, `unify_with_occurs_check/2`, `?=`, `unifiable/3`, with the `occurs_check` flag's three modes
# and the cyclic-term links that let rational trees unify. Bindings are made with `Trail!` and
# undone with `Undo!` to a `Mark` (src/pl-inline.jl), in the local data (src/pl-global.jl), which
# every function takes EXPLICITLY where upstream reaches `LD` implicitly. As upstream, unification
# does NOT undo on failure: partial bindings stay until the caller undoes to its mark — in SWI,
# backtracking does that.
#
# NOT PORTED, deliberately: CMP_MODE_PARTIAL (`partial_compare/3`), attributed-variable ordering,
# the standard order's cyclic-term machinery (`compare_descend`, CMP_INCOMPARABLE), attributed
# variables in unification (`assignAttVar`, wakeup), and the stack-overflow retry loops.

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

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# UNIFICATION (pl-prims.c)
# ═════════════════════════════════════════════════════════════════════════════════════════════════

"""
    OccursCheckError{T}(var, term)

Raised where SWI-Prolog raises `error(occurs_check(Var, Term), _)`: the `occurs_check` flag is
`OCCURS_CHECK_ERROR` and a unification would bind `var` to a `term` that contains it.
"""
struct OccursCheckError{T} <: Exception
    var::T
    term::T
end

# ── cyclic terms (O_CYCLIC) ──────────────────────────────────────────────────────────────────────
# Bart Demoen's algorithm, as pl-prims.c describes it: before unifying the arguments of two
# compounds, link the first to the second; a compound met again resolves through its link, and a
# pair that resolves to ONE compound is already being unified — so `X = f(X), Y = f(Y), X = Y`
# terminates. Links are reset whether the unification succeeds or fails. (`initCyclic` only sets a
# segstack's unit size upstream; there is nothing to port.)

# PORT: pl-prims.c linkTermsCyclic
# DIVERGES: upstream overwrites `f1`'s functor cell with a reference to `f2`'s and stacks the cell
# on `cycle.lstack`; interface terms cannot be written, so the link is an entry in `cycle_links`, an
# identity map from a compound to its partner, and `f1` is stacked to delete it again.
"Link compound `f1` to `f2` for the rest of this unification (pl-prims.c)."
function linkTermsCyclic!(ld::PL_local_data{T}, f1::T, f2::T)::Nothing where {T}
    ld.cycle_links[f1] = f2                         # *p1 = makeRefG(p2)
    push!(ld.cycle_lstack, f1)                      # pushSegStack(&LD->cycle.lstack, p1, Word)
    return nothing
end

# PORT: pl-prims.c exitCyclic
"Drop every link, one stacked compound at a time (pl-prims.c)."
function exitCyclic!(ld::PL_local_data)::Nothing
    while !isempty(ld.cycle_lstack)
        delete!(ld.cycle_links, pop!(ld.cycle_lstack))  # *p = *unRef(*p)
    end
    return nothing
end

"Compound `f` with its links followed (`do_unify`: `while ( isRef(f1->definition) ) f1 = unRef(…)`)."
function _cyclic_deref(ld::PL_local_data{T}, f::T)::T where {T}
    while true
        n = get(ld.cycle_links, f, nothing)
        n === nothing && return f
        f = n
    end
end

# DIVERGES: two compounds with SYMBOL heads unify as SWI's do — the same name and arity, then the
# arguments. A compound with any other head (a variable or a compound — MeTTa's) has no functor;
# two compounds with the same number of children then unify child by child, heads included.
"""
The functor test of `do_unify` (`f1->definition != f2->definition`): `(child index of argument 0,
arity)` when compounds `f1` and `f2` unify argument by argument, `nothing` when they cannot unify.
"""
function _unify_functor(f1, f2)::Union{Nothing, Tuple{Int, Int}}
    n = nchildren(f1)
    n == nchildren(f2) || return nothing
    if n >= 1 && kind(child(f1, 1)) === SYM && kind(child(f2, 1)) === SYM
        sym_key(child(f1, 1)) == sym_key(child(f2, 1)) || return nothing
        return (2, n - 1)
    end
    return (1, n)
end

# ── unify ────────────────────────────────────────────────────────────────────────────────────────
# PORT: pl-prims.c unify_simple_ptrs
# DIVERGES: (1) "the same cell" (`t1 == t2`) is `===`, or two terms of one variable (`var_key`).
# (2) Two variables: upstream binds the younger cell to the older (by address, "always point
# downwards"); here the larger `var_key` is bound to the smaller. No local stack, so no fresh global
# variable for two local ones. (3) No attributed variables. (4) Atomic data: a symbol by `sym_key`
# (upstream: the same word), a grounded value by the term type's `gnd_equal` (upstream: the same
# word, or `equalIndirect` on the bits — the reference type's `gnd_equal` is that identity).
"""
Unify two DEREFERENCED terms when neither is compound (pl-prims.c): `BOOLEX_TRUE` (bindings made
with `Trail!`), `BOOLEX_FALSE`, or `DO_COMPOUND` when both are compounds.
"""
function unify_simple_ptrs(ld::PL_local_data{T}, t1::T, t2::T)::boolex_t where {T}
    if t1 === t2
        return BOOLEX_TRUE
    end
    k1 = kind(t1)
    k2 = kind(t2)
    if k1 === VAR
        if k2 === VAR
            v1 = var_key(t1)
            v2 = var_key(t2)
            if v1 > v2                              # SWAPW(t1, t2)
                t1, t2 = t2, t1
                v1, v2 = v2, v1
            end
            if v1 < v2                              # always point downwards
                Trail!(ld, v2, t1)
                return BOOLEX_TRUE
            end
            return BOOLEX_TRUE                      # one variable, two terms
        end
        Trail!(ld, var_key(t1), t2)                 # Trail(t1, w2)
        return BOOLEX_TRUE
    end
    if k2 === VAR
        Trail!(ld, var_key(t2), t1)                 # Trail(t2, w1)
        return BOOLEX_TRUE
    end
    if k1 !== k2                                    # tagex(w1) != tagex(w2)
        return BOOLEX_FALSE
    end
    if k1 === SYM
        return sym_key(t1) == sym_key(t2) ? BOOLEX_TRUE : BOOLEX_FALSE
    elseif k1 === GND
        return gnd_equal(t1, t2) ? BOOLEX_TRUE : BOOLEX_FALSE
    end
    return DO_COMPOUND
end

# PORT: pl-prims.c do_unify
# DIVERGES: only a pair of compounds REACHED THROUGH A BINDING (one side was a variable that
# dereferenced to a compound) is checked against and entered into the cyclic links; upstream links
# every pair. Upstream's link is one pointer write; here it is an identity-map entry, and linking
# every pair made `=` 27–38× slower than swipl on 8191-cell trees (measured 2026-10-03, tools/bench.jl:
# 80% of the samples in the map). Termination is kept: interface terms are finite trees, so a pair
# can only be met again through a binding, and the second time it is, its link is found. Answers
# are kept: a pair unified twice instead of once unifies the second time without binding anything.
"""
    do_unify(ld, t1, t2) -> boolex_t

Unify `t1` and `t2` under the bindings in `ld` (pl-prims.c): bind variables with `Trail!`, walk
compounds argument by argument with an explicit agenda, and link compound pairs so that rational
trees terminate. Does NOT undo on failure.
"""
function do_unify(ld::PL_local_data{T}, t1::T, t2::T)::boolex_t where {T}
    bound = kind(t1) === VAR || kind(t2) === VAR    # reached through a binding (see above)
    t1 = deRef(ld, t1)
    t2 = deRef(ld, t2)

    rc = unify_simple_ptrs(ld, t1, t2)
    if rc != DO_COMPOUND
        return rc
    end
    rc = BOOLEX_TRUE

    f = _unify_functor(t1, t2)                      # f1->definition != f2->definition
    if f === nothing
        return BOOLEX_FALSE
    end

    agenda = ld.unify_agenda
    initTermAgendaLR!(agenda, f[2], t1, t2, f[1])
    bound && linkTermsCyclic!(ld, t1, t2)

    while true
        found, l0, r0 = nextTermAgendaLR!(agenda)
        found || break
        l = deRef(ld, l0)
        r = deRef(ld, r0)
        rc = unify_simple_ptrs(ld, l, r)
        rc == BOOLEX_TRUE && continue
        rc == BOOLEX_FALSE && break                 # (no overflow codes to break on)
        rc = BOOLEX_TRUE

        bound = kind(l0) === VAR || kind(r0) === VAR
        if bound                                    # O_CYCLIC
            l = _cyclic_deref(ld, l)
            r = _cyclic_deref(ld, r)
            l === r && continue
        end

        f = _unify_functor(l, r)
        if f === nothing
            rc = BOOLEX_FALSE
            break
        end
        pushWorkAgendaLR!(agenda, f[2], l, r, f[1])
        bound && linkTermsCyclic!(ld, l, r)
    end

    clearTermAgendaLR!(agenda)
    exitCyclic!(ld)
    return rc
end

# PORT: pl-prims.c raw_unify_ptrs
"Unify under the local data's `occurs_check` flag (pl-prims.c)."
function raw_unify_ptrs(ld::PL_local_data{T}, t1::T, t2::T)::boolex_t where {T}
    flag = ld.prolog_flag_occurs_check
    if flag == OCCURS_CHECK_FALSE
        return do_unify(ld, t1, t2)
    elseif flag == OCCURS_CHECK_TRUE
        return unify_with_occurs_check!(ld, t1, t2, OCCURS_CHECK_TRUE)
    end
    return unify_with_occurs_check!(ld, t1, t2, OCCURS_CHECK_ERROR)
end

# PORT: pl-prims.c unify_ptrs
# DIVERGES: no `flags` and no overflow retry — stacks cannot overflow; `true` or `false` (an
# occurs-check error is thrown).
"Unify `t1` and `t2` (pl-prims.c `unify_ptrs`): `true` or `false`; does not undo on failure."
unify_ptrs(ld::PL_local_data{T}, t1::T, t2::T) where {T} =
    raw_unify_ptrs(ld, t1, t2) == BOOLEX_TRUE

# PORT: pl-prims.c can_unify
# DIVERGES: no foreign frame and no wakeup of delayed goals (no attributed variables): a mark, and
# an undo whatever happens. An exception (an occurs-check error) propagates after the undo, where
# upstream hands it back through `ex`.
"Whether `t1` and `t2` can be unified, leaving no binding behind (pl-prims.c)."
function can_unify(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    m = Mark(ld)
    try
        return unify_ptrs(ld, t1, t2)
    finally
        Undo!(ld, m)
    end
end

# ── occurs check ─────────────────────────────────────────────────────────────────────────────────
"Upstream's `v == t` (the same cell): the same variable when `v` is one, else the same compound."
_same_cell(v, t)::Bool =
    if kind(v) === VAR
        kind(t) === VAR && var_key(t) == var_key(v)
    else
        t === v
    end

# PORT: pl-prims.c var_occurs_in
# DIVERGES: "the same cell" is `_same_cell` — `v` is a variable, or (asked by the unifier of a
# binding's value) a compound, to find a cycle made through bindings. A visited compound is an entry
# in `occurs_marked` where upstream sets FIRST_MASK on its functor cell; `occurs_visited` is
# upstream's `visited` stack, popped to clear the marks.
"Whether `v` occurs in `t` under the bindings in `ld` (pl-prims.c)."
function var_occurs_in(ld::PL_local_data{T}, v::T, t::T)::Bool where {T}
    t = deRef(ld, t)
    unified = false                                 # enter at `unified:`, skipping the first test
    if _same_cell(v, t)
        kind(t) === EXPR || return false
        unified = true
    end

    compound = false
    rc = false
    agenda = ld.occurs_agenda
    visited = ld.occurs_visited
    marked = ld.occurs_marked
    while true
        if !unified && _same_cell(v, t)
            rc = true
            break
        end
        unified = false
        if kind(t) === EXPR                         # isTerm(*t)
            off, arity = _comp_shape(t)
            if !compound
                compound = true
                marked[t] = nothing                 # f->definition |= FIRST_MASK
                push!(visited, t)
                initTermAgenda!(agenda, arity, t, off)
            elseif !haskey(marked, t)
                marked[t] = nothing
                push!(visited, t)
                pushWorkAgenda!(agenda, arity, t, off)
            end
        end
        compound || break
        n = nextTermAgenda!(ld, agenda)
        n === nothing && break
        t = n
    end

    if compound
        while !isempty(visited)                     # f->definition &= ~FIRST_MASK
            delete!(marked, pop!(visited))
        end
        clearTermAgenda!(agenda)
    end
    return rc
end

# PORT: pl-prims.c failed_unify_with_occurs_check
# DIVERGES: raises an `OccursCheckError` where upstream raises the Prolog error term.
"Fail (`OCCURS_CHECK_TRUE`) or raise the occurs-check error, as `Var = Term` (pl-prims.c)."
function failed_unify_with_occurs_check(
    ld::PL_local_data{T}, t1::T, t2::T, mode::occurs_check_t
)::boolex_t where {T}
    if mode == OCCURS_CHECK_TRUE
        return BOOLEX_FALSE
    end
    t1 = deRef(ld, t1)
    t2 = deRef(ld, t2)
    if kind(t2) === VAR                             # try to make Var = Term
        t1, t2 = t2, t1
    end
    throw(OccursCheckError{T}(t1, t2))
end

# PORT: pl-prims.c unify_with_occurs_check
# DIVERGES: no `onStack(global, …)` test (no local stack) and no attributed-variable trail entries.
"""
Unify with the occurs check in `mode` (pl-prims.c): a variable against a term that contains it
fails or raises; two non-variables are unified and every binding made is then checked for a cycle.
"""
function unify_with_occurs_check!(
    ld::PL_local_data{T}, t1::T, t2::T, mode::occurs_check_t
)::boolex_t where {T}
    t1 = deRef(ld, t1)
    t2 = deRef(ld, t2)
    if kind(t1) === VAR                             # canBind(*t1)
        if var_occurs_in(ld, t1, t2)
            return failed_unify_with_occurs_check(ld, t1, t2, mode)
        end
        return do_unify(ld, t1, t2)
    end
    if kind(t2) === VAR
        if var_occurs_in(ld, t2, t1)
            return failed_unify_with_occurs_check(ld, t1, t2, mode)
        end
        return do_unify(ld, t1, t2)
    end

    m = Mark(ld)
    rc = do_unify(ld, t1, t2)
    if rc == BOOLEX_TRUE
        tt = length(ld.trail)
        mt = m.trailtop
        while tt > mt                               # while(--tt >= mt)
            key = ld.trail[tt]                      # tt->address
            p2 = deRef(ld, ld.bindings[key])        # deRef2(p, p2): its value, dereferenced
            if var_occurs_in(ld, p2, p2)
                if mode == OCCURS_CHECK_ERROR
                    t = p2                          # *t = *p2: the value, kept past the undo
                    Undo!(ld, m)
                    failed_unify_with_occurs_check(ld, mk_var(T, key), t, mode)
                end
                rc = BOOLEX_FALSE
                break
            end
            tt -= 1
        end
    end
    return rc
end

# ── the predicates ───────────────────────────────────────────────────────────────────────────────
# PORT: pl-prims.c unify as pl_unify
"""
    pl_unify!(ld, t1, t2) -> Bool

`=/2` (pl-prims.c, through `PL_unify`): unify under the `occurs_check` flag. On failure the partial
bindings stay until the caller undoes to its [`mark`](@ref) — in SWI, backtracking does.
"""
pl_unify!(ld::PL_local_data{T}, t1::T, t2::T) where {T} = unify_ptrs(ld, t1, t2)

# PORT: pl-prims.c not_unify as pl_not_unify
# DIVERGES: the quick tests read kinds: two symbols differ by `sym_key` (upstream: different words),
# two grounded values by `gnd_equal`.
"""
    pl_not_unify(ld, t1, t2) -> Bool

`\\=/2` (pl-prims.c): `t1` and `t2` cannot be unified. Leaves no binding behind.
"""
function pl_not_unify(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    p1 = deRef(ld, t1)
    p2 = deRef(ld, t2)
    if kind(p1) === VAR || kind(p2) === VAR
        ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE && return false   # can unify
        return !can_unify(ld, p1, p2)               # full_check
    end
    p1 === p2 && return false
    kind(p1) !== kind(p2) && return true
    if kind(p1) === SYM
        return sym_key(p1) != sym_key(p2)
    elseif kind(p1) === GND
        return !gnd_equal(p1, p2)
    end
    return !can_unify(ld, p1, p2)                   # full_check
end

# PORT: pl-prims.c unify_with_occurs_check as pl_unify_with_occurs_check
"""
    pl_unify_with_occurs_check!(ld, t1, t2) -> Bool

`unify_with_occurs_check/2` (pl-prims.c): `=` with the `occurs_check` flag `true` for its duration.
"""
function pl_unify_with_occurs_check!(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    old = ld.prolog_flag_occurs_check
    ld.prolog_flag_occurs_check = OCCURS_CHECK_TRUE
    try
        return unify_ptrs(ld, t1, t2)
    finally
        ld.prolog_flag_occurs_check = old
    end
end

# PORT: pl-prims.c can_compare as pl_can_compare
"""
    pl_can_compare(ld, t1, t2) -> Bool

`?=/2` (pl-prims.c): it can be decided now and forever whether `t1` and `t2` are equal — they are
identical (they unify without binding anything) or they cannot unify. Leaves no binding behind.
"""
function pl_can_compare(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    m = Mark(ld)
    try
        if unify_ptrs(ld, t1, t2)
            return length(ld.trail) == m.trailtop  # fr->mark.trailtop != tTop ⇒ false
        end
        return true                                 # could not unify
    finally
        Undo!(ld, m)
    end
end

# PORT: pl-prims.c unifiable_occurs_check
"`unifiable/3`'s occurs check when one side is a variable (pl-prims.c)."
function unifiable_occurs_check(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    flag = ld.prolog_flag_occurs_check
    flag == OCCURS_CHECK_FALSE && return true
    p1 = deRef(ld, t1)
    var_occurs_in(ld, p1, t2) || return true
    return failed_unify_with_occurs_check(ld, p1, t2, flag) == BOOLEX_TRUE
end

# PORT: pl-prims.c unify_all_trail_ptrs
# DIVERGES: every binding is trailed anyway (no `mark_bar`), and no overflow retry.
"Unify, keeping every binding on the trail above the returned mark; undo on plain failure (pl-prims.c)."
function unify_all_trail_ptrs(
    ld::PL_local_data{T}, t1::T, t2::T
)::Tuple{Bool, mark} where {T}
    m = Mark(ld)
    rc = raw_unify_ptrs(ld, t1, t2)                 # an occurs-check error propagates, no undo
    if rc == BOOLEX_TRUE
        return (true, m)
    end
    Undo!(ld, m)
    return (false, m)
end

# PORT: pl-prims.c unifiable
# DIVERGES: returns the substitution as `var => value` pairs (`nothing` when the terms do not
# unify) where upstream unifies a Prolog list of `Var = Value`; the comparison of a variable with
# the other side is identity of the variable (upstream: `PL_compare` equal).
"""
    unifiable(ld, t1, t2) -> Union{Nothing, Vector{Pair{T, T}}}

`unifiable/3` (pl-prims.c): the bindings that would make `t1` and `t2` identical, newest first, read
off the trail as it is rewound — so nothing stays bound — or `nothing` if they do not unify.
"""
function unifiable(
    ld::PL_local_data{T}, t1::T, t2::T
)::Union{Nothing, Vector{Pair{T, T}}} where {T}
    p1 = deRef(ld, t1)
    p2 = deRef(ld, t2)
    if kind(p1) === VAR                             # PL_is_variable(t1)
        if _same_cell(p1, p2)                       # PL_compare(t1, t2) == CMP_EQUAL
            return Pair{T, T}[]
        end
        unifiable_occurs_check(ld, t1, t2) || return nothing
        return Pair{T, T}[p1 => p2]
    end
    if kind(p2) === VAR
        unifiable_occurs_check(ld, t2, t1) || return nothing
        return Pair{T, T}[p2 => p1]
    end

    ok, m = unify_all_trail_ptrs(ld, t1, t2)
    ok || return nothing
    list = Pair{T, T}[]
    while length(ld.trail) > m.trailtop             # while(--tt >= mt), newest first
        key = pop!(ld.trail)
        value = ld.bindings[key]                    # gp[5] = *p
        push!(list, mk_var(T, key) => value)        # gp[4] = makeRefG(p)
        delete!(ld.bindings, key)                   # setVar(*p)
    end
    return list
end

# PORT: pl-prims.c unifiable as pl_unifiable
"`unifiable/3` (pl-prims.c): see [`unifiable`](@ref)."
pl_unifiable(ld::PL_local_data{T}, t1::T, t2::T) where {T} = unifiable(ld, t1, t2)

# ── copying an answer out ────────────────────────────────────────────────────────────────────────
# No upstream counterpart: SWI's bindings ARE the term, so an answer needs no copying. Here a caller
# that keeps an answer past the next `Undo!` must take a bound term out first.
# DIVERGES: a cyclic binding (a rational tree, legal under `OCCURS_CHECK_FALSE`) cannot be built as
# an interface term — the reference type is a tree — so it raises an `ArgumentError`, where SWI
# hands back the cyclic term.
"""
    resolve_term(ld, t) -> T

`t` with every bound variable replaced by its value, recursively: a term that no longer needs `ld`.
Unbound variables stay; ground subterms are shared, not copied. Raises an `ArgumentError` on a
cyclic binding.
"""
function resolve_term(ld::PL_local_data{T}, t::T)::T where {T}
    t = deRef(ld, t)
    (kind(t) !== EXPR || is_ground(t)) && return t
    stack = Tuple{T, Vector{T}}[(t, T[])]           # (compound, its children resolved so far)
    on_path = IdDict{T, Nothing}(t => nothing)      # compounds being resolved: a revisit is a cycle
    while true
        node, kids = stack[end]
        i = length(kids) + 1
        if i > nchildren(node)
            pop!(stack)
            delete!(on_path, node)
            r = mk_expr(T, kids)
            isempty(stack) && return r
            push!(stack[end][2], r)
            continue
        end
        c = deRef(ld, child(node, i))
        if kind(c) === EXPR && !is_ground(c)
            haskey(on_path, c) && throw(
                ArgumentError(
                    "resolve_term: a cyclic binding (a rational tree) has no interface term"
                )
            )
            on_path[c] = nothing
            push!(stack, (c, T[]))
        else
            push!(kids, c)
        end
    end
end
