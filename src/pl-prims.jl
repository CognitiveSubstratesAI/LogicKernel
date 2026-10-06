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
# The standard order comes in two entries: without `ld`, for RESOLVED terms (finite trees: the fast
# walk is always the answer), and with `ld` (V5a), under bindings, where a term can be a rational
# tree — upstream's cyclic machinery (`linkTermsCyclic` in `do_compare`, `compare_descend`,
# `is_acyclic`) is ported there.
#
# NOT PORTED, deliberately: CMP_MODE_PARTIAL (`partial_compare/3`), the `incomparable` flag's
# `error` value (`compare_std`), attributed-variable ordering, attributed variables in unification
# (`assignAttVar`, wakeup), and the stack-overflow retry loops.

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

# The whole of pl-prims.c `compareAtoms`, for an implementation's `atomic_compare` (Q1, 2026-10-03):
# an atom is its name and whether it is a reserved symbol — the two blob types a kernel term can
# have. DIVERGES: upstream reads the blob type from the atom handle; released blobs and the other
# blob types (streams, clause references, wide text) do not exist here.
"""
    compareAtoms(a::Symbol, a_reserved::Bool, b::Symbol, b_reserved::Bool) -> Int

Two atoms in the standard order (pl-prims.c `compareAtoms`): of ONE blob type, by that type's
order — reserved symbols by `compareReservedSymbol` (`strcmp`), text atoms by their text (the
two-argument method); of two types, by the types' RANK — a reserved symbol (rank 0) before every
text atom, so `[]` sorts before `''`.
"""
function compareAtoms(a::Symbol, ra::Bool, b::Symbol, rb::Bool)::Int
    if ra == rb                                         # a1->type == a2->type
        return ra ? compareReservedSymbol(a, b) : compareAtoms(a, b)
    end
    r1 = ra ? RESERVED_SYMBOL_RANK : TEXT_ATOM_RANK     # SCALAR_TO_CMP(a1->type->rank, …)
    r2 = rb ? RESERVED_SYMBOL_RANK : TEXT_ATOM_RANK
    return _sign(r1 - r2)
end

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
# DIVERGES: upstream orders atomic cells by their tags itself; the interface hides payloads, so two
# atomic terms are ordered by the implementation's `atomic_compare`, which must follow the same
# ladder — numbers < strings < atoms, an atom by its blob type's rank (`compareAtoms`) — with ONE
# addition SWI has no counterpart for: a grounded value of no SWI type (NUM_OTHER) sorts as a
# non-text blob, after strings and before `[]` and every text atom (`OTHER_BLOB_RANK`,
# src/pl-ressymbol.jl).
"""
    compare_primitives(t1, t2, mode::Int) -> Int

One step of the walk (pl-prims.c `compare_primitives`): variables before atomic terms before
compounds; two variables by [`var_key`](@ref); two atomic terms by [`atomic_compare`](@ref); two
compounds → `CMP_COMPOUND`, meaning "descend".
"""
function compare_primitives(t1, t2, mode::Int)::Int
    t1 === t2 && return CMP_EQUAL               # w1 == w2: the same term (a variable: itself)
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
# DIVERGES: a SWI functor is a name plus an arity. Below a symbol head the functor is that name and
# arity (children - 1); any other compound has the functor `$expr/n` (Q2, src/pl-ressymbol.jl), n
# its children. By arity, as upstream; at one arity `$expr` sorts before every symbol name. Two
# symbol names — and two `$expr` — are left to the walk, which compares the head as child 1 first:
# the order upstream gets by comparing the names here.
"""
    compare_functors(t1, t2, mode::Int) -> Int

Two compounds by functor (pl-prims.c `compare_functors`): arity first, then `\$expr/n` before a
symbol head. `CMP_EQUAL` means "compare the children", head first.
"""
function compare_functors(t1, t2, mode::Int)::Int
    off1, a1 = _comp_shape(t1)
    off2, a2 = _comp_shape(t2)
    if a1 == a2
        off1 == off2 && return CMP_EQUAL
        mode == CMP_MODE_EQUAL && return CMP_NOTEQ
        return off1 < off2 ? CMP_LESS : CMP_GREATER     # `$expr/n` (offset 1) first
    end
    mode == CMP_MODE_EQUAL && return CMP_NOTEQ
    return a1 < a2 ? CMP_LESS : CMP_GREATER
