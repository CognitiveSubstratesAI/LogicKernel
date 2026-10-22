# UPSTREAM: swipl-devel src/pl-prims.c @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-incl.h @ 8e1bc1110be4
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
# PORT: pl-incl.h CMPEX_LESS
"`cmpNumbers`' less (pl-incl.h `cmpex_t`)."
const CMPEX_LESS = -1
# PORT: pl-incl.h CMPEX_EQUAL
"`cmpNumbers`' equal (pl-incl.h `cmpex_t`)."
const CMPEX_EQUAL = 0
# PORT: pl-incl.h CMPEX_GREATER
"`cmpNumbers`' greater (pl-incl.h `cmpex_t`)."
const CMPEX_GREATER = 1
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
# `CMP_ERROR` from the argument tests (no memory overflow). The result is returned, a tuple, where
# upstream writes it through `*c1` and `*c2`.
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
        while i < n                             # be tested; child 1, the head, is compared too
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

# PORT: pl-prims.c skip_list
# DIVERGES: the term itself and its tail returned, `(length, tail)`, where upstream writes the tail
# through `tailp`; two cells are the same cell when `===` (upstream compares the cell words).
"Walk the list `l` (Brent's cycle detection): `(cells, tail)`, the tail the first non-list or the cell a cycle returns to (pl-prims.c)."
function skip_list(ld::PL_local_data{T}, l::T)::Tuple{Int, T} where {T}
    l = deRef(ld, l)

    if !is_pair(l)
        return (0, l)
    else
        length = 0
        checkCell = currentCell = l
        lam = 0
        power = 1

        while true
            currentCell = deRef(ld, child(currentCell, 3))      # TailList(currentCell)
            length += 1

            (!is_pair(currentCell) || checkCell === currentCell) && break

            lam += 1
            if power == lam
                checkCell = currentCell
                power *= 2
                lam = 0
            end
        end

        return (length, currentCell)
    end
end

# PORT: pl-prims.c skip_list as skip_list_cells
# DIVERGES: on a LOCATION (L1d step 9); returns the tail dereferenced, `(length, kind, word, pos)` as
# `_deref_loc` gives it (`pos` the location itself for a word in a slot), where upstream writes
# `*tailp`; Brent's cycle check compares the cells' positions, as upstream's pointers.
"The length of the list at location `l` and its dereferenced tail (pl-prims.c `skip_list`)."
function skip_list_cells(
    ld::PL_local_data{T}, l::Int
)::Tuple{Int, UInt8, word, Int} where {T}
    k, w, p = _deref_loc(ld, l)
    p = p > 0 ? p : l
    _is_list_word(ld, k, w) || return (0, k, w, p)
    length = 0
    checkCell = currentCell = p
    lam = 0
    power = 1
    while true
        k, w, currentCell = _deref_loc(ld, valPtr(w) + 2)      # TailList(currentCell); deRef
        length += 1
        (!_is_list_word(ld, k, w) || checkCell == currentCell) && break
        lam += 1
        if power == lam
            checkCell = currentCell
            power *= 2
            lam = 0
        end
    end
    return (length, k, w, currentCell)
end

# ORIGINAL: pl-data.h `isList(w)` on a dereferenced location's `(kind, word)`: a `'[|]'/2` compound.
@inline _is_list_word(ld::PL_local_data, k::UInt8, w::word)::Bool =
    k == DU_WORD && _is_gcompound(w) && ld.gstack[valPtr(w)] == ld.functor_dot2

# PORT: pl-prims.c lengthList
"The length of the list term reference `list` holds; -1 if it is not one, -2 if partial (pl-prims.c)."
function lengthList(ld::PL_local_data{T}, list::term_t, errors::Bool)::Int where {T}
    length, k, w, _ = skip_list_cells(ld, -(list + 1))     # on the cells (L1e e4); the boundary on terms
    if k != DU_TERM
        k == DU_WORD && w == ld.atom_nil_w && return length    # isNil(*tail)
        errors && PL_error(ld, ERR_TYPE, mk_sym(T, :list), list)
        return k == DU_CELL ? -2 : -1                       # isVar(*tail) ? -2 : -1
    end
    ld.cold_pairs += 1
    length, tail = skip_list(ld, slotValue(ld, list + 1))

    is_nil(tail) && return length

    errors && PL_error(ld, ERR_TYPE, mk_sym(T, :list), list)

    return kind(tail) === VAR ? -2 : -1
end

# ── numbervars (pl-prims.c), since R1e's write_canonical ────────────────────────────────────────

# PORT: pl-incl.h av_action
"What `numberVars` does with an attributed variable (pl-incl.h `av_action`)."
@enum av_action::UInt8 begin
    AV_BIND
    AV_SKIP
    AV_ERROR
end

# PORT: pl-incl.h NV_ERROR
"`numberVars`' result when it raised an error (pl-incl.h)."
const NV_ERROR = -1

# PORT: pl-incl.h nv_options
# DIVERGES: the functor is its name (every `'$VAR'/1`); `singletons` and `numbered_check` are
# `Int`s as upstream's (`singletons` takes 0, 1 and 2 in `numberVars`).
"The options of `numberVars` (pl-incl.h `nv_options`)."
mutable struct nv_options{T}
    functor::T                      # Functor to use ($VAR/1): its name
    offset::Int                     # offset
    on_attvar::av_action            # How to handle attvars
    singletons::Int                 # Write singletons as $VAR('_')
    numbered_check::Bool            # Check for already numbered
end

# PORT: pl-prims.c ALREADY_NUMBERED
"`do_number_vars`' code: a `'\$VAR'(N)` with `N` past the start (pl-prims.c)."
const ALREADY_NUMBERED = -10
# PORT: pl-prims.c CONTAINS_ATTVAR
"`do_number_vars`' code: an attributed variable under `AV_ERROR` (pl-prims.c)."
const CONTAINS_ATTVAR = -11
# PORT: pl-prims.c REPRESENTATION_ERROR
"`do_number_vars`' code: a number past the tagged range (pl-prims.c)."
const REPRESENTATION_ERROR = -12

# PORT: pl-prims.c do_number_vars
# DIVERGES: a variable is bound to a NEW `'$VAR'(A)` compound through the trail (`Trail!`; upstream
# builds it on the global stack and `bindConst`s), whose argument `A` is a FRESH VARIABLE bound to
# the number — or, in singletons mode, to `_` — so the compound keeps its identity while its
# argument is rewritten (upstream writes the argument cell in place: `*p = ATOM_var`, `*p =
# consInt(v)`); "new one we created ourselves" — a `'$VAR'` compound above the mark's global top —
# is one in `ld.numbervars_made` (the compounds this walk made, cleared by `numberVars`); `visited`
# is an `IdDict` of the compounds entered (upstream's mark bits). No attributed variables (none in
# the kernel: `AV_*` is kept for `nv_options`); no signals (`NV_EINTR`); no global-stack overflow.
"Number the variables of `p` from `n`: the next number, or a code below 0 (pl-prims.c)."
function do_number_vars(
    ld::PL_local_data{T}, p::T, options::nv_options{T}, n::Int
)::Int where {T}
    agenda = ld.occurs_agenda
    start = n
    visited = ld.numbervars_visited
    made = ld.numbervars_made
    fkey = sym_key(options.functor)
    k_anon = sym_key(mk_sym(T, :_))                 # ATOM_anonvar
    k_var = sym_key(mk_sym(T, :var))                # ATOM_var

    initTermAgenda!(agenda, 0, p, 1)                # (initTermAgenda(&agenda, 1, p))
    first = true
    while true
        if first
            first = false
            q = deRef(ld, p)
        else
            q = nextTermAgenda!(ld, agenda)
            q === nothing && break
        end
        if kind(q) === VAR                          # canBind(*p)
            arg = _cell_var(ld, allocGlobalCells!(ld, 1))     # the argument cell, rewritable
            if options.singletons != 0
                Trail!(ld, var_key(arg), mk_sym(T, :_))             # a[1] = ATOM_anonvar
            else
                v = n + options.offset
                (PLMINTAGGEDINT <= v <= PLMAXTAGGEDINT) || return REPRESENTATION_ERROR
                Trail!(ld, var_key(arg), mk_gnd(T, Int64(v)))       # a[1] = consInt(v)
                n += 1
            end
            a = mk_expr(T, T[options.functor, arg])
            Trail!(ld, var_key(q), a)               # bindConst(p, v)
            # the mark is on the term the engine HANDS BACK for the binding: since L1c a cell
            # variable's binding copies `a` onto the global stack, and reading it exports a
            # term of its own (one level deep, memoized per position) — `a` itself is never
            # seen again; a keyed variable's binding is `a` as stored (upstream: the mark bit
            # on the functor cell it wrote). TRANSITIONAL: numberVars over cells (L1d/L1e).
            made[deRef(ld, q)] = nothing
        elseif kind(q) === EXPR                     # isTerm(*p)
            h = child(q, 1)
            if nchildren(q) == 2 && kind(h) === SYM && sym_key(h) == fkey
                if haskey(made, q)                  # new one we created ourselves
                    if options.singletons != 0
                        cell = child(q, 2)          # Word p = &f->arguments[0] (a variable)
                        cur = deRef(ld, cell)
                        if options.singletons == 1
                            if kind(cur) === SYM && sym_key(cur) == k_anon
                                v = n + options.offset
                                (PLMINTAGGEDINT <= v <= PLMAXTAGGEDINT) ||
                                    return REPRESENTATION_ERROR
                                _set_binding!(ld, var_key(cell), mk_sym(T, :var))   # *p = ATOM_var
                                n += 1
                            end
                        else
                            if kind(cur) === SYM && sym_key(cur) == k_var
                                v = n + options.offset
                                _set_binding!(ld, var_key(cell), mk_gnd(T, Int64(v)))   # *p = consInt(v)
                                n += 1
                            end
                        end
                    end
                else
                    arg = deRef(ld, child(q, 2))
                    if options.numbered_check && isInteger(arg)
                        if isTaggedInt(arg) && int64_value(arg) >= start
                            return ALREADY_NUMBERED
                        end
                    end
                    if kind(arg) === VAR || kind(arg) === EXPR
                        @goto do_number             # number '$VAR'(_)
                    end
                end
                continue
            end

            @label do_number
            if options.singletons == 0
                haskey(visited, q) && continue      # visited(f)
                visited[q] = nothing
            end
            pushWorkAgenda!(agenda, nchildren(q) - 1, q, 2)
        end
    end

    clearTermAgenda!(agenda)                        # out:
    return n                                        # anything else
end

# PORT: pl-prims.c numberVars as numberVars_terms
# TRANSITIONAL (L1d step 7a, until L1f): numberVars on TERMS — the boundary's path (`numberVars` below
# redoes the numbering here when its cell walk meets a slot's side value or a keyed variable).
# DIVERGES: the marks of a walk (`made`, `visited`) are the local data's scratch, cleared here
# (upstream: `initvisited`/`unvisit`, the global-stack mark); the error for `CONTAINS_ATTVAR` is
# kept for the shape (no attributed variables); no signals, no stack growth (`makeMoreStackSpace`).
"Number the variables of term reference `t` from `n` ON TERMS: the next number, or `NV_ERROR` with the error raised (pl-prims.c `numberVars`)."
function numberVars_terms(
    ld::PL_local_data{T}, t::term_t, options::nv_options{T}, n::Int
)::Int where {T}
    if !(PLMINTAGGEDINT <= n <= PLMAXTAGGEDINT)     # inTaggedNumRange(n)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :tagged_integer))
        return NV_ERROR
    end

    options.offset = n

    m = Mark(ld)
    empty!(ld.numbervars_visited)
    empty!(ld.numbervars_made)
    rc = do_number_vars(ld, slotValue(ld, t + 1), options, 0)
    empty!(ld.numbervars_visited)                   # unvisit()
    if rc >= 0                                      # all ok
        DiscardMark(ld, m)
        if options.singletons != 0
            options.singletons = 2
            rc2 = do_number_vars(ld, slotValue(ld, t + 1), options, 0)
            empty!(ld.numbervars_visited)
            @assert rc == rc2
        end
        empty!(ld.numbervars_made)
        return rc + options.offset
    else
        empty!(ld.numbervars_made)
        if rc == CONTAINS_ATTVAR
            DiscardMark(ld, m)
            PL_error(ld, ERR_TYPE, mk_sym(T, :free_of_attvar), t)
            return NV_ERROR
        elseif rc == ALREADY_NUMBERED
            DiscardMark(ld, m)
            PL_error(
                ld, "", 0, "already numbered", ERR_PERMISSION, mk_sym(T, :numbervars),
                mk_sym(T, :term), t
            )
            return NV_ERROR
        else
            @assert rc == REPRESENTATION_ERROR
            DiscardMark(ld, m)
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :tagged_integer))
            return NV_ERROR
        end
    end
end

# ── numbervars on the CELLS (L1d step 7a; the workspace's L1_plan/stageL1d_design.md §3g) ─────────
# Upstream's walk on locations: a variable cell is bound (`bindConst`, trailed) to a `'$VAR'(N)` laid
# out at gTop, its argument a WORD — so the singletons passes rewrite the ones made "ourselves" (above
# the mark's globaltop: upstream's address test) in place, untrailed, as upstream; a visited compound
# is MARKed on its functor cell (`visitedWord_cells`, on `ld.cycle_vstack`), cleared by `unvisit_cells`.
# THE BOUNDARY (a slot's side value, a keyed variable — `DU_TERM` — anywhere in the walk): unvisit,
# Undo to the mark, and the whole numbering redone on terms (`numberVars_terms`), counted in
# `cold_pairs`. TRANSITIONAL until L1f.

# ORIGINAL: `do_number_vars_cells`' code for the boundary (no upstream counterpart: upstream has none).
"`do_number_vars_cells`: the walk met the boundary (a slot's side value, a keyed variable)."
const NV_BOUNDARY = -14

# PORT: pl-prims.c do_number_vars as do_number_vars_cells
# DIVERGES: on locations (`_deref_loc`'s), the one-sided cell agenda (`ld.walk_agenda`); `gtop` is the
# mark's `globaltop` (upstream passes the mark; positions, so "at or above the old top" is `> gtop`);
# `fw` the functor word of `options.functor/1` and `anon`/`var` the atom words of `_` and `var`
# (upstream: `options->functor`, `ATOM_anonvar`, `ATOM_var`). `numbered_check` reads a tagged integer
# (a value-table integer is past the tagged range: upstream's "cannot be bigger"). The boundary
# returns `NV_BOUNDARY`. NOT PORTED: attributed variables (no cell holds one: `on_attvar` is never
# read), NV_EINTR (no signals), the global-stack overflow (`hasGlobalSpace`: the stack grows).
"Number the variables of the term at location `l` from `n` on the cells: the next number, or a code below 0 (pl-prims.c `do_number_vars`)."
function do_number_vars_cells(
    ld::PL_local_data{T}, l::Int, options::nv_options{T}, n::Int, gtop::Int, fw::word,
    anon::word, var::word
)::Int where {T}
    a = ld.walk_agenda
    start = n

    initCellAgenda!(a, 1, l)                                # initTermAgenda(&agenda, 1, p)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)
        if k == DU_CELL                                     # canBind(*p)
            if options.singletons != 0
                arg = anon                                  # a[1] = ATOM_anonvar
            else
                v = n + options.offset
                if !(PLMINTAGGEDINT <= v <= PLMAXTAGGEDINT) # valInt(a[1]) != v
                    n = REPRESENTATION_ERROR
                    break                                   # goto out
                end
                arg = consInt(v)                            # a[1] = consInt(v)
                n += 1
            end
            c = _alloc_compound!(ld, fw, 1)                 # a = gTop; a[0] = functor; gTop += 2
            ld.gstack[c + 1] = arg
            _bind_const!(ld, p, consPtr(c, TAG_COMPOUND | STG_GLOBAL))   # bindConst(p, v)
        elseif k == DU_TERM                                 # the boundary
            n = NV_BOUNDARY
            break
        elseif k == DU_WORD && _is_gcompound(w)             # isTerm(*p)
            c = valPtr(w)
            if ld.gstack[c] == fw                           # f->definition == options->functor
                if c > gtop                                 # new one we created ourselves
                    if options.singletons != 0
                        ap = c + 1                          # Word p = &f->arguments[0]
                        if options.singletons == 1
                            if ld.gstack[ap] == anon
                                v = n + options.offset
                                if !(PLMINTAGGEDINT <= v <= PLMAXTAGGEDINT)
                                    n = REPRESENTATION_ERROR
                                    break
                                end
                                ld.gstack[ap] = var         # *p = ATOM_var
                                n += 1
                            end
                        else
                            if ld.gstack[ap] == var
                                ld.gstack[ap] = consInt(n + options.offset)   # *p = consInt(v)
                                n += 1
                            end
                        end
                    end
                    continue
                else
                    ka, wa, _ = _deref_loc(ld, c + 1)       # deRef(p)
                    if options.numbered_check && ka == DU_VALUE && isTaggedIntW(wa)
                        if valInt(wa) >= start
                            n = ALREADY_NUMBERED
                            break
                        end
                    end
                    if ka == DU_TERM
                        n = NV_BOUNDARY
                        break
                    end
                    (ka == DU_CELL || (ka == DU_WORD && _is_gcompound(wa))) ||
                        continue                            # number '$VAR'(_) only
                end
            end

            # do_number:
            options.singletons == 0 && visitedWord_cells(ld, c) && continue    # visited(f)
            pushWorkCellAgenda!(a, arityFunctor(ld.functors, ld.gstack[c]), c + 1)
        end
    end

    clearCellAgenda!(a)                                     # out:
    return n
