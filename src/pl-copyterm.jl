# UPSTREAM: swipl-devel src/pl-copyterm.c @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# COPYING TERMS — SWI-Prolog's `copy_term/2`, `copy_term_nat/2` and `duplicate_term/2`, the
# attribute-free path only.
#
# WHAT UPSTREAM DOES. A term is copied with its variables renamed consistently — a variable met twice
# becomes one fresh variable met twice — and, under `COPY_SHARE` (`copy_term/2`), a GROUND subterm is
# not copied but shared with the original; `duplicate_term/2` copies every compound. Upstream uses the
# GC mark bits of the global stack to classify each cell (virgin, visited, shared, ground) in a
# marking pass (`mark_for_copy`, `mark_for_duplicate`), then copies (`copy_term`), then clears the
# marks (`cp_unmark`); cyclic terms are copied by `initCyclicCopy`'s link table.
#
# WHAT THE KERNEL DOES INSTEAD. A term is an immutable value and a variable a keyed value, so there
# are no cells to mark and nothing to unmark: ONE bottom-up walk with an explicit work stack builds
# the copy. A compound is SHARED when every child of it is its own copy (an atomic, or a compound
# shared in turn: `===`) — a compound with a variable below, bound or not, is rebuilt, as upstream's
# is (a ground term is `is_ground`; a term with a bound variable has a cell that is a reference).
# A CYCLIC term exists only through the binding store (a variable bound to a term that holds it), so
# the walk follows a bound variable once and meets it again as an `in progress` mark: the copy is then
# a FRESH variable bound (trailed) to the copy of the term — a cyclic copy, as upstream's.
#
# CELL IDENTITY (the marker is at `copy_term`): the copy keeps the TERM, not the identity of its
# cells. Upstream marks cells, so a compound met twice is copied once; the walk here knows a
# compound again only by the bound variable it was reached through. A compound met both directly
# and through its variable is copied twice — and where that is the entry of a cycle (`f(C)`,
# `C = [a|X]`, `X` bound to `C`) the copy is the cycle unrolled by one compound: `[a|R]` with
# `R = [a|R]`. Every answer is the same (`==`, `=@=`, unification, writing); `same_term/2` and the
# factorising of a cyclic term would tell, and the kernel has neither. It goes with the term layout
# (step L1), where a copy is of cells.
#
# NOT PORTED: attributed variables (`COPY_ATTRS`, `must_copy_attvar`, `unshare_attvar`: no attributed
# variables), `copy_term/4`, `copy_term_nat/4` (`COPY_MARKED`, `mark_vars`), `size_abstract_term/3`
# (`COPY_ABSTRACT`), `duplicate_term`'s `nshare`/`share` (the shared subterms of `duplicate_term/2`
# are none: `nshare` is 0), the fast heap terms (`$fast_record`, `term_to_fastheap`) and
# the stack-space retry loop of `copy_term_refs` (no global stack to grow).

# PORT: pl-copyterm.c cp_options
"The options of a copy (pl-copyterm.c `cp_options`): the kernel's is the sharing of ground terms (`COPY_SHARE`)."
struct cp_options
    share::Bool
end

# One compound being copied: the original, the copies of its children so far (children 1…n, the
# head first), the index of the next child, whether every child so far is its own copy, and the
# keys of the bound variables the walk went through to reach it (their copies are this one's).
mutable struct _cp_frame{T}
    orig::T
    kids::Vector{T}
    next::Int
    same::Bool
    chain::Vector{UInt64}
end

# The state of one copy.
mutable struct _cp_state{T}
    share::Bool
    vars::Dict{UInt64, T}               # an unbound variable → its fresh variable
    done::Dict{UInt64, T}               # a bound variable → the copy of the term it is bound to
    inprogress::Set{UInt64}             # bound variables whose term is being copied
    cyclic::Dict{UInt64, T}             # a bound variable met again in progress → its placeholder
end

# PORT: pl-copyterm.c copy_term
# DIVERGES: see the file header — one bottom-up walk over values; the cyclic copy is a fresh
# variable bound to the copy; a compound met both directly and through its variable is copied
# twice (the header's CELL IDENTITY: no answer differs, `same_term/2` would — step L1).
"""
    copy_term(ld, from, options) -> T

A copy of `from` under the bindings in `ld`: variables renamed consistently, ground subterms
shared where `options.share`, a cyclic term copied as a cyclic term (pl-copyterm.c `copy_term`).
"""
function copy_term(ld::PL_local_data{T}, from::T, options::cp_options)::T where {T}
    return copy_term(ld, from, options, Dict{UInt64, T}())
end

# ORIGINAL: the walk with the caller's map of fresh variables — an unbound variable already in
# `vars` is copied to its entry, a new one is added to it — so that several copies share their
# variables, as the arguments of one record do (`putSlotValue!`, src/pl-inline.jl: L1b's boundary).
"`copy_term` with the fresh variables of `vars` (an unbound variable's key → its copy), extended in place."
function copy_term(
    ld::PL_local_data{T}, from::T, options::cp_options, vars::Dict{UInt64, T}
)::T where {T}
    st = _cp_state{T}(
        options.share, vars, Dict{UInt64, T}(), Set{UInt64}(), Dict{UInt64, T}()
    )
    stack = _cp_frame{T}[]
    result = _cp_visit!(ld, st, stack, from)
    while !isempty(stack)
        f = stack[end]
        if f.next <= length(f.kids)
            i = f.next
            f.next += 1
            c = child(f.orig, i)
            r = _cp_visit!(ld, st, stack, c)
            if r !== nothing                            # a finished child: no frame was pushed
                f.kids[i] = r
                r === c || (f.same = false)
            end
        else
            pop!(stack)
            r = _cp_finish!(ld, st, f)
            if isempty(stack)
                result = r
            else
                p = stack[end]
                i = p.next - 1                          # the parent's child being completed
                p.kids[i] = r
                r === child(p.orig, i) || (p.same = false)
            end
        end
    end
    return result::T