end

# PORT: pl-prims.c do_compare
"""
    do_compare(t1, t2, mode::Int) -> Int

Compare two compounds of the same shape child by child, left to right, depth first, with an
explicit agenda instead of recursion (pl-prims.c `do_compare` over a `term_agendaLR`) — so a deep
term cannot overflow the stack. The first difference decides.
"""
function do_compare(t1, t2, mode::Int)::Int
    T = term_type(t1)
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
function compare_fast(t1, t2, mode::Int)::Int
    rc = compare_primitives(t1, t2, mode)
    rc == CMP_COMPOUND || return rc
    rc = compare_functors(t1, t2, mode)
    rc == CMP_EQUAL || return rc
    return do_compare(t1, t2, mode)
end

# PORT: pl-prims.c compare_std
# DIVERGES: no cyclic-term fallback (`compare_descend`) — interface terms are finite trees, so the single fast walk is always the answer.
"""
    compare_std(t1, t2, mode::Int) -> Int

The standard-order comparison in `mode` (pl-prims.c `compare_std`).
"""
function compare_std(t1, t2, mode::Int)::Int
    return compare_fast(t1, t2, mode)
end

# PORT: pl-prims.c compareStandard
"""
    compareStandard(t1, t2, eq::Bool = false) -> Int

The standard order of terms (pl-prims.c `compareStandard`, Prolog `compare/3`): `-1`, `0` or `1`.
`0` exactly when the terms are identical — the same variables, identical atomic terms (see
[`atomic_compare`](@ref)) and the same structure. With `eq = true` it only decides equality and
returns `0` or `CMP_NOTEQ` (`2`), skipping the ordering work (`==/2`).

Both terms must be of ONE term type ([`term_type`](@ref)), or it throws an `ArgumentError`.
"""
function compareStandard(t1, t2, eq::Bool=false)::Int
    term_type(t1) === term_type(t2) || throw(
        ArgumentError(
            "compareStandard: terms of two term types, $(term_type(t1)) and $(term_type(t2))"
        )
    )
    return compare_std(t1, t2, eq ? CMP_MODE_EQUAL : CMP_MODE_ORDER)
end

# ── the standard order UNDER BINDINGS (V5a) ──────────────────────────────────────────────────────
# Upstream's chain takes `DECL_LD` and dereferences every pair (prims:1997-2184). A built-in reads
# its arguments from slots whose variables may be bound (decision 2), and through bindings a term
# can be a RATIONAL TREE (`occurs_check=false`), so these methods port upstream's cyclic machinery
# as well: `linkTermsCyclic` in `do_compare`, `compare_descend` (Brent's cycle detection) and
# `is_acyclic`. The methods above, without `ld`, stay the entry for RESOLVED terms — finite trees,
# where the fast walk is always the answer.

"`compare_descend` result: no order exists between the two terms (pl-incl.h `CMP_INCOMPARABLE`)."
const CMP_INCOMPARABLE = 4

# PORT: pl-prims.c do_compare
# DIVERGES: only a pair of compounds REACHED THROUGH A BINDING is looked up in and entered into the
# cyclic links, as `do_unify` does — see there ("WHY IT IS SAFE"): an interface term is a finite
# tree, so a cycle can only pass through a binding. `bound` says whether the top pair was reached
# through one. Returns `(rc, linked)` where upstream writes `*linked`; no `CMP_UNDECIDED`
# (`CMP_MODE_PARTIAL` is not ported) and no `CMP_ERROR` (no memory overflow to report).
"""
    do_compare(ld, f1, f2, bound, mode) -> (Int, Bool)

Compare the children of two compounds of one shape under the bindings in `ld` (pl-prims.c
`do_compare`), linking compound pairs so that rational trees terminate; `linked` is true when a
link was followed — the order found may then be wrong for cyclic terms (`compare_std`).
"""
function do_compare(
    ld::PL_local_data{T}, f1::T, f2::T, bound::Bool, mode::Int
)::Tuple{Int, Bool} where {T}
    linked = false
    agenda = ld.compare_agenda
    initTermAgendaLR!(agenda, nchildren(f1), f1, f2, 1)     # goto compound
    bound && linkTermsCyclic!(ld, f1, f2)
    rc = CMP_EQUAL
    while true
        found, l0, r0 = nextTermAgendaLR!(agenda)
        found || break
        l = deRef(ld, l0)
        r = deRef(ld, r0)
        rc = compare_primitives(l, r, mode)
        if rc != CMP_COMPOUND
            rc == CMP_EQUAL && continue
            break
        end
        rc = CMP_EQUAL
        b = kind(l0) === VAR || kind(r0) === VAR           # reached through a binding
        if b                                                # O_CYCLIC
            l1 = _cyclic_deref(ld, l)
            r1 = _cyclic_deref(ld, r)
            if l1 !== l || r1 !== r                         # isRef(f1->definition) || …
                linked = true
                l, r = l1, r1
                l === r && continue
            end
        end
        rc = compare_functors(l, r, mode)
        rc == CMP_EQUAL || break
        pushWorkAgendaLR!(agenda, nchildren(l), l, r, 1)
        b && linkTermsCyclic!(ld, l, r)
    end
    clearTermAgendaLR!(agenda)
    return (rc, linked)
