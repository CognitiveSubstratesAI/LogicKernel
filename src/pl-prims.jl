# UPSTREAM: swipl-devel src/pl-prims.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
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

"`compare_descend_cells` result: no order exists between the two terms (pl-incl.h `CMP_INCOMPARABLE`)."
const CMP_INCOMPARABLE = 4

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
    length, k, w, _ = skip_list_cells(ld, -(list + 1))     # on the cells (L1e e4)
    k == DU_WORD && w == ld.atom_nil_w && return length    # isNil(*tail)
    errors && PL_error(ld, ERR_TYPE, mk_sym(T, :list), list)
    return k == DU_CELL ? -2 : -1                       # isVar(*tail) ? -2 : -1
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



# ── numbervars on the CELLS (L1d step 7a; the workspace's L1_plan/stageL1d_design.md §3g) ─────────
# Upstream's walk on locations: a variable cell is bound (`bindConst`, trailed) to a `'$VAR'(N)` laid
# out at gTop, its argument a WORD — so the singletons passes rewrite the ones made "ourselves" (above
# the mark's globaltop: upstream's address test) in place, untrailed, as upstream; a visited compound
# is MARKed on its functor cell (`visitedWord_cells`, on `ld.cycle_vstack`), cleared by `unvisit_cells`.

# PORT: pl-prims.c do_number_vars as do_number_vars_cells
# DIVERGES: on locations (`_deref_loc`'s), the one-sided cell agenda (`ld.walk_agenda`); `gtop` is the
# mark's `globaltop` (upstream passes the mark; positions, so "at or above the old top" is `> gtop`);
# `fw` the functor word of `options.functor/1` and `anon`/`var` the atom words of `_` and `var`
# (upstream: `options->functor`, `ATOM_anonvar`, `ATOM_var`). `numbered_check` reads a tagged integer
# (a value-table integer is past the tagged range: upstream's "cannot be bigger"). NOT PORTED:
# attributed variables (no cell holds one: `on_attvar` is never read), NV_EINTR (no signals), the
# global-stack overflow (`hasGlobalSpace`: the stack grows).
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
# looked up here (upstream's caller passes `PL_new_functor(name, 1)`). The error for
# `CONTAINS_ATTVAR` is kept for the shape (no attributed variables); no signals (`NV_EINTR`), no
# stack growth (`makeMoreStackSpace`: the stack grows on demand).
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

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# UNIFICATION (pl-prims.c)
# ═════════════════════════════════════════════════════════════════════════════════════════════════

# ── cyclic terms (O_CYCLIC) ──────────────────────────────────────────────────────────────────────
# Bart Demoen's algorithm, as pl-prims.c describes it: before unifying the arguments of two
# compounds, link the first to the second; a compound met again resolves through its link, and a
# pair that resolves to ONE compound is already being unified — so `X = f(X), Y = f(Y), X = Y`
# terminates. Links are reset whether the unification succeeds or fails. (`initCyclic` only sets a
# segstack's unit size upstream; there is nothing to port.) On the cells: `_link_cells!`,
# `_exit_cycles!`, `_cycle_root` (below).

# ── unify ────────────────────────────────────────────────────────────────────────────────────────
# PORT: pl-prims.c unify_simple_ptrs
# DIVERGES: on two CONSTANT terms — since L1f f3 its one caller is the VM's constant test
# (`_unify_const_loc`: a clause's literal against an atom's or a value word's term), and a term
# variable can be bound nowhere (the cells are the only store: `unify_simple_cells` binds), so the
# variable arms are gone. "The same cell" (`t1 == t2`) is `===`; atomic data: a symbol by `sym_key`
# (upstream: the same word), a grounded value by the term type's `gnd_equal` (upstream: the same
# word, or `equalIndirect` on the bits — the reference type's `gnd_equal` is that identity).
"""
Unify two constant terms (pl-prims.c): `BOOLEX_TRUE` when they are the same constant, else
`BOOLEX_FALSE`; `DO_COMPOUND` when both are compounds.
"""
function unify_simple_ptrs(ld::PL_local_data{T}, t1::T, t2::T)::boolex_t where {T}
    if t1 === t2
        return BOOLEX_TRUE
    end
    k1 = kind(t1)
    if k1 !== kind(t2)                              # tagex(w1) != tagex(w2)
        return BOOLEX_FALSE
    end
    if k1 === SYM
        return sym_key(t1) == sym_key(t2) ? BOOLEX_TRUE : BOOLEX_FALSE
    elseif k1 === GND
        return gnd_equal(t1, t2) ? BOOLEX_TRUE : BOOLEX_FALSE
    end
    return DO_COMPOUND
end

# ── unification on the CELLS (L1c sub-commit 4: the hot half of L1d) ─────────────────────────────
# Upstream's `Word` pointer is a LOCATION here: a global position (`loc > 0`), or a local-stack slot
# (`loc = -i` for slot `i`; term reference `t` is slot `t + 1`). A slot is never an unbound variable
# — it holds a reference to a cell, an atom or compound word, or its side value — so dereferencing
# ends in a global cell or a value, and only GLOBAL cells are ever bound: upstream's local stack lies
# above its global stack and a variable binds the younger to the older, so a local cell points at a
# global one and never the reverse (user, 2026-10-15; test_unify_cells.jl pins it). A slot's side
# value (`SLOT_VALUE`, D-0024's indirect) is always ground and reads as a VALUE, its side word
# (`_side_word`, f3-1); since L1f f3 every location dereferences to a cell or a word.
"`_deref_loc`: an unbound cell, at the position returned."
const DU_CELL = 0x01
"`_deref_loc`: an atom or a compound word, returned."
const DU_WORD = 0x02
"`_deref_loc`: a VALUE word (returned): a value-table word whose entry is a value, in the cell at the position, a tagged integer (L1d step 4; in a slot, position 0), or a slot's grounded side value as its side word (`_side_word`, f3-1; position 0)."
const DU_VALUE = 0x03
"`_deref_loc`: an ATTRIBUTED VARIABLE (AV1; pl-data.h `TAG_ATTVAR`): its word, in the cell at the position returned — `canBind` but not `isVar` (pl-data.h); every caller decides which of the two it asks, as upstream's word tests do."
const DU_ATTVAR = 0x04