end

# PORT: pl-prims.c numberVars
# DIVERGES: on the CELLS (L1d step 7a, `do_number_vars_cells`); the functor word of `options.functor/1`
# looked up here (upstream's caller passes `PL_new_functor(name, 1)`); the boundary — `NV_BOUNDARY` —
# unvisits, undoes to the mark and numbers on terms (`numberVars_terms`), counted in `cold_pairs`.
# The error for `CONTAINS_ATTVAR` is kept for the shape (no attributed variables); no signals
# (`NV_EINTR`), no stack growth (`makeMoreStackSpace`: the stack grows on demand).
"Number the variables of term reference `t` from `n`: the next number, or `NV_ERROR` with the error raised (pl-prims.c)."
function numberVars(
    ld::PL_local_data{T}, t::term_t, options::nv_options{T}, n::Int
)::Int where {T}
    if !(PLMINTAGGEDINT <= n <= PLMAXTAGGEDINT)     # inTaggedNumRange(n)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :tagged_integer))
        return NV_ERROR
    end

    options.offset = n
    fw = lookupFunctorDef(ld.functors, _atom_word!(ld, options.functor), 1)
    anon = _atom_word!(ld, mk_sym(T, :_))           # ATOM_anonvar
    var = _atom_word!(ld, mk_sym(T, :var))          # ATOM_var

    m = Mark(ld)
    # initvisited(): `ld.cycle_vstack` is empty between walks
    rc = do_number_vars_cells(ld, -(t + 1), options, 0, m.globaltop, fw, anon, var)
    unvisit_cells(ld)                               # unvisit()
    if rc == NV_BOUNDARY
        Undo!(ld, m)
        DiscardMark(ld, m)
        ld.cold_pairs += 1
        return numberVars_terms(ld, t, options, n)
    end
    if rc >= 0                                      # all ok
        DiscardMark(ld, m)
        if options.singletons != 0
            options.singletons = 2
            rc2 = do_number_vars_cells(ld, -(t + 1), options, 0, m.globaltop, fw, anon, var)
            unvisit_cells(ld)
            @assert rc == rc2
        end
        return rc + options.offset
    else
        if rc == CONTAINS_ATTVAR
            DiscardMark(ld, m)
            PL_error(ld, ERR_TYPE, mk_sym(T, :free_of_attvar), t)
            return NV_ERROR
        elseif rc == ALREADY_NUMBERED
            DiscardMark(ld, m)
            PL_error(
                ld, "", 0, "already numbered", ERR_PERMISSION, mk_sym(T, :numbervars),
                mk_sym(T, :term), t
            )
            return NV_ERROR
        else
            @assert rc == REPRESENTATION_ERROR
            DiscardMark(ld, m)
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :tagged_integer))
            return NV_ERROR
        end
    end
end

# PORT: pl-prims.c numbervar_options
"The options of numbervars/4 (pl-prims.c `numbervar_options`)."
const numbervar_options = (
    PL_option_t(:attvar, OPT_ATOM),
    PL_option_t(:functor_name, OPT_ATOM),
    PL_option_t(:singletons, OPT_BOOL)
)

# PORT: pl-prims.c numbervars as pl_numbervars4_va
# DIVERGES: the options' values are returned by `PL_scan_options` (see there), the defaults applied
# to `nothing`; the functor is its name (`nv_options`); `PL_is_acyclic` on the cells (L1d step 3).
# numbervars/4 only: numbervars(+Term, +Functor, +Start, -End) — the comment's older form — is not
# this predicate's (upstream's A2 is always Start).
"numbervars(+Term, +Start, -End, +Options): number Term's variables from Start, End the next number (pl-prims.c)."
function pl_numbervars4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    name = mk_sym(T, Symbol("\$VAR"))             # ATOM_isovar
    av = mk_sym(T, :error)                          # ATOM_error
    singletons = false

    t = PL_copy_term_ref(ld, A1)

    n = PL_get_intptr_ex(ld, A2)
    n === nothing && return FFALSE
    endt = A3
    options = A4

    vals = PL_scan_options(ld, options, 0, "numbervar_option", numbervar_options)
    vals === nothing && return FFALSE
    vals[1] === nothing || (av = vals[1]::T)
    vals[2] === nothing || (name = vals[2]::T)
    vals[3] === nothing || (singletons = vals[3]::Bool)

    on_attvar = if sym_key(av) == sym_key(mk_sym(T, :error))
        AV_ERROR
    elseif sym_key(av) == sym_key(mk_sym(T, :skip))
        AV_SKIP
    elseif sym_key(av) == sym_key(mk_sym(T, :bind))
        AV_BIND
    else
        return if PL_error(ld, ERR_DOMAIN, mk_sym(T, :numbervar_option), options)
            FTRUE
        else
            FFALSE
        end
    end

    if singletons                                   # Hack
        is_acyclic_cells(ld, -(A1 + 1)) || (singletons = false)
    end

    opts = nv_options{T}(name, 0, on_attvar, singletons ? 1 : 0, false)  # numbered_check = false
    n = numberVars(ld, t, opts, n)
    n != NV_ERROR && return PL_unify_int64(ld, endt, n) ? FTRUE : FFALSE

    return FFALSE
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
# DIVERGES: no `flags` and no overflow retry — stacks cannot overflow; `true` or `false`. An
# occurs-check error is raised, as upstream's: `false`, with the error pending.
"Unify `t1` and `t2` (pl-prims.c `unify_ptrs`): `true` or `false`; does not undo on failure."
unify_ptrs(ld::PL_local_data{T}, t1::T, t2::T) where {T} =
    raw_unify_ptrs(ld, t1, t2) == BOOLEX_TRUE

# PORT: pl-prims.c can_unify
# DIVERGES: no foreign frame and no wakeup of delayed goals (no attributed variables): a mark, and
# an undo whatever happens. An occurs-check error stays pending (`ld.exception_term`), where
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

# ── unification on the CELLS (L1c sub-commit 4: the hot half of L1d) ─────────────────────────────
# Upstream's `Word` pointer is a LOCATION here: a global position (`loc > 0`), or a local-stack slot
# (`loc = -i` for slot `i`; term reference `t` is slot `t + 1`). A slot is never an unbound variable
# — it holds a reference to a cell, an atom or compound word, or its side value — so dereferencing
# ends in a global cell or a value, and only GLOBAL cells are ever bound: upstream's local stack lies
# above its global stack and a variable binds the younger to the older, so a local cell points at a
# global one and never the reverse (user, 2026-10-15; test_unify_cells.jl pins it). What has no word
# form yet is the BOUNDARY — a slot's side value (`SLOT_VALUE`: the exception's ball, a value with
# no word), a value-table entry that is a KEYED variable (gone with the stamp, L1f) — and a pair
# with such a side is unified on TERMS (`do_unify`), each side converted: a cell its variable, an
# atom its symbol, a compound its cold export (COUNTED in `cold_exports`), so the stamp machinery
# stays in `_var_ref_word`/`_cell_pos` until L1f. The term-level `do_unify` stays for the cold
# callers (built-ins, the FLI) until L1e; `unify_with_occurs_check` stays on terms (its own L1d step).
"`_deref_loc`: an unbound cell, at the position returned."
const DU_CELL = 0x01
"`_deref_loc`: an atom or a compound word, returned."
const DU_WORD = 0x02
"`_deref_loc`: a VALUE word (returned): a value-table word whose entry is a value, in the cell at the position, or a tagged integer (L1d step 4; in a slot, position 0)."
const DU_VALUE = 0x03
"`_deref_loc`: the boundary — a slot's side value (the position is `-slot`), or a keyed variable's value-table word."
const DU_TERM = 0x04

# ORIGINAL: upstream's `deRef` (pl-data.h) on a LOCATION (above); the result says what was found,
# as the word tests on `*p` do after upstream's `deRef`.
"Location `loc` dereferenced: `(kind, word, position)`, see `DU_*` (pl-data.h `deRef`)."
@inline function _deref_loc(
    ld::PL_local_data{T}, loc::Int
)::Tuple{UInt8, word, Int} where {T}
    if loc < 0
        w = ld.slots[-loc]
        if !isRef(w)
            w == SLOT_VALUE && return (DU_TERM, word(0), loc)
            (isAtomW(w) || _is_gcompound(w)) && return (DU_WORD, w, 0)
            isTaggedIntW(w) && return (DU_VALUE, w, 0)                  # L1d step 4
            if _is_vword(w)                                             # L1e e1: a value-table word
                kind(ld.vtable[valPtr(w)]) === VAR && return (DU_TERM, w, 0)   # (a keyed variable)
                return (DU_VALUE, w, 0)
            end
            throw(_slot_word_error(w))
        end
        p = unRef(w)
    else
        p = loc
    end
    while true
        c = ld.gstack[p]
        isVar(c) && return (DU_CELL, word(0), p)
        if isRef(c)
            p = unRef(c)
        elseif isAtomW(c) || _is_gcompound(c)
            return (DU_WORD, c, p)
        elseif isTaggedIntW(c)                      # a small integer (L1d step 4)
            return (DU_VALUE, c, p)
        else                                        # a value-table word
            kind(ld.vtable[valPtr(c)]) === VAR && return (DU_TERM, c, p)
            return (DU_VALUE, c, p)
        end
    end
end

# ORIGINAL (L1c-6): `deRef2(p, k); canBind(*k)` for slot `i` on the WORDS — an unbound cell is a
# variable, any other word is not; only the BOUNDARY (a slot's side value, a keyed variable's
# value-table word) is decided on its term, `@noinline` so the hot test carries no term path.
"Whether slot `i`, dereferenced, is an unbound variable (pl-vmi.c I_VAR's test, on the words)."
@inline function _slot_is_var(ld::PL_local_data{T}, i::Int)::Bool where {T}
    k, w, p = _deref_loc(ld, -i)
    k == DU_CELL && return true
    k == DU_TERM || return false
    return _boundary_is_var(ld, w, p)
end

# ORIGINAL (L1c-6): the boundary's `canBind` — a slot's side value or a keyed variable's entry, as a
# term (TRANSITIONAL: the stamp falls at L1f, and with it the keyed variables).
"Whether the boundary location (`DU_TERM`: word `w`, position `p`) holds an unbound variable."
@noinline function _boundary_is_var(ld::PL_local_data{T}, w::word, p::Int)::Bool where {T}
    t = p < 0 ? ld.slot_values[-p] : ld.vtable[valPtr(w)]
    return canBind(deRef(ld, t))
end

# ORIGINAL: the boundary's conversion (above): what a dereferenced location holds, as a TERM.
"The term at a dereferenced location (a compound through the counted cold export)."
function _loc_term(ld::PL_local_data{T}, k::UInt8, w::word, p::Int)::T where {T}
    k == DU_CELL && return _cell_var(ld, p)
    if k == DU_TERM
        p < 0 && return ld.slot_values[-p]
        return ld.vtable[valPtr(w)]
    end
    k == DU_VALUE && return _value_term(ld, w)
    isAtomW(w) && return _atom_value(ld, w)
    return _compound_term(ld, valPtr(w))
end

# ORIGINAL: `ARGP` as a location for `do_unify_cells`: a slot or a global cell; 0 for a read-mode
# cursor into a TERM (the term path).
"The location `ARGP` points at, or 0 when it points into a term."
@inline _argp_loc(a::argp_t)::Int =
    a.form == ARGP_SLOT ? -(a.pos + 1) : (a.form == ARGP_GLOBAL ? a.pos : 0)

# PORT: pl-prims.c unify_simple_ptrs as unify_simple_cells
# DIVERGES: on dereferenced locations. Two unbound cells: the HIGHER position is bound to the
# lower's reference (upstream: by address, "always point downwards"; no variable lives on the local
# stack, so no fresh global variable for two local ones). A value-table word is upstream's indirect:
# shared by binding, two compared by the term type's `gnd_equal` (`equalIndirect`: SWI's identity in
# the reference type, `1 = 1.0` fails). The boundary (`DU_TERM` on either side) is unified on terms.
# No attributed variables.
"Unify two dereferenced locations when neither is a compound; `DO_COMPOUND` when both are (pl-prims.c)."
function unify_simple_cells(
    ld::PL_local_data{T}, k1::UInt8, w1::word, p1::Int, k2::UInt8, w2::word, p2::Int
)::boolex_t where {T}
    if k1 == DU_TERM || k2 == DU_TERM                # the boundary: on terms
        return do_unify(ld, _loc_term(ld, k1, w1, p1), _loc_term(ld, k2, w2, p2))
    end
    if k1 == DU_CELL
        if k2 == DU_CELL
            p1 == p2 && return BOOLEX_TRUE          # t1 == t2
            if p1 > p2                              # SWAPW(t1, t2)
                p1, p2 = p2, p1
            end
            _bind_const!(ld, p2, makeRefG(p1))      # Trail(t2, makeRefG(t1)): always point downwards
            return BOOLEX_TRUE
        end
        _bind_const!(ld, p1, w2)                    # Trail(t1, w2)
        return BOOLEX_TRUE
    end
    if k2 == DU_CELL
        _bind_const!(ld, p2, w1)                    # Trail(t2, w1)
        return BOOLEX_TRUE
    end
    w1 == w2 && return BOOLEX_TRUE
    k1 == k2 || return BOOLEX_FALSE                 # tagex(w1) != tagex(w2)
    if k1 == DU_VALUE
        # two small integers that are not the same word are two values (L1d step 4: upstream's
        # `tagex(w1) != tagex(w2)` for a tagged pair with `w1 != w2`); else equalIndirect, by the
        # term type's `gnd_equal` (a tagged integer against an indirect number: its term)
        (isTaggedIntW(w1) && isTaggedIntW(w2)) && return BOOLEX_FALSE
        return if gnd_equal(_value_term(ld, w1), _value_term(ld, w2))
            BOOLEX_TRUE
        else
            BOOLEX_FALSE
        end
    end
    (_is_gcompound(w1) && _is_gcompound(w2)) && return DO_COMPOUND   # tag(w1) == TAG_COMPOUND
    return BOOLEX_FALSE                             # two atoms, or an atom and a compound
end

# PORT: pl-prims.c linkTermsCyclic as _link_cells!
# DIVERGES: the functor word is SAVED beside the position: Q2's `$expr/n` unifies with `f/k`
# (different functor words), so `exitCyclic`'s `*p = *unRef(*p)` would give it the other's.
"Link compound `p1` to compound `p2` for the cycle check: its functor cell a reference (pl-prims.c)."
function _link_cells!(ld::PL_local_data, p1::Int, p2::Int)::Nothing
    push!(ld.cycle_cells, p1)                       # pushSegStack(&LD->cycle.lstack, p1, Word)
    push!(ld.cycle_saved, ld.gstack[p1])
    ld.gstack[p1] = makeRefG(p2)                    # *p1 = makeRefG(p2)
    return nothing
end

# PORT: pl-prims.c exitCyclic as _exit_cycles!
"Restore every linked functor cell, the last link first (pl-prims.c)."
function _exit_cycles!(ld::PL_local_data)::Nothing
    while !isempty(ld.cycle_cells)
        ld.gstack[pop!(ld.cycle_cells)] = pop!(ld.cycle_saved)   # *p = *unRef(*p)
    end
    return nothing
end

"Compound `p` with its cycle links followed (`do_unify`: `while ( isRef(f1->definition) ) f1 = unRef(…)`)."
@inline function _cycle_root(ld::PL_local_data, p::Int)::Int
    while true
        c = ld.gstack[p]
        isRef(c) || return p
        p = unRef(c)
    end
end