end

# PORT: pl-prims.c compare_fast
# DIVERGES: returns `(rc, linked)` where upstream writes `*linked`; no `c1`/`c2` (only
# `CMP_MODE_PARTIAL` reads them, not ported).
"""
    compare_fast(ld, t1, t2, mode) -> (Int, Bool)

One walk over both terms under the bindings in `ld` (pl-prims.c `compare_fast`). The result is
right for `CMP_MODE_EQUAL`, and for the order when both terms are acyclic; `linked` as `do_compare`.
"""
function compare_fast(
    ld::PL_local_data{T}, t1::T, t2::T, mode::Int
)::Tuple{Int, Bool} where {T}
    bound = kind(t1) === VAR || kind(t2) === VAR
    t1 = deRef(ld, t1)
    t2 = deRef(ld, t2)
    rc = compare_primitives(t1, t2, mode)
    rc == CMP_COMPOUND || return (rc, false)
    rc = compare_functors(t1, t2, mode)                     # f1->definition != f2->definition
    rc == CMP_EQUAL || return (rc, false)
    rc, linked = do_compare(ld, t1, t2, bound, mode)        # initCyclic(): nothing to set
    exitCyclic!(ld)
    return (rc, linked)
end

# PORT: pl-prims.c compare_descend
# DIVERGES: two compounds are the same pair when they are the same objects (`===`) — a cycle passes
# through a binding, and a binding's value is one object (upstream: the same `Functor` cells). No
# `CMP_ERROR` from the argument tests (no memory overflow).
"""
    compare_descend(ld, t1, t2, mode) -> (Int, T, T)

The slow but sound order of two terms under the bindings in `ld` (pl-prims.c `compare_descend`):
at each compound skip the leading children that are equal and descend into the first pair that is
not, until a pair decides — or the descent cycles (Brent's algorithm on the compound pairs), which
is `CMP_INCOMPARABLE`, with the pair where it cycles.
"""
function compare_descend(
    ld::PL_local_data{T}, p1::T, p2::T, mode::Int
)::Tuple{Int, T, T} where {T}
    s1, s2, have_s = p1, p2, false                          # Functor s1 = NULL, s2 = NULL
    power = 1
    steps = 0
    while true
        p1 = deRef(ld, p1)
        p2 = deRef(ld, p2)
        rc = compare_primitives(p1, p2, mode)
        rc == CMP_COMPOUND || return (rc, p1, p2)
        rc = compare_functors(p1, p2, mode)
        rc == CMP_EQUAL || return (rc, p1, p2)
        if have_s && p1 === s1 && p2 === s2
            return (CMP_INCOMPARABLE, p1, p2)
        end
        steps += 1
        if steps == power
            s1, s2, have_s = p1, p2, true
            power *= 2
            steps = 0
        end
        n = nchildren(p1)
        i = 1                                   # the pair differs, so the last child need not
        while i < n                             # be tested (the head, child 1, is equal)
            rc, _ = compare_fast(ld, child(p1, i), child(p2, i), CMP_MODE_EQUAL)
            rc == CMP_EQUAL || break
            i += 1
        end
        p1 = child(p1, i)
        p2 = child(p2, i)
    end
end

# PORT: pl-prims.c termChain
# DIVERGES: `p` (an argument cell, or NULL) is the compound and the child index of the argument —
# 0 for NULL.
"A chain of compounds linked by their last argument (pl-prims.c `termChain`)."
struct termChain{T}
    head::T
    tail::T
    p_term::T           # the compound whose argument `p` is
    p_arg::Int          # its child index; 0: NULL