# ORIGINAL: upstream's `deRef` (pl-data.h) on a LOCATION (above); the result says what was found,
# as the word tests on `*p` do after upstream's `deRef`. Since AV1 (audit D-0122 condition 1) the last
# branch ASSERTS a known kind: an attributed variable is `DU_ATTVAR`, a value-table word `DU_VALUE`, and
# any other word an internal error — before AV1 every unknown word was read as a value-table word.
"Location `loc` dereferenced: `(kind, word, position)`, see `DU_*` (pl-data.h `deRef`)."
@inline function _deref_loc(
    ld::PL_local_data{T}, loc::Int
)::Tuple{UInt8, word, Int} where {T}
    if loc < 0
        w = ld.slots[-loc]
        if !isRef(w)
            w == SLOT_VALUE && return (DU_VALUE, _side_word(-loc), 0)  # a side value (f3-1, D-0110)
            (isAtomW(w) || _is_gcompound(w)) && return (DU_WORD, w, 0)
            isTaggedIntW(w) && return (DU_VALUE, w, 0)                  # L1d step 4
            if _is_vword(w)                                             # L1e e1: a value-table word
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
        elseif isAttVar(c)                          # an attributed variable (AV1)
            return (DU_ATTVAR, c, p)
        else                                        # a value-table word, asserted (AV1)
            _is_vword(c) || throw(_cell_word_error(p, c))
            return (DU_VALUE, c, p)
        end
    end
end

# ORIGINAL (L1c-6; SPLIT in AV1b, as upstream's two tests): `deRef(p); canBind(*p)` for slot `i` on the
# WORDS — I_VAR's and I_NONVAR's test (pl-vmi.c): an unbound cell or an attributed variable is a variable.
"Whether slot `i`, dereferenced, is unbound or attributed (pl-vmi.c I_VAR's `canBind`, on the words)."
@inline function _slot_can_bind(ld::PL_local_data{T}, i::Int)::Bool where {T}
    k, _, _ = _deref_loc(ld, -i)
    return k == DU_CELL || k == DU_ATTVAR                   # canBind(*p)
end

# ORIGINAL (L1c-6; SPLIT in AV1b): `deRef(p); isVar(*p)` for slot `i` on the WORDS — I_CATCH's and
# I_CALLCLEANUP's test (pl-vmi.c): only an unbound cell; an attributed variable is not `isVar`.
"Whether slot `i`, dereferenced, is an unbound cell (pl-vmi.c I_CATCH's `isVar`, on the words)."
@inline function _slot_is_var(ld::PL_local_data{T}, i::Int)::Bool where {T}
    k, _, _ = _deref_loc(ld, -i)
    return k == DU_CELL                                     # isVar(*p)
end

# ORIGINAL: `ARGP` as a location for `do_unify_cells`: a slot or a global cell.
"The location `ARGP` points at."
@inline _argp_loc(a::argp_t)::Int = a.form == ARGP_SLOT ? -(a.pos + 1) : a.pos

# PORT: pl-prims.c unify_simple_ptrs as unify_simple_cells
# DIVERGES: on dereferenced locations. Two unbound cells: the HIGHER position is bound to the
# lower's reference (upstream: by address, "always point downwards"; no variable lives on the local
# stack, so no fresh global variable for two local ones). A value-table word is upstream's indirect:
# shared by binding, two compared by the term type's `gnd_equal` (`equalIndirect`: SWI's identity in
# the reference type, `1 = 1.0` fails). An attributed variable (AV2): a plain variable is bound to a
# reference to it, as upstream's `makeRefG`; an attributed variable against anything else is
# `assignAttVar` (AV3), bound with a wakeup. Its space test, upstream's `hasGlobalSpace(0)` →
# `overflowCode(0)`, is `ensureGlobalSpace(ld, 0)`, which RAISES the overflow (the stack grows on demand,
# so only the limit can refuse), and the unification fails: `do_unify_cells` has no overflow codes to
# break on (a `GLOBAL_OVERFLOW` here would read as `DO_COMPOUND`).
"Unify two dereferenced locations when neither is a compound; `DO_COMPOUND` when both are (pl-prims.c)."
function unify_simple_cells(
    ld::PL_local_data{T}, k1::UInt8, w1::word, p1::Int, k2::UInt8, w2::word, p2::Int
)::boolex_t where {T}
    if k1 == DU_CELL
        if k2 == DU_CELL
            p1 == p2 && return BOOLEX_TRUE          # t1 == t2
            if p1 > p2                              # SWAPW(t1, t2)
                p1, p2 = p2, p1
            end
            _bind_const!(ld, p2, makeRefG(p1))      # Trail(t2, makeRefG(t1)): always point downwards
            return BOOLEX_TRUE
        end
        if k2 == DU_ATTVAR                          # if ( isAttVar(w2) ) w2 = makeRefG(t2)
            _bind_const!(ld, p1, makeRefG(p2))      # Trail(t1, w2)
            return BOOLEX_TRUE
        end
        _bind_const!(ld, p1, _value_word!(ld, w2))  # Trail(t1, w2) (a side word: its value's word, f3-1)
        return BOOLEX_TRUE
    end
    if k2 == DU_CELL
        if k1 == DU_ATTVAR                          # if ( isAttVar(w1) ) w1 = makeRefG(t1)
            _bind_const!(ld, p2, makeRefG(p1))      # Trail(t2, w1)
            return BOOLEX_TRUE
        end
        _bind_const!(ld, p2, _value_word!(ld, w1))  # Trail(t2, w1)
        return BOOLEX_TRUE
    end
    (k1 == DU_ATTVAR && k2 == DU_ATTVAR && p1 == p2) && return BOOLEX_TRUE   # t1 == t2: the same attvar
    if k1 == DU_ATTVAR                              # if ( isAttVar(w1) )
        ensureGlobalSpace(ld, 0) || return BOOLEX_FALSE     # if ( !hasGlobalSpace(0) ) return overflowCode(0)
        assignAttVar(ld, p1, (k2, w2, p2))          # assignAttVar(t1, t2)
        return BOOLEX_TRUE
    end
    if k2 == DU_ATTVAR                              # if ( isAttVar(w2) )
        ensureGlobalSpace(ld, 0) || return BOOLEX_FALSE     # if ( !hasGlobalSpace(0) ) return overflowCode(0)
        assignAttVar(ld, p2, (k1, w1, p1))          # assignAttVar(t2, t1)
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
# upstream links every pair (a link is one word write).
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