# DIVERGES: upstream's `f1->definition != f2->definition` on the functor WORDS, plus Q2 (user,
# 2026-10-04): `$expr/n` (a compound whose head is not a symbol; src/pl-ressymbol.jl) unifies with
# ANY compound of n children, child by child, heads included — against `f/k` (k + 1 == n) the head
# pair is the first argument cell against `f`'s atom word, decided at once, then the k argument
# pairs; against another `$expr/n` every argument pair.
"""
The functor test of `do_unify_cells`: push the argument pairs of the compounds at `p1` and `p2`
(Q2's head pair unified at once); false when they cannot unify.
"""
function _push_compound_pair!(
    ld::PL_local_data{T}, a::cell_agendaLR, p1::Int, p2::Int
)::Bool where {T}
    f1 = ld.gstack[p1]
    f2 = ld.gstack[p2]
    if f1 == f2                                     # f1->definition == f2->definition
        n = arityFunctor(ld.functors, f1)
        n == 0 && return true
        return pushWorkCellAgendaLR!(a, n, p1, p2, 1)
    end
    n1 = arityFunctor(ld.functors, f1)
    n2 = arityFunctor(ld.functors, f2)
    e1 = nameFunctor(ld.functors, f1) == ld.atom_dexpr
    e2 = nameFunctor(ld.functors, f2) == ld.atom_dexpr
    if e1 && !e2                                    # (X a…) = f(…): X = f, then the arguments
        n1 == n2 + 1 || return false
        k, w, p = _deref_loc(ld, p1 + 1)
        unify_simple_cells(ld, k, w, p, DU_WORD, nameFunctor(ld.functors, f2), 0) ==
        BOOLEX_TRUE || return false
        n2 == 0 && return true
        return pushWorkCellAgendaLR!(a, n2, p1 + 1, p2, 1)
    elseif e2 && !e1
        n2 == n1 + 1 || return false
        k, w, p = _deref_loc(ld, p2 + 1)
        unify_simple_cells(ld, DU_WORD, nameFunctor(ld.functors, f1), 0, k, w, p) ==
        BOOLEX_TRUE || return false
        n1 == 0 && return true
        return pushWorkCellAgendaLR!(a, n1, p1, p2 + 1, 1)
    end
    return false                                    # two `$expr` of different arity, or f/n ≠ g/m
end

# PORT: pl-prims.c do_unify as do_unify_cells
# DIVERGES: on locations (above); the agenda holds pairs of global positions (`cell_agendaLR`); a
# cycle link overwrites the compound's functor cell with a reference to the other's, as upstream's,
# the word saved beside it (`_link_cells!`, Q2). Both compounds are linked on EVERY pair, as
# upstream links every pair (the term-level `do_unify` links only pairs reached through a binding —
# its DIVERGES; on cells a link is one word write).
"""
    do_unify_cells(ld, l1, l2) -> boolex_t

Unify the terms at locations `l1` and `l2` (pl-prims.c `do_unify`): bind cells, trailed below the
mark bar; walk compounds argument by argument with the cell agenda; link compound pairs so that
rational trees terminate. Does NOT undo on failure.
"""
function do_unify_cells(ld::PL_local_data{T}, l1::Int, l2::Int)::boolex_t where {T}
    k1, w1, p1 = _deref_loc(ld, l1)                 # deRef(t1)
    k2, w2, p2 = _deref_loc(ld, l2)                 # deRef(t2)
    rc = unify_simple_cells(ld, k1, w1, p1, k2, w2, p2)
    rc != DO_COMPOUND && return rc
    rc = BOOLEX_TRUE

    f1 = valPtr(w1)                                 # Functor f1 = valueTerm(*t1)
    f2 = valPtr(w2)
    agenda = ld.ucell_agenda
    initCellAgendaLR!(agenda, 0, 0, 0, 1)
    @assert isempty(ld.cycle_cells)                 # initCyclic()
    if !_push_compound_pair!(ld, agenda, f1, f2)    # f1->definition != f2->definition
        clearCellAgendaLR!(agenda)
        _exit_cycles!(ld)
        return BOOLEX_FALSE
    end
    _link_cells!(ld, f1, f2)                        # linkTermsCyclic(f1, f2)

    while true
        found, a1, a2 = nextCellAgendaLR!(agenda)
        found || break
        k1, w1, p1 = _deref_loc(ld, a1)
        k2, w2, p2 = _deref_loc(ld, a2)
        rc = unify_simple_cells(ld, k1, w1, p1, k2, w2, p2)
        rc == BOOLEX_TRUE && continue
        rc == BOOLEX_FALSE && break                 # (no overflow codes to break on)
        rc = BOOLEX_TRUE

        f1 = _cycle_root(ld, valPtr(w1))            # O_CYCLIC: the links followed
        f2 = _cycle_root(ld, valPtr(w2))
        f1 == f2 && continue

        if !_push_compound_pair!(ld, agenda, f1, f2)
            rc = BOOLEX_FALSE
            break
        end
        _link_cells!(ld, f1, f2)
    end

    clearCellAgendaLR!(agenda)
    _exit_cycles!(ld)
    return rc
end

# PORT: pl-prims.c raw_unify_ptrs as raw_unify_cells
"Unify two locations under the local data's `occurs_check` flag (pl-prims.c)."
function raw_unify_cells(ld::PL_local_data{T}, l1::Int, l2::Int)::boolex_t where {T}
    flag = ld.prolog_flag_occurs_check
    flag == OCCURS_CHECK_FALSE && return do_unify_cells(ld, l1, l2)
    return unify_with_occurs_check_cells(ld, l1, l2, flag)   # on the cells since L1d step 2
end

# PORT: pl-prims.c unify_ptrs as unify_ptrs_cells
# DIVERGES: as `unify_ptrs`: no `flags`, no overflow retry.
"Unify two locations (pl-prims.c `unify_ptrs`): `true` or `false`; does not undo on failure."
unify_ptrs_cells(ld::PL_local_data{T}, l1::Int, l2::Int) where {T} =
    raw_unify_cells(ld, l1, l2) == BOOLEX_TRUE

# ── is_acyclic on CELLS (L1d step 3; the workspace's L1_plan/stageL1d_design.md) ─────────────────
# THE BITS (user, 2026-10-16: name them): a word is tag (bits 0-2, TAG_MASK) | storage (bits 3-4,
# STG_MASK) | MARK_MASK (bit 5) | FIRST_MASK (bit 6) | payload from bit LMASK_BITS = 7. A functor word
# keeps its arity at bits 7-11 (F_ARITY_BITS) and its index above; a cycle link (`_link_cells!`) is a
# reference word, its position also from bit 7. So ACYCLIC_TEMP_MASK = FIRST_MASK (bit 6) and
# ACYCLIC_PERM_MASK = MARK_MASK (bit 5) are free in every word: `arityFunctor`/`indexFunctor` shift
# past them, `isFunctor`/`tagex` read bits 0-4, `isRef`/`tag` bits 0-2. THE ORDER (upstream: do_compare
# exits its links before compare_std calls is_acyclic): no cycle link may be in place while the marks
# are — a linked functor cell holds a reference, not its functor; asserted at the entry.
"ACYCLIC_TEMP_MASK (pl-prims.c): a functor cell whose term chain is being walked (= FIRST_MASK)."
const ACYCLIC_TEMP_MASK = FIRST_MASK
"ACYCLIC_PERM_MASK (pl-prims.c): a functor cell known to start no cycle (= MARK_MASK)."
const ACYCLIC_PERM_MASK = MARK_MASK
"`ph_acyclic_mark_cells`: the walk met the boundary (a term): decide on terms."
const ACYCLIC_BOUNDARY = 2

# PORT: pl-prims.c ph_acyclic_mark as ph_acyclic_mark_cells
# DIVERGES: positions for upstream's `Functor`s — a chain's `head` and `tail` are the compounds'
# positions, `p` the location of the argument to resume (0: NULL); the chains' segstack is
# `ld.acyclic_chains`, reused. A compound of no arguments ends a chain (upstream reads its
# `arguments - 1`). An argument at the BOUNDARY (a keyed variable's binding) stops the walk with
# `ACYCLIC_BOUNDARY` — the caller decides on terms. No MEMORY_OVERFLOW.
"""
    ph_acyclic_mark_cells(ld, top) -> Int

Whether the compound at global position `top` is acyclic (pl-prims.c `ph_acyclic_mark`): `1` yes,
`0` no, `ACYCLIC_BOUNDARY` met a term. Leaves marks on the functor cells for `ph_acyclic_unmark_cells`.
"""
function ph_acyclic_mark_cells(ld::PL_local_data{T}, top::Int)::Int where {T}
    stack = ld.acyclic_chains                               # agenda.stack
    empty!(stack)
    work = (top, top, 0)                                    # agenda.work: (head, tail, p)
    head = top
    tail = top
    pv = 0
    while true
        f = ld.gstack[tail]
        if (f & ACYCLIC_TEMP_MASK) != 0                     # is_acyclic_temp(&tail->definition)
            if (f & ACYCLIC_PERM_MASK) == 0
                empty!(stack)
                return 0
            end
            @goto end_of_chain
        end
        ld.gstack[tail] = f | ACYCLIC_TEMP_MASK             # set_acyclic_temp
        arity = arityFunctor(ld.functors, f)
        if arity > 1
            new_workspace = false
            iter = tail                                     # iter = tail: `tail` moves on below, `iter` not
            for i in arity:-1:2
                k, w, _ = _deref_loc(ld, iter + i - 1)      # p = iter->arguments + i - 2; deRef(p)
                k == DU_TERM && return ACYCLIC_BOUNDARY
                if k == DU_WORD && _is_gcompound(w)         # isTerm(*p)
                    push!(stack, work)
                    if !new_workspace
                        work = (head, tail, iter + arity)   # agenda.work.p = iter->arguments + arity-1
                        head = tail = valPtr(w)
                        new_workspace = true
                    else
                        work = (valPtr(w), valPtr(w), 0)
                    end
                end
            end
            new_workspace && continue
        end
        arity == 0 && @goto end_of_chain
        pv = tail + arity                                   # p = tail->arguments + arity-1
        @label process_p
        k, w, _ = _deref_loc(ld, pv)
        k == DU_TERM && return ACYCLIC_BOUNDARY
        if k == DU_WORD && _is_gcompound(w)
            tail = valPtr(w)
            continue
        end
        @label end_of_chain
        head == top && return 1
        iter = head
        while iter != tail                                  # set_acyclic_perm along the chain
            g = ld.gstack[iter]
            ld.gstack[iter] = g | ACYCLIC_PERM_MASK
            _, wi, _ = _deref_loc(ld, iter + arityFunctor(ld.functors, g))
            iter = valPtr(wi)
        end
        ld.gstack[tail] |= ACYCLIC_PERM_MASK
        head, tail, p = work
        @assert !isempty(stack) "ph_acyclic_mark_cells: the agenda ran out"
        work = pop!(stack)
        if p != 0
            pv = p
            @goto process_p
        end
    end
end

# PORT: pl-prims.c ph_acyclic_unmark as ph_acyclic_unmark_cells
# DIVERGES: the cell agenda on one side (`acell_agenda`), from the compound at `top`.
"Clear both acyclic marks from every marked compound reachable from `top` (pl-prims.c)."
function ph_acyclic_unmark_cells(ld::PL_local_data{T}, top::Int)::Nothing where {T}
    f = ld.gstack[top]
    (f & ACYCLIC_TEMP_MASK) == 0 && return nothing
    ld.gstack[top] = f & ~(ACYCLIC_TEMP_MASK | ACYCLIC_PERM_MASK)      # clear_acyclic_both
    a = ld.acell_agenda
    initCellAgendaLR!(a, arityFunctor(ld.functors, f), top, top, 1)
    while true
        found, l, _ = nextCellAgendaLR!(a)
        found || break
        k, w, _ = _deref_loc(ld, l)
        (k == DU_WORD && _is_gcompound(w)) || continue
        q = valPtr(w)
        g = ld.gstack[q]
        (g & ACYCLIC_TEMP_MASK) == 0 && continue
        ld.gstack[q] = g & ~(ACYCLIC_TEMP_MASK | ACYCLIC_PERM_MASK)
        pushWorkCellAgendaLR!(a, arityFunctor(ld.functors, g), q, q, 1)
    end
    clearCellAgendaLR!(a)
    return nothing
end

# PORT: pl-prims.c is_acyclic as is_acyclic_cells
# DIVERGES: on a location; the boundary (a slot's side value, a keyed variable's binding, met at the
# top or inside the walk) is decided by the term-level `is_acyclic` on the export, counted in
# `cold_pairs`. No MEMORY_OVERFLOW.
"Whether the term at location `l` is acyclic (pl-prims.c `is_acyclic`)."
function is_acyclic_cells(ld::PL_local_data{T}, l::Int)::Bool where {T}
    k, w, p = _deref_loc(ld, l)
    if k == DU_TERM
        ld.cold_pairs += 1
        return is_acyclic(ld, _loc_term(ld, k, w, p))
    end
    (k == DU_WORD && _is_gcompound(w)) || return true
    @assert isempty(ld.cycle_cells) "is_acyclic_cells: a cycle link is in place (exitCyclic first)"
    q = valPtr(w)
    rc = ph_acyclic_mark_cells(ld, q)
    ph_acyclic_unmark_cells(ld, q)
    if rc == ACYCLIC_BOUNDARY
        ld.cold_pairs += 1
        return is_acyclic(ld, _loc_term(ld, k, w, p))
    end
    return rc == 1
end

# ── the standard order on CELLS (L1d step 1; the workspace's L1_plan/stageL1d_design.md §3) ──────
# Locations as `do_unify_cells`'s (a global position, or `-i` for slot `i`). The order is the term
# compare's, so a sort or a `==` gives the same answer on either path: variables by KEY (`gkey`;
# upstream by address — a key's stamp and position follow allocation as an address does), atomic
# values by the term type's ladder (`compare_primitives` on the stored value or the atom's symbol —
# no export), compounds by arity, then `$expr/n` before symbol functors (Q2), then name, then the
# arguments left to right. The BOUNDARY (a slot's side value, a keyed variable) compares as terms.
"`compare_primitives_cells`: the pair is decided on TERMS (the boundary)."
const CMP_TERMS = -5

"The tag rank of a dereferenced location: unbound cell 0, atomic 1, compound 2 (`_tag_rank`)."
@inline _loc_rank(k::UInt8, w::word)::Int =
    k == DU_CELL ? 0 : ((k == DU_WORD && _is_gcompound(w)) ? 2 : 1)

"The atomic TERM a dereferenced atomic location holds (an atom's symbol, a stored value): no export."
@inline function _loc_atomic(ld::PL_local_data{T}, k::UInt8, w::word)::T where {T}
    # (the long form: `@inline f(…)::T where {T} = …` left `::T` at top level — did not load, 2026-10-16)
    return k == DU_VALUE ? _value_term(ld, w) : _atom_value(ld, w)   # a tagged word too (L1d-4)
end

# PORT: pl-prims.c compare_primitives as compare_primitives_cells
# DIVERGES: (1) two unbound cells are ordered by POSITION, upstream's address order
# (`SCALAR_TO_CMP(p1, p2)`; F3B f3b-2 — by `gkey` before). The same order as the keys the term
# compare reads (`var_key`): a live cell's key is its allocation's stamp, then its position, and
# allocation is LIFO at `gTop + 1`, so of two live cells the higher one is the younger (pl-alloc.jl
# `allocGlobalCells!`, the only `gkey` writer). (2) On two dereferenced locations; no
# CMP_MODE_PARTIAL (not ported); `CMP_TERMS` at the boundary.
"One step of the cell walk (pl-prims.c `compare_primitives`): decided, `CMP_COMPOUND`, or `CMP_TERMS`."
function compare_primitives_cells(
    ld::PL_local_data{T}, k1::UInt8, w1::word, p1::Int, k2::UInt8, w2::word, p2::Int,
    mode::Int
)::Int where {T}
    (k1 == DU_TERM || k2 == DU_TERM) && return CMP_TERMS
    if k1 == DU_CELL && k2 == DU_CELL
        p1 == p2 && return CMP_EQUAL                         # w1 == w2: the same cell
        mode == CMP_MODE_EQUAL && return CMP_NOTEQ
        return p1 < p2 ? CMP_LESS : CMP_GREATER              # SCALAR_TO_CMP(p1, p2)
    end
    k1 != DU_CELL && k1 == k2 && w1 == w2 && return CMP_EQUAL   # the same word
    r1, r2 = _loc_rank(k1, w1), _loc_rank(k2, w2)
    if r1 != r2
        mode == CMP_MODE_EQUAL && return CMP_NOTEQ
        return r1 < r2 ? CMP_LESS : CMP_GREATER
    end
    r1 == 2 && return CMP_COMPOUND
    if isTaggedIntW(w1) && isTaggedIntW(w2)          # two small integers (L1d step 4): by value, as
        mode == CMP_MODE_EQUAL && return CMP_NOTEQ   # compare_primitives' TAG_INTEGER/STG_INLINE
        return valInt(w1) < valInt(w2) ? CMP_LESS : CMP_GREATER     # branch (w1 != w2 here)
    end
    return compare_primitives(_loc_atomic(ld, k1, w1), _loc_atomic(ld, k2, w2), mode)
end

# PORT: pl-prims.c compare_functors as compare_functors_cells
# DIVERGES: on the functor WORDS of the compounds at `q1`, `q2`: arity first, then `$expr/n` before a
# symbol functor (Q2, as `compare_functors` on terms), then the names' symbols by `compare_primitives`
# (the atom ladder: `compareAtoms`). `CMP_EQUAL`: the same functor — the arguments decide.
"Two compounds on the stack by functor (pl-prims.c `compare_functors`)."
function compare_functors_cells(
    ld::PL_local_data{T}, q1::Int, q2::Int, mode::Int
)::Int where {T}
    f1, f2 = ld.gstack[q1], ld.gstack[q2]
    f1 == f2 && return CMP_EQUAL
    mode == CMP_MODE_EQUAL && return CMP_NOTEQ
    a1, a2 = arityFunctor(ld.functors, f1), arityFunctor(ld.functors, f2)
    a1 == a2 || return a1 < a2 ? CMP_LESS : CMP_GREATER
    n1, n2 = nameFunctor(ld.functors, f1), nameFunctor(ld.functors, f2)
    e1, e2 = n1 == ld.atom_dexpr, n2 == ld.atom_dexpr
    e1 != e2 && return e1 ? CMP_LESS : CMP_GREATER       # `$expr/n` first
    return compare_primitives(_atom_value(ld, n1), _atom_value(ld, n2), CMP_MODE_ORDER)