end

# PORT: pl-prims.c ph_acyclic_mark
# DIVERGES: the marks (`ACYCLIC_TEMP_MASK`, `ACYCLIC_PERM_MASK` on a functor cell) are entries in two
# identity maps that live for one call — so there is no `ph_acyclic_unmark`. A compound of no
# arguments ends a chain (upstream reads its `arguments - 1`, the functor cell, which is no term).
# No MEMORY_OVERFLOW.
"""
    ph_acyclic_mark(ld, top) -> Bool

Whether compound `top` is acyclic under the bindings in `ld` (pl-prims.c `ph_acyclic_mark`): walk
it as chains of last arguments, marking each compound while its chain is open (temporary) and when
it is done (permanent); meeting a temporarily marked compound again is a cycle.
"""
function ph_acyclic_mark(ld::PL_local_data{T}, top::T)::Bool where {T}
    temp = IdDict{T, Nothing}()
    perm = IdDict{T, Nothing}()
    stack = termChain{T}[]                                  # agenda.stack
    work = termChain{T}(top, top, top, 0)                   # agenda.work (never read at the top)
    head = top
    tail = top
    pv = top
    while true
        if haskey(temp, tail)                               # is_acyclic_temp(&tail->definition)
            haskey(perm, tail) || return false
            @goto end_of_chain
        end
        temp[tail] = nothing                                # set_acyclic_temp
        off, arity = _comp_shape(tail)
        if arity > 1
            new_workspace = false
            iter = tail
            for i in arity:-1:2
                q = deRef(ld, child(iter, off + i - 2))     # p = iter->arguments + i - 2
                if kind(q) === EXPR
                    push!(stack, work)
                    if !new_workspace
                        work = termChain{T}(head, tail, iter, off + arity - 1)
                        head = q
                        tail = q
                        new_workspace = true
                    else
                        work = termChain{T}(q, q, q, 0)
                    end
                end
            end
            new_workspace && continue
        end
        if arity == 0
            @goto end_of_chain
        end
        pv = deRef(ld, child(tail, off + arity - 1))        # p = tail->arguments + arity-1
        @label process_p
        if kind(pv) === EXPR
            tail = pv
            continue
        end
        @label end_of_chain
        head === top && return true
        iter = head
        while iter !== tail                                 # mark the chain permanent
            perm[iter] = nothing
            o, a = _comp_shape(iter)
            iter = deRef(ld, child(iter, o + a - 1))
        end
        perm[tail] = nothing
        head = work.head
        tail = work.tail
        p_term, p_arg = work.p_term, work.p_arg
        @assert !isempty(stack) "ph_acyclic_mark: the agenda ran out"
        work = pop!(stack)
        if p_arg != 0
            pv = deRef(ld, child(p_term, p_arg))
            @goto process_p
        end
    end
end

# PORT: pl-prims.c is_acyclic
"Whether `p` is acyclic under the bindings in `ld` (pl-prims.c `is_acyclic`)."
function is_acyclic(ld::PL_local_data{T}, p::T)::Bool where {T}
    p = deRef(ld, p)
    kind(p) === EXPR || return true
    return ph_acyclic_mark(ld, p)                           # ph_acyclic_unmark: see above
end

# PORT: pl-prims.c compare_std
# DIVERGES: NOT PORTED — the `incomparable` flag's `error` value: it raises a ball holding the
# cyclic pair, which `PL_raise_exception` cannot copy (it resolves the ball, and `resolve_term`
# refuses a cycle). So an incomparable pair keeps the fast result, as swipl's default
# `incomparable=arbitrary` does; `CMP_MODE_PARTIAL` is not ported either.
"""
    compare_std(ld, t1, t2, mode) -> Int

The standard-order comparison in `mode` under the bindings in `ld` (pl-prims.c `compare_std`): the
fast walk, and — when it followed a cyclic link, in an ordering mode, found the terms different,
and one of them is cyclic — the sound descent instead.
"""
function compare_std(ld::PL_local_data{T}, t1::T, t2::T, mode::Int)::Int where {T}
    rc, linked = compare_fast(ld, t1, t2, mode)
    if linked && mode != CMP_MODE_EQUAL && rc != CMP_EQUAL &&
        !(is_acyclic(ld, t1) && is_acyclic(ld, t2))
        rc2, _, _ = compare_descend(ld, t1, t2, mode)
        if rc2 != CMP_INCOMPARABLE
            rc = rc2
        end                                                 # else keep the fast result
    end
    return rc