# PORT: pl-prims.c ph_acyclic_mark as ph_acyclic_mark_cells
# DIVERGES: positions for upstream's `Functor`s — a chain's `head` and `tail` are the compounds'
# positions, `p` the location of the argument to resume (0: NULL); the chains' segstack is
# `ld.acyclic_chains`, reused. A compound of no arguments ends a chain (upstream reads its
# `arguments - 1`). No MEMORY_OVERFLOW.
"""
    ph_acyclic_mark_cells(ld, top) -> Int

Whether the compound at global position `top` is acyclic (pl-prims.c `ph_acyclic_mark`): `1` yes,
`0` no. Leaves marks on the functor cells for `ph_acyclic_unmark_cells`.
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
# DIVERGES: on a location. No MEMORY_OVERFLOW.
"Whether the term at location `l` is acyclic (pl-prims.c `is_acyclic`)."
function is_acyclic_cells(ld::PL_local_data{T}, l::Int)::Bool where {T}
    k, w, _ = _deref_loc(ld, l)
    (k == DU_WORD && _is_gcompound(w)) || return true
    @assert isempty(ld.cycle_cells) "is_acyclic_cells: a cycle link is in place (exitCyclic first)"
    q = valPtr(w)
    rc = ph_acyclic_mark_cells(ld, q)
    ph_acyclic_unmark_cells(ld, q)
    return rc == 1
end

# ── FACTORIZE (pl-prims.c), since group F (D-0123): the writer's `@(Template, Substitutions)` ──
# Factorizing a term based on its internal sharing, on the CELLS as upstream's four passes
# (pl-prims.c:1256-1276): `scan_shared` marks every compound it visits (MARK_MASK on the functor
# cell) and FIRST_MASK on those met twice, listing `Var = Term` for each; `reverse_factor_pointers`
# puts a shared compound's functor word into its `Var` and a reference to it into the functor cell;
# `link_shared` links every location of a shared compound into a reference chain (assignments
# trailed: `TrailAssignment!`); `restore_shared_functors` puts the functor words back and makes the
# end of each chain a real variable. MARK_MASK and FIRST_MASK are bits 5 and 6, free in every word
# (see `is_acyclic_cells`). A location is `_deref_loc`'s (a global position, or `-i` for slot `i`:
# only the walk's start, a fresh wrapper, is a slot). The agenda is a fresh `cell_agenda` per pass.

# ORIGINAL: upstream's `deRef(p)` returning the LOCATION it ends at (a slot that holds no reference
# stays the slot), where `_deref_loc` returns the word too and 0 for a slot's own word.
"The location `l` dereferences to: the last reference followed, or `l` itself."
@inline function _fz_deref(ld::PL_local_data, l::Int)::Int
    if l < 0
        w = ld.slots[-l]
        isRef(w) || return l
        l = unRef(w)
    end
    while true
        c = ld.gstack[l]
        isRef(c) || return l
        l = unRef(c)
    end
end

# ORIGINAL: `*p` of a location (a slot's word, or a global cell's).
"The word at location `l`."
@inline _fz_word(ld::PL_local_data, l::Int)::word = l < 0 ? ld.slots[-l] : ld.gstack[l]

# PORT: pl-prims.c scan_shared
# DIVERGES: `t` and `vart` are locations; returns `(rc, count)`, where upstream sets `*count`.
"""
    scan_shared(ld, t, vart) -> (boolex_t, count)