end

# PORT: pl-prims.c do_compare as do_compare_cells
# DIVERGES: the cell agenda on positions; EVERY compound pair linked (`_link_cells!`, the functor
# word saved and restored by `_exit_cycles!`), as upstream — the term version links only pairs reached
# through a binding; returns `(rc, linked)`; a pair at the boundary is compared as terms.
"""
    do_compare_cells(ld, q1, q2, mode) -> (Int, Bool)

Compare the arguments of two compounds on the stack with one functor (pl-prims.c `do_compare`),
linking compound pairs so that rational trees terminate; `linked` when a link was followed.
"""
function do_compare_cells(
    ld::PL_local_data{T}, q1::Int, q2::Int, mode::Int
)::Tuple{Int, Bool} where {T}
    linked = false
    agenda = ld.ccell_agenda
    initCellAgendaLR!(agenda, arityFunctor(ld.functors, ld.gstack[q1]), q1, q2, 1)   # goto compound
    _link_cells!(ld, q1, q2)
    rc = CMP_EQUAL
    while true
        found, a1, a2 = nextCellAgendaLR!(agenda)
        found || break
        k1, w1, p1 = _deref_loc(ld, a1)
        k2, w2, p2 = _deref_loc(ld, a2)
        rc = compare_primitives_cells(ld, k1, w1, p1, k2, w2, p2, mode)
        if rc == CMP_TERMS                               # the boundary: this pair as terms
            ld.cold_pairs += 1                           # (counted: the zero-export test)
            rc = compare_std(ld, _loc_term(ld, k1, w1, p1), _loc_term(ld, k2, w2, p2), mode)
        end
        if rc != CMP_COMPOUND
            rc == CMP_EQUAL && continue
            break
        end
        c1, c2 = valPtr(w1), valPtr(w2)
        if isRef(ld.gstack[c1]) || isRef(ld.gstack[c2])   # O_CYCLIC
            linked = true
            c1, c2 = _cycle_root(ld, c1), _cycle_root(ld, c2)
            if c1 == c2
                rc = CMP_EQUAL
                continue
            end
        end
        rc = compare_functors_cells(ld, c1, c2, mode)
        rc == CMP_EQUAL || break
        pushWorkCellAgendaLR!(agenda, arityFunctor(ld.functors, ld.gstack[c1]), c1, c2, 1)
        _link_cells!(ld, c1, c2)
    end
    clearCellAgendaLR!(agenda)
    return (rc, linked)
end

# PORT: pl-prims.c compare_fast as compare_fast_cells
"One walk over the terms at locations `l1`, `l2` (pl-prims.c `compare_fast`): `(rc, linked)`."
function compare_fast_cells(
    ld::PL_local_data{T}, l1::Int, l2::Int, mode::Int
)::Tuple{Int, Bool} where {T}
    k1, w1, p1 = _deref_loc(ld, l1)
    k2, w2, p2 = _deref_loc(ld, l2)
    rc = compare_primitives_cells(ld, k1, w1, p1, k2, w2, p2, mode)
    if rc == CMP_TERMS                                   # the boundary (counted)
        ld.cold_pairs += 1
        return (
            compare_std(ld, _loc_term(ld, k1, w1, p1), _loc_term(ld, k2, w2, p2), mode),
            false
        )
    end
    rc == CMP_COMPOUND || return (rc, false)
    q1, q2 = valPtr(w1), valPtr(w2)
    rc = compare_functors_cells(ld, q1, q2, mode)          # f1->definition != f2->definition
    rc == CMP_EQUAL || return (rc, false)
    @assert isempty(ld.cycle_cells)                        # initCyclic()
    rc, linked = do_compare_cells(ld, q1, q2, mode)
    _exit_cycles!(ld)                                      # exitCyclic()
    return (rc, linked)
end

# PORT: pl-prims.c compare_descend as compare_descend_cells
# DIVERGES: on locations; the pair Brent's algorithm remembers is the two compounds' POSITIONS
# (upstream: the `Functor` cells); returns `(rc, l1, l2)` where upstream writes `*c1`, `*c2`; a pair
# at the boundary is decided as terms (counted). A `$expr/0` pair (no argument to descend into)
# is equal. No `CMP_ERROR` from the argument tests (no memory overflow).
"""
    compare_descend_cells(ld, l1, l2, mode) -> (Int, Int, Int)

The slow but sound order of the terms at locations `l1`, `l2` (pl-prims.c `compare_descend`): at
each compound skip the leading arguments that are equal (`==`, decidable for rational trees) and
descend into the first pair that is not, until a pair decides — or the descent cycles (Brent's
algorithm on the compound pairs): `CMP_INCOMPARABLE`, with the locations where it cycles.
"""
function compare_descend_cells(
    ld::PL_local_data{T}, l1::Int, l2::Int, mode::Int
)::Tuple{Int, Int, Int} where {T}
    s1, s2 = 0, 0                                         # Functor s1 = NULL, s2 = NULL
    power, steps = 1, 0
    while true
        k1, w1, p1 = _deref_loc(ld, l1)
        k2, w2, p2 = _deref_loc(ld, l2)
        rc = compare_primitives_cells(ld, k1, w1, p1, k2, w2, p2, mode)
        if rc == CMP_TERMS                                # the boundary (counted)
            ld.cold_pairs += 1
            return (
                compare_std(ld, _loc_term(ld, k1, w1, p1), _loc_term(ld, k2, w2, p2), mode),
                l1,
                l2
            )
        end
        rc == CMP_COMPOUND || return (rc, l1, l2)
        f1, f2 = valPtr(w1), valPtr(w2)
        rc = compare_functors_cells(ld, f1, f2, mode)      # f1->definition != f2->definition
        rc == CMP_EQUAL || return (rc, l1, l2)
        f1 == s1 && f2 == s2 && return (CMP_INCOMPARABLE, l1, l2)
        steps += 1
        if steps == power
            s1, s2 = f1, f2
            power *= 2
            steps = 0
        end
        arity = arityFunctor(ld.functors, ld.gstack[f1])
        arity == 0 && return (CMP_EQUAL, l1, l2)          # (`$expr/0`: nothing to descend into)
        i = 0                                             # the pair differs, so the last
        while i + 1 < arity                               # argument need not be tested
            rc, _ = compare_fast_cells(ld, f1 + 1 + i, f2 + 1 + i, CMP_MODE_EQUAL)
            rc == CMP_EQUAL || break
            i += 1
        end
        l1, l2 = f1 + 1 + i, f2 + 1 + i                   # p1 = &f1->arguments[i]
    end
end

# PORT: pl-prims.c compare_std as compare_std_cells
# DIVERGES: NOT PORTED, as the term path's `compare_std`: the `incomparable` flag's
# `error` value (`raiseIncomparable`: its ball holds the cyclic pair, which `PL_raise_exception`'s
# copy cannot resolve) — an incomparable pair keeps the fast result, as swipl's default
# `incomparable=arbitrary` does; CMP_MODE_PARTIAL not ported either.
"The standard order of the terms at locations `l1`, `l2` in `mode` (pl-prims.c `compare_std`)."
function compare_std_cells(ld::PL_local_data{T}, l1::Int, l2::Int, mode::Int)::Int where {T}
    rc, linked = compare_fast_cells(ld, l1, l2, mode)
    if linked && mode != CMP_MODE_EQUAL && rc != CMP_EQUAL &&
        !(is_acyclic_cells(ld, l1) && is_acyclic_cells(ld, l2))   # upstream's shortcut (L1d step 3)
        rc2, _, _ = compare_descend_cells(ld, l1, l2, mode)
        rc2 != CMP_INCOMPARABLE && (rc = rc2)              # else keep the fast result
    end
    return rc
end

# PORT: pl-prims.c compareStandard as compareStandard_cells
"""
    compareStandard_cells(ld, l1, l2, eq::Bool) -> Int

The standard order of the terms at locations `l1`, `l2` (pl-prims.c `compareStandard`): `-1`, `0`,
`1`; with `eq` `0` or `CMP_NOTEQ`. The term-level `compareStandard(ld, t1, t2, eq)` stays for the
callers that hold terms (the sort family, until L1d step 7).
"""
compareStandard_cells(ld::PL_local_data{T}, l1::Int, l2::Int, eq::Bool) where {T} =
    compare_std_cells(ld, l1, l2, eq ? CMP_MODE_EQUAL : CMP_MODE_ORDER)

# ORIGINAL: pl-vmi.c B_EQ_VC's `*v1 == c` on a location: the atomic constant `c` (a clause literal,
# a term) against what the location holds — an unbound cell or a compound is never identical to it;
# an atom word or a stored value by `compare_primitives` in equality mode (SWI's identity); the
# boundary as a term.
"Whether the location `l` holds a term identical to the atomic term `c` (pl-vmi.c B_EQ_VC)."
function _identical_atomic(ld::PL_local_data{T}, l::Int, c::T)::Bool where {T}
    k, w, p = _deref_loc(ld, l)
    k == DU_CELL && return false
    k == DU_TERM &&
        return compare_primitives(deRef(ld, _loc_term(ld, k, w, p)), c, CMP_MODE_EQUAL) ==
               CMP_EQUAL
    k == DU_WORD && _is_gcompound(w) && return false
    return compare_primitives(_loc_atomic(ld, k, w), c, CMP_MODE_EQUAL) == CMP_EQUAL
end

# ── the occurs check on CELLS (L1d step 2; the workspace's L1_plan/stageL1d_design.md) ──────────
# PORT: pl-prims.c var_occurs_in as var_occurs_in_cells
# DIVERGES: `v` is a global POSITION (the variable's cell, or — asked by the trail walk — the cell
# holding a binding's value), `t` a location; a visited compound gets FIRST_MASK on its functor cell
# exactly as upstream (bit 6, which the functor's index and arity ignore), the positions stacked to
# clear it (`occurs_cells`, upstream's `visited` segstack); the walk is the cell agenda on one side.
# A pair at the BOUNDARY (a slot's side value, a keyed variable's binding) is checked on terms
# (`var_occurs_in`), counted in `cold_pairs`. No MEMORY_OVERFLOW.
# FIRST_MASK is bit 6, free in every word (see `is_acyclic_cells`); no cycle link may be in place
# while it is set — asserted: the trail walk runs after `do_unify_cells` exited its links.
"Whether the cell at position `v` occurs in the term at location `t` (pl-prims.c `var_occurs_in`)."
function var_occurs_in_cells(ld::PL_local_data{T}, v::Int, t::Int)::Bool where {T}
    @assert isempty(ld.cycle_cells) "var_occurs_in_cells: a cycle link is in place (exitCyclic first)"
    k, w, p = _deref_loc(ld, t)                         # deRef(t)
    unified = false
    if p == v && p != 0                                 # v == t
        (k == DU_WORD && _is_gcompound(w)) || return false
        unified = true                                  # goto unified
    end
    compound = false
    rc = false
    agenda = ld.ocell_agenda
    visited = ld.occurs_cells
    while true
        if !unified && p == v && p != 0                 # v == t
            rc = true
            break
        end
        unified = false
        if k == DU_TERM                                 # the boundary (counted)
            ld.cold_pairs += 1
            vt =
                isVar(ld.gstack[v]) ? _cell_var(ld, v) : _loc_term(ld, _deref_loc(ld, v)...)
            if var_occurs_in(ld, vt, _loc_term(ld, k, w, p))
                rc = true
                break
            end
        elseif k == DU_WORD && _is_gcompound(w)         # isTerm(*t)
            q = valPtr(w)
            arity = arityFunctor(ld.functors, ld.gstack[q])
            if !compound
                compound = true
                ld.gstack[q] |= FIRST_MASK              # f->definition |= FIRST_MASK
                push!(visited, q)
                initCellAgendaLR!(agenda, arity, q, q, 1)
            elseif (ld.gstack[q] & FIRST_MASK) == 0
                ld.gstack[q] |= FIRST_MASK
                push!(visited, q)
                pushWorkCellAgendaLR!(agenda, arity, q, q, 1)
            end
        end
        compound || break
        found, a, _ = nextCellAgendaLR!(agenda)         # t = nextTermAgenda(&agenda)
        found || break
        k, w, p = _deref_loc(ld, a)
    end
    if compound                                         # out:
        while !isempty(visited)
            q = pop!(visited)
            ld.gstack[q] &= ~FIRST_MASK                 # f->definition &= ~FIRST_MASK
        end
        clearCellAgendaLR!(agenda)
    end
    return rc
end

# PORT: pl-prims.c unify_with_occurs_check as unify_with_occurs_check_cells
# DIVERGES: on locations; no `onStack(global, …)` test (every variable is a global cell); the trail
# walk reads global positions (a KEYED variable's entry — until L1f — is checked on terms, counted);
# the failure's value is its dereferenced word, read before `Undo!` (upstream copies `*p2` to a fresh
# cell: see `failed_unify_with_occurs_check_cells`), and the error is built on the cells (f3b-4). No
# attributed variables (the wakeup entries of the trail).
"""
    unify_with_occurs_check_cells(ld, l1, l2, mode) -> boolex_t

Unify the terms at locations `l1`, `l2` with the occurs check in `mode` (pl-prims.c): a variable
against a term containing it fails or raises; two non-variables are unified and every binding made
is then checked for a cycle.
"""
function unify_with_occurs_check_cells(
    ld::PL_local_data{T}, l1::Int, l2::Int, mode::occurs_check_t
)::boolex_t where {T}
    k1, w1, p1 = _deref_loc(ld, l1)
    k2, w2, p2 = _deref_loc(ld, l2)
    if k1 == DU_TERM || k2 == DU_TERM                   # the boundary (counted)
        ld.cold_pairs += 1
        return unify_with_occurs_check!(
            ld, _loc_term(ld, k1, w1, p1), _loc_term(ld, k2, w2, p2), mode
        )
    end
    if k1 == DU_CELL                                    # canBind(*t1)
        if var_occurs_in_cells(ld, p1, l2)
            return failed_unify_with_occurs_check_cells(
                ld, (k1, w1, p1), (k2, w2, p2), mode
            )
        end
        return do_unify_cells(ld, l1, l2)
    end
    if k2 == DU_CELL                                    # canBind(*t2)
        if var_occurs_in_cells(ld, p2, l1)
            return failed_unify_with_occurs_check_cells(
                ld, (k1, w1, p1), (k2, w2, p2), mode
            )
        end
        return do_unify_cells(ld, l1, l2)
    end

    m = Mark(ld)
    ld.mark_bar = NO_MARK_BAR                           # see also unify_all_trail_ptrs()
    rc = do_unify_cells(ld, l1, l2)
    DiscardMark(ld, m)
    if rc == BOOLEX_TRUE
        tt = length(ld.trail)
        mt = m.trailtop
        while tt > mt                                   # while(--tt >= mt)
            e = ld.trail[tt]                            # Word p = tt->address
            if isTrailVal(e)                            # assignment of an attvar (L1b D: the branch)
                tt -= 1
                e = ld.trail[tt]
            end
            occurs, kp = if _trail_stack(e) == TRAIL_KEYED   # a keyed variable (counted)
                ld.cold_pairs += 1
                key = _trail_key(ld, e)
                pv = deRef(ld, something(_binding(ld, key)))
                (var_occurs_in(ld, pv, pv), 0)
            else
                pos = _trail_pos(e)
                kq, wq, q = _deref_loc(ld, pos)         # deRef2(p, p2)
                (var_occurs_in_cells(ld, q, q), pos)
            end
            if occurs
                if mode == OCCURS_CHECK_ERROR
                    if kp != 0                          # *t = *p2 — read before the Undo (see above)
                        val = _deref_loc(ld, kp)
                        Undo!(ld, m)
                        failed_unify_with_occurs_check_cells(
                            ld, _deref_loc(ld, kp), val, mode
                        )
                    else
                        key = _trail_key(ld, e)
                        val = deRef(ld, something(_binding(ld, key)))
                        Undo!(ld, m)
                        failed_unify_with_occurs_check(ld, mk_var(T, key), val, mode)
                    end
                end
                rc = BOOLEX_FALSE
                break
            end
            tt -= 1
        end
    end
    return rc
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
# NOT PORTED: `blockGC`/`unblockGC` around `PL_error`: they hold off the stack garbage collector
# (pl-gc.c), which the kernel does not have until G1.
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
    return PL_error(ld, ERR_OCCURS_CHECK, t1, t2) ? BOOLEX_TRUE : BOOLEX_FALSE
end