end

# Visit term `t`: follow its bound variables (noting them), then an unbound variable and an atomic
# are finished at once (the copy is returned) and a compound gets a frame (`nothing` is returned).
function _cp_visit!(
    ld::PL_local_data{T}, st::_cp_state{T}, stack::Vector{_cp_frame{T}}, t::T
)::Union{Nothing, T} where {T}
    chain = UInt64[]
    while kind(t) === VAR
        k = var_key(t)
        b = _binding(ld, k)
        b === nothing && break
        if haskey(st.done, k)                           # copied already
            return _cp_chain_done!(st, chain, st.done[k])
        end
        if k in st.inprogress                           # a cycle: its copy is a variable, bound later
            # a KEYED variable, not a cell (L1a): `copy_exception!` drops its binding's trail entry
            # to freeze a cyclic ball, which a cell's binding would not survive (`Undo!` frees the
            # cell); bound at once, it is never compared unbound, so its key's order is not seen
            w = get!(() -> mk_var(T, fresh_var_keys!(1)), st.cyclic, k)
            return _cp_chain_done!(st, chain, w)
        end
        push!(chain, k)
        t = b
    end
    kt = kind(t)
    if kt === VAR                                       # unbound: one fresh variable per variable
        w = get!(() -> _cell_var(ld, allocGlobalCells!(ld, 1)), st.vars, var_key(t))
        return _cp_chain_done!(st, chain, w)
    elseif kt !== EXPR
        return _cp_chain_done!(st, chain, t)
    end
    union!(st.inprogress, chain)
    push!(stack, _cp_frame{T}(t, Vector{T}(undef, nchildren(t)), 1, true, chain))
    return nothing
end

# The copy `r` is the copy of every variable of `chain`.
function _cp_chain_done!(st::_cp_state{T}, chain::Vector{UInt64}, r::T)::T where {T}
    for k in chain
        st.done[k] = r
    end
    return r
end

# A compound's children are all copied: share it or build the copy; and bind the placeholders of
# the bound variables it was reached through, which a cycle met.
function _cp_finish!(ld::PL_local_data{T}, st::_cp_state{T}, f::_cp_frame{T})::T where {T}
    r = (st.share && f.same) ? f.orig : mk_expr(T, f.kids)
    for k in f.chain
        delete!(st.inprogress, k)
    end
    out = r
    for k in f.chain
        w = get(st.cyclic, k, nothing)
        if w !== nothing
            Trail!(ld, var_key(w), r)                   # the cyclic copy: w = r, and r holds w
            out = w
        end
        st.done[k] = out
    end
    return out
end

# ── the built-ins ───────────────────────────────────────────────────────────────────────────────
# PORT: pl-copyterm.c copy_term_refs
# DIVERGES: values, no global stack: nothing to allocate, so no retry (see the file header).
"Put a copy of the term `from` references into a new term reference, and return it (pl-copyterm.c)."
function copy_term_refs(
    ld::PL_local_data{T}, from::term_t, options::cp_options
)::term_t where {T}
    copy = new_term_ref(ld)
    setSlotValue!(ld, copy + 1, copy_term(ld, slotValue(ld, from + 1), options))
    return copy
end

# `PL_is_atomic(t)`: the term `t` references is neither a variable nor a compound.
function _cp_atomic(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k = kind(deRef(ld, slotValue(ld, t + 1)))
    return k !== VAR && k !== EXPR
end

# PORT: pl-copyterm.c copy_term as pl_copy_term2_va
# (PRED_IMPL("copy_term", 2, copy_term, 0)); the table's flag is `PL_FA_ISO`.
"`copy_term(+In, -Out)`: `Out` is `In` with its variables renamed, ground subterms shared."
function pl_copy_term2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    if _cp_atomic(ld, A1)
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
    copy = copy_term_refs(ld, A1, cp_options(true))
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c copy_term_nat as pl_copy_term_nat2_va
# (PRED_IMPL("copy_term_nat", 2, copy_term_nat, 0)) — no attributes either way, so as copy_term/2.
"`copy_term_nat(+In, -Out)`: `copy_term/2` without attributes."
function pl_copy_term_nat2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    copy = copy_term_refs(ld, A1, cp_options(true))        # (upstream has no atomic shortcut here)
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c duplicate_term as pl_duplicate_term2_va
# (PRED_IMPL("duplicate_term", 2, duplicate_term, 0))
"`duplicate_term(+In, -Out)`: `Out` is a copy of `In` that shares no compound with it."
function pl_duplicate_term2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    if _cp_atomic(ld, A1)
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
    copy = copy_term_refs(ld, A1, cp_options(false))
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c BeginPredDefs as PL_predicates_from_copyterm
# DIVERGES: the ported entries only (upstream's table also has `copy_term/4`, `copy_term_nat/4`,
# `size_abstract_term/3`, `$fast_record/2`, `$fast_recorded/2`).
"pl-copyterm.c's registration table (`BeginPredDefs(copyterm)`): the ported entries."
const PL_predicates_from_copyterm = (
    PL_extension("copy_term", 2, pl_copy_term2_va, PL_FA_VARARGS | PL_FA_ISO),
    PL_extension("duplicate_term", 2, pl_duplicate_term2_va, PL_FA_VARARGS),
    PL_extension("copy_term_nat", 2, pl_copy_term_nat2_va, PL_FA_VARARGS)
)