Mark the compounds of the term at location `t` (pl-prims.c): MARK_MASK on each, FIRST_MASK on one
met twice, for which a `[Var = Term|…]` cell is appended at location `vart`. The count is the
places that must be shared; `GLOBAL_OVERFLOW` when the list's cells do not fit.
"""
function scan_shared(
    ld::PL_local_data{T}, t::Int, vart::Int
)::Tuple{boolex_t, Int} where {T}
    agenda = cell_agenda(0, 0, NTuple{2, Int}[])
    shared = 0
    equals2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(=))), 2)

    initCellAgenda!(agenda, 1, t)                           # initTermAgenda(&agenda, 1, t)
    while true
        l = nextCellAgendaNoDeRef!(agenda)                  # p = nextTermAgenda(&agenda)
        l == 0 && break
        p = _fz_deref(ld, l)
        w = _fz_word(ld, p)
        if _is_gcompound(w)                                 # isTerm(*p)
            q = valPtr(w)                                   # Functor f = valueTerm(*p)
            d = ld.gstack[q]                                # Word d = &f->definition

            if (d & MARK_MASK) != 0                         # is_marked(d)
                if (d & FIRST_MASK) == 0                    # !is_first(d)
                    v = allocGlobalNoShift(ld, 6)
                    v == 0 && return (GLOBAL_OVERFLOW, shared)

                    ld.gstack[v] = ld.functor_dot2          # v[0] = FUNCTOR_dot2
                    ld.gstack[v + 1] = consPtr(v + 3, TAG_COMPOUND | STG_GLOBAL)
                    ld.gstack[v + 2] = ld.atom_nil_w        # v[2] = ATOM_nil
                    ld.gstack[v + 3] = equals2              # v[3] = FUNCTOR_equals2
                    ld.gstack[v + 4] = word(0)              # v[4] = 0: for now
                    ld.gstack[v + 5] = consPtr(q, TAG_COMPOUND | STG_GLOBAL)

                    c = consPtr(v, TAG_COMPOUND | STG_GLOBAL)
                    if vart < 0                             # *vart = consPtr(&v[0], …)
                        ld.slots[-vart] = c
                    else
                        ld.gstack[vart] = c
                    end
                    vart = v + 2

                    ld.gstack[q] = d | FIRST_MASK           # set_first(d)
                    shared += 1                             # this is already the second one
                end
                shared += 1
            else
                arity = arityFunctor(ld.functors, d)

                pushWorkCellAgenda!(agenda, arity, q + 1)   # pushWorkAgenda(&agenda, arity, f->arguments)
                ld.gstack[q] = d | MARK_MASK                # set_marked(d)
            end
        end
    end
    clearCellAgenda!(agenda)

    return (BOOLEX_TRUE, shared)
end

# PORT: pl-prims.c unscan_shared
# DIVERGES: `t` is a location.
"Clear the marks `scan_shared` left on the term at location `t` (pl-prims.c): needed to restore if we run out of stack."
function unscan_shared(ld::PL_local_data{T}, t::Int)::Nothing where {T}
    agenda = cell_agenda(0, 0, NTuple{2, Int}[])

    initCellAgenda!(agenda, 1, t)
    while true
        l = nextCellAgendaNoDeRef!(agenda)
        l == 0 && break
        w = _fz_word(ld, _fz_deref(ld, l))
        if _is_gcompound(w)
            q = valPtr(w)
            d = ld.gstack[q]

            if (d & MARK_MASK) != 0
                ld.gstack[q] = d & ~(MARK_MASK | FIRST_MASK)   # clear_marked(d); clear_first(d)
                arity = arityFunctor(ld.functors, d)
                pushWorkCellAgenda!(agenda, arity, q + 1)
            end
        end
    end
    clearCellAgenda!(agenda)
    return nothing
end

# PORT: pl-prims.c reverse_factor_pointers
# DIVERGES: `vars` is a location.
"For each `Var = Term` of the list at location `vars`: Term's functor word into Var, a marked reference to Var into Term's functor cell (pl-prims.c)."
function reverse_factor_pointers(ld::PL_local_data{T}, vars::Int)::Nothing where {T}
    while _fz_word(ld, vars) != ld.atom_nil_w
        v = valPtr(_fz_word(ld, vars))                      # Word v = (Word)valueTerm(*vars)
        t = valPtr(ld.gstack[v + 5])                        # Functor t = valueTerm(v[5])

        ld.gstack[v + 4] = ld.gstack[t] & ~(MARK_MASK | FIRST_MASK)    # v[4] is the variable
        ld.gstack[t] = makeRefG(v + 4) | MARK_MASK | FIRST_MASK

        vars = v + 2
    end
    return nothing
end

# PORT: pl-prims.c restore_shared_functors
# DIVERGES: `vars` is a location.
"For each `Var = Term` of the list at location `vars`: Term's functor word back from the end of Var's chain, which becomes a variable (pl-prims.c)."
function restore_shared_functors(ld::PL_local_data{T}, vars::Int)::Nothing where {T}
    while _fz_word(ld, vars) != ld.atom_nil_w
        v = valPtr(_fz_word(ld, vars))
        t = valPtr(ld.gstack[v + 5])
        p = _fz_deref(ld, v + 4)                            # Word p = &v[4]; deRef(p)

        ld.gstack[t] = ld.gstack[p]                         # t->definition = *p
        ld.gstack[p] = word(0)                              # setVar(*p)

        vars = v + 2
    end
    return nothing
end

# PORT: pl-prims.c link_shared
# DIVERGES: `t` is a location; a location of a shared compound is a global position (only the
# walk's start, never shared, is a slot), asserted.
"Link every location of a shared compound of the term at location `t` into its reference chain, and unmark the others (pl-prims.c)."
function link_shared(ld::PL_local_data{T}, t::Int)::Nothing where {T}
    agenda = cell_agenda(0, 0, NTuple{2, Int}[])

    initCellAgenda!(agenda, 1, t)
    while true
        l = nextCellAgendaNoDeRef!(agenda)
        l == 0 && break
        p = _fz_deref(ld, l)
        w = _fz_word(ld, p)
        if _is_gcompound(w)
            q = valPtr(w)
            d = ld.gstack[q]

            if isRef(d)                                     # shared term
                v = _fz_deref(ld, unRef(d & ~(FIRST_MASK | MARK_MASK)))   # v = unRef(…); deRef(v)

                if (d & MARK_MASK) != 0                     # is_marked(d)
                    arity = arityFunctor(ld.functors, ld.gstack[v])   # arityFunctor(*v)
                    pushWorkCellAgenda!(agenda, arity, q + 1)
                end

                @assert p > 0 "link_shared: a shared compound's location is a slot"
                if v < p
                    TrailAssignment!(ld, p)
                    ld.gstack[p] = makeRefG(v)              # *p = makeRefG(v)
                else
                    TrailAssignment!(ld, p)
                    ld.gstack[p] = ld.gstack[v]             # *p = *v
                    ld.gstack[v] = makeRefG(p)              # *v = makeRefG(p)
                end
            elseif (d & MARK_MASK) != 0                     # is_marked(d)
                fun = d & ~(FIRST_MASK | MARK_MASK)

                ld.gstack[q] = d & ~MARK_MASK               # clear_marked(d)
                arity = arityFunctor(ld.functors, fun)
                pushWorkCellAgenda!(agenda, arity, q + 1)
            end
        end
    end
    clearCellAgenda!(agenda)
    return nothing
end

# PORT: pl-prims.c PL_factorize_term
# DIVERGES: the local data is an argument (upstream: `GET_LD`); the wrapper `'var'(Term)` is made
# with `PL_unify_functor` and `PL_unify_arg` (upstream's `PL_unify_term`). No garbage collector or
# stack shift to make room (`makeMoreStackSpace`): a global overflow — the list's cells, or the cells
# `TrailAssignment!` saves old values in (`ensureGlobalSpace`) — is raised after the marks are
# cleared and the frame discarded, and the call fails; the trail grows on demand (no
# TRAIL_OVERFLOW). No `checkStacks` (`CHK_SECURE` is `O_DEBUG` only).
"""
    PL_factorize_term(ld, term, template, factors) -> Bool