# PORT: pl-prims.c failed_unify_with_occurs_check as failed_unify_with_occurs_check_cells
# DIVERGES: the two terms are DEREFERENCED locations `(k, w, p)` (`_deref_loc`), where upstream takes
# `Word`s and dereferences them here; the error built on the cells (`pushWordAsTermRef`, f3b-4). The
# trail walk's value (`unify_with_occurs_check_cells`) is its word read before the Undo, where upstream
# copies `*p2` into a fresh global cell above the restored top: here `PL_error`'s term references take
# fresh global cells, which would overwrite it. NOT PORTED: `blockGC`/`unblockGC` (no stack GC until G1).
"Fail (`OCCURS_CHECK_TRUE`) or raise the occurs-check error, as `Var = Term`, on the cells (pl-prims.c)."
function failed_unify_with_occurs_check_cells(
    ld::PL_local_data{T}, t1::Tuple{UInt8, word, Int}, t2::Tuple{UInt8, word, Int},
    mode::occurs_check_t
)::boolex_t where {T}
    if mode == OCCURS_CHECK_TRUE
        return BOOLEX_FALSE
    end
    if t2[1] == DU_CELL                             # isVar(*t2): try to make Var = Term
        t1, t2 = t2, t1
    end
    return PL_error(ld, ERR_OCCURS_CHECK, t1, t2) ? BOOLEX_TRUE : BOOLEX_FALSE
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
    ld.mark_bar = NO_MARK_BAR                       # see also unify_all_trail_ptrs()
    rc = do_unify(ld, t1, t2)
    DiscardMark(ld, m)
    if rc == BOOLEX_TRUE
        tt = length(ld.trail)
        mt = m.trailtop
        while tt > mt                               # while(--tt >= mt)
            e = ld.trail[tt]                        # Word p = tt->address
            if isTrailVal(e)                        # assignment of an attvar (L1b D: the branch)
                tt -= 1
                e = ld.trail[tt]                    # p = (--tt)->address
                # NOT PORTED: the `attvar` wakeup list's two entries below (src/pl-attvar.jl)
            end
            key = _trail_key(ld, e)
            p2 = deRef(ld, something(_binding(ld, key)))   # deRef2(p, p2): its value, dereferenced
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

`\\=/2` (pl-prims.c): `t1` and `t2` cannot be unified. Leaves no binding behind. An occurs-check
error from the full check stays pending, and the result is `false`, as the predicate raises it.
"""
function pl_not_unify(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    p1 = deRef(ld, t1)
    p2 = deRef(ld, t2)
    if kind(p1) === VAR || kind(p2) === VAR
        ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE && return false   # can unify
        return !can_unify(ld, p1, p2) && ld.exception_term == 0   # full_check
    end
    p1 === p2 && return false
    kind(p1) !== kind(p2) && return true
    if kind(p1) === SYM
        return sym_key(p1) != sym_key(p2)
    elseif kind(p1) === GND
        return !gnd_equal(p1, p2)
    end
    return !can_unify(ld, p1, p2) && ld.exception_term == 0       # full_check
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
identical (they unify without binding anything) or they cannot unify. Leaves no binding behind. An
occurs-check error stays pending, and the result is `false` (upstream: "keep exception").
"""
function pl_can_compare(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    m = Mark(ld)
    try
        if unify_ptrs(ld, t1, t2)
            return length(ld.trail) == m.trailtop  # fr->mark.trailtop != tTop ⇒ false
        end
        return ld.exception_term == 0               # could not unify, unless an error is pending
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
    ld.mark_bar = NO_MARK_BAR                       # every assignment trailed
    rc = raw_unify_ptrs(ld, t1, t2)
    if rc == BOOLEX_TRUE                            # the caller discards the mark
        return (true, m)
    end
    if ld.exception_term == 0                       # check for occurs error
        Undo!(ld, m)
    end
    DiscardMark(ld, m)
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
    DiscardMark(ld, m)
    list = Pair{T, T}[]
    while length(ld.trail) > m.trailtop             # while(--tt >= mt), newest first
        e = pop!(ld.trail)
        if isTrailVal(e)                            # an assignment (L1b D): the cell below it
            a = pop!(ld.trail)                      # p2 = tt[-1].address; then tt--
            key = _trail_key(ld, a)
            push!(list, mk_var(T, key) => something(_binding(ld, key)))     # gp[4], gp[5] = *p2
            ld.gstack[_trail_pos(a)] = ld.gstack[trailValP(e)]  # *tt->address = trailVal(p)
            # NOT PORTED: the `attvar` wakeup list's restore (src/pl-attvar.jl)
            continue
        end
        key = _trail_key(ld, e)
        value = something(_binding(ld, key))        # gp[5] = *p
        push!(list, mk_var(T, key) => value)        # gp[4] = makeRefG(p)
        _untrail!(ld, e)                            # setVar(*p)
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
    return _resolve_term(ld, t, false)
end

# `cut`: a variable bound to a compound already on the path is kept as the variable (the caller's, if it
# was imported) instead of raising, and the compounds of that cycle are kept AS THEMSELVES (one level deep,
# their children cells' variables) so the cycle closes on the same term — the exception ball's cycle
# (f3b-1, `_slot_compound_term`; test_write_family_swipl.jl: `deRef(child(t, 3)) === t`).
function _resolve_term(ld::PL_local_data{T}, t::T, cut::Bool)::T where {T}
    t = deRef(ld, t)
    kind(t) === VAR && return _caller_var(ld, t)
    (kind(t) !== EXPR || is_ground(t)) && return t
    stack = Tuple{T, Vector{T}}[(t, T[])]           # (compound, its children resolved so far)
    on_path = IdDict{T, Nothing}(t => nothing)      # compounds being resolved: a revisit is a cycle
    cyc = Bool[false]                               # (cut) the frame is on a cycle: kept as the compound itself
    while true
        node, kids = stack[end]
        i = length(kids) + 1
        if i > nchildren(node)
            pop!(stack)
            delete!(on_path, node)
            r = pop!(cyc) ? node : mk_expr(T, kids)    # a node on a cycle stays the compound the cycle closes on
            isempty(stack) && return r
            push!(stack[end][2], r)
            continue
        end
        c0 = child(node, i)
        c = deRef(ld, c0)
        if kind(c) === EXPR && !is_ground(c)
            if haskey(on_path, c)
                if cut && kind(c0) === VAR
                    j = something(findlast(f -> f[1] === c, stack))     # the frames from the revisited node down are the cycle
                    cyc[j:end] .= true
                    push!(kids, _caller_var(ld, c0))
                    continue
                end
                throw(
                    ArgumentError(
                        "resolve_term: a cyclic binding (a rational tree) has no interface term"
                    )
                )
            end
            on_path[c] = nothing
            push!(stack, (c, T[]))
            push!(cyc, false)
        else
            push!(kids, kind(c) === VAR ? _caller_var(ld, c) : c)
        end
    end
end

# ORIGINAL (f3b-1, TRANSITIONAL — with the stamp, f3): an answer leaves the engine with the variable the
# CALLER passed. A keyed caller variable written into a cell is bound to a fresh cell
# (`_import_var!`); that cell's variable is the engine's representative, and the term-level readers hand the
# caller's own variable back, as they did when the writers stored it (a value-table word, a side value).
"The keyed variable the cell variable `v` was imported for, else `v`."
@inline function _caller_var(ld::PL_local_data{T}, v::T)::T where {T}
    isempty(ld.import_origin) && return v
    k = var_key(v)
    o = get(ld.import_origin, k, k)
    return o == k ? v : mk_var(T, o)
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
# `foreignWakeup` (no attributed variables).
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
        if unify_ptrs(ld, t1, t2)                       # && foreignWakeup(ex)
            PL_discard_foreign_frame(ld, fid)
            return true
        end
        if ld.exception_term != 0 && kind(slotValue(ld, ex + 1)) === VAR
            PL_put_term(ld, ex, ld.exception_term)
        end
        if !handle_exception && kind(slotValue(ld, ex + 1)) !== VAR
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

# PORT: pl-prims.c can_unify as can_unify_cells
# DIVERGES: on LOCATIONS (L1e e4): `unify_ptrs_cells`; no `foreignWakeup` (no attributed variables).
"Whether the terms at locations `l1`, `l2` can be unified, without doing so (pl-prims.c `can_unify`); `ex` gets an exception."
function can_unify_cells(ld::PL_local_data{T}, l1::Int, l2::Int, ex::term_t)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    if fid != 0
        handle_exception = ex == 0
        ex == 0 && (ex = PL_new_term_ref(ld))
        if unify_ptrs_cells(ld, l1, l2)                     # && foreignWakeup(ex)
            PL_discard_foreign_frame(ld, fid)
            return true
        end
        ld.exception_term != 0 && PL_is_variable(ld, ex) &&
            PL_put_term(ld, ex, ld.exception_term)
        !handle_exception && !PL_is_variable(ld, ex) && PL_clear_exception(ld)
        PL_discard_foreign_frame(ld, fid)
    end
    return false
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
    k1, w1, _ = _deref_loc(ld, -(A1 + 1))                    # deRef(p1); w1 = *p1 (L1e e4: the cells)
    k2, w2, _ = _deref_loc(ld, -(A1 + 2))                    # deRef(p2); w2 = *p2
    if k1 != DU_TERM && k2 != DU_TERM
        if k1 == DU_CELL || k2 == DU_CELL                   # isVar(w1) || isVar(w2)
            ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE && return FFALSE   # can unify
        elseif k1 == k2 && w1 == w2                         # w1 == w2
            return FFALSE
        elseif !(k1 == DU_WORD && _is_gcompound(w1) && k2 == DU_WORD && _is_gcompound(w2))
            return if compare_primitives_cells(ld, k1, w1, 0, k2, w2, 0, CMP_MODE_EQUAL) ==
                CMP_EQUAL
                FFALSE                           # tag(w1) != tag(w2), the atomic cases
            else
                FTRUE                           # tag(w1) != tag(w2), the atomic cases
            end                           # tag(w1) != tag(w2), the atomic cases
        end
        ex = PL_new_term_ref(ld)                            # full_check:
        can_unify_cells(ld, -(A1 + 1), -(A1 + 2), ex) && return FFALSE
        PL_is_variable(ld, ex) || return PL_raise_exception(ld, ex) ? FTRUE : FFALSE
        return FTRUE
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    p1 = deRef(ld, slotValue(ld, A1 + 1))                    # Word p1 = valTermRef(A1)
    p2 = deRef(ld, slotValue(ld, A1 + 2))                    # Word p2 = p1+1
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
    A1 = PL__t0                                              # on the cells (L1d step 1):
    return if compareStandard_cells(ld, -(A1 + 1), -(A1 + 2), true) == CMP_EQUAL
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-prims.c nonequal as pl_nonequal2_va
# (PRED_IMPL("\\==", 2, nonequal, 0))
# DIVERGES: no `CMP_ERROR` (see `pl_equal2_va`).
"`\\==/2` (pl-prims.c): the arguments are not identical."
function pl_nonequal2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0                                              # on the cells (L1d step 1):
    return if compareStandard_cells(ld, -(A1 + 1), -(A1 + 2), true) == CMP_EQUAL
        FFALSE
    else
        FTRUE
    end
end

# PORT: pl-prims.c PL_same_term
# DIVERGES (L1f f1c): on the words (`_deref_loc`): an unbound cell is the same term only as the same cell;
# equal words; two value-table words (upstream: two indirects) by `equalIndirect` — the term type's
# `gnd_equal` on their values (SWI's identity: `1` and `1.0` differ). The BOUNDARY (a keyed variable, a
# slot's side value) is compared on its term — a variable by its key, a value by `===` — counted in
# `cold_pairs`: TRANSITIONAL until L1f f3.
"Whether term references `t1` and `t2` hold the same term — the same variable or compound, or equal atomic values (pl-prims.c)."
function PL_same_term(ld::PL_local_data{T}, t1::term_t, t2::term_t)::Bool where {T}
    k1, w1, p1 = _deref_loc(ld, -(t1 + 1))                  # deRef(t1)
    k2, w2, p2 = _deref_loc(ld, -(t2 + 1))                  # deRef(t2)
    if k1 == DU_TERM || k2 == DU_TERM                       # (the boundary: on terms)
        ld.cold_pairs += 1
        a = deRef(ld, _loc_term(ld, k1, w1, p1))
        b = deRef(ld, _loc_term(ld, k2, w2, p2))
        kind(a) === VAR && return kind(b) === VAR && var_key(a) == var_key(b)
        return a === b
    end
    k1 == DU_CELL && return k2 == DU_CELL && p1 == p2       # isVar(*t1): t1 == t2
    w1 == w2 && return true                                 # *t1 == *t2
    if _is_vword(w1) && _is_vword(w2)                       # isIndirect(*t1) && isIndirect(*t2)
        return gnd_equal(_value_term(ld, w1), _value_term(ld, w2))   # equalIndirect
    end
    return false
end

# PORT: pl-prims.c same_term as pl_same_term2_va
# (PRED_IMPL("same_term", 2, same_term, 0))
"`same_term(@T1, @T2)`: `T1` and `T2` are the same term — the same variable or compound, or equal atomic values."
function pl_same_term2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return PL_same_term(ld, A1, A2) ? FTRUE : FFALSE
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
    # the order's argument on the WORDS (L1d step 1): `Word d = valTermRef(A1); deRef(d)` — an unbound
    # CELL takes the answer's atom word (`PL_unify_atom(A1, a)`: `bindConst` on the cell, no term
    # read); only the BOUNDARY (a slot's side value, a keyed variable: DU_TERM) reads a term, counted
    k, w, dp = _deref_loc(ld, -(A1 + 1))
    p1, p2 = -(A2 + 1), -(A2 + 2)                            # Word p1 = valTermRef(A2); p2 = p1+1 (cells, L1d)
    given = k != DU_CELL                                     # canBind(*d) ⇒ a = 0
    kk = UInt64(0)
    if given
        if k == DU_TERM                                      # the boundary: the term, as before
            d = deRef(ld, slotValue(ld, A1 + 1))
            given = kind(d) !== VAR
            given && kind(d) !== SYM &&
                return PL_type_error(ld, "atom", A1) ? FTRUE : FFALSE
            given && (kk = sym_key(d))
        elseif k == DU_WORD && isAtomW(w)                    # isAtom(*d)
            kk = sym_key(_atom_value(ld, w))
        else                                                 # a compound word, a value
            return PL_type_error(ld, "atom", A1) ? FTRUE : FFALSE
        end
    end
    smaller = false
    if given
        if kk == sym_key(mk_sym(T, :(=)))                    # ATOM_equals
            return compareStandard_cells(ld, p1, p2, true) == CMP_EQUAL ? FTRUE : FFALSE
        end
        smaller = kk == sym_key(mk_sym(T, :<))               # ATOM_smaller
        if !smaller && kk != sym_key(mk_sym(T, :>))          # ATOM_larger
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :order), A1) ? FTRUE : FFALSE
        end
    end
    val = compareStandard_cells(ld, p1, p2, false)
    if given                                                 # diff is given
        return (smaller ? val < 0 : val > 0) ? FTRUE : FFALSE
    end
    a = if val < 0
        :<
    elseif val > 0
        :>
    else
        :(=)
    end              # unify diff
    k == DU_TERM && return PL_unify_atom(ld, A1, mk_sym(T, a)) ? FTRUE : FFALSE   # the boundary
    _bind_const!(ld, dp, _atom_word!(ld, mk_sym(T, a)))      # PL_unify_atom(A1, a) on the cell
    return FTRUE
end

# PORT: pl-prims.c std_lt as pl_std_lt2_va
# (PRED_IMPL("@<", 2, std_lt, 0)) — on the CELLS (L1d step 1)
# DIVERGES: no `CMP_ERROR` (see `pl_equal2_va`); the three below likewise.
"`@</2` (pl-prims.c `std_lt`): the first argument before the second in the standard order."
function pl_std_lt2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    p1, p2 = -(PL__t0 + 1), -(PL__t0 + 2)                    # Word p1 = valTermRef(A1); p2 = p1+1
    return compareStandard_cells(ld, p1, p2, false) < 0 ? FTRUE : FFALSE   # rc < 0
end

# PORT: pl-prims.c std_leq as pl_std_leq2_va
"`@=</2` (pl-prims.c `std_leq`): the first argument not after the second in the standard order."
function pl_std_leq2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    p1, p2 = -(PL__t0 + 1), -(PL__t0 + 2)
    return compareStandard_cells(ld, p1, p2, false) <= 0 ? FTRUE : FFALSE  # rc <= 0
end

# PORT: pl-prims.c std_gt as pl_std_gt2_va
"`@>/2` (pl-prims.c `std_gt`): the first argument after the second in the standard order."
function pl_std_gt2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    p1, p2 = -(PL__t0 + 1), -(PL__t0 + 2)
    return compareStandard_cells(ld, p1, p2, false) > 0 ? FTRUE : FFALSE   # rc > 0
end