end

# PORT: pl-prims.c compareStandard
# DIVERGES: `eq` is not optional here (no method of three arguments, so none overlaps the method for
# resolved terms); no `raiseIncomparable` (see `compare_std`).
"""
    compareStandard(ld, t1, t2, eq::Bool) -> Int

The standard order of `t1` and `t2` under the bindings in `ld` (pl-prims.c `compareStandard`), as
[`compareStandard`](@ref) for resolved terms: `-1`, `0` or `1`; with `eq` `0` or `CMP_NOTEQ`.
"""
function compareStandard(ld::PL_local_data{T}, t1::T, t2::T, eq::Bool)::Int where {T}
    return compare_std(ld, t1, t2, eq ? CMP_MODE_EQUAL : CMP_MODE_ORDER)
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
# arguments. A compound with any other head has the functor `$expr/n` (Q2, src/pl-ressymbol.jl),
# and it unifies with ANY compound of n children, child by child, heads included — `(X a) = f(a)`
# binds `X = f` — so the index keys `$expr/n` as a wildcard. A VM must match the same way:
# `H_FUNCTOR $expr/n` against any compound of n children, `H_FUNCTOR f/k` against a `$expr/(k+1)`.
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
# 80% of the samples in the map).
#   WHY IT IS SAFE: in SWI any compound cell can lie on a cycle — terms live on a mutable heap and a
#   cell can point back at an ancestor. An interface term cannot: it is an immutable finite tree, so
#   following children from any compound never returns to it. A cycle can therefore only pass
#   through a VARIABLE BINDING, and every walk around one reaches its compounds through a binding;
#   the first time a pair is reached that way it is linked, the second time the link is found — so
#   unification terminates. Answers are kept: a pair unified twice instead of once unifies the
#   second time without binding anything.
#   🔴 THIS DEPENDS ON THE REPRESENTATION. A term type whose compounds can share MUTABLE structure,
#   or point back at an ancestor, breaks the argument — it must restore linking EVERY pair. Guards:
#   test_unify.jl's cycle_1/cycle_2, the 398 rational trees of test_unify_swipl.jl, and the mutation
#   "links not followed", under which cycle_2 does not terminate.
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

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# THE BUILT-INS (V5a2, decision 5) — pl-prims.c's PRED_IMPLs of the predicates ported above, under
# upstream's C names (`PRED_IMPL(name, arity, fname, flags)` is `pl_<fname><arity>_va`), each a
# line-for-line port over term references: `A1` is `PL__t0`, `A2` is `PL__t0 + 1`, … — a built-in's
# handles ARE its frame's argument slots. The functions above, on bare terms, stay the kernel's
# term-level API.
# ═════════════════════════════════════════════════════════════════════════════════════════════════

# PORT: pl-prims.c can_unify
# DIVERGES: `t1`/`t2` are terms (upstream: cells); `ex` is a term reference or 0 (NULL). No
# `foreignWakeup` (no attributed variables). An occurs-check error is the pending Prolog error
# (`_unify_ptrs_raising`).
"""
    can_unify(ld, t1, t2, ex) -> Bool

Whether `t1` and `t2` unify, leaving no binding behind (pl-prims.c `can_unify`); an exception
raised by the attempt is moved into term reference `ex` and cleared when the caller passes one.
"""
function can_unify(ld::PL_local_data{T}, t1::T, t2::T, ex::term_t)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    if fid != 0
        handle_exception = ex == 0
        if ex == 0
            ex = PL_new_term_ref(ld)
        end
        if _unify_ptrs_raising(ld, t1, t2)              # && foreignWakeup(ex)
            PL_discard_foreign_frame(ld, fid)
            return true
        end
        if ld.exception_term != 0 && kind(ld.slots[ex + 1]) === VAR
            PL_put_term(ld, ex, ld.exception_term)
        end
        if !handle_exception && kind(ld.slots[ex + 1]) !== VAR
            PL_clear_exception(ld)
        end
        PL_discard_foreign_frame(ld, fid)
    end
    return false
end