Unify `template` with the term `term` references, every subterm it shares replaced by a variable,
and `factors` with the list of `Var = Subterm` for those (pl-prims.c): a cyclic term becomes the
acyclic `Template` and `Substitutions` of `@(Template, Substitutions)`.
"""
function PL_factorize_term(
    ld::PL_local_data{T}, term::term_t, template::term_t, factors::term_t
)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    fid == 0 && return false
    wrapped = PL_new_term_ref(ld)
    vars = PL_new_term_ref(ld)
    (
        PL_unify_functor(ld, wrapped, mk_sym(T, :var), 1) &&    # PL_FUNCTOR, FUNCTOR_var1,
        PL_unify_arg(ld, 1, wrapped, term)                      # PL_TERM, term
    ) || return false

    PL_put_nil(ld, vars)
    t = -(wrapped + 1)                                          # t = valTermRef(wrapped)

    rc, count = scan_shared(ld, t, -(vars + 1))
    if rc != BOOLEX_TRUE || !ensureGlobalSpace(ld, count)       # tTop + 2*count > tMax; gTop + count > gMax
        unscan_shared(ld, t)
        PL_discard_foreign_frame(ld, fid)
        rc != BOOLEX_TRUE && raiseStackOverflow(ld, rc)         # makeMoreStackSpace(rc, …): no GC
        return false
    end

    reverse_factor_pointers(ld, -(vars + 1))
    link_shared(ld, t)
    restore_shared_functors(ld, -(vars + 1))
    PL_close_foreign_frame(ld, fid)

    _PL_get_arg(ld, 1, wrapped, wrapped)
    return PL_unify(ld, template, wrapped) && PL_unify(ld, factors, vars)
end

# ── the standard order on CELLS (L1d step 1; the workspace's L1_plan/stageL1d_design.md §3) ──────
# Locations as `do_unify_cells`'s (a global position, or `-i` for slot `i`). The order is the term
# compare's, so a sort or a `==` gives the same answer on either path: variables by POSITION
# (upstream by address), atomic values by the term type's ladder (`compare_primitives` on the stored
# value or the atom's symbol — no export), compounds by arity, then `$expr/n` before symbol functors
# (Q2), then name, then the arguments left to right.

"The tag rank of a dereferenced location: a variable (attributed too) 0, atomic 1, compound 2 (`_tag_rank`)."
@inline _loc_rank(k::UInt8, w::word)::Int =
    (k == DU_CELL || k == DU_ATTVAR) ? 0 : ((k == DU_WORD && _is_gcompound(w)) ? 2 : 1)

"The atomic TERM a dereferenced atomic location holds (an atom's symbol, a stored value): no export."
@inline function _loc_atomic(ld::PL_local_data{T}, k::UInt8, w::word)::T where {T}
    # (the long form: `@inline f(…)::T where {T} = …` left `::T` at top level — did not load, 2026-10-16)
    return k == DU_VALUE ? _value_term(ld, w) : _atom_value(ld, w)   # a tagged word too (L1d-4)
end

# PORT: pl-prims.c compare_primitives as compare_primitives_cells
# DIVERGES: (1) two unbound cells are ordered by POSITION, upstream's address order
# (`SCALAR_TO_CMP(p1, p2)`; F3B f3b-2): allocation is LIFO at `gTop + 1`, so of two live cells the
# higher one is the younger (pl-alloc.jl `allocGlobalCells!`). (2) On two dereferenced locations; no
# CMP_MODE_PARTIAL (not ported). (3) An attributed variable (AV3, D-0122 condition 4: the rows
# `==`, `\==`, compare/3 on one) is a variable here as upstream's TAG_ATTVAR (pl-prims.c:1859-1866):
# against an unbound cell or another attributed variable by POSITION, as (1); `==` NOTEQ.
"One step of the cell walk (pl-prims.c `compare_primitives`): decided, or `CMP_COMPOUND`."
function compare_primitives_cells(
    ld::PL_local_data{T}, k1::UInt8, w1::word, p1::Int, k2::UInt8, w2::word, p2::Int,
    mode::Int
)::Int where {T}
    if (k1 == DU_CELL || k1 == DU_ATTVAR) && (k2 == DU_CELL || k2 == DU_ATTVAR)   # TAG_VAR, TAG_ATTVAR
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
# through a binding; returns `(rc, linked)`.
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
# (upstream: the `Functor` cells); returns `(rc, l1, l2)` where upstream writes `*c1`, `*c2`. A
# `$expr/0` pair (no argument to descend into) is equal. No `CMP_ERROR` from the argument tests (no
# memory overflow).
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
# DIVERGES: NOT PORTED: the `incomparable` flag's
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
`1`; with `eq` `0` or `CMP_NOTEQ`.
"""
compareStandard_cells(ld::PL_local_data{T}, l1::Int, l2::Int, eq::Bool) where {T} =
    compare_std_cells(ld, l1, l2, eq ? CMP_MODE_EQUAL : CMP_MODE_ORDER)

# ORIGINAL: pl-vmi.c B_EQ_VC's `*v1 == c` on a location: the atomic constant `c` (a clause literal,
# a term) against what the location holds — an unbound cell or a compound is never identical to it;
# an atom word or a stored value by `compare_primitives` in equality mode (SWI's identity).
"Whether the location `l` holds a term identical to the atomic term `c` (pl-vmi.c B_EQ_VC)."
function _identical_atomic(ld::PL_local_data{T}, l::Int, c::T)::Bool where {T}
    k, w, _ = _deref_loc(ld, l)
    (k == DU_CELL || k == DU_ATTVAR) && return false   # an attributed variable too (AV3): never `*v1 == c`
    k == DU_WORD && _is_gcompound(w) && return false
    return compare_primitives(_loc_atomic(ld, k, w), c, CMP_MODE_EQUAL) == CMP_EQUAL
end

# ── the occurs check on CELLS (L1d step 2; the workspace's L1_plan/stageL1d_design.md) ──────────
# PORT: pl-prims.c var_occurs_in as var_occurs_in_cells
# DIVERGES: `v` is a global POSITION (the variable's cell, or — asked by the trail walk — the cell
# holding a binding's value), `t` a location; a visited compound gets FIRST_MASK on its functor cell
# exactly as upstream (bit 6, which the functor's index and arity ignore), the positions stacked to
# clear it (`occurs_cells`, upstream's `visited` segstack); the walk is the cell agenda on one side.
# No MEMORY_OVERFLOW.
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
        if k == DU_WORD && _is_gcompound(w)             # isTerm(*t)
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