# PORT: pl-prims.c std_geq as pl_std_geq2_va
"`@>=/2` (pl-prims.c `std_geq`): the first argument not before the second in the standard order."
function pl_std_geq2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    p1, p2 = -(PL__t0 + 1), -(PL__t0 + 2)
    return compareStandard_cells(ld, p1, p2, false) >= 0 ? FTRUE : FFALSE  # rc >= 0
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
# no local-stack position). No attributed variables (`isTrailVal`), no overflow retry.
"""
    unifiable(ld, t1, t2, subst) -> Bool

`unifiable/3` (pl-prims.c) on term references: unify `subst` with the list of `Var = Value` that
would make `t1` and `t2` identical, newest binding first — nothing stays bound.
"""
function unifiable(
    ld::PL_local_data{T}, t1::term_t, t2::term_t, subst::term_t
)::Bool where {T}
    dot, eq, nil = mk_sym(T, Symbol("[|]")), mk_sym(T, :(=)), mk_nil(T)
    if PL_is_variable(ld, t1)
        if PL_compare(ld, t1, t2) == CMP_EQUAL
            return PL_unify_atom(ld, subst, nil)
        end
        unifiable_occurs_check(ld, slotValue(ld, t1 + 1), slotValue(ld, t2 + 1)) ||
            return false
        b = mk_expr(T, T[eq, slotValue(ld, t1 + 1), slotValue(ld, t2 + 1)])
        return unify_ptrs(ld, mk_expr(T, T[dot, b, nil]), slotValue(ld, subst + 1))
    end
    if PL_is_variable(ld, t2)
        unifiable_occurs_check(ld, slotValue(ld, t2 + 1), slotValue(ld, t1 + 1)) ||
            return false
        b = mk_expr(T, T[eq, slotValue(ld, t2 + 1), slotValue(ld, t1 + 1)])
        return unify_ptrs(ld, mk_expr(T, T[dot, b, nil]), slotValue(ld, subst + 1))
    end
    ok, m = unify_all_trail_ptrs(ld, slotValue(ld, t1 + 1), slotValue(ld, t2 + 1))
    ok || return false
    DiscardMark(ld, m)
    if length(ld.trail) > m.trailtop                    # tt > mt
        pairs = T[]
        while length(ld.trail) > m.trailtop             # while(--tt >= mt), newest first
            e = pop!(ld.trail)
            if isTrailVal(e)                            # an assignment (L1b D): the cell below it
                a = pop!(ld.trail)
                key = _trail_key(ld, a)
                push!(
                    pairs, mk_expr(T, T[eq, mk_var(T, key), something(_binding(ld, key))])
                )
                ld.gstack[_trail_pos(a)] = ld.gstack[trailValP(e)]  # *tt->address = trailVal(p)
                continue                                # NOT PORTED: the `attvar` wakeup restore
            end
            key = _trail_key(ld, e)
            push!(pairs, mk_expr(T, T[eq, mk_var(T, key), something(_binding(ld, key))]))
            _untrail!(ld, e)                            # setVar(*p)
        end
        list = foldr((x, acc) -> mk_expr(T, T[dot, x, acc]), pairs; init=nil)
        return unify_ptrs(ld, list, slotValue(ld, subst + 1))
    end
    return PL_unify_atom(ld, subst, nil)
end

# ── unifiable/3 on the CELLS (L1e e4; the workspace's L1_plan/stageL1e_design.md §4) ──────────────
# PORT: pl-prims.c unifiable_occurs_check as unifiable_occurs_check_cells
# DIVERGES: on term references, the variable's cell and the term's location (`var_occurs_in_cells`, L1d
# step 2); the error built on the cells (`failed_unify_with_occurs_check_cells`, f3b-4). Both
# callers pass a variable (`PL_is_variable`), so `t1` is an unbound cell — or the boundary, a keyed
# variable (`DU_TERM`): then the check runs on the terms (`unifiable_occurs_check`), counted in
# `cold_pairs` (TRANSITIONAL: goes with `_loc_term`, f3).
"Whether binding the variable `t1` references to the term `t2` references passes the occurs check (pl-prims.c)."
function unifiable_occurs_check_cells(
    ld::PL_local_data{T}, t1::term_t, t2::term_t
)::Bool where {T}
    flag = ld.prolog_flag_occurs_check
    flag == OCCURS_CHECK_FALSE && return true
    k, w, p = _deref_loc(ld, -(t1 + 1))
    if k == DU_TERM                                 # the boundary: on the terms (TRANSITIONAL, f3)
        ld.cold_pairs += 1
        k2, w2, p2 = _deref_loc(ld, -(t2 + 1))
        k2 == DU_TERM && (ld.cold_pairs += 1)
        return unifiable_occurs_check(
            ld, deRef(ld, _loc_term(ld, k, w, p)), deRef(ld, _loc_term(ld, k2, w2, p2))
        )
    end
    @assert k == DU_CELL                            # PL_is_variable(t1) at both call sites
    var_occurs_in_cells(ld, p, -(t2 + 1)) || return true
    return failed_unify_with_occurs_check_cells(
        ld, (k, word(0), p), _deref_loc(ld, -(t2 + 1)), flag
    ) == BOOLEX_TRUE
end

# PORT: pl-prims.c unify_all_trail_ptrs as unify_all_trail_ptrs_cells
# DIVERGES: on locations (`raw_unify_cells`); as `unify_all_trail_ptrs`: every assignment trailed
# (`mark_bar` off), no overflow retry.
"Unify the terms at locations `l1`, `l2`, every binding on the trail above the returned mark; undone on plain failure (pl-prims.c)."
function unify_all_trail_ptrs_cells(
    ld::PL_local_data{T}, l1::Int, l2::Int
)::Tuple{Bool, mark} where {T}
    m = Mark(ld)
    ld.mark_bar = NO_MARK_BAR                       # every assignment trailed
    if raw_unify_cells(ld, l1, l2) == BOOLEX_TRUE   # the caller discards the mark
        return (true, m)
    end
    ld.exception_term == 0 && Undo!(ld, m)          # check for occurs error
    DiscardMark(ld, m)
    return (false, m)
end

# ORIGINAL: `[T1 = T2]` laid out at gTop from two term references (upstream: PL_unify_term with
# FUNCTOR_dot2, FUNCTOR_equals2, PL_TERM t1, PL_TERM t2, ATOM_nil), unified with `subst`.
function _unifiable_single!(
    ld::PL_local_data{T}, t1::term_t, t2::term_t, subst::term_t
)::Bool where {T}
    p = allocGlobalCells!(ld, 6)
    ld.gstack[p] = ld.functor_dot2
    ld.gstack[p + 1] = consPtr(p + 3, TAG_COMPOUND | STG_GLOBAL)
    ld.gstack[p + 2] = ld.atom_nil_w
    ld.gstack[p + 3] = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(=))), 2)
    _cell_link!(ld, p + 4, t1 + 1)                  # PL_TERM, t1
    _cell_link!(ld, p + 5, t2 + 1)                  # PL_TERM, t2
    r = PL_new_term_ref(ld)
    ld.slots[r + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)
    return PL_unify(ld, r, subst)
end

# PORT: pl-prims.c unifiable as unifiable_cells
# DIVERGES: on the cells (L1e e4): the substitution list laid out at gTop from the trail, newest binding first,
# 6 cells per binding as upstream (`[V = Value|…]`: `gp[4] = makeRefG(p)`, `gp[5] = *p`, `setVar(*p)`); exactly
# the cells it uses are allocated (upstream allocates `(tt-mt)*6+1` and lowers gTop). A trail entry of a KEYED
# variable (the boundary, until L1f) — the whole substitution built on terms (`unifiable(ld, t1, t2, subst)`),
# counted. No attributed variables (the attvar wakeup restore), no overflow retry.
"`unifiable(T1, T2, Subst)` on the cells (pl-prims.c `unifiable`)."
function unifiable_cells(
    ld::PL_local_data{T}, t1::term_t, t2::term_t, subst::term_t
)::Bool where {T}
    if PL_is_variable(ld, t1)
        PL_compare(ld, t1, t2) == CMP_EQUAL && return PL_unify_atom(ld, subst, mk_nil(T))
        unifiable_occurs_check_cells(ld, t1, t2) || return false
        return _unifiable_single!(ld, t1, t2, subst)
    end
    if PL_is_variable(ld, t2)
        unifiable_occurs_check_cells(ld, t2, t1) || return false
        return _unifiable_single!(ld, t2, t1, subst)
    end
    ok, m = unify_all_trail_ptrs_cells(ld, -(t1 + 1), -(t2 + 1))
    ok || return false
    tt, mt = length(ld.trail), m.trailtop
    if tt <= mt                                               # no binding: DiscardMark(m); []
        DiscardMark(ld, m)
        return PL_unify_atom(ld, subst, mk_nil(T))
    end
    for i in (mt + 1):tt                                      # a keyed variable: the boundary, on terms
        e = ld.trail[i]
        if !isTrailVal(e) && _trail_stack(e) == TRAIL_KEYED
            Undo!(ld, m)
            DiscardMark(ld, m)
            ld.cold_pairs += 1
            return unifiable(ld, t1, t2, subst)
        end
    end
    DiscardMark(ld, m)
    n = 0                                                     # the bindings: a value entry and its
    i = tt                                                    # cell count once
    while i > mt
        isTrailVal(ld.trail[i]) && (i -= 1)
        n += 1
        i -= 1
    end
    list = allocGlobalCells!(ld, 6 * n + 1)                   # tail = list = gTop; gp = list+1
    ld.gstack[list] = ld.atom_nil_w                           # *list = ATOM_nil
    tail, gp = list, list + 1
    eq2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(=))), 2)
    while length(ld.trail) > mt                               # while(--tt >= mt)
        e = pop!(ld.trail)
        ld.gstack[tail] = consPtr(gp, TAG_COMPOUND | STG_GLOBAL)   # *tail = consPtr(&gp[0], …)
        ld.gstack[gp] = ld.functor_dot2
        ld.gstack[gp + 1] = consPtr(gp + 3, TAG_COMPOUND | STG_GLOBAL)
        ld.gstack[gp + 2] = ld.atom_nil_w
        tail = gp + 2
        ld.gstack[gp + 3] = eq2
        if isTrailVal(e)                                      # an assignment: the cell below it
            a = pop!(ld.trail)
            p2 = _trail_pos(a)
            ld.gstack[gp + 4] = makeRefG(p2)                  # gp[4] = makeRefG(p2)
            ld.gstack[gp + 5] = ld.gstack[p2]                 # gp[5] = *p2
            ld.gstack[p2] = ld.gstack[trailValP(e)]           # *tt->address = trailVal(p)
        else
            p = _trail_pos(e)
            ld.gstack[gp + 5] = ld.gstack[p]                  # gp[5] = *p
            ld.gstack[gp + 4] = makeRefG(p)                   # gp[4] = makeRefG(p)
            ld.gstack[p] = word(0)                            # setVar(*p)
        end
        gp += 6
    end
    r = PL_new_term_ref(ld)                                   # pushWordAsTermRef(list)
    ld.slots[r + 1] = ld.gstack[list]
    return PL_unify(ld, r, subst)
end

# PORT: pl-prims.c unifiable as pl_unifiable3_va
# (PRED_IMPL("unifiable", 3, unifiable, 0)) — on the cells since L1e e4 (`unifiable_cells`)
"`unifiable/3` (pl-prims.c)."
function pl_unifiable3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    return unifiable_cells(ld, A1, A2, A3) ? FTRUE : FFALSE
end

# PORT: pl-prims.c atom_number as pl_atom_number2_va
# (PRED_IMPL("atom_number", 2, atom_number, 0))
# DIVERGES: `PL_get_nchars` is `PL_get_text` (no `PL_mb_text`/`PL_save_text`: an atom's or a
# string's text is already UTF-8, `REP_UTF8`; a number's is ASCII).
"""
`atom_number/2` (pl-prims.c): the number a text atom or string writes, by `str_number` with no
flags (so no escapes: `0'\\n` fails); else the atom a number writes; else a type error.
"""
function pl_atom_number2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    s = PL_get_text(ld, A1, CVT_ATOM | CVT_STRING)
    if s !== nothing                                # PL_get_nchars(A1, …, REP_UTF8|CVT_ATOM|…)
        @assert s.encoding === ENC_UTF8             # REP_UTF8: as `PL_get_text` gives it
        b = UInt8[s.text; 0x00]                     # char *s, EOS-terminated
        n = number()
        rc, q = str_number(ld, b, 1, n, UInt32(0))
        if rc == NUM_OK
            if b[q] == 0x00                         # *q == EOS
                ok = PL_unify_number(ld, A2, n)
                clearNumber(n)
                return ok ? FTRUE : FFALSE
            end
            clearNumber(n)
            return FFALSE
        end
        return FFALSE
    end
    s = PL_get_text(ld, A2, CVT_NUMBER)
    if s !== nothing                                # PL_get_nchars(A2, &len, &s, CVT_NUMBER)
        return PL_unify_atom(ld, A1, mk_sym(T, Symbol(String(s.text)))) ? FTRUE : FFALSE
    end                                             # PL_unify_atom_nchars(A1, len, s)
    if !PL_is_variable(ld, A2)
        return PL_error(ld, ERR_TYPE, mk_sym(T, :number), A2) ? FTRUE : FFALSE
    elseif !PL_is_atom(ld, A1)
        return PL_error(ld, ERR_TYPE, mk_sym(T, :atom), A1) ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-prims.c throw as pl_throw1_va
# (PRED_IMPL("throw", 1, throw, 0))
"`throw/1` (pl-prims.c): raise the ball; a variable raises `instantiation_error`."
function pl_throw1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    if PL_is_variable(ld, A1)
        return PL_error(ld, ERR_INSTANTIATION) ? FTRUE : FFALSE
    end
    return PL_raise_exception(ld, A1) ? FTRUE : FFALSE
end

# ── ground/1, functor/3, term_variables/2,3, '$free_variable_set'/3, '$skip_list'/3 (pl-prims.c),
# since V9g-b: what boot/bags.pl's bagof/3 and setof/3 and boot/init.pl's length/2 call ───────────

# PORT: pl-prims.c ph_ground
# DIVERGES: one walk — a visited compound is an entry in an identity map that lives for the call,
# where upstream marks its functor cell in one walk and unmarks it in a second (`ph_mark`,
# `ph_unmark`); the walk starts at the compound's arguments.
"The first unbound variable of compound `top` under the bindings in `ld`, or `nothing` (pl-prims.c)."
function ph_ground(ld::PL_local_data{T}, top::T)::Union{Nothing, T} where {T}
    visited = IdDict{T, Nothing}()
    agenda = term_agenda{T}(aNode{T}(top, 0, 0), aNode{T}[])

    visited[top] = nothing
    off, arity = _comp_shape(top)
    initTermAgenda!(agenda, arity, top, off)
    while true
        p = nextTermAgenda!(ld, agenda)
        p === nothing && break
        if canBind(p)
            clearTermAgenda!(agenda)
            return p
        end
        if isTerm(p)
            if !haskey(visited, p)                      # !ph_visited(f, ph)
                visited[p] = nothing
                o, a = _comp_shape(p)
                pushWorkAgenda!(agenda, a, p, o)
            end
        end
    end

    return nothing
end

# PORT: pl-prims.c ground
# DIVERGES: a compound whose own value holds no variable (`is_ground`) is ground without a walk.
"The first unbound variable of `p` under the bindings in `ld`, or `nothing` when it is ground (pl-prims.c)."
function ground(ld::PL_local_data{T}, p::T)::Union{Nothing, T} where {T}
    p = deRef(ld, p)
    if canBind(p)
        return p
    end
    if !isTerm(p)
        return nothing
    end
    is_ground(p) && return nothing

    return ph_ground(ld, p)
end

# PORT: pl-prims.c ground as pl_ground1_va
# (PRED_IMPL("ground", 1, ground, PL_FA_ISO))
"`ground(@Term)`: `Term` holds no unbound variable (pl-prims.c)."
function pl_ground1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return ground_cells(ld, -(A1 + 1)) == 0 ? FTRUE : FFALSE    # ground(valTermRef(A1)) == NULL
end