# PORT: pl-prims.c unify as pl_unify2_va
# (PRED_IMPL("=", 2, unify, 0))
"`=/2` (pl-prims.c)."
function pl_unify2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
end

# PORT: pl-prims.c not_unify as pl_not_unify2_va
# (PRED_IMPL("\\=", 2, not_unify, 0))
# DIVERGES: the quick tests on words are the kernel's atomic identity (`compare_primitives`):
# two atomic terms unify exactly when they are identical, as upstream's word and indirect tests
# decide; a compound on either side goes to the full check. No attributed variables.
"`\\=/2` (pl-prims.c): the arguments cannot unify; an occurs-check error is raised again."
function pl_not_unify2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    p1 = deRef(ld, ld.slots[A1 + 1])                    # Word p1 = valTermRef(A1)
    p2 = deRef(ld, ld.slots[A1 + 2])                    # Word p2 = p1+1
    if kind(p1) === VAR || kind(p2) === VAR
        ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE && return FFALSE   # can unify
        @goto full_check
    end
    p1 === p2 && return FFALSE                          # w1 == w2
    if kind(p1) !== EXPR || kind(p2) !== EXPR           # tag(w1) != tag(w2), the atomic cases
        return compare_primitives(p1, p2, CMP_MODE_EQUAL) == CMP_EQUAL ? FFALSE : FTRUE
    end
    @label full_check
    ex = PL_new_term_ref(ld)
    can_unify(ld, p1, p2, ex) && return FFALSE
    if !PL_is_variable(ld, ex)
        return PL_raise_exception(ld, ex) ? FTRUE : FFALSE
    end
    return FTRUE
end

# PORT: pl-prims.c unify_with_occurs_check as pl_unify_with_occurs_check2_va
# (PRED_IMPL("unify_with_occurs_check", 2, unify_with_occurs_check, 0))
"`unify_with_occurs_check/2` (pl-prims.c): `=` with the `occurs_check` flag `true` for its duration."
function pl_unify_with_occurs_check2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    old = ld.prolog_flag_occurs_check
    ld.prolog_flag_occurs_check = OCCURS_CHECK_TRUE
    rc = PL_unify(ld, A1, A2)
    ld.prolog_flag_occurs_check = old
    return rc ? FTRUE : FFALSE
end

# ── type checking (pl-prims.c), registered since V6b ─────────────────────────────────────────────
# PORT: pl-prims.c nonvar as pl_nonvar1_va
# (PRED_IMPL("nonvar", 1, nonvar, 0))
"`nonvar/1` (pl-prims.c): the argument is not an unbound variable."
function pl_nonvar1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_variable(ld, A1) ? FFALSE : FTRUE
end