# PORT: pl-prims.c PL_var_occurs_in
# DIVERGES: the local data is an argument; no overflow code to raise (`var_occurs_in_cells` returns a
# Bool: no MEMORY_OVERFLOW). Since group F (D-0123): the writer's `reunify_acyclic_substitutions`.
"Whether the variable term reference `var` holds occurs in the term `value` references (pl-prims.c)."
function PL_var_occurs_in(ld::PL_local_data{T}, var::term_t, value::term_t)::Bool where {T}
    _, _, v = _deref_loc(ld, -(var + 1))                # Word v = valTermRef(var); deRef(v)
    return var_occurs_in_cells(ld, v, -(value + 1))
end

# PORT: pl-prims.c unify_with_occurs_check as unify_with_occurs_check_cells
# DIVERGES: on locations; no `onStack(global, …)` test (every variable is a global cell); the trail
# walk reads global positions; the failure's value is its dereferenced word, read before `Undo!`
# (upstream copies `*p2` to a fresh cell: see `failed_unify_with_occurs_check_cells`), and the error
# is built on the cells (f3b-4). An attributed variable is `canBind` (since AV2: its occurs test, row
# av22). The trail walk skips an attvar assignment's wakeup entries (since AV3, pl-prims.c:720-725):
# the tail's assignment, then the head's or the old tail cell's, each two entries when a value entry
# (`registerWakeup` trails both: `NO_MARK_BAR` is above every cell).
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
    if k1 == DU_CELL || k1 == DU_ATTVAR                 # canBind(*t1) (AV2: an attributed variable)
        if var_occurs_in_cells(ld, p1, l2)
            return failed_unify_with_occurs_check_cells(
                ld, (k1, w1, p1), (k2, w2, p2), mode
            )
        end
        return do_unify_cells(ld, l1, l2)
    end
    if k2 == DU_CELL || k2 == DU_ATTVAR                 # canBind(*t2) (AV2)
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
                e = ld.trail[tt]                        # p = (--tt)->address
                tt -= 1                                 # if ( isTrailVal((--tt)->address) ) tt--
                isTrailVal(ld.trail[tt]) && (tt -= 1)   #   tail of wakeup list
                tt -= 1                                 # if ( isTrailVal((--tt)->address) ) tt--
                isTrailVal(ld.trail[tt]) && (tt -= 1)   #   head of wakeup list
            end
            pos = _trail_pos(e)
            _, _, q = _deref_loc(ld, pos)               # deRef2(p, p2)
            if var_occurs_in_cells(ld, q, q)
                if mode == OCCURS_CHECK_ERROR           # *t = *p2 — read before the Undo (see above)
                    val = _deref_loc(ld, pos)
                    Undo!(ld, m)
                    failed_unify_with_occurs_check_cells(ld, _deref_loc(ld, pos), val, mode)
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

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# THE BUILT-INS (V5a2, decision 5) — pl-prims.c's PRED_IMPLs of the predicates ported above, under
# upstream's C names (`PRED_IMPL(name, arity, fname, flags)` is `pl_<fname><arity>_va`), each a
# line-for-line port over term references: `A1` is `PL__t0`, `A2` is `PL__t0 + 1`, … — a built-in's
# handles ARE its frame's argument slots.
# ═════════════════════════════════════════════════════════════════════════════════════════════════


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
# DIVERGES: on LOCATIONS (L1e e4): `unify_ptrs_cells`. Since AV4 the wakeup runs (`foreignWakeup`);
# from AV3 to AV4 a pending one was refused (a `NotPortedError` naming AV4).
"Whether the terms at locations `l1`, `l2` can be unified, without doing so (pl-prims.c `can_unify`); `ex` gets an exception."
function can_unify_cells(ld::PL_local_data{T}, l1::Int, l2::Int, ex::term_t)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    if fid != 0
        handle_exception = ex == 0
        ex == 0 && (ex = PL_new_term_ref(ld))
        if unify_ptrs_cells(ld, l1, l2) && foreignWakeup(ld, ex)   # unify_ptrs(…) && foreignWakeup(ex)
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
# decide; a compound or an attributed variable on either side goes to the full check.
"`\\=/2` (pl-prims.c): the arguments cannot unify; an occurs-check error is raised again."
function pl_not_unify2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    k1, w1, _ = _deref_loc(ld, -(A1 + 1))                    # deRef(p1); w1 = *p1 (L1e e4: the cells)
    k2, w2, _ = _deref_loc(ld, -(A1 + 2))                    # deRef(p2); w2 = *p2
    if k1 == DU_CELL || k2 == DU_CELL                   # isVar(w1) || isVar(w2)
        ld.prolog_flag_occurs_check == OCCURS_CHECK_FALSE && return FFALSE   # can unify
    elseif k1 == k2 && w1 == w2                         # w1 == w2
        return FFALSE
    elseif k1 == DU_ATTVAR || k2 == DU_ATTVAR           # isAttVar(w1) || isAttVar(w2): goto full_check
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
# DIVERGES (since L1f f1c): on the words (`_deref_loc`): an unbound cell is the same term only as the same cell;
# equal words; two indirects — value-table words or a slot's side words (f3-1) — by `equalIndirect`:
# the term type's `gnd_equal` on their values (SWI's identity: `1` and `1.0` differ), so two equal big
# integers are the same term wherever they are held, as swipl's (audit D-0117 (a)).
"Whether term references `t1` and `t2` hold the same term — the same variable or compound, or equal atomic values (pl-prims.c)."
function PL_same_term(ld::PL_local_data{T}, t1::term_t, t2::term_t)::Bool where {T}
    k1, w1, p1 = _deref_loc(ld, -(t1 + 1))                  # deRef(t1)
    k2, w2, p2 = _deref_loc(ld, -(t2 + 1))                  # deRef(t2)
    k1 == DU_CELL && return k2 == DU_CELL && p1 == p2       # isVar(*t1): t1 == t2
    w1 == w2 && return true                                 # *t1 == *t2
    if (_is_vword(w1) || _is_side_word(w1)) &&              # isIndirect(*t1) &&
        (_is_vword(w2) || _is_side_word(w2))                 # isIndirect(*t2)
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
    # the order's argument on the WORDS (L1d step 1): `Word d = valTermRef(A1); deRef(d)` — a cell that
    # `canBind` (unbound, or since AV1b attributed) takes the answer's atom word (`PL_unify_atom(A1, a)`:
    # `bindConst` on the cell, no term read)
    k, w, dp = _deref_loc(ld, -(A1 + 1))
    p1, p2 = -(A2 + 1), -(A2 + 2)                            # Word p1 = valTermRef(A2); p2 = p1+1 (cells, L1d)
    given = !(k == DU_CELL || k == DU_ATTVAR)                # canBind(*d) ⇒ a = 0 (AV1b)
    kk = UInt64(0)
    if given
        if k == DU_WORD && isAtomW(w)                       # isAtom(*d)
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
    bindConst(ld, dp, _atom_word!(ld, mk_sym(T, a)))         # PL_unify_atom(A1, a) on the cell
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