# PORT: pl-prims.c functor as pl_functor3_va
# (PRED_IMPL("functor", 3, functor, 0)); the table's flag is `PL_FA_ISO`.
# DIVERGES: a compound whose head is no symbol is named `$expr`, its arity the number of its
# children (`PL_get_name_arity`). NOT PORTED: the global stack's overflow — an arity that does not
# fit the stacks is refused (`NotPortedError`) rather than built (see `'$length'/2`, src/pl-list.jl).
"`functor(?Term, ?Name, ?Arity)` (pl-prims.c): the name and arity of `Term`, or the term of that name and arity."
function pl_functor3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    k, w, q = _deref_loc(ld, -(A1 + 1))                 # p = valTermRef(A1); deRef(p) (L1e e4: the words)
    k == DU_TERM && (ld.cold_pairs += 1)                # the boundary: its kind on the term
    isterm = if k == DU_WORD
        _is_gcompound(w)
    else
        k == DU_TERM && isTerm(deRef(ld, _loc_term(ld, k, w, q)))
    end
    isatomic =
        k == DU_VALUE || (k == DU_WORD && isAtomW(w)) ||
        (k == DU_TERM && isAtomic(deRef(ld, _loc_term(ld, k, w, q))))

    if isterm                                           # isTerm(*p)
        na = PL_get_name_arity(ld, A1)::Tuple{T, Int}   # fd = valueFunctor(functorTerm(*p))

        if na[2] == 0
            return PL_domain_error(ld, "compound_non_zero_arity", A1) ? FTRUE : FFALSE
        end

        return if (PL_unify_atom(ld, A2, na[1]) && PL_unify_integer(ld, A3, na[2]))
            FTRUE
        else
            FFALSE
        end
    end
    if isatomic                                         # isAtomic(*p)
        return (PL_unify(ld, A2, A1) && PL_unify_integer(ld, A3, 0)) ? FTRUE : FFALSE
    end
    if !PL_is_atomic(ld, A2)
        return PL_error(ld, ERR_TYPE, mk_sym(T, :atomic), A2) ? FTRUE : FFALSE
    end

    arity = PL_get_size_ex(ld, A3)
    if arity === nothing
        return FFALSE
    end
    if arity == 0
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
    name = PL_get_atom_ex(ld, A2)
    if name !== nothing
        ensureGlobalSpace(ld, 1 + arity) || return FFALSE   # (L1f f2)
        return PL_unify_functor(ld, A1, name, arity) ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-prims.c univ as pl_univ2_va
# (PRED_IMPL("=..", 2, univ, PL_FA_ISO)) — on the CELLS from the start (L1e e4, audit D-0020): the compound
# laid out at gTop from the list's words (`needsRef(*h) ? makeRefG(h) : *h`), the other direction through the
# FLI writers on cells (e3). DIVERGES: a compound whose head is no symbol (the kernel's `$expr/n`, Q2) gives
# the list of ALL its children, the head first (it has no functor name; swipl has no such term); a list
# element at the boundary (DU_TERM) is stored as its term's word, counted in `cold_pairs`.
"`Term =.. List` (pl-prims.c `univ`): `List` is `[Name|Args]` of the compound `Term`, or `[Term]` of an atomic."
function pl_univ2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    t, list = PL__t0, PL__t0 + 1
    if PL_is_variable(ld, t)
        tail = PL_copy_term_ref(ld, list)
        head = PL_new_term_ref(ld)
        if !PL_get_list(ld, tail, head, tail)
            PL_get_nil(ld, tail) &&
                return if PL_error(ld, ERR_DOMAIN, mk_sym(T, :non_empty_list), tail)
                    FTRUE
                else
                    FFALSE
                end
            return PL_error(ld, ERR_TYPE, mk_sym(T, :list), tail) ? FTRUE : FFALSE
        end
        if PL_get_nil(ld, tail)                             # A =.. [H]
            PL_is_atomic(ld, head) ||
                return PL_error(ld, ERR_TYPE, mk_sym(T, :atomic), head) ? FTRUE : FFALSE
            return PL_unify(ld, t, head) ? FTRUE : FFALSE
        end
        name = PL_get_atom_ex(ld, head)
        name === nothing && return FFALSE
        arity = lengthList(ld, tail, false)
        if arity < 0
            arity == -1 &&
                return PL_error(ld, ERR_TYPE, mk_sym(T, :list), list) ? FTRUE : FFALSE
            return PL_error(ld, ERR_INSTANTIATION) ? FTRUE : FFALSE
        end
        ensureGlobalSpace(ld, arity + 1) || return FFALSE  # allocGlobal(arity+1) (L1f f2)
        p = _alloc_compound!(
            ld, lookupFunctorDef(ld.functors, _atom_word!(ld, name), arity), arity
        )
        ld.slots[head + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)   # *valTermRef(head) = consPtr(p, …)
        k, w, _ = _deref_loc(ld, -(tail + 1))               # Word l = valTermRef(tail); deRef(l)
        i = 0
        while _is_list_word(ld, k, w)                       # while(isList(*l))
            i += 1
            hk, hw, hp = _deref_loc(ld, valPtr(w) + 1)      # Word h = HeadList(l); deRef(h)
            ld.gstack[p + i] = if hk == DU_CELL             # *p++ = needsRef(*h) ? makeRefG(h) : *h
                makeRefG(hp)
            elseif hk == DU_TERM
                ld.cold_pairs += 1
                _word_of!(ld, deRef(ld, _loc_term(ld, hk, hw, hp)))
            else
                hw
            end
            k, w, _ = _deref_loc(ld, valPtr(w) + 2)         # l = TailList(l); deRef(l)
        end
        return PL_unify(ld, t, head) ? FTRUE : FFALSE
    end
    k, w, _ = _deref_loc(ld, -(t + 1))                      # p = valTermRef(t); deRef(p)
    if k == DU_WORD && _is_gcompound(w)                     # isTerm(*p)
        f = ld.gstack[valPtr(w)]
        n = arityFunctor(ld.functors, f)
        n == 0 && return PL_domain_error(ld, "compound_non_zero_arity", t) ? FTRUE : FFALSE
        head = PL_new_term_ref(ld)
        l = PL_new_term_ref(ld)
        PL_unify_list_ex(ld, list, head, l) || return FFALSE
        nm = nameFunctor(ld.functors, f)
        if nm != ld.atom_dexpr                              # PL_unify_atom(head, fd->name)
            PL_unify_atom(ld, head, _atom_value(ld, nm)) || return FFALSE
        else                                                # `$expr/n`: its first child is the head
            PL_unify_arg(ld, 1, t, head) || return FFALSE
        end
        for a in (nm == ld.atom_dexpr ? 2 : 1):n
            (PL_unify_list_ex(ld, l, head, l) && PL_unify_arg(ld, a, t, head)) ||
                return FFALSE
        end
        return PL_unify_nil_ex(ld, l) ? FTRUE : FFALSE
    elseif k == DU_TERM                                     # the boundary: decide its kind on the term
        ld.cold_pairs += 1
    end
    if PL_is_atomic(ld, t)                                  # 3 =.. X, 3.4 =.. X, "foo" =.. X
        head = PL_new_term_ref(ld)
        l = PL_new_term_ref(ld)
        PL_unify_list_ex(ld, list, head, l) && PL_unify(ld, head, t) &&
            PL_unify_nil_ex(ld, l) &&
            return FTRUE
    end
    return FFALSE
end

# PORT: pl-prims.c term_variables_loop
# DIVERGES: the variables are pushed on `vars` (upstream: term references); a visited variable is
# its key in `visitedv`, a visited compound an entry in `visitedf` (upstream: marks on the cells).
# NOT PORTED: `flags` (`TV_ATTVAR`, `TV_SINGLETON`, `TV_SHARED`, `TV_ATTS`: term_singletons/2,
# term_attvars/2 and friends), the signal check, `TV_NOSPACE`/`TV_NOMEM`.
"Push the unbound variables the agenda walks on `vars`, each once, in depth-first order; their count, or `maxcount + 1` as soon as there are more (pl-prims.c)."
function term_variables_loop(
    ld::PL_local_data{T}, agenda::term_agenda{T}, maxcount::Int, vars::Vector{T},
    visitedv::Set{UInt64}, visitedf::IdDict{T, Nothing}
)::Int where {T}
    count = 0

    while true
        p = nextTermAgenda!(ld, agenda)
        p === nothing && break

        if canBind(p)
            k = var_key(p)
            if k in visitedv                            # visitedWord(p)
                continue
            end
            push!(visitedv, k)

            count += 1
            if count > maxcount
                return count
            end
            push!(vars, p)                              # *valTermRef(v) = makeRefG(p)
        elseif isTerm(p)
            if haskey(visitedf, p)                      # visited(f)
                continue
            end
            visitedf[p] = nothing
            off, arity = _comp_shape(p)
            pushWorkAgenda!(agenda, arity, p, off)
        end
    end

    return count
end

# PORT: pl-prims.c term_variables_to_termv
# DIVERGES: returns `(count, variables)` where upstream leaves the variables in term references
# from `*vp`; the walk starts at a compound holding the term (an agenda walks arguments).
"The unbound variables of the term `t` references, in depth-first order, and their count — `maxcount + 1` if there are more (pl-prims.c)."
function term_variables_to_termv(
    ld::PL_local_data{T}, t::term_t, maxcount::Int
)::Tuple{Int, Vector{T}} where {T}
    root = mk_expr(T, T[slotValue(ld, t + 1)])
    agenda = term_agenda{T}(aNode{T}(root, 0, 0), aNode{T}[])
    vars = T[]

    initTermAgenda!(agenda, 1, root, 1)
    count = term_variables_loop(
        ld, agenda, maxcount, vars, Set{UInt64}(), IdDict{T, Nothing}()
    )
    clearTermAgenda!(agenda)

    return (count, vars)
end

# PORT: pl-prims.c term_variables
# DIVERGES: `tail` 0 is "no tail", as upstream's. NOT PORTED: `flags` (see `term_variables_loop`),
# and the retries after `TV_NOSPACE`, `TV_EINTR`, `TV_NOMEM`.
"Unify `vars` with the list of the unbound variables of `t`, ending in `tail` (0: in `[]`) (pl-prims.c)."
function term_variables(
    ld::PL_local_data{T}, t::term_t, vars::term_t, tail::term_t
)::Bool where {T}
    list = PL_copy_term_ref(ld, vars)
    head = PL_new_term_ref(ld)
    maxcount = typemax(Int)                             # ~0

    if tail == 0
        type, len = PL_skip_list(ld, vars)
        type == PL_LIST && (maxcount = len)
    end

    count, v0 = term_variables_to_termv_cells(ld, t, maxcount)  # on the cells (L1d step 5)
    if count > maxcount
        return false
    end

    for i in 1:count
        if !PL_unify_list(ld, list, head, list) || !PL_unify(ld, head, v0 + i - 1)
            return false
        end
    end
    PL_reset_term_refs(ld, head)

    if tail != 0
        return PL_unify(ld, list, tail)
    else
        return PL_unify_nil(ld, list)
    end
end

# PORT: pl-prims.c term_variables2 as pl_term_variables2_va
# (PRED_IMPL("term_variables", 2, term_variables2, PL_FA_ISO))
"`term_variables(+Term, -Vars)`: the unbound variables of `Term`, in depth-first order (pl-prims.c)."
function pl_term_variables2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return term_variables(ld, A1, A2, 0) ? FTRUE : FFALSE
end

# PORT: pl-prims.c term_variables3 as pl_term_variables3_va
# (PRED_IMPL("term_variables", 3, term_variables3, 0))
"`term_variables(+Term, -Vars, ?Tail)`: as term_variables/2, the list ending in `Tail` (pl-prims.c)."
function pl_term_variables3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    return term_variables(ld, A1, A2, A3) ? FTRUE : FFALSE
end

# PORT: pl-prims.c free_variables_loop
# DIVERGES: returns `(goal, module name)` — `nothing` where upstream leaves `goal` unbound or
# `*mname` 0 — and pushes the free variables on `vars`; the marks are as `term_variables_loop`'s;
# `&mark` is an agenda entry that no term can be (`mark`, held by `markbox`); the walk starts at a
# compound holding the term. The goal after `Module:` is read as every other argument is
# (upstream defect, see register Q4).
"""
The free variables of `Template^Goal` as the ISO standard defines them (7.1.1.4; pl-prims.c): walk
`t0`, pushing on `vars` every unbound variable met outside the left side of an outermost `^`, and
return the goal without its `^` and `Module:` prefixes, and the last module named.
"""
function free_variables_loop(
    ld::PL_local_data{T}, t0::T, vars::Vector{T}
)::Tuple{Union{Nothing, T}, Union{Nothing, T}} where {T}
    in_goal = false
    existential = false                 # true when processing left of ^
    mark = mk_expr(T, T[])              # mark that tells us we completed vars
    markbox = mk_expr(T, T[mark])
    root = mk_expr(T, T[t0])
    agenda = term_agenda{T}(aNode{T}(root, 0, 0), aNode{T}[])
    visitedv = Set{UInt64}()
    visitedf = IdDict{T, Nothing}()
    goal::Union{Nothing, T} = nothing
    mname::Union{Nothing, T} = nothing
    hat = mk_sym(T, :^)
    colon = mk_sym(T, :(:))

    initTermAgenda!(agenda, 1, root, 1)
    while true
        n = nextTermAgenda!(ld, agenda)
        n === nothing && break
        t = n
        if t === mark
            existential = false
            continue
        end

        @label again
        if canBind(t)
            k = var_key(t)
            if !(k in visitedv)                         # !visitedWord(t) && !existential
                push!(visitedv, k)
                existential || push!(vars, t)
            end

            continue
        end

        if isTerm(t)
            off, arity = _comp_shape(t)

            if haskey(visitedf, t)                      # visited(f)
                if !in_goal && !existential
                    goal = t
                    in_goal = true
                end
                continue
            end
            visitedf[t] = nothing

            if !in_goal
                if _hasFunctor(t, hat, 2) && existential == false   # fd == FUNCTOR_hat2
                    pushWorkAgenda!(agenda, 1, t, off + 1)          # &f->arguments[1]
                    pushWorkAgenda!(agenda, 1, markbox, 1)          # &mark
                    pushWorkAgenda!(agenda, 1, t, off)              # &f->arguments[0]
                    existential = true
                    continue
                end
                if _hasFunctor(t, colon, 2) && !existential         # fd == FUNCTOR_colon2
                    a1 = deRef(ld, child(t, off))

                    if isAtom(a1)
                        mname = a1
                    end
                    t = deRef(ld, child(t, off + 1))    # (see DIVERGES)
                    @goto again
                elseif !existential
                    goal = t
                    in_goal = true
                end
            end

            pushWorkAgenda!(agenda, arity, t, off)

            continue
        elseif !in_goal && !existential     # non-term goal (atom or invalid)
            goal = t
            in_goal = true
        end
    end

    clearTermAgenda!(agenda)

    return (goal, mname)
end

# ── the walks on CELLS (L1d step 5; the workspace's L1_plan/stageL1d_design.md §3d) ──────────────
# Locations as `_deref_loc`'s. A compound is marked on its FUNCTOR cell (MARK_MASK, as upstream); a
# variable cell — upstream marks the cell itself (`visitedWord`), which ours cannot: a marked variable
# cell is no `isVar` (`w == 0`) and `_deref_loc` would read it as a value-table word — in the side
# vector `ld.tv_seen` by position (a representation-only DIVERGES: behaviour identical). Both go on
# `ld.cycle_vstack` (upstream's `LD->cycle.vstack`), cleared by `unvisit_cells`.

# PORT: pl-prims.c FUNCTOR_hat2
# (the handle itself is generated into pl-funct.ih from src/ATOMS; free_variables_loop uses it)
"The functor word of `^/2` (pl-funct.ih `FUNCTOR_hat2`): the same in every database."
const FUNCTOR_hat2 = builtin_functor("hat", 2)
# PORT: pl-prims.c FUNCTOR_colon2
# (the handle itself is generated into pl-funct.ih from src/ATOMS; free_variables_loop uses it)
"The functor word of `:/2` (pl-funct.ih `FUNCTOR_colon2`): the same in every database."
const FUNCTOR_colon2 = builtin_functor("colon", 2)

# PORT: pl-prims.c ph_visitedWord as ph_visited_cells
# (`ph_visited(f, ph)` on the functor cell at global position `c`)
"Whether the compound at global position `c` was visited in this phase (`mark`: marking), marking or unmarking it if not (pl-prims.c)."
@inline function ph_visited_cells(ld::PL_local_data, c::Int, mark::Bool)::Bool
    f = ld.gstack[c]
    if mark                                                 # ph_mark
        (f & MARK_MASK) != 0 && return true
        ld.gstack[c] = f | MARK_MASK
    else                                                    # ph_unmark
        (f & MARK_MASK) == 0 && return true
        ld.gstack[c] = f & ~MARK_MASK
    end
    return false
end

"`ground_cells`/`ph_ground_cells`: a variable lies in the boundary (a keyed variable's binding)."
const GROUND_BOUNDARY = -1

# PORT: pl-prims.c ph_ground as ph_ground_cells
# DIVERGES: on locations, the one-sided cell agenda (`ld.walk_agenda`); returns the first unbound
# cell's POSITION (upstream: its address), 0 for none. The boundary (`DU_TERM`) is decided by the
# term-level `ground` on its term, counted in `cold_pairs`: a variable there gives `GROUND_BOUNDARY`
# in both phases, so they stop at the same compound (upstream's `assert(rc1 == rc2)`).
"The first unbound cell of the term at location `l` in phase `mark`, 0 if none, `GROUND_BOUNDARY` (pl-prims.c)."
function ph_ground_cells(ld::PL_local_data{T}, l::Int, mark::Bool)::Int where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)
        if k == DU_CELL                                     # canBind(*p)
            clearCellAgenda!(a)
            return p
        elseif k == DU_TERM                                 # the boundary: on the term
            ld.cold_pairs += 1
            if ground(ld, _loc_term(ld, k, w, p)) !== nothing
                clearCellAgenda!(a)
                return GROUND_BOUNDARY
            end
        elseif k == DU_WORD && _is_gcompound(w)             # isTerm(*p)
            c = valPtr(w)
            if !ph_visited_cells(ld, c, mark)
                pushWorkCellAgenda!(a, arityFunctor(ld.functors, ld.gstack[c]), c + 1)
            end
        end
    end
    return 0