# PORT: pl-prims.c var as pl_var1_va
# (PRED_IMPL("var", 1, var, 0))
"`var/1` (pl-prims.c): the argument is an unbound variable."
function pl_var1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_variable(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c integer as pl_integer1_va
# (PRED_IMPL("integer", 1, integer, 0))
"`integer/1` (pl-prims.c): the argument is an integer."
function pl_integer1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_integer(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c float as pl_float1_va
# (PRED_IMPL("float", 1, float, 0))
"`float/1` (pl-prims.c): the argument is a float."
function pl_float1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_float(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c rational as pl_rational1_va
# (PRED_IMPL("rational", 1, rational, 0))
"`rational/1` (pl-prims.c): the argument is a rational number, an integer included."
function pl_rational1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_rational(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c string as pl_string1_va
# (PRED_IMPL("string", 1, string, 0))
"`string/1` (pl-prims.c): the argument is a string."
function pl_string1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_string(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c number as pl_number1_va
# (PRED_IMPL("number", 1, number, 0))
"`number/1` (pl-prims.c): the argument is a number."
function pl_number1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_number(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c atom as pl_atom1_va
# (PRED_IMPL("atom", 1, atom, 0))
"`atom/1` (pl-prims.c): the argument is a text atom (not `[]`)."
function pl_atom1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_atom(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c atomic as pl_atomic1_va
# (PRED_IMPL("atomic", 1, atomic, 0))
"`atomic/1` (pl-prims.c): the argument is atomic."
function pl_atomic1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_atomic(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c compound as pl_compound1_va
# (PRED_IMPL("compound", 1, compound, 0))
"`compound/1` (pl-prims.c): the argument is a compound term."
function pl_compound1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_compound(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c callable as pl_callable1_va
# (PRED_IMPL("callable", 1, callable, PL_FA_ISO))
"`callable/1` (pl-prims.c): the argument is callable."
function pl_callable1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_is_callable(ld, A1) ? FTRUE : FFALSE
end

# PORT: pl-prims.c equal as pl_equal2_va
# (PRED_IMPL("==", 2, equal, 0))
# DIVERGES: no `CMP_ERROR` (the kernel's compare raises nothing; see `compare_std`).
"`==/2` (pl-prims.c): the arguments are identical."
function pl_equal2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    p1 = ld.slots[A1 + 1]                               # Word p1 = valTermRef(A1)
    p2 = ld.slots[A1 + 2]                               # Word p2 = p1+1
    return compareStandard(ld, p1, p2, true) == CMP_EQUAL ? FTRUE : FFALSE
end

# PORT: pl-prims.c nonequal as pl_nonequal2_va
# (PRED_IMPL("\\==", 2, nonequal, 0))
# DIVERGES: no `CMP_ERROR` (see `pl_equal2_va`).
"`\\==/2` (pl-prims.c): the arguments are not identical."
function pl_nonequal2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    p1 = ld.slots[A1 + 1]                               # Word p1 = valTermRef(A1)
    p2 = ld.slots[A1 + 2]                               # Word p2 = p1+1
    return compareStandard(ld, p1, p2, true) == CMP_EQUAL ? FFALSE : FTRUE
end

# PORT: pl-prims.c compare as pl_compare3_va
# (PRED_IMPL("compare", 3, compare, PL_FA_ISO))
# DIVERGES: no `CMP_ERROR` (see `pl_equal2_va`). An atom is any symbol, `[]` included (`isAtom`:
# SWI-7's `[]` is an atom to it).
"`compare/3` (pl-prims.c): the order of the second and third arguments, unified with or checked against the first."
function pl_compare3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    d = deRef(ld, ld.slots[A1 + 1])                     # Word d = valTermRef(A1); deRef(d)
    p1 = ld.slots[A2 + 1]                               # Word p1 = valTermRef(A2)
    p2 = ld.slots[A2 + 2]                               # Word p2 = p1+1
    given = kind(d) !== VAR                             # canBind(*d) ⇒ a = 0
    smaller = false
    if given
        if kind(d) === SYM                              # isAtom(*d)
            k = sym_key(d)
            if k == sym_key(mk_sym(T, :(=)))            # ATOM_equals
                return compareStandard(ld, p1, p2, true) == CMP_EQUAL ? FTRUE : FFALSE
            end
            smaller = k == sym_key(mk_sym(T, :<))       # ATOM_smaller
            if !smaller && k != sym_key(mk_sym(T, :>))  # ATOM_larger
                return PL_error(ld, ERR_DOMAIN, mk_sym(T, :order), A1) ? FTRUE : FFALSE
            end
        else
            return PL_type_error(ld, "atom", A1) ? FTRUE : FFALSE
        end
    end
    val = compareStandard(ld, p1, p2, false)
    if given                                            # diff is given
        return (smaller ? val < 0 : val > 0) ? FTRUE : FFALSE
    end
    a = if val < 0
        :<
    elseif val > 0
        :>
    else
        :(=)
    end              # unify diff
    return PL_unify_atom(ld, A1, mk_sym(T, a)) ? FTRUE : FFALSE
end

# PORT: pl-prims.c can_compare as pl_can_compare2_va
# (PRED_IMPL("?=", 2, can_compare, 0))
"`?=/2` (pl-prims.c): it can be decided now and forever whether the arguments are equal."
function pl_can_compare2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    fid = PL_open_foreign_frame(ld)
    rc = PL_unify(ld, A1, A2)
    if rc
        fr = ld.fliframes[fliFrameOfFid(ld, fid)]      # FliFrame fr = valTermRef(fid)
        if fr.mark.trailtop != length(ld.trail)         # fr->mark.trailtop != tTop
            rc = false
        end
    elseif ld.exception_term != 0
        PL_close_foreign_frame(ld, fid)                 # keep exception
        return FFALSE
    else
        rc = true                                       # could not unify
    end
    PL_discard_foreign_frame(ld, fid)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-prims.c unifiable
# DIVERGES: the list is BUILT (`mk_expr`) where upstream writes it onto the global stack, and unified
# with `subst` directly (upstream: through `pushWordAsTermRef`, a temporary reference that occupies
# no local-stack position). An occurs-check error from the unification or from the occurs check is
# the pending Prolog error. No attributed variables (`isTrailVal`), no overflow retry.
"""
    unifiable(ld, t1, t2, subst) -> Bool

`unifiable/3` (pl-prims.c) on term references: unify `subst` with the list of `Var = Value` that
would make `t1` and `t2` identical, newest binding first — nothing stays bound.
"""
function unifiable(
    ld::PL_local_data{T}, t1::term_t, t2::term_t, subst::term_t
)::Bool where {T}
    dot, eq, nil = mk_sym(T, Symbol("[|]")), mk_sym(T, :(=)), mk_nil(T)
    try
        if PL_is_variable(ld, t1)
            if PL_compare(ld, t1, t2) == CMP_EQUAL
                return PL_unify_atom(ld, subst, nil)
            end
            unifiable_occurs_check(ld, ld.slots[t1 + 1], ld.slots[t2 + 1]) || return false
            b = mk_expr(T, T[eq, ld.slots[t1 + 1], ld.slots[t2 + 1]])
            return _unify_ptrs_raising(ld, mk_expr(T, T[dot, b, nil]), ld.slots[subst + 1])
        end
        if PL_is_variable(ld, t2)
            unifiable_occurs_check(ld, ld.slots[t2 + 1], ld.slots[t1 + 1]) || return false
            b = mk_expr(T, T[eq, ld.slots[t2 + 1], ld.slots[t1 + 1]])
            return _unify_ptrs_raising(ld, mk_expr(T, T[dot, b, nil]), ld.slots[subst + 1])
        end
        ok, m = unify_all_trail_ptrs(ld, ld.slots[t1 + 1], ld.slots[t2 + 1])
        ok || return false
        if length(ld.trail) > m.trailtop                # tt > mt
            pairs = T[]
            while length(ld.trail) > m.trailtop         # while(--tt >= mt), newest first
                key = pop!(ld.trail)
                push!(pairs, mk_expr(T, T[eq, mk_var(T, key), ld.bindings[key]]))
                delete!(ld.bindings, key)               # setVar(*p)
            end
            list = foldr((x, acc) -> mk_expr(T, T[dot, x, acc]), pairs; init=nil)
            return _unify_ptrs_raising(ld, list, ld.slots[subst + 1])
        end
        return PL_unify_atom(ld, subst, nil)            # DiscardMark(m)
    catch e
        e isa OccursCheckError{T} || rethrow()
        PL_error(ld, ERR_OCCURS_CHECK, e.var, e.term)
        return false
    end
end

# PORT: pl-prims.c unifiable as pl_unifiable3_va
# (PRED_IMPL("unifiable", 3, unifiable, 0))
"`unifiable/3` (pl-prims.c)."
function pl_unifiable3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    return unifiable(ld, A1, A2, A3) ? FTRUE : FFALSE
end

# PORT: pl-prims.c BeginPredDefs as PL_predicates_from_prims
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order (prims:6570-6623);
# `PRED_DEF` ors in `PL_FA_VARARGS`. The others of upstream's table arrive with their ports.
"pl-prims.c's registration table (`BeginPredDefs(prims)`): the ported entries."
const PL_predicates_from_prims = (
    PL_extension("=", 2, pl_unify2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("\\=", 2, pl_not_unify2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension(
        "unify_with_occurs_check", 2, pl_unify_with_occurs_check2_va,
        PL_FA_ISO | PL_FA_VARARGS
    ),
    PL_extension("nonvar", 1, pl_nonvar1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("var", 1, pl_var1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("integer", 1, pl_integer1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("float", 1, pl_float1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("rational", 1, pl_rational1_va, PL_FA_VARARGS),
    PL_extension("number", 1, pl_number1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("atomic", 1, pl_atomic1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("atom", 1, pl_atom1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("string", 1, pl_string1_va, PL_FA_VARARGS),
    PL_extension("compound", 1, pl_compound1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("callable", 1, pl_callable1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("==", 2, pl_equal2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("\\==", 2, pl_nonequal2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("compare", 3, pl_compare3_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("?=", 2, pl_can_compare2_va, PL_FA_VARARGS),
    PL_extension("unifiable", 3, pl_unifiable3_va, PL_FA_VARARGS)
)