# ── unifiable/3 on the CELLS (L1e e4; the workspace's L1_plan/stageL1e_design.md §4) ──────────────
# PORT: pl-prims.c unifiable_occurs_check as unifiable_occurs_check_cells
# DIVERGES: on term references, the variable's cell and the term's location (`var_occurs_in_cells`, L1d
# step 2); the error built on the cells (`failed_unify_with_occurs_check_cells`, f3b-4). Both
# callers pass a variable (`PL_is_variable`), so `t1` is an unbound cell.
"Whether binding the variable `t1` references to the term `t2` references passes the occurs check (pl-prims.c)."
function unifiable_occurs_check_cells(
    ld::PL_local_data{T}, t1::term_t, t2::term_t
)::Bool where {T}
    flag = ld.prolog_flag_occurs_check
    flag == OCCURS_CHECK_FALSE && return true
    k, w, p = _deref_loc(ld, -(t1 + 1))
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
        # ORIGINAL (audit D-0162 item 3): the bar is still off when the unification returns — so every
        # wakeup-list cell `registerWakeup` changed was trailed as an address AND a value entry, which is
        # why unifiable's restore never takes its address-entry branch (AV3-P7 equivalent, D-0100).
        @assert ld.mark_bar == NO_MARK_BAR "unify_all_trail_ptrs: the bar was on during the unification"
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

# ORIGINAL (AV3): one restore of `unifiable`'s attvar branch (pl-prims.c, "restore tail/head of wakeup
# list"): the trail's top entry is a value entry — the cell below it gets its old value back — or an
# address entry, whose cell is cleared (`setVar`); the entries are popped (upstream: `tt--`, then
# `tTop = m.trailtop`).
"Undo one wakeup-list assignment of an attvar binding at the trail's top (pl-prims.c `unifiable`)."
function _unifiable_restore_wakeup_cell!(ld::PL_local_data)::Nothing
    e = pop!(ld.trail)                                        # p = (--tt)->address
    if isTrailVal(e)                                          # if ( isTrailVal(p) )
        a = pop!(ld.trail)                                    #   tt--
        ld.gstack[_trail_pos(a)] = ld.gstack[trailValP(e)]    #   *tt->address = trailVal(p)
    else
        ld.gstack[_trail_pos(e)] = word(0)                    # else setVar(*p)
    end
    return nothing
end

# PORT: pl-prims.c unifiable as unifiable_cells
# DIVERGES: on the cells (L1e e4): the substitution list laid out at gTop from the trail, newest binding first,
# 6 cells per binding as upstream (`[V = Value|…]`: `gp[4] = makeRefG(p)`, `gp[5] = *p`, `setVar(*p)`); exactly
# the cells it uses are allocated (upstream allocates `(tt-mt)*6+1` and lowers gTop), so the count
# skips an attvar assignment's wakeup entries as the list loop does. An attributed variable's binding
# (AV3: `assignAttVar`'s trailed pattern, pl-attvar.c) is undone as upstream's: the attvar re-inserted,
# the wakeup list's tail and head (or the old tail cell) restored. `LD->alerted` is NOT touched (as
# upstream): the next check point clears the bit and finds the list empty. No overflow retry.
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
    DiscardMark(ld, m)
    n = 0                                                     # the bindings: a value entry and its
    i = tt                                                    # cell count once
    while i > mt
        if isTrailVal(ld.trail[i])                            # an attvar's assignment
            i -= 1                                            # its address entry
            i -= 1
            isTrailVal(ld.trail[i]) && (i -= 1)       # the wakeup list's tail
            i -= 1
            isTrailVal(ld.trail[i]) && (i -= 1)       # … its head (or the old tail cell)
        end
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
            @assert isAttVar(ld.gstack[trailValP(e)])         # assert(isAttVar(trailVal(p)))
            ld.gstack[p2] = ld.gstack[trailValP(e)]           # re-insert the attvar: *tt->address = trailVal(p)
            _unifiable_restore_wakeup_cell!(ld)               # restore tail of wakeup list
            _unifiable_restore_wakeup_cell!(ld)               # restore head of wakeup list
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

# PORT: pl-prims.c ground as pl_ground1_va
# (PRED_IMPL("ground", 1, ground, PL_FA_ISO))
"`ground(@Term)`: `Term` holds no unbound variable (pl-prims.c)."
function pl_ground1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return ground_cells(ld, -(A1 + 1)) == 0 ? FTRUE : FFALSE    # ground(valTermRef(A1)) == NULL
end

# PORT: pl-prims.c acyclic_term as pl_acyclic_term1_va
# (PRED_IMPL("acyclic_term", 1, acyclic_term, PL_FA_ISO))
# DIVERGES: `PL_is_acyclic` on the cells (`is_acyclic_cells`); no MEMORY_OVERFLOW.
"`acyclic_term(@Term)`: `Term` has no cycle (pl-prims.c)."
function pl_acyclic_term1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return is_acyclic_cells(ld, -(A1 + 1)) ? FTRUE : FFALSE
end