end

# PORT: pl-prims.c ground as ground_cells
# DIVERGES: on a location; returns a POSITION, 0 or `GROUND_BOUNDARY` (see `ph_ground_cells`).
"The first unbound cell of the term at location `l`: its position, 0 when ground, `GROUND_BOUNDARY` (pl-prims.c `ground`)."
function ground_cells(ld::PL_local_data{T}, l::Int)::Int where {T}
    k, w, p = _deref_loc(ld, l)                             # deRef(p)
    k == DU_CELL && return p                                # canBind(*p)
    if k == DU_TERM
        ld.cold_pairs += 1
        return ground(ld, _loc_term(ld, k, w, p)) === nothing ? 0 : GROUND_BOUNDARY
    end
    (k == DU_WORD && _is_gcompound(w)) || return 0          # !isTerm(*p)
    rc1 = ph_ground_cells(ld, l, true)                      # mark functors
    rc2 = ph_ground_cells(ld, l, false)                     # unmark the very same functors
    @assert rc1 == rc2
    return rc1
end

# PORT: pl-prims.c visitedWord as visitedWord_cells
# DIVERGES: a FUNCTOR cell is marked in place (`set_marked`); a VARIABLE cell in `ld.tv_seen` (see the
# section header). Both pushed on `ld.cycle_vstack`.
"Whether the functor or variable cell at global position `p` was visited; marks it if not (pl-prims.c)."
@inline function visitedWord_cells(ld::PL_local_data, p::Int)::Bool
    w = ld.gstack[p]
    if isVar(w)
        s = ld.tv_seen
        p > length(s) && _grow_tv_seen!(ld, p)
        s[p] && return true                                 # is_marked(p)
        s[p] = true                                         # set_marked(p)
    else
        (w & MARK_MASK) != 0 && return true
        ld.gstack[p] = w | MARK_MASK
    end
    push!(ld.cycle_vstack, p)                               # pushSegStack(&LD->cycle.vstack, p)
    return false
end

# ORIGINAL: the side vector grows to cover position `p` (new entries false); it never shrinks.
"Grow `ld.tv_seen` to cover global position `p`."
@noinline function _grow_tv_seen!(ld::PL_local_data, p::Int)::Nothing
    s = ld.tv_seen
    n = length(s)
    resize!(s, max(p, 2 * n, 64))
    fill!(view(s, (n + 1):length(s)), false)
    return nothing
end

# PORT: pl-prims.c unvisit_and_unfirst as unvisit_cells
# DIVERGES: a variable cell's mark is its side-vector entry (see the section header).
"Clear every mark `visitedWord_cells` left (pl-prims.c `unvisit_and_unfirst`)."
function unvisit_cells(ld::PL_local_data)::Nothing
    v = ld.cycle_vstack
    while !isempty(v)
        p = pop!(v)                                         # popSegStack(&LD->cycle.vstack, &p)
        w = ld.gstack[p]
        if isVar(w)
            ld.tv_seen[p] = false
        else
            ld.gstack[p] = w & ~(MARK_MASK | FIRST_MASK)    # clear_both(p)
        end
    end
    return nothing
end

# ORIGINAL: upstream's `v = PL_new_term_ref_noshift(); *valTermRef(v) = w` — a term reference holding
# the word `w` (a reference to a cell), with no fresh cell made for it (ours: `new_term_ref` binds a
# fresh global cell, which the store would overwrite).
"A new term reference holding the slot word `w`; 0 when the local stack has no room."
function _new_term_ref_word!(ld::PL_local_data, w::word)::Int
    ensureLocalSpace(ld, 1) || return 0
    t = ld.lTop
    ld.slots[t + 1] = w
    ld.lTop = t + 1
    ld.fliframes[ld.fli_context].size += 1
    return t
end

"`term_variables_loop_cells`/`free_variables_loop_cells`: the walk met the boundary; redo it on terms."
const TV_BOUNDARY = -1

# PORT: pl-prims.c term_variables_loop as term_variables_loop_cells
# DIVERGES: on locations; each variable's term reference holds `makeRefG(p)` as upstream's (no
# export). The boundary stops the walk with `TV_BOUNDARY` — the caller redoes it on terms (a
# variable met through a keyed binding and through a cell must be one variable). NOT PORTED: as
# `term_variables_loop` (no `flags`, no signals, no `TV_NOSPACE`).
"The unbound variables the agenda `a` walks, each once, depth-first, as new term references; their count, `maxcount + 1` as soon as there are more, or `TV_BOUNDARY` (pl-prims.c)."
function term_variables_loop_cells(
    ld::PL_local_data{T}, a::cell_agenda, maxcount::Int
)::Int where {T}
    count = 0
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)
        if k == DU_CELL                                     # canBind(w)
            visitedWord_cells(ld, p) && continue
            count += 1
            count > maxcount && return count
            _new_term_ref_word!(ld, makeRefG(p))            # *valTermRef(v) = makeRefG(p)
        elseif k == DU_TERM
            return TV_BOUNDARY
        elseif k == DU_WORD && _is_gcompound(w)             # isTerm(w)
            c = valPtr(w)
            visitedWord_cells(ld, c) && continue            # visited(f)
            pushWorkCellAgenda!(a, arityFunctor(ld.functors, ld.gstack[c]), c + 1)
        end
    end
    return count
end

# PORT: pl-prims.c term_variables_to_termv as term_variables_to_termv_cells
# DIVERGES: returns `(count, v0)` where upstream writes `*vp`; the boundary (see
# `term_variables_loop_cells`) redoes the walk with the term-level `term_variables_to_termv`, its
# variables stored in new term references (counted in `cold_pairs`).
"The unbound variables of the term `t` references, depth-first, as term references from `v0`: `(count, v0)`, `count` = `maxcount + 1` if there are more (pl-prims.c)."
function term_variables_to_termv_cells(
    ld::PL_local_data{T}, t::term_t, maxcount::Int
)::Tuple{Int, Int} where {T}
    v0 = PL_new_term_refs(ld, 0)
    a = ld.walk_agenda
    initCellAgenda!(a, 1, -(t + 1))                         # initTermAgenda(&agenda, 1, valTermRef(t))
    count = term_variables_loop_cells(ld, a, maxcount)
    clearCellAgenda!(a)
    unvisit_cells(ld)                                       # unvisit_and_unfirst()
    if count == TV_BOUNDARY
        PL_reset_term_refs(ld, v0)
        ld.cold_pairs += 1
        count, vs = term_variables_to_termv(ld, t, maxcount)
        for v in vs
            setSlotValue!(ld, new_term_ref(ld) + 1, v)
        end
    end
    return (count, v0)
end

"`free_variables_loop_cells`' agenda entry for upstream's `&mark` (no location is it)."
const FV_MARK = typemin(Int)

# PORT: pl-prims.c free_variables_loop as free_variables_loop_cells
# DIVERGES: on locations; returns `(n, mname)` — `mname` the module's atom WORD, 0 for none — and
# stores the goal's word in term reference `goal` (upstream: `*valTermRef(goal) = *t`; a value-table
# value is referenced by its cell, which a slot holds); each free variable a new term reference
# holding `makeRefG(p)`. `&mark` is `FV_MARK`. The goal after `Module:` is dereferenced, as the term
# version's (upstream defect, register Q4). The boundary stops the walk with `TV_BOUNDARY` — the
# caller redoes it on terms.
"The free variables of the `Template^Goal` at location `l` (ISO 7.1.1.4; pl-prims.c), as new term references: `(n, module word)`, the goal in `goal`; `n` = `TV_BOUNDARY` at the boundary."
function free_variables_loop_cells(
    ld::PL_local_data{T}, l::Int, goal::term_t
)::Tuple{Int, word} where {T}
    a = ld.walk_agenda
    in_goal = false
    existential = false                                     # true when processing left of ^
    n = 0
    mname = word(0)
    initCellAgenda!(a, 1, l)
    while true
        t = nextCellAgendaNoDeRef!(a)
        t == 0 && break
        if t == FV_MARK                                     # t == &mark
            existential = false
            continue
        end
        k, w, p = _deref_loc(ld, t)                         # nextTermAgenda: deRef(t)
        @label again
        if k == DU_CELL                                     # canBind(*t)
            if !visitedWord_cells(ld, p) && !existential
                _new_term_ref_word!(ld, makeRefG(p))        # *valTermRef(v) = makeRefG(t)
                n += 1
            end
            continue
        end
        if k == DU_TERM
            clearCellAgenda!(a)
            return (TV_BOUNDARY, word(0))
        end
        if k == DU_WORD && _is_gcompound(w)                 # isTerm(*t)
            c = valPtr(w)
            fd = ld.gstack[c]                               # modified by visited
            if visitedWord_cells(ld, c)                     # visited(f)
                if !in_goal && !existential
                    ld.slots[goal + 1] = w                  # *valTermRef(goal) = *t
                    in_goal = true
                end
                continue
            end
            if !in_goal
                if fd == FUNCTOR_hat2 && !existential
                    pushWorkCellAgenda!(a, 1, c + 2)        # &f->arguments[1]
                    pushWorkCellAgenda!(a, 1, FV_MARK)      # &mark
                    pushWorkCellAgenda!(a, 1, c + 1)        # &f->arguments[0]
                    existential = true
                    continue
                end
                if fd == FUNCTOR_colon2 && !existential
                    k1, w1, _ = _deref_loc(ld, c + 1)       # deRef2(&f->arguments[0], a1)
                    (k1 == DU_WORD && isAtomW(w1)) && (mname = w1)
                    k, w, p = _deref_loc(ld, c + 2)         # t = &f->arguments[1] (see DIVERGES)
                    @goto again
                elseif !existential
                    ld.slots[goal + 1] = w                  # *valTermRef(goal) = *t
                    in_goal = true
                end
            end
            pushWorkCellAgenda!(a, arityFunctor(ld.functors, fd), c + 1)
            continue
        elseif !in_goal && !existential                     # non-term goal (atom or invalid)
            # needsRef(*t) ? makeRefG(t) : *t — a value-table word is held through its cell
            ld.slots[goal + 1] = (k == DU_VALUE && !isTaggedIntW(w)) ? makeRefG(p) : w
            in_goal = true
        end
    end
    clearCellAgenda!(a)
    return (n, mname)
end

# PORT: pl-prims.c free_variable_set as pl_free_variable_set3_va
# (PRED_IMPL("$free_variable_set", 3, free_variable_set, 0))
# DIVERGES: on the CELLS (L1d step 5): `free_variables_loop_cells` leaves the free variables in term
# references from `v0`, as upstream's; `PL_cons_functor(goal, FUNCTOR_colon2, m, goal)` is the
# compound laid out on the stack. No retry for local space (the local stack grows on demand). The
# boundary (`TV_BOUNDARY`) redoes it all on terms (`_free_variable_set_term`), counted in `cold_pairs`.
"`'\$free_variable_set'(+Template^GoalIn, -GoalOut, -VarTemplate)`: `GoalOut` is `GoalIn` without its `^`, `VarTemplate` is `v(V1, …)` of its free variables (pl-prims.c)."
function pl_free_variable_set3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    goal = PL_new_term_ref(ld)
    v0 = PL_new_term_refs(ld, 0)
    n, mname = free_variables_loop_cells(ld, -(A1 + 1), goal)
    unvisit_cells(ld)                                       # unvisit()
    if n == TV_BOUNDARY
        PL_reset_term_refs(ld, goal)
        ld.cold_pairs += 1
        return _free_variable_set_term(ld, A1, A2, A3)
    end

    if PL_unify_functor(ld, A3, mk_sym(T, :v), n)
        for i in 1:n
            PL_unify_arg(ld, i, A3, v0 + i - 1) || return FFALSE
        end

        if mname != 0                                       # PL_put_atom(m, mname);
            q = _alloc_compound!(ld, FUNCTOR_colon2, 2)     # PL_cons_functor(goal, FUNCTOR_colon2, m, goal)
            ld.gstack[q + 1] = mname
            _cell_link!(ld, q + 2, goal + 1)
            ld.slots[goal + 1] = consPtr(q, TAG_COMPOUND | STG_GLOBAL)
        end

        return PL_unify(ld, A2, goal) ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-prims.c free_variable_set as _free_variable_set_term
# TRANSITIONAL (L1d step 5, until L1f): `'$free_variable_set'/3` on TERMS — the boundary of the cells
# version. The free variables come back in a vector (upstream: term references), so there is no
# retry for local space; `PL_cons_functor(goal, FUNCTOR_colon2, m, goal)` is written out.
"`'\$free_variable_set'/3` on terms (pl-prims.c), for the boundary of `pl_free_variable_set3_va`."
function _free_variable_set_term(
    ld::PL_local_data{T}, A1::term_t, A2::term_t, A3::term_t
)::foreign_t where {T}
    goal = PL_new_term_ref(ld)
    vars = T[]

    g, mname = free_variables_loop(ld, slotValue(ld, A1 + 1), vars)
    g === nothing || (setSlotValue!(ld, goal + 1, g))
    n = length(vars)

    if PL_unify_functor(ld, A3, mk_sym(T, :v), n)
        v = PL_new_term_ref(ld)
        for i in 1:n
            setSlotValue!(ld, v + 1, vars[i])
            if !PL_unify_arg(ld, i, A3, v)
                return FFALSE
            end
        end

        if mname !== nothing            # PL_cons_functor(goal, FUNCTOR_colon2, m, goal)
            setSlotValue!(
                ld,
                goal + 1,
                mk_expr(
                    T, T[mk_sym(T, :(:)), mname, linkValI(ld, slotValue(ld, goal + 1))]
                )
            )
        end

        return PL_unify(ld, A2, goal) ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-prims.c skip_list as pl_skip_list3_va
# (PRED_IMPL("$skip_list", 3, skip_list, 0))
"`'\$skip_list'(-Length, +List, -Tail)`: the cells of `List` before its `Tail` — `[]`, a variable, or what else ends it (pl-prims.c)."
function pl_skip_list3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    len, k, _, tp = skip_list_cells(ld, -(A2 + 1))         # skip_list(valTermRef(A2), &tail) (L1e e4)
    if k != DU_TERM
        return if (unify_ptrs_cells(ld, -(A3 + 1), tp) && PL_unify_integer(ld, A1, len))
            FTRUE
        else
            FFALSE
        end
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    len, tail = skip_list(ld, slotValue(ld, A2 + 1))
    if unify_ptrs(ld, slotValue(ld, A3 + 1), tail) && PL_unify_integer(ld, A1, len)
        return FTRUE
    end

    return FFALSE
end

# PORT: pl-prims.c BeginPredDefs as PL_predicates_from_prims
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order (prims:6570-6677);
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
    PL_extension("ground", 1, pl_ground1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("compound", 1, pl_compound1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("callable", 1, pl_callable1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("==", 2, pl_equal2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("\\==", 2, pl_nonequal2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("same_term", 2, pl_same_term2_va, PL_FA_VARARGS),       # (L1f f1c)
    PL_extension("compare", 3, pl_compare3_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("?=", 2, pl_can_compare2_va, PL_FA_VARARGS),
    PL_extension("@<", 2, pl_std_lt2_va, PL_FA_ISO | PL_FA_VARARGS),       # (L1d step 1)
    PL_extension("@=<", 2, pl_std_leq2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("@>", 2, pl_std_gt2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("@>=", 2, pl_std_geq2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("functor", 3, pl_functor3_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("=..", 2, pl_univ2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("numbervars", 4, pl_numbervars4_va, PL_FA_VARARGS),     # (L1d step 7a, D-0016)
    PL_extension("term_variables", 2, pl_term_variables2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("term_variables", 3, pl_term_variables3_va, PL_FA_VARARGS),
    PL_extension("\$free_variable_set", 3, pl_free_variable_set3_va, PL_FA_VARARGS),
    PL_extension("unifiable", 3, pl_unifiable3_va, PL_FA_VARARGS),
    PL_extension("atom_number", 2, pl_atom_number2_va, PL_FA_VARARGS),
    PL_extension("\$skip_list", 3, pl_skip_list3_va, PL_FA_VARARGS),
    PL_extension("throw", 1, pl_throw1_va, PL_FA_ISO | PL_FA_VARARGS)
)

# ── fail/0, true/0 (since V9f: a meta-called `true`, as catch/3's recover goal often is) ─────────
# In a clause body they compile inline (`I_FAIL`, `I_TRUE`, since V9a); called as a TERM —
# `call(true)`, a variable goal — they resolve these predicates, registered from pl-ext.c's table
# (`foreigns`, src/pl-ext.jl).
# PORT: pl-prims.c pl_fail
"`fail/0` as a predicate (pl-prims.c): fails."
pl_fail(ld::PL_local_data{T}) where {T} = FFALSE

# PORT: pl-prims.c pl_true
"`true/0` as a predicate (pl-prims.c): succeeds."
pl_true(ld::PL_local_data{T}) where {T} = FTRUE