# PORT: pl-prims.c cyclic_term as pl_cyclic_term1_va
# (PRED_IMPL("cyclic_term", 1, cyclic_term, 0))
# DIVERGES: as `acyclic_term/1` above: `is_acyclic_cells`, no MEMORY_OVERFLOW (so no ERR_NOMEM branch).
"`cyclic_term(@Term)`: `Term` has a cycle (pl-prims.c)."
function pl_cyclic_term1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return is_acyclic_cells(ld, -(A1 + 1)) ? FFALSE : FTRUE
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
    k, w, _ = _deref_loc(ld, -(A1 + 1))                 # p = valTermRef(A1); deRef(p) (L1e e4: the words)
    isterm = k == DU_WORD && _is_gcompound(w)
    isatomic = k == DU_VALUE || (k == DU_WORD && isAtomW(w))

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
# the list of ALL its children, the head first (it has no functor name; swipl has no such term).
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
            ld.gstack[p + i] = if hk == DU_CELL || hk == DU_ATTVAR   # *p++ = needsRef(*h) ? makeRefG(h) : *h (AV1)
                makeRefG(hp)
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



# PORT: pl-prims.c term_variables
# DIVERGES: `tail` 0 is "no tail", as upstream's. NOT PORTED: `flags` (see `term_variables_loop_cells`),
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


# PORT: pl-prims.c ph_ground as ph_ground_cells
# DIVERGES: on locations, the one-sided cell agenda (`ld.walk_agenda`); returns the first cell that
# `canBind` — unbound, or (AV1b) an attributed variable — by its POSITION (upstream: its address), 0 for
# none.
"The first unbound or attributed cell of the term at location `l` in phase `mark`, 0 if none (pl-prims.c)."
function ph_ground_cells(ld::PL_local_data{T}, l::Int, mark::Bool)::Int where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)
        if k == DU_CELL || k == DU_ATTVAR                   # canBind(*p) (AV1b)
            clearCellAgenda!(a)
            return p
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
# DIVERGES: on a location; returns a POSITION, 0 when ground (see `ph_ground_cells`).
"The first unbound or attributed cell of the term at location `l`: its position, 0 when ground (pl-prims.c)."
function ground_cells(ld::PL_local_data{T}, l::Int)::Int where {T}
    k, w, p = _deref_loc(ld, l)                             # deRef(p)
    (k == DU_CELL || k == DU_ATTVAR) && return p            # canBind(*p) (AV1b)
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


# PORT: pl-prims.c term_variables_loop as term_variables_loop_cells
# DIVERGES: on locations; each variable's term reference holds `makeRefG(p)` as upstream's (no
# export). NOT PORTED: `flags`, signals, `TV_NOSPACE`.
"The unbound variables the agenda `a` walks, each once, depth-first, as new term references; their count, `maxcount + 1` as soon as there are more (pl-prims.c)."
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
        elseif k == DU_WORD && _is_gcompound(w)             # isTerm(w)
            c = valPtr(w)
            visitedWord_cells(ld, c) && continue            # visited(f)
            pushWorkCellAgenda!(a, arityFunctor(ld.functors, ld.gstack[c]), c + 1)
        end
    end
    return count
end

# PORT: pl-prims.c term_variables_to_termv as term_variables_to_termv_cells
# DIVERGES: returns `(count, v0)` where upstream writes `*vp`.
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
    return (count, v0)
end

"`free_variables_loop_cells`' agenda entry for upstream's `&mark` (no location is it)."
const FV_MARK = typemin(Int)

# PORT: pl-prims.c free_variables_loop as free_variables_loop_cells
# DIVERGES: on locations; returns `(n, mname)` — `mname` the module's atom WORD, 0 for none — and
# stores the goal's word in term reference `goal` (upstream: `*valTermRef(goal) = *t`; a slot's side
# word, which is never stored, as its value, `_slot_store!`); each free variable a new term reference
# holding `makeRefG(p)`. `&mark` is `FV_MARK`. The goal after `Module:` is dereferenced, as the term
# version's did (upstream defect, register Q4).
"The free variables of the `Template^Goal` at location `l` (ISO 7.1.1.4; pl-prims.c), as new term references: `(n, module word)`, the goal in `goal`."
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
            # needsRef(*t) ? makeRefG(t) : *t — `*t`: canBind (above) took every bindable word, so a
            # value word is the value (audit D-0117 (b): at a slot's root it has no cell to reference)
            if _is_side_word(w)                             # (f3-1) a slot's side value: its
                _slot_store!(ld, goal + 1, _indirect_value(ld, w))  # value stored again
            else
                ld.slots[goal + 1] = w                      # *valTermRef(goal) = *t
            end
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
# compound laid out on the stack. No retry for local space (the local stack grows on demand).
"`'\$free_variable_set'(+Template^GoalIn, -GoalOut, -VarTemplate)`: `GoalOut` is `GoalIn` without its `^`, `VarTemplate` is `v(V1, …)` of its free variables (pl-prims.c)."
function pl_free_variable_set3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    goal = PL_new_term_ref(ld)
    v0 = PL_new_term_refs(ld, 0)
    n, mname = free_variables_loop_cells(ld, -(A1 + 1), goal)
    unvisit_cells(ld)                                       # unvisit()

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


# PORT: pl-prims.c skip_list as pl_skip_list3_va
# (PRED_IMPL("$skip_list", 3, skip_list, 0))
"`'\$skip_list'(-Length, +List, -Tail)`: the cells of `List` before its `Tail` — `[]`, a variable, or what else ends it (pl-prims.c)."
function pl_skip_list3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    len, _, _, tp = skip_list_cells(ld, -(A2 + 1))         # skip_list(valTermRef(A2), &tail) (L1e e4)
    return if (unify_ptrs_cells(ld, -(A3 + 1), tp) && PL_unify_integer(ld, A1, len))
        FTRUE
    else
        FFALSE
    end
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
    PL_extension("acyclic_term", 1, pl_acyclic_term1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("cyclic_term", 1, pl_cyclic_term1_va, PL_FA_VARARGS),
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

# ── repeat/0 (NF4: the first non-deterministic built-in of the `a1, a2, …` convention) ─────────────
# PORT: pl-prims.c pl_repeat
"`repeat/0` (pl-prims.c): succeeds, and again on every backtrack — an integer retry context (`REDO_INT`)."
function pl_repeat(ld::PL_local_data{T}, h::control_t{T})::foreign_t where {T}
    c = PL_foreign_control(h)
    if c == FRG_FIRST_CALL || c == FRG_REDO
        return PL_retry(2)                          # ForeignRedoInt(2L)
    end
    return FTRUE                                    # FRG_CUTTED, default: succeed
end

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
