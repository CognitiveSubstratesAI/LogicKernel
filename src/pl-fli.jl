# UPSTREAM: swipl-devel src/pl-fli.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-fli.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-incl.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-atom.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1996-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): re-cite only, no code change (cbf4e189..18168e62 compared, D-0447 Q1) — pl-fli.c: access-only (d755bdc4), the validate_api flag ported; PL_get_arg_values, PL_get_list_slice and the validateAPI gate are owner FLI1 (docs/architecture.md, deferred owners); pl-fli.h: the validate_api flag ported; the validateAPI macros are owner FLI1 (docs/architecture.md, deferred owners).
# THE TERM REFERENCES of SWI-Prolog's foreign language interface (pl-fli.c): a `term_t` is a
# position on the local stack (src/pl-incl.jl § the local stack), allocated at `lTop` inside the
# innermost foreign frame, which counts them. Since V5a2, the `PL_*` functions the first built-ins
# and the foreign call path use, under upstream's names, on `(ld, term_t)`.

# The check upstream's API stubs make (fli:535-550): a term reference is made inside a foreign frame
# newer than the running Prolog frame — never while a query's answer has been left without one (after
# `PL_next_solution` returned a deterministic last answer and was called again). Only the stubs check
# (`PL_new_term_ref_api`, `PL_new_term_refs_api` below), the foreign-interface surface: the kernel's
# own ports call the LD forms, which make no check, as upstream's C files do (pl-fli.h:72-74 maps
# their `PL_new_term_ref()`/`PL_new_term_refs(n)` to the LDFUNC forms) — since ENG3 (audit D-0379).
function _check_foreign_environment(ld::PL_local_data{T}, what::String)::Nothing where {T}
    env = ld.environment_frame
    if env != 0 && ld.fliframes[ld.fli_context].base <= ld.frames[env].base
        error(what * "(): No foreign environment")              # fatalError()
    end
    return nothing
end

# PORT: pl-fli.c PL_new_term_refs
# (pl-fli.c:450-476, the LD form: no foreign-environment check — `PL_new_term_refs_api` makes it.)
# DIVERGES: `n` positions. Each new reference holds a fresh variable: `setVar` of a cell is a new
# variable key here (decision 2). `O_CHECK_TERM_REFS` is `O_DEBUG` only.
"`n` new term references, each holding a fresh variable; the first one, or 0 (pl-fli.c)."
function PL_new_term_refs(ld::PL_local_data{T}, n::Int)::Int where {T}
    if !ensureLocalSpace(ld, n)
        return 0
    end

    t = ld.lTop
    r = t                                       # consTermRef(t)

    p = allocGlobalCells!(ld, n)
    for i in 0:(n - 1)
        ld.slots[t + 1] = makeRefG(p + i)       # setVar(*t++): a global cell's reference (L1b C5)
        t += 1
    end
    ld.lTop = t
    fr = ld.fli_context
    ld.fliframes[fr].size += n

    return r
end

# PORT: pl-fli.c new_term_ref
# DIVERGES: the new reference holds a fresh variable (as `PL_new_term_refs`).
"A new term reference holding a fresh variable, without making room first (pl-fli.c)."
function new_term_ref(ld::PL_local_data{T})::Int where {T}
    t = ld.lTop
    r = t                                       # consTermRef(t)
    _slot_new_var!(ld, t + 1)                   # setVar(*t++)
    t += 1

    ld.lTop = t
    fr = ld.fli_context
    ld.fliframes[fr].size += 1

    return r
end

# PORT: pl-fli.c PL_new_term_ref
# (pl-fli.c:503-508, the LD form the kernel's ports call: no foreign-environment check.)
"A new term reference holding a fresh variable, or 0 (pl-fli.c)."
function PL_new_term_ref(ld::PL_local_data{T})::Int where {T}
    if !ensureLocalSpace(ld, 1)
        return 0
    end

    return new_term_ref(ld)
end

# PORT: pl-fli.c PL_new_term_refs as PL_new_term_refs_api
# (pl-fli.c:535-541, `API_STUB(term_t)(PL_new_term_refs)(size_t n)`.)
# DIVERGES: a name of its own — upstream's stub and its LD form share the name, the LDFUNC macro of
# pl-fli.h:74 tells them apart; the local data is an argument (upstream: `GET_LD`).
"""
`PL_new_term_refs` as a foreign caller reaches it (pl-fli.c's API stub): an error while no foreign
frame is newer than the running Prolog frame, else `n` new term references (the first one, or 0).
"""
function PL_new_term_refs_api(ld::PL_local_data{T}, n::Int)::Int where {T}
    # if ( (void*)fli_context <= (void*)environment_frame ) fatalError("PL_new_term_refs(): …")
    _check_foreign_environment(ld, "PL_new_term_refs")

    return PL_new_term_refs(ld, n)
end

# PORT: pl-fli.c PL_new_term_ref as PL_new_term_ref_api
# (pl-fli.c:544-550, `API_STUB(term_t)(PL_new_term_ref)()`.)
# DIVERGES: a name of its own — upstream's stub and its LD form share the name, the LDFUNC macro of
# pl-fli.h:72 tells them apart; the local data is an argument (upstream: `GET_LD`).
"""
`PL_new_term_ref` as a foreign caller reaches it (pl-fli.c's API stub): an error while no foreign
frame is newer than the running Prolog frame, else a new term reference (or 0).
"""
function PL_new_term_ref_api(ld::PL_local_data{T})::Int where {T}
    # if ( (void*)fli_context <= (void*)environment_frame ) fatalError("PL_new_term_ref(): …")
    _check_foreign_environment(ld, "PL_new_term_ref")

    return PL_new_term_ref(ld)
end

# PORT: pl-fli.c PL_reset_term_refs
# DIVERGES: lowering `lTop` drops the records above it (decision 3; there are none above a term
# reference of the innermost foreign frame).
"Free term reference `r` and every one allocated after it (pl-fli.c)."
function PL_reset_term_refs(ld::PL_local_data{T}, r::Int)::Nothing where {T}
    fr = ld.fli_context
    f = ld.fliframes[fr]

    lowerLTop!(ld, r)                           # lTop = (LocalFrame) valTermRef(r);
    f.size = ld.lTop - (f.base + SIZEOF_FLIFRAME)
    @assert f.size >= 0 "PL_reset_term_refs: below its foreign frame"   # DEBUG(0, …)
    return nothing
end

# PORT: pl-fli.c PL_copy_term_ref
# DIVERGES: no `globalizeTermRef`. Upstream moves an unbound variable out of a local cell, which
# nothing may point into; a slot holds no unbound word, its variable is a global cell already.
# `CHK_SECURE` is `O_DEBUG` only.
"A new term reference to the term `from` references; or 0 (pl-fli.c)."
function PL_copy_term_ref(ld::PL_local_data{T}, from::Int)::Int where {T}
    if !ensureLocalSpace(ld, 1)
        return 0
    end

    t = ld.lTop
    r = t                                       # consTermRef(t)
    _slot_link!(ld, t + 1, from + 1)                # *t = linkValI(valHandleP(from))
    ld.lTop = t + 1
    fr = ld.fli_context
    ld.fliframes[fr].size += 1

    return r
end

# PORT: pl-fli.c PL_cons_list
# DIVERGES: no global space to ensure, so it cannot fail; on the CELLS (L1e e3): three cells at gTop,
# `bindConsVal` as `_cell_link!` (linkValI from the head's and tail's slots).
"Make term reference `l` hold the list cell of the terms `head` and `tail` reference (pl-fli.c)."
function PL_cons_list(
    ld::PL_local_data{T}, l::term_t, head::term_t, tail::term_t
)::Bool where {T}
    a = _alloc_compound!(ld, ld.functor_dot2, 2)            # a = allocGlobal(3); a[0] = FUNCTOR_dot2
    _cell_link!(ld, a + 1, head + 1)                        # bindConsVal(&a[1], valHandleP(head))
    _cell_link!(ld, a + 2, tail + 1)                        # bindConsVal(&a[2], valHandleP(tail))
    ld.slots[l + 1] = consPtr(a, TAG_COMPOUND | STG_GLOBAL) # setHandle(l, consPtr(a, …))
    return true
end

# PORT: pl-fli.c PL_cons_list_v
# DIVERGES: no global space to ensure, so it cannot fail; on the CELLS, as `PL_cons_list`: the
# `count` list cells at `gTop`, each head `_cell_link!` (`bindConsVal`) from the consecutive term
# references `elems`, `elems+1`, …, the last tail `[]`. `list` is set after the heads are read, so
# it may be `elems` itself.
"Make term reference `list` hold the list of the `count` terms the references `elems`… hold (pl-fli.c)."
function PL_cons_list_v(
    ld::PL_local_data{T}, list::term_t, count::Int, elems::term_t
)::Bool where {T}
    if count > 0
        p = allocGlobalCells!(ld, 3 * count)                    # p = gTop; (3*count cells)
        for i in 0:(count - 1)
            q = p + 3 * i
            ld.gstack[q] = ld.functor_dot2                      # p[0] = FUNCTOR_dot2
            _cell_link!(ld, q + 1, elems + i + 1)               # bindConsVal(&p[1], valHandleP(elems))
            ld.gstack[q + 2] =
                i + 1 < count ? consPtr(q + 3, TAG_COMPOUND | STG_GLOBAL) : ld.atom_nil_w
        end
        ld.slots[list + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)  # setHandle(list, consPtr(gTop, …))
    else
        ld.slots[list + 1] = ld.atom_nil_w                      # setHandle(list, ATOM_nil)
    end
    return true
end

# PORT: pl-fli.c PL_unify_list
# DIVERGES: no global space to ensure; on the CELLS (L1e e3): a cell that `canBind` — unbound, or (AV1b) an
# attributed variable — bound (`bindConst`) to a new `'[|]'/2` compound at gTop, `h`/`t` its argument
# cells' references; a list word's arguments linked (`linkValI`).
"Unify term reference `l` with a list cell, putting its head and tail into `h` and `t` (pl-fli.c)."
function PL_unify_list(
    ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t
)::Bool where {T}
    k, w, q = _deref_loc(ld, -(l + 1))                      # p = valHandleP(l); deRef(p)
    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*p) (AV1b)
        a = _alloc_compound!(ld, ld.functor_dot2, 2)        # a[0] = FUNCTOR_dot2; setVar(a[1]), (a[2])
        ld.slots[h + 1] = makeRefG(a + 1)                   # setHandle(h, makeRefG(&a[1]))
        ld.slots[t + 1] = makeRefG(a + 2)                   # setHandle(t, makeRefG(&a[2]))
        bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL))      # bindConst(p, c)
        return true
    elseif _is_list_word(ld, k, w)                          # isList(*p)
        _slot_link_loc!(ld, h + 1, _deref_loc(ld, valPtr(w) + 1))    # setHandle(h, linkValI(a))
        _slot_link_loc!(ld, t + 1, _deref_loc(ld, valPtr(w) + 2))    # setHandle(t, linkValI(a+1))
        return true
    end
    return false
end

# PORT: pl-fli.c PL_unify_nil
"Unify term reference `l` with `[]` (pl-fli.c)."
PL_unify_nil(ld::PL_local_data{T}, l::term_t) where {T} = PL_unify_atom(ld, l, mk_nil(T))

# PORT: pl-fli.c PL_skip_list
# DIVERGES: returns `(type, length)` where upstream writes the length through `len`; on the WORDS (L1e e2:
# `skip_list_cells`, L1d step 9). NOT PORTED: `tail` (upstream unifies it with the list's tail): no
# caller here passes one.
"The type of the list term reference `list` holds — `PL_LIST`, `PL_PARTIAL_LIST`, `PL_CYCLIC_TERM`, `PL_NOT_A_LIST` — and its cells (pl-fli.c)."
function PL_skip_list(ld::PL_local_data{T}, list::term_t)::Tuple{Int, Int} where {T}
    length, k, w, _ = skip_list_cells(ld, -(list + 1))
    k == DU_WORD && w == ld.atom_nil_w && return (PL_LIST, length)    # isNil(*tail)
    k == DU_CELL && return (PL_PARTIAL_LIST, length)                  # canBind(*tail)
    _is_list_word(ld, k, w) && return (PL_CYCLIC_TERM, length)        # isList(*tail)
    return (PL_NOT_A_LIST, length)
end

# PORT: pl-fli.c PL_unify_functor
# `flags` (G1-B, default 0): as `PL_unify_compound`'s.
# DIVERGES: the functor is its name and arity; no global space to ensure. A term that `canBind` (unbound,
# or since AV1b an attributed variable: `bindConst`) is bound to `name` of `arity` fresh variables.
"Unify term reference `t` with a term `name/arity` — binding it to one of fresh variables, or checking its functor (pl-fli.c)."
function PL_unify_functor(
    ld::PL_local_data{T}, t::term_t, name::T, arity::Int, flags::Int=0
)::Bool where {T}
    k, w, q = _deref_loc(ld, -(t + 1))                      # p = valHandleP(t); deRef(p) (L1e e3)
    nw = _atom_word!(ld, name)                              # nameFunctor(f)
    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*p) (AV1b)
        if arity == 0
            bindConst(ld, q, nw, flags)                     # bindConst(p, name)
        else                                                # *a = f; setVar(*++a)…
            a = _alloc_compound!(ld, lookupFunctorDef(ld.functors, nw, arity), arity)
            bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL), flags)   # bindConst(p, to)
        end
        return true
    end
    arity == 0 && return k == DU_WORD && w == nw            # *p == nameFunctor(f)
    return k == DU_WORD && _is_gcompound(w) &&              # hasFunctor(*p, f)
           ld.gstack[valPtr(w)] == lookupFunctorDef(ld.functors, nw, arity)
end

# PORT: pl-fli.c PL_unify_compound
# DIVERGES: `f` is a functor WORD (`$expr/n` too); no global space to ensure.
# `flags` (G1-B, default 0) is what `bind_attvar_const` passes to its `ensureGlobalSpace`: `ALLOW_GC` from a caller the audit rules SAFE (docs/g1gc_safe_points.md).
"Unify term reference `t` with a compound of functor word `f` — binding it to one of fresh arguments, or checking its functor (pl-fli.c)."
function PL_unify_compound(
    ld::PL_local_data{T}, t::term_t, f::word, flags::Int=0
)::Bool where {T}
    k, w, q = _deref_loc(ld, -(t + 1))                      # p = valHandleP(t); deRef(p)
    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*p) (AV1b)
        a = _alloc_compound!(ld, f, arityFunctor(ld.functors, f))  # *a = f; setVar(*++a)…
        bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL), flags)   # bindConst(p, to)
        return true
    end
    return k == DU_WORD && _is_gcompound(w) && ld.gstack[valPtr(w)] == f   # hasFunctor(*p, f)
end

# PORT: pl-fli.c PL_unify_arg_sz as PL_unify_arg
# DIVERGES: a compound whose head is no symbol has every child as an argument (see `_PL_get_arg`).
"Unify argument `index` (from 1) of the compound term reference `t` holds with the term `a` references (pl-fli.c)."
function PL_unify_arg(
    ld::PL_local_data{T}, index::Int, t::term_t, a::term_t
)::Bool where {T}
    k, x, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t) (L1e e3: the cells)
    if k == DU_WORD && _is_gcompound(x)                     # isTerm(w)
        q = valPtr(x)
        0 < index <= arityFunctor(ld.functors, ld.gstack[q]) || return false   # index <= arity
        return unify_ptrs_cells(ld, q + index, -(a + 1))    # unify_ptrs(argTermP(w, index-1), valHandleP(arg))
    end
    return false
end

# PORT: pl-fli.c PL_put_term
# DIVERGES: no `globalizeTermRef` (as `PL_copy_term_ref`), so it cannot fail; on the WORDS
# (`_slot_link!`, L1c) — a compound's word moved, not exported and copied back, and a value (the
# exception's ball, decision 1) kept a value, as upstream's frozen ball stays where it is.
"Make term reference `t1` reference the term `t2` references (pl-fli.c)."
function PL_put_term(ld::PL_local_data{T}, t1::Int, t2::Int)::Bool where {T}
    _slot_link!(ld, t1 + 1, t2 + 1)                 # setHandle(t1, linkValI(p2))
    return true
end

# PORT: pl-fli.h PL_put_variable
# DIVERGES: a slot holds no unbound word, so its fresh variable is a global cell (as `new_term_ref`'s).
"Make term reference `t` hold a fresh variable (pl-fli.h)."
function PL_put_variable(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    _slot_new_var!(ld, t + 1)                       # setVar(*valTermRef(t))
    return true
end

# PORT: pl-fli.h PL_put_atom
"Make term reference `t` hold the atom `a` (pl-fli.h)."
function PL_put_atom(ld::PL_local_data{T}, t::term_t, a::T)::Bool where {T}
    ld.slots[t + 1] = _atom_word!(ld, a)            # setHandle(t, a)
    return true
end

# PORT: pl-fli.c PL_put_bool
# DIVERGES: the atom `true` or `false` as a symbol of the term type, put as `PL_put_atom` puts it.
"Make term reference `t` hold the atom `true` if `val`, else `false` (pl-fli.c)."
function PL_put_bool(ld::PL_local_data{T}, t::term_t, val::Bool)::Bool where {T}
    PL_put_atom(ld, t, mk_sym(T, val ? Symbol("true") : Symbol("false")))  # PL_put_atom(t, val ? ATOM_true : ATOM_false)
    return true
end

# PORT: pl-fli.c PL_put_nil
"Make term reference `l` hold `[]` (pl-fli.c)."
PL_put_nil(ld::PL_local_data{T}, l::term_t) where {T} = PL_put_atom(ld, l, mk_nil(T))

# PORT: pl-fli.h PL_put_int64
# DIVERGES: the integer's word as `PL_put_intptr` lays it (a tagged integer, or a value-table word
# under `_slot_store!`'s older-slot rule); it cannot fail (no `put_int64` allocation to refuse).
"Make term reference `t` hold the integer `i` (pl-fli.h)."
PL_put_int64(ld::PL_local_data{T}, t::term_t, i::Int) where {T} = PL_put_intptr(ld, t, i)

# PORT: pl-fli.c PL_put_integer
"Make term reference `t` hold the integer `i` (pl-fli.c)."
PL_put_integer(ld::PL_local_data{T}, t::term_t, i::Int) where {T} = PL_put_int64(ld, t, i)

# PORT: pl-fli.c PL_put_pointer
# DIVERGES: a pointer is a `UInt` (a `uintptr_t`); on a 64-bit platform `pointerToInt` is the identity
# (pl-inline.h), so the integer put is the pointer's bits as an `int64_t`.
"Make term reference `t` hold the pointer `ptr` as an integer (pl-fli.c)."
function PL_put_pointer(ld::PL_local_data{T}, t::term_t, ptr::UInt)::Bool where {T}
    return PL_put_int64(ld, t, reinterpret(Int, ptr))       # PL_put_int64(t, (int64_t)pointerToInt(ptr))
end

# PORT: pl-fli.c PL_put_float
# DIVERGES: the float's word as `PL_put_intptr` lays an integer (`mk_gnd`); a NaN is the canonical one
# (`put_double`, as `put_number` does); it cannot fail (no `put_double` allocation to refuse).
"Make term reference `t` hold the float `f` (pl-fli.c)."
function PL_put_float(ld::PL_local_data{T}, t::term_t, f::Float64)::Bool where {T}
    isnan(f) && (f = PL_nan())
    setSlotValue!(ld, t + 1, mk_gnd(T, f))
    return true
end

# PORT: pl-fli.c _PL_put_number
# DIVERGES: the number is a `number` record; its word as `_slot_store!` lays a number (tagged, or
# a value-table word), so it cannot fail.
"Make term reference `t` hold the number `n` (pl-fli.c)."
function _PL_put_number(ld::PL_local_data{T}, t::term_t, n::number)::Bool where {T}
    setSlotValue!(ld, t + 1, put_number(T, n))      # setHandle(t, consInt(…)) / put_number(&w, n)
    return true
end

# PORT: pl-fli.c PL_put_functor
# DIVERGES: the functor is a functor WORD (as `PL_cons_functor`'s); no global space to ensure, so it
# cannot fail. The arguments are the unbound cells `_alloc_compound!` lays out (`setVar`).
"Make term reference `t` hold a new term of functor word `f` whose arguments are fresh variables — the atom `f` names if its arity is 0 (pl-fli.c)."
function PL_put_functor(ld::PL_local_data{T}, t::term_t, f::word)::Bool where {T}
    arity = arityFunctor(ld.functors, f)                    # size_t arity = arityFunctor(f)
    if arity == 0
        ld.slots[t + 1] = nameFunctor(ld.functors, f)       # setHandle(t, nameFunctor(f))
    else
        a = _alloc_compound!(ld, f, arity)                  # a = allocGlobal(1+arity); *a++ = f; setVar(*a++)…
        ld.slots[t + 1] = consPtr(a, TAG_COMPOUND | STG_GLOBAL)     # setHandle(t, consCompound(a))
    end
    return true
end

# PORT: pl-fli.c PL_put_list
# DIVERGES: no global space to ensure, so it cannot fail.
"Make term reference `l` hold a new list cell whose head and tail are fresh variables (pl-fli.c)."
function PL_put_list(ld::PL_local_data{T}, l::term_t)::Bool where {T}
    a = _alloc_compound!(ld, ld.functor_dot2, 2)            # a = allocGlobal(3); *a++ = FUNCTOR_dot2; setVar(*a++)…
    ld.slots[l + 1] = consPtr(a, TAG_COMPOUND | STG_GLOBAL) # setHandle(l, consCompound(a))
    return true
end

# PORT: pl-fli.c PL_cons_functor
# DIVERGES: the arguments are a typed `Vararg` of term references (upstream's `va_list`, read by
# `cons_functorv`), the functor a functor WORD; no global space to ensure, so it cannot fail. Each
# argument is laid in by `_cell_link!` (`bindConsVal`), a slot's side value through its word (f3b-1).
"Make term reference `h` hold a new compound of functor word `fd` whose arguments are the terms `a…` reference (pl-fli.c)."
function PL_cons_functor(
    ld::PL_local_data{T}, h::term_t, fd::word, a::Vararg{term_t, N}
)::Bool where {T, N}
    @assert arityFunctor(ld.functors, fd) == N                  # size_t arity = arityFunctor(fd)
    if N == 0
        ld.slots[h + 1] = nameFunctor(ld.functors, fd)          # setHandle(h, nameFunctor(fd))
        return true
    end
    p = _alloc_compound!(ld, fd, N)                             # a = t = gTop; gTop += 1+arity; *a = fd
    for i in 1:N
        _cell_link!(ld, p + i, a[i] + 1)                        # bindConsVal(++a, valHandleP(r))
    end
    ld.slots[h + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)     # setHandle(h, consPtr(t, …))
    return true
end

# PORT: pl-fli.c PL_cons_functor_v
# DIVERGES: the functor is a functor WORD, as `PL_cons_functor`'s; no global space to ensure, so it
# cannot fail. The arguments are the consecutive term references `a0`, `a0+1`, …, each laid in by
# `_cell_link!` (`bindConsVal`).
"Make term reference `h` hold a new compound of functor word `fd` whose arguments are the term references `a0`… (pl-fli.c)."
function PL_cons_functor_v(
    ld::PL_local_data{T}, h::term_t, fd::word, a0::term_t
)::Bool where {T}
    arity = arityFunctor(ld.functors, fd)                       # size_t arity = arityFunctor(fd)
    if arity == 0
        ld.slots[h + 1] = nameFunctor(ld.functors, fd)          # setHandle(h, nameFunctor(fd))
    else
        p = _alloc_compound!(ld, fd, arity)                     # a = t = gTop; gTop += 1+arity; *a = fd
        for i in 1:arity
            _cell_link!(ld, p + i, a0 + i)                      # bindConsVal(++a, ai++): slot of a0+i-1
        end
        ld.slots[h + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL) # setHandle(h, consPtr(t, …))
    end
    return true
end

# PORT: pl-fli.c pushWordAsTermRef
# DIVERGES: the word is a DEREFERENCED location `(k, w, p)` (`_deref_loc`), where upstream passes a
# `Word` — a slot's own word has no global position here; `linkValNoG(p)` is `_slot_link_loc!`. The
# handles are TMP_PTR_SIZE consecutive references from `ld.tmp_h`, made by `emptyStacks!`.
"A temporary term reference holding the location `(k, w, p)`; release it with `popTermRef` (pl-fli.c)."
function pushWordAsTermRef(
    ld::PL_local_data{T}, loc::Tuple{UInt8, word, Int}
)::term_t where {T}
    i = ld.tmp_top                                  # int i = LD->tmp.top++
    ld.tmp_top += 1
    t = ld.tmp_h + i                                # term_t t = LD->tmp.h[i]
    @assert i < TMP_PTR_SIZE
    _slot_link_loc!(ld, t + 1, loc)                 # setHandle(t, linkValNoG(p))
    return t
end

# PORT: pl-fli.c popTermRef
# DIVERGES: `setVar` of the handle makes it reference its PERMANENT cell again, unbound (as
# `_reset_exception_slot!`): a fresh cell would be freed by the next `Undo!` under the handle.
"Release the last temporary term reference `pushWordAsTermRef` handed out (pl-fli.c)."
function popTermRef(ld::PL_local_data{T})::Nothing where {T}
    ld.tmp_top -= 1                                 # int i = --LD->tmp.top
    i = ld.tmp_top
    @assert i >= 0
    c = ld.tmp_cells + i
    ld.gstack[c] = word(0)                          # setVar(*valTermRef(LD->tmp.h[i]))
    ld.slots[ld.tmp_h + i + 1] = makeRefG(c)
    return nothing
end

# PORT: pl-incl.h PushPtr
# DIVERGES: `p` is a global position and the temporary handle takes the reference to it (`makeRefG`, where
# upstream's `makeRefLG` covers a local or a global pointer); it rides the handle across a collection, as upstream's.
"Keep the global position `p` safe over a collection in the next temporary handle; take it back with `PopPtr!` (pl-incl.h)."
function PushPtr!(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    i = ld.tmp_top                                  # int i = LD->tmp.top++
    ld.tmp_top += 1
    @assert i < TMP_PTR_SIZE
    ld.slots[ld.tmp_h + i + 1] = makeRefG(p)        # *valTermRef(LD->tmp.h[i]) = makeRefLG(p)
    return nothing
end

# PORT: pl-incl.h PopPtr
# DIVERGES: returns the position (upstream assigns its argument); the handle is reset by `popTermRef`.
"The global position the last `PushPtr!` kept, as a collection left it (pl-incl.h)."
function PopPtr!(ld::PL_local_data{T})::Int where {T}
    @assert ld.tmp_top > 0
    p = unRef(ld.slots[ld.tmp_h + ld.tmp_top])      # p = unRef(*valTermRef(LD->tmp.h[i]))
    popTermRef(ld)                                  # setVar(*valTermRef(LD->tmp.h[i]))
    return p
end

# PORT: pl-incl.h PushVal
# DIVERGES: a value-table word is kept as `_slot_link_loc!` keeps one in a slot older than the foreign frame (its
# indirect form: the handles predate every frame), so `PopVal!` may hand back that form of the word, equal in value.
"Keep the word `w` safe over a collection in the next temporary handle; take it back with `PopVal!` (pl-incl.h)."
function PushVal!(ld::PL_local_data{T}, w::word)::Nothing where {T}
    i = ld.tmp_top                                  # int i = LD->tmp.top++
    ld.tmp_top += 1
    @assert i < TMP_PTR_SIZE
    _slot_link_loc!(ld, ld.tmp_h + i + 1, (_is_vword(w) ? DU_VALUE : DU_WORD, w, 0))   # *valTermRef(LD->tmp.h[i]) = w
    return nothing
end

# PORT: pl-incl.h PopVal
# DIVERGES: returns the word (upstream assigns its argument).
"The word the last `PushVal!` kept, as a collection left it (pl-incl.h)."
function PopVal!(ld::PL_local_data{T})::word where {T}
    @assert ld.tmp_top > 0
    w = ld.slots[ld.tmp_h + ld.tmp_top]             # w = *valTermRef(LD->tmp.h[i])
    popTermRef(ld)                                  # setVar(*valTermRef(LD->tmp.h[i]))
    return w
end

# (untyped: an implementation's leaves may be of different concrete types under one term type)
"`p` is a compound `name/arity` (`hasFunctor`): a symbol head named `name` and `arity` arguments."
_hasFunctor(p, name, arity::Int) =
    kind(p) === EXPR && nchildren(p) == arity + 1 && kind(child(p, 1)) === SYM &&
    sym_key(child(p, 1)) == sym_key(name)

# PORT: pl-fli.h classify_exception
"The class of the ball term reference `exception` holds, `EXCEPT_NONE` for none (pl-fli.h)."
function classify_exception(ld::PL_local_data{T}, exception::Int)::except_class where {T}
    exception == 0 && return EXCEPT_NONE
    k, w, _ = _deref_loc(ld, -(exception + 1))      # valTermRef(exception); deRef (L1e e5: the words)
    return classify_exception_cells(ld, k, w)
end

# PORT: pl-fli.c classify_exception_p as classify_exception_cells
# DIVERGES: on a dereferenced location's `(kind, word)` (L1e e5), the functors compared as words.
# `error(resource_error(_), _)` is `EXCEPT_RESOURCE` since upstream's fix 85d0cc2
# (SWI-Prolog/swipl-devel#1535, docs/upstream_reports.md #5); until it the test was for the ATOM
# `resource_error`, which nothing raises, and the stack overflow's error ranked as an ordinary one.
"The class of the exception the dereferenced `(k, w)` holds (pl-fli.c `classify_exception_p`)."
function classify_exception_cells(
    ld::PL_local_data{T}, k::UInt8, w::word
)::except_class where {T}
    k == DU_CELL && return EXCEPT_NONE                                  # isVar(*p)
    if k == DU_WORD && isAtomW(w)                                       # isTextAtom(*p)
        w == _atom_word!(ld, mk_sym(T, :time_limit_exceeded)) && return EXCEPT_TIMEOUT
    elseif k == DU_WORD && _is_gcompound(w)
        q = valPtr(w)
        f = ld.gstack[q]
        if f == lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :error)), 2)                                          # hasFunctor(*p, FUNCTOR_error2)
            ka, wa, _ = _deref_loc(ld, q + 1)                          # p = argTermP(*p, 0); deRef(p)
            ka == DU_WORD && _is_gcompound(wa) &&
                ld.gstack[valPtr(wa)] == lookupFunctorDef(
                    ld.functors, _atom_word!(ld, mk_sym(T, :resource_error)), 1
                ) &&
                return EXCEPT_RESOURCE
            return EXCEPT_ERROR
        elseif f == lookupFunctorDef(
            ld.functors, _atom_word!(ld, mk_sym(T, :time_limit_exceeded)), 1
        )
            return EXCEPT_TIMEOUT
        elseif f == lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :unwind)), 1)
            ka, wa, _ = _deref_loc(ld, q + 1)
            ka == DU_WORD && isAtomW(wa) && wa == _atom_word!(ld, mk_sym(T, :abort)) &&
                return EXCEPT_ABORT
            if ka == DU_WORD && _is_gcompound(wa)
                fa = ld.gstack[valPtr(wa)]
                fa == lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :halt)), 1) &&
                    return EXCEPT_HALT
                fa == lookupFunctorDef(
                    ld.functors, _atom_word!(ld, mk_sym(T, :thread_exit)), 1
                ) && return EXCEPT_THREAD_EXIT
            end
            return EXCEPT_UNWIND
        end
    end
    return EXCEPT_OTHER
end

# PORT: pl-fli.c PL_get_atom
# DIVERGES: returns the atom, or `nothing`, where upstream writes it through `a` and returns a Bool;
# on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): an atom word its symbol (`_atom_value`).
"The atom term reference `t` holds — a text atom or a reserved symbol such as `[]` — or `nothing` (pl-fli.c)."
function PL_get_atom(ld::PL_local_data{T}, t::term_t)::Union{Nothing, T} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        isAtomW(w) && return _atom_value(ld, w)             # isAtom(w)
    end
    return nothing
end

# ORIGINAL (R2 LB4 b2): the integer a `DU_VALUE` word that is not tagged holds, on a term type that tags no
# integer. Upstream keeps every integer of the tagged range tagged, so its `int` and `unsigned int` readers
# (swipl-devel cbf4e189 src/pl-fli.c:2004-2040) test the tag alone; a term type with no `Int64` payload
# (`_tagged_int_word`: the fixture `Term{Union{BigInt, Float64, String}}` of the D-0231 rows) writes even 0 as
# a value-table word, so on it the boot files' `:- meta_predicate` masks (`PL_cvt_i_uint`) read as no integer
# and five init.pl directives failed. `nothing` on every other type (`_holds_payload` is a compile-time
# constant: the branch folds away), and for a value that is not an integer of `Int64`'s range.
"The integer an untagged value word `w` holds on a term type that tags no integer, else `nothing` (see above)."
@inline function _untagged_int(
    ld::PL_local_data{T}, w::word
)::Union{Nothing, Int64} where {T}
    _holds_payload(T, Int64) && return nothing
    v = _indirect_value(ld, w)
    (isInteger(v) && integer_is_int64(v)) || return nothing
    return int64_value(v)
end

# PORT: pl-fli.c PL_get_integer
# (swipl-devel cbf4e189, src/pl-fli.c:2003-2016)
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`; on the WORDS (L1e e2):
# a tagged integer's value (`valInt(w)`), or on a term type that tags no integer the value-table word's
# (`_untagged_int`).
"The C `int` term reference `t` holds — a tagged integer in `int`'s range — or `nothing` (pl-fli.c)."
function PL_get_integer(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_VALUE || return nothing
    val = isTaggedIntW(w) ? valInt(w) : _untagged_int(ld, w)    # isTaggedInt(w); sword val = valInt(w)
    val === nothing && return nothing
    (val > typemax(Int32) || val < typemin(Int32)) && return nothing
    return Int(val)
end

# PORT: pl-fli.c PL_get_uint
# (pl-fli.c:2027-2039 at the pin, since MOD4)
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`; on the WORDS, as
# `PL_get_integer` above (the untagged branch too).
"The C `unsigned int` term reference `t` holds — a tagged integer in `0..UINT_MAX` — or `nothing` (pl-fli.c)."
function PL_get_uint(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_VALUE || return nothing
    val = isTaggedIntW(w) ? valInt(w) : _untagged_int(ld, w)    # isTaggedInt(w); sword val = valInt(w)
    val === nothing && return nothing
    (val < 0 || val > typemax(UInt32)) && return nothing   # val < 0 || val > UINT_MAX
    return Int(val)
end

# PORT: pl-fli.c PL_cvt_i_uint
# (pl-fli.c:1252-1263 at the pin, since MOD4)
# DIVERGES: returns the value, or `nothing` after the error, where upstream writes it through `c`;
# `PL_representation_error("uint")` is its `PL_error(..., ERR_REPRESENTATION, ATOM uint)` (pl-error.c:866-872).
"""
The C `unsigned int` term reference `t` holds, or `nothing` after raising `representation_error(uint)`
(an integer out of range) or `type_error(integer, T)` (pl-fli.c).
"""
function PL_cvt_i_uint(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    c = PL_get_uint(ld, t)
    c === nothing || return c                               # if ( PL_get_uint(t, c) ) return true
    if PL_is_integer(ld, t)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :uint))  # PL_representation_error("uint")
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
    return nothing
end

# PORT: pl-fli.c PL_get_long
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`; on the WORDS
# (`valHandle(t)`, `_deref_loc`, L1d step 7a): a tagged integer its value (a `long` is 64 bits: in
# range), a value-table integer that fits `Int64` (`get_int64`) its value (a slot's side value too).
"The C `long` term reference `t` holds — an integer in `Int64`'s range — or `nothing` (pl-fli.c)."
function PL_get_long(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))
    k == DU_VALUE || return nothing
    isTaggedIntW(w) && return Int(valInt(w))                # isTaggedInt(w)
    v = _indirect_value(ld, w)
    (isInteger(v) && integer_is_int64(v)) && return Int(int64_value(v))   # get_int64(w, &i64)
    return nothing
end

# PORT: pl-fli.c PL_get_int64
# DIVERGES: `Int` is 64 bits and a C `long` is 64 bits on the kernel's platform (LP64), so it is `PL_get_long`.
"The `int64_t` term reference `t` holds — an integer in `Int64`'s range — or `nothing` (pl-fli.c)."
PL_get_int64(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_long(ld, t)

# PORT: pl-fli.c atom_to_bool
# DIVERGES: `nothing` for neither, where upstream returns -1.
"The Boolean atom `a` names — `true`/`on` or `false`/`off` — or `nothing` (pl-fli.c)."
function atom_to_bool(ld::PL_local_data{T}, a::T)::Union{Nothing, Bool} where {T}
    k = sym_key(a)
    (k == sym_key(mk_sym(T, Symbol("true"))) || k == sym_key(mk_sym(T, :on))) && return true
    (k == sym_key(mk_sym(T, Symbol("false"))) || k == sym_key(mk_sym(T, :off))) &&
        return false
    return nothing
end

# PORT: pl-fli.c PL_get_stdbool
# DIVERGES: returns the Boolean, or `nothing`, where upstream writes it through `b`.
"The Boolean term reference `t` holds — `true`/`on`, `false`/`off`, `1` or `0` — or `nothing` (pl-fli.c)."
function PL_get_stdbool(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Bool} where {T}
    k, x, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t) (L1e e2: the words)
    k == DU_WORD && isAtomW(x) && return atom_to_bool(ld, _atom_value(ld, x))   # isAtom(w)
    if k == DU_VALUE                                        # w == consInt(0) / consInt(1)
        isTaggedIntW(x) && valInt(x) == 0 && return false
        isTaggedIntW(x) && valInt(x) == 1 && return true
    end
    return nothing
end

# PORT: pl-fli.c PL_get_functor
# DIVERGES: returns `(name, arity)`, or `nothing`, where upstream writes a `functor_t` (as
# `PL_get_name_arity`: an atom goal makes no functor-table entry). On the WORDS (`valHandle(t)`,
# `_deref_loc`): a compound word's functor from the functor table; an atom word (every kernel atom is
# a callable atom or a reserved symbol) as `name/0`. A compound whose head is no symbol (the kernel's
# `$expr/n`) has NO functor here — it names no predicate (query_answers, get_head_functor, callProlog
# refuse it).
"The functor of the term `t` references — `(name, arity)` of a compound or an atom — or `nothing` (pl-fli.c)."
function PL_get_functor(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        if _is_gcompound(w)                                 # isTerm(w): *f = functorTerm(w)
            f = ld.gstack[valPtr(w)]
            name = nameFunctor(ld.functors, f)
            name == ld.atom_dexpr && return nothing
            return (_atom_value(ld, name), arityFunctor(ld.functors, f))
        end
        return (_atom_value(ld, w), 0)                      # isCallableAtom(w) || isReservedSymbol(w)
    end
    return nothing
end

# PORT: pl-fli.c PL_get_intptr
# DIVERGES: the branch of a 64-bit platform whose `long` is a pointer's size (`SIZEOF_LONG ==
# SIZEOF_VOIDP`: Linux, macOS): `PL_get_long`, as `PL_get_intptr_ex`.
"The `intptr_t` term reference `t` holds, or `nothing` (pl-fli.c)."
PL_get_intptr(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_long(ld, t)

# PORT: pl-fli.c PL_get_uintptr
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`; `size_t` is 64 bits
# (the `SIZEOF_VOIDP < 8` range check is not taken).
"The non-negative integer term reference `t` holds, as an unsigned `size_t`, or `nothing` (pl-fli.c)."
function PL_get_uintptr(ld::PL_local_data{T}, t::term_t)::Union{Nothing, UInt} where {T}
    v = PL_get_int64(ld, t)                                 # PL_get_int64(t, &val)
    (v === nothing || v < 0) && return nothing              # val < 0
    return UInt(v)                                          # *i = (size_t)val
end

# PORT: pl-fli.c PL_get_pointer
# DIVERGES: returns the pointer as a `UInt` (a `uintptr_t`), or `nothing`, where upstream writes a
# `void *` through `ptr`; on a 64-bit platform `intToPointer` is the identity (pl-inline.h), so a
# negative `int64_t` is the pointer of its bits.
"The pointer the integer term reference `t` holds, as a `UInt`, or `nothing` (pl-fli.c)."
function PL_get_pointer(ld::PL_local_data{T}, t::term_t)::Union{Nothing, UInt} where {T}
    p = PL_get_int64(ld, t)                                 # PL_get_int64(t, &p)
    p === nothing && return nothing
    return reinterpret(UInt, p)                             # *ptr = intToPointer((uintptr_t)p)
end

# PORT: pl-fli.c PL_get_bool
# DIVERGES: as `PL_get_stdbool` (upstream writes an `int`).
"The Boolean term reference `t` holds, or `nothing` (pl-fli.c)."
PL_get_bool(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_stdbool(ld, t)

# PORT: pl-fli.c PL_get_name_arity_sz as PL_get_name_arity
# DIVERGES: returns `(name, arity)`, or `nothing`, where upstream writes them through pointers; a
# compound whose head is no symbol (the kernel's `$expr/n`) is named `$expr`, its arity the number
# of its children, as the writer writes it. On the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b —
# the FLI readers the writer calls, L1e done early): a compound word's functor from the functor table
# (`valueFunctor(functorTerm(w))`), the reserved `$expr` named as above; an atom word's symbol.
"The name and arity of the compound or the text atom term reference `t` holds, or `nothing` (pl-fli.c)."
function PL_get_name_arity(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        if _is_gcompound(w)                                 # isTerm(w)
            f = ld.gstack[valPtr(w)]                        # functorTerm(w)
            name = nameFunctor(ld.functors, f)
            arity = arityFunctor(ld.functors, f)
            name == ld.atom_dexpr && return (mk_sym(T, Symbol("\$expr")), arity)
            return (_atom_value(ld, name), arity)
        end
        a = _atom_value(ld, w)
        isTextAtom(a) && return (a, 0)                      # isTextAtom(w)
    end
    return nothing
end

# PORT: pl-fli.c _PL_get_arg_sz as _PL_get_arg
# DIVERGES: a compound whose head is no symbol (`$expr/n`) has every child as an argument (see
# `PL_get_name_arity`), so its argument `index` is child `index`; else child `index + 1`.
# On the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a compound word's argument cell into `a` as `linkValI` reads it
# (`_slot_from_cell!`: the cell's word, or a reference to it — an unbound cell, or a value-table word,
# which upstream copies as its indirect and a slot does not hold); on the cells a `$expr/n` compound
# has every child as an argument already. Not a compound: false (upstream's `PL_get_arg`).
"Put argument `index` (from 1) of the compound term reference `t` holds into `a` (pl-fli.c)."
function _PL_get_arg(ld::PL_local_data{T}, index::Int, t::term_t, a::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD && _is_gcompound(w)
        _slot_from_cell!(ld, a + 1, valPtr(w) + index)      # setHandle(a, linkValI(&f->arguments[index-1]))
        return true
    end
    return false
end

# PORT: pl-fli.c PL_get_arg_sz as PL_get_arg
# DIVERGES: a compound whose head is no symbol has every child as an argument (see `_PL_get_arg`);
# the negative `int` index of the `PL_get_arg` wrapper (a fatal error upstream) is no argument here; the
# `valid_term_t`/`valid_user_term_t` checks are upstream's `O_VALIDATE_API` and are not made.
"Put argument `index` (from 1) of the compound term reference `t` holds into `a`; false if `t` is no compound or has no such argument (pl-fli.c)."
function PL_get_arg(ld::PL_local_data{T}, index::Int, t::term_t, a::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD && _is_gcompound(w) && index > 0        # isTerm(w) && index > 0
        q = valPtr(w)
        if index <= arityFunctor(ld.functors, ld.gstack[q]) # --index < arity
            _slot_from_cell!(ld, a + 1, q + index)          # setHandle(a, linkValI(&f->arguments[index]))
            return true
        end
    end
    return false
end

# PORT: pl-fli.c PL_get_compound_name_arity_sz as PL_get_compound_name_arity
# DIVERGES: returns `(name, arity)`, or `nothing`, where upstream writes them through pointers; a
# compound whose head is no symbol is named `$expr`, as `PL_get_name_arity` names it.
"The name and arity of the compound term reference `t` holds — an atom is none — or `nothing` (pl-fli.c)."
function PL_get_compound_name_arity(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD && _is_gcompound(w)                     # isTerm(w)
        f = ld.gstack[valPtr(w)]                            # fd = valueFunctor(functorTerm(w))
        name = nameFunctor(ld.functors, f)
        arity = arityFunctor(ld.functors, f)
        name == ld.atom_dexpr && return (mk_sym(T, Symbol("\$expr")), arity)
        return (_atom_value(ld, name), arity)
    end
    return nothing
end

# PORT: pl-fli.h PL_is_functor
# DIVERGES: the functor is a name and an arity (upstream: a `functor_t`); on the WORDS
# (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e done early): a
# compound word's functor compared by arity and name (`hasFunctor`) — a `$expr/n` compound has no
# symbol head, so it is no `name/arity`.
"Whether term reference `t` holds a compound `name/arity` (pl-fli.h)."
function PL_is_functor(ld::PL_local_data{T}, t::term_t, name::T, arity::Int)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        _is_gcompound(w) || return false                    # hasFunctor(w, f)
        f = ld.gstack[valPtr(w)]
        arityFunctor(ld.functors, f) == arity || return false
        n = nameFunctor(ld.functors, f)
        n == ld.atom_dexpr && return false
        return sym_key(_atom_value(ld, n)) == sym_key(name)
    end
    return false
end

# PORT: pl-fli.c PL_is_pair
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a compound word whose functor is `'[|]'/2` (`FUNCTOR_dot2`).
"Whether term reference `t` holds a list cell (pl-fli.c)."
function PL_is_pair(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        return _is_gcompound(w) && ld.gstack[valPtr(w)] == ld.functor_dot2   # isList(w)
    end
    return false
end

# PORT: pl-fli.c PL_get_list
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a list cell's head and tail cells into `h` and `t` as `linkValI` reads
# them (`_slot_from_cell!`) — the cell's position read first, so `PL_get_list(l, h, l)` holds.
"Put the head and the tail of the list cell term reference `l` holds into `h` and `t` (pl-fli.c); false if it holds none."
function PL_get_list(ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(l + 1))                      # word w = valHandle(l)
    if k == DU_WORD
        if _is_gcompound(w) && ld.gstack[valPtr(w)] == ld.functor_dot2   # isList(w)
            a = valPtr(w) + 1                               # Word a = argTermP(w, 0)
            _slot_from_cell!(ld, h + 1, a)                  # setHandle(h, linkValI(a++))
            _slot_from_cell!(ld, t + 1, a + 1)              # setHandle(t, linkValI(a))
            return true
        end
    end
    return false
end

# PORT: pl-fli.c PL_get_nil
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): the `[]` word (`ATOM_nil`).
"Whether term reference `l` holds `[]` (pl-fli.c)."
function PL_get_nil(ld::PL_local_data{T}, l::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(l + 1))                      # word w = valHandle(l)
    k == DU_WORD && return w == ld.atom_nil_w               # isNil(w)
    return false
end

# PORT: pl-fli.c PL_is_list
# DIVERGES: on the WORDS (L1e e2): a `'[|]'/2` compound word or ATOM_nil (`isList(w) || isNil(w)`).
"Whether term reference `t` holds a list cell or `[]` (pl-fli.c)."
function PL_is_list(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    return k == DU_WORD && (w == ld.atom_nil_w || _is_list_word(ld, k, w))
end

# ORIGINAL (L1e e2): pl-data.h `hasFunctor(w, FUNCTOR_colon2)` on a dereferenced location's word.
# The functor is the constant `FUNCTOR_colon2` (src/pl-prims.jl; pl-data.h:274 at the pin cbf4e189 compares
# against the generated constant), not a per-call lookup: a lookup boxed a `:` symbol on every test (MOD4).
"Whether `(k, w)` from `_deref_loc` is a `:/2` compound word."
@inline function _is_colon2_word(ld::PL_local_data{T}, k::UInt8, w::word)::Bool where {T}
    k == DU_WORD && _is_gcompound(w) || return false
    return ld.gstack[valPtr(w)] == FUNCTOR_colon2           # valueTerm(w)->definition == FUNCTOR_colon2
end

# ORIGINAL (L1e e2): upstream's `setHandle(h, linkValI(p))` for slot `i` from a dereferenced location
# `(k, w, p)`: a cell that `needsRef` — unbound, or (AV1) an attributed variable — its reference
# (`makeRefG(p)`), any other word itself — but a value-table word
# into a slot older than the innermost foreign frame as its value (e1's rule, `_slot_store!`), and a slot's
# side value read as a value (its side word, f3-1) as its value wherever the slot lies.
"Store in slot `i` what the dereferenced location `(k, w, p)` holds (`setHandle(h, linkValI(p))`)."
function _slot_link_loc!(
    ld::PL_local_data{T}, i::Int, (k, w, p)::Tuple{UInt8, word, Int}
)::Nothing where {T}
    if k == DU_CELL || k == DU_ATTVAR                   # needsRef(w)
        ld.slots[i] = makeRefG(p)
    elseif _is_side_word(w) || (_is_vword(w) && _slot_older_than_fli(ld, i))
        _slot_store!(ld, i, _indirect_value(ld, w))
    else
        ld.slots[i] = w
    end
    return nothing
end

# PORT: pl-fli.c PL_strip_module_flags as PL_strip_module
# DIVERGES: as `PL_strip_module_ex` — the module an index into `gd`'s table, passed in and returned
# (0 for upstream's NULL), an unqualified term getting the context module when none is given (since MOD2;
# `user` outside a frame); no `flags`
# (`SM_NOCREATE`: its callers are not ported).
"""
    PL_strip_module(gd, ld, raw, m, plain) -> (ok, m)

Put the term in `raw`, stripped of its atom `Module:` qualifiers, into `plain`, and return the
module they name (pl-fli.c): unlike `PL_strip_module_ex`, a qualifier that is no atom stays.
"""
function PL_strip_module(
    gd::PL_global_data{T}, ld::PL_local_data{T}, raw::term_t, m::Int, plain::term_t
)::Tuple{Bool, Int} where {T}
    k, w, q = _deref_loc(ld, -(raw + 1))                    # p = valTermRef(raw); deRef(p)
    if _is_colon2_word(ld, k, w)                            # hasFunctor(*p, FUNCTOR_colon2)
        ok, rc, m2 = stripModule_cells(gd, ld, -(raw + 1))
        ok || return (false, m2)
        _slot_link_loc!(ld, plain + 1, rc)                  # setHandle(plain, linkValI(p))
        return (true, m2)
    end
    if m == 0                                   # if ( *m == NULL )
        # *m = environment_frame ? contextModule(environment_frame) : MODULE_user   (since MOD2)
        m = if ld.environment_frame != 0
            contextModule(gd, ld, ld.environment_frame)
        else
            MODULE_user(gd).index
        end
    end
    raw != plain && _slot_link_loc!(ld, plain + 1, (k, w, q))   # needsRef(*p) ? makeRefG(p) : *p
    return (true, m)
end

# PORT: pl-fli.c charCode
# DIVERGES: the atom's text is its `sym_text` (since R1): ONE CHARACTER — one code point — gives its
# code, where upstream reads a one-byte ISO-Latin-1 atom or a one-`wchar_t` UCS atom (and, on a
# 2-byte `wchar_t`, a surrogate pair): the same characters, read from UTF-8.
"The character code of the one-character text atom `w`, else -1 (pl-fli.c): `[]` is not text."
function charCode(w)::Int
    if kind(w) === SYM                                      # isAtom(w)
        (is_reserved_symbol(w) || is_blob(w)) && return -1  # not PL_BLOB_TEXT
        s = sym_text(w)
        length(s) == 1 && return Int(s[1])
    end
    return -1
end

# PORT: pl-fli.c uncachedCodeToAtom
# DIVERGES: the atom is a term of the term type `T` (an atom is a symbol), built by `_atom_from_text` from the
# character (so a code 0 is refused as in every atom: `NotPortedError`); upstream's `lookupAtom` of the one byte
# (a code below 256) or its UCS-atom blob (`lookupBlob`, `put_wchar`) are one symbol of the character here.
"The one-character atom of the code `chrcode`, made afresh (pl-fli.c)."
function uncachedCodeToAtom(::Type{T}, chrcode::Int)::T where {T}
    return _atom_from_text(T, string(Char(chrcode)))
end

# PORT: pl-fli.c codeToAtom
# DIVERGES: no `GD->atoms.for_code` cache of the atoms of the codes below 2^15 (see `cleanupCodeToAtom`): a
# symbol is its text and costs no table lookup, so the page/entry branch is `uncachedCodeToAtom` itself, the
# same atom as the cache would hand back. `EOF` (-1) is `end_of_file`.
"The one-character atom of the code `chrcode`; `end_of_file` for -1 (pl-fli.c)."
function codeToAtom(::Type{T}, chrcode::Int)::T where {T}
    chrcode == -1 && return mk_sym(T, :end_of_file)         # EOF: ATOM_end_of_file
    @assert chrcode >= 0
    return uncachedCodeToAtom(T, chrcode)                   # the cache miss and the codes from 2^15 on
end

# PORT: pl-fli.c cleanupCodeToAtom
# DIVERGES: a no-op, as there is no `GD->atoms.for_code` page table to free (the cache of `codeToAtom` is
# absent: a representation difference, `codeToAtom` gives the same atom with or without it).
"Free the cache of the atoms of character codes; nothing here, there is none (pl-fli.c)."
function cleanupCodeToAtom()::Nothing
    return nothing
end

# PORT: pl-fli.c PL_strip_module_ex
# DIVERGES: the module is an INDEX into `gd`'s table (0 for upstream's NULL), passed in and returned
# with the result; with none given, an unqualified term gets the context module (since MOD2; see
# `stripModule_cells`). No `globalizeTermRef` (a slot's variable is a global cell already).
"""
    PL_strip_module_ex(gd, ld, raw, m, plain) -> (ok, m)

Put the term in `raw`, stripped of its `Module:` qualifiers, into `plain`, and return the module
they name — `m` if there are none and `m` is given, else the context module (pl-fli.c). A qualifier that is not
an atom raises `type_error(module, M)`, or `instantiation_error` when it is a variable.
"""
function PL_strip_module_ex(
    gd::PL_global_data{T}, ld::PL_local_data{T}, raw::term_t, m::Int, plain::term_t
)::Tuple{Bool, Int} where {T}
    k, w, q = _deref_loc(ld, -(raw + 1))                    # p = valTermRef(raw); deRef(p)
    if _is_colon2_word(ld, k, w)                            # hasFunctor(*p, FUNCTOR_colon2)
        ok, rc, m2 = stripModule_cells(gd, ld, -(raw + 1))
        ok || return (false, m2)
        if _is_colon2_word(ld, rc[1], rc[2])                # hasFunctor(*p, FUNCTOR_colon2)
            a1 = _deref_loc(ld, valPtr(rc[2]) + 1)          # Word a1 = argTermP(*p, 0); deRef(a1)
            _slot_link_loc!(ld, plain + 1, a1)              # setHandle(plain, linkValI(a1))
            return (PL_type_error(ld, "module", plain), m2)
        end
        _slot_link_loc!(ld, plain + 1, rc)                  # setHandle(plain, linkValI(p))
        return (true, m2)
    end
    if m == 0                                   # if ( *m == NULL )
        # *m = environment_frame ? contextModule(environment_frame) : MODULE_user   (since MOD2)
        m = if ld.environment_frame != 0
            contextModule(gd, ld, ld.environment_frame)
        else
            MODULE_user(gd).index
        end
    end
    _slot_link_loc!(ld, plain + 1, (k, w, q))               # setHandle(plain, linkValG(p))
    return (true, m)
end

# PORT: pl-fli.c has_emergency_space as has_emergency_space_local
# DIVERGES: the local stack's (upstream: of the stack passed), in positions.
"""
Whether `needed` positions fit above `lTop` — taking what is lacking from the local stack's spare
(pl-fli.c).
"""
function has_emergency_space_local(ld::PL_local_data{T}, needed::Int)::Bool where {T}
    lacking = ld.lTop + needed - ld.lMax
    lacking <= 0 && return true
    if lacking < ld.local_spare
        ld.lMax += lacking
        ld.local_spare -= lacking
        return true
    end
    return false
end

# PORT: pl-fli.c has_emergency_space as has_emergency_space_global
# DIVERGES (since L1f f1b): the global stack's (copy_exception's caller): `lacking` is what `n` more cells take past
# the limit (`_stacks_in_use`), taken from the spare (upstream: `s->max` raised by it).
"Whether `n` more global cells fit, using the global stack's spare if needed (pl-fli.c `has_emergency_space`)."
function has_emergency_space_global(ld::PL_local_data, n::Int)::Bool
    lacking = _stacks_in_use(ld, n) - ld.stacks_limit
    lacking <= 0 && return true
    if lacking < ld.global_spare
        ld.global_spare -= lacking                  # s->max += lacking; s->spare -= lacking
        return true
    end
    return false
end

# PORT: pl-fli.c copy_exception as copy_exception!
# DIVERGES (L1e e5): `duplicate_term(ex, bin)` on the CELLS (`do_copy_term_cells`, share off; L1d step 6)
# into a fresh global cell that `bin` references, as upstream's copy at gTop; PL_raise_exception then
# freezes the global stack (`freezeGlobal!`), so no undo frees the ball — left below `frozen_bar` until
# a collection frees it (upstream lowers the bar at a thread's end only; G1-E). A copy that does
# not fit (since L1f f1b: `GLOBAL_OVERFLOW`, the frame rewound, nothing raised to clear) takes upstream's
# three fallbacks in turn: an `error(F, _)` ball without its context, `error(resource_error(stack),
# global)` in the global spare, `abort`. The kernel prints none of upstream's three warnings
# (decision 1). A copy fails only before `exception_processing` is set — PL_raise_exception sets it
# first, as upstream, whose fallbacks need memory exhaustion.
"Copy the ball `ex` references into `bin`, its cycles kept (pl-fli.c)."
function copy_exception!(ld::PL_local_data{T}, ex::term_t, bin::term_t)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    dest = allocGlobalCells!(ld, 1)             # (L1e e5) duplicate_term() onto the cells, `bin` its reference
    rc = do_copy_term_cells(ld, -(ex + 1), dest, cp_options(COPY_ATTRS))
    if rc == 1
        ld.slots[bin + 1] = makeRefG(dest)
        PL_close_foreign_frame(ld, fid)
        return true
    end
    PL_rewind_foreign_frame(ld, fid)
    PL_clear_exception(ld)
    ld.exception_processing = true
    if PL_is_functor(ld, ex, mk_sym(T, :error), 2)
        arg = PL_new_term_ref(ld)
        f = PL_new_term_ref(ld)
        if _PL_get_arg(ld, 1, ex, arg) && copy_term_refs(ld, arg, f, cp_options(COPY_ATTRS))
            p = allocGlobalCells!(ld, 3)        # PL_cons_functor_v(bin, FUNCTOR_error2, av)
            ld.gstack[p] = lookupFunctorDef(
                ld.functors, _atom_word!(ld, mk_sym(T, :error)), 2
            )
            ld.gstack[p + 1] = ld.slots[f + 1]  # av+0: the formal's copy; av+1 a fresh variable
            ld.slots[bin + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)
            PL_close_foreign_frame(ld, fid)     # (WARNING: Removed error context …: not printed)
            return true
        end
    elseif has_emergency_space_global(ld, 5)
        p = allocGlobalCells!(ld, 5)            # (WARNING: cannot raise exception …: not printed)
        ld.gstack[p] = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :error)), 2)
        ld.gstack[p + 1] = consPtr(p + 3, TAG_COMPOUND | STG_GLOBAL)
        ld.gstack[p + 2] = _atom_word!(ld, mk_sym(T, :global))
        ld.gstack[p + 3] = lookupFunctorDef(
            ld.functors, _atom_word!(ld, mk_sym(T, :resource_error)), 1
        )
        ld.gstack[p + 4] = _atom_word!(ld, mk_sym(T, :stack))
        ld.slots[bin + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)
        PL_close_foreign_frame(ld, fid)
        return true
    end
    PL_close_foreign_frame(ld, fid)
    ld.slots[bin + 1] = _atom_word!(ld, mk_sym(T, :abort))   # PL_put_atom(bin, ATOM_abort)
    return true
end

# PORT: pl-fli.c PL_raise_exception
# DIVERGES: the ball is copied by `copy_exception!` (see there: `duplicate_term`, its cycles kept as
# untrailed bindings); `freezeGlobal` is that copy's.
"Make the term `exception` references the pending exception, unless a more urgent one is pending; false (pl-fli.c)."
function PL_raise_exception(ld::PL_local_data{T}, exception::Int)::Bool where {T}
    @assert exception < ld.lTop                             # valTermRef(exception) < lTop
    PL_is_variable(ld, exception) &&                        # if ( PL_is_variable(exception) )
        error("Cannot throw variable exception")            # fatalError()

    ld.exception_processing = true                          # LD->exception.processing = true
    if exception != ld.exception_bin                        # re-throwing
        co = classify_exception(ld, ld.exception_bin)
        cn = classify_exception(ld, exception)
        if cn >= co
            if cn == EXCEPT_RESOURCE
                enableSpareStacks!(ld)
            end
            copy_exception!(ld, exception, ld.exception_bin)
            PL_is_atom(ld, ld.exception_bin) || freezeGlobal!(ld)   # if (!PL_is_atom(exception_bin)) freezeGlobal()
        end
    end
    ld.exception_term = ld.exception_bin

    return false
end

# ── the subset built-ins use (V5a2) ──────────────────────────────────────────────────────────────

# PORT: pl-fli.h PL_is_variable
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): an unbound cell or (AV1b) an attributed variable.
"Whether term reference `t` holds a variable, unbound or attributed (pl-fli.h; `canBind`)."
function PL_is_variable(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, _, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    return k == DU_CELL || k == DU_ATTVAR                   # canBind(w) (AV1b)
end

# PORT: pl-fli.h PL_is_attvar
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`), as `PL_is_variable`; one function for upstream's
# two (this inline LD form and pl-fli.c's API stub, which only validates `t`).
"Whether term reference `t` holds an attributed variable (pl-fli.h; `isAttVar`)."
function PL_is_attvar(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, _, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    return k == DU_ATTVAR                                   # return isAttVar(w)
end

# The type tests on a term reference (V6b): `valHandle(t)` is the slot dereferenced through the
# bindings; each then asks pl-data.h's test (src/pl-incl.jl).

# PORT: pl-fli.c PL_is_integer
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a tagged integer, or a value-table word whose entry is an integer
# (upstream's indirect).
"Whether term reference `t` holds an integer (pl-fli.c)."
function PL_is_integer(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isInteger(w)
        return isTaggedIntW(w) || isInteger(_indirect_value(ld, w))
    end
    return false
end

# PORT: pl-fli.c PL_is_float
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1e e2): a value-table word whose entry is a float
# (upstream's indirect, `isFloat(w)`).
"Whether term reference `t` holds a float (pl-fli.c)."
function PL_is_float(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isFloat(w)
        return !isTaggedIntW(w) && isFloat(_indirect_value(ld, w))
    end
    return false
end

# PORT: pl-fli.c PL_is_rational
# DIVERGES: on the WORDS (L1e e2): a tagged integer, or a value-table word whose entry is an integer or a
# rational (`isRational(w)`).
"Whether term reference `t` holds a rational number, an integer included (pl-fli.c)."
function PL_is_rational(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isRational(w)
        return isTaggedIntW(w) || isRational(_indirect_value(ld, w))
    end
    return false
end

# PORT: pl-fli.c PL_is_compound
# DIVERGES: on the WORDS (L1e e2): a compound word (`isTerm(w)`).
"Whether term reference `t` holds a compound term (pl-fli.c)."
function PL_is_compound(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_WORD && return _is_gcompound(w)                 # isTerm(w)
    return false
end

# PORT: pl-fli.c isCallable
# DIVERGES: no closure blobs. A compound with a non-symbol head (`$expr/n`, the kernel's) is not
# callable: its name is no text atom, as `lookupBodyProcedure` refuses it as a goal.
"Whether `t` is callable (pl-fli.c `isCallable`): a text atom, or a compound named by one or by `[]`."
function isCallable(t)::Bool
    if isTerm(t)
        h = child(t, 1)
        return kind(h) === SYM && ((!is_reserved_symbol(h) && !is_blob(h)) || is_nil(h))  # PL_BLOB_TEXT || ATOM_nil
    end
    return isTextAtom(t)
end

# PORT: pl-fli.c PL_is_callable
# DIVERGES: on the WORDS (L1e e2): a text atom's word, or a compound word whose functor is named by a text
# atom or `[]` (`isCallable`: no closure blobs; a `$expr/n` functor is not callable, as on terms).
"Whether term reference `t` holds a callable term (pl-fli.c)."
function PL_is_callable(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        isAtomW(w) && return isTextAtom(_atom_value(ld, w))
        name = nameFunctor(ld.functors, ld.gstack[valPtr(w)])   # a compound: its functor's name
        name == ld.atom_dexpr && return false
        h = _atom_value(ld, name)
        return (!is_reserved_symbol(h) && !is_blob(h)) || is_nil(h)  # PL_BLOB_TEXT || ATOM_nil
    end
    return false
end

# PORT: pl-fli.c PL_is_string
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a value-table word whose entry is a string (upstream's indirect).
"Whether term reference `t` holds a string (pl-fli.c)."
function PL_is_string(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isString(w)
        return !isTaggedIntW(w) && isString(_indirect_value(ld, w))
    end
    return false
end

# PORT: pl-fli.h PL_is_atom
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): an atom word whose symbol is text (`isTextAtom`).
"Whether term reference `t` holds a text atom — not `[]` (pl-fli.h)."
function PL_is_atom(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_WORD && return isAtomW(w) && isTextAtom(_atom_value(ld, w))   # isTextAtom(w)
    return false
end

# PORT: pl-fli.c PL_is_blob
# DIVERGES: returns the NAME of the blob type (`nothing` when `t` holds no atom) where upstream returns a
# bool and sets `*type`; the type is read off the symbol: a blob's own type, `reserved_symbol`, else `text`
# (`ucs_text` for a text with a character above 0xFF, as `textToAtom` stores it).
"The blob type name of the atom term reference `t` holds, else `nothing` (pl-fli.c `PL_is_blob`)."
function PL_is_blob(ld::PL_local_data{T}, t::term_t)::Union{Nothing, String} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    (k == DU_WORD && isAtomW(w)) || return nothing
    a = _atom_value(ld, w)
    is_blob(a) && return string(blob_type(a))
    is_reserved_symbol(a) && return "reserved_symbol"
    return _is_ucs_text(sym_text(a)) ? "ucs_text" : "text"
end

# ORIGINAL: pl-atom.c blob/2 as pl_blob2_va
# (PRED_IMPL("blob", 2, blob, 0))
# DIVERGES: placed after the FLI it calls (pl-atom.jl is loaded before `PL_local_data`); a dead blob
# reports `deadBlobType` as upstream (since RD2); no released blobs.
"`blob(@Term, ?Type)` (pl-atom.c): `Term` is an atom of blob type `Type`."
function pl_blob2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    name = PL_is_blob(ld, A1)
    name === nothing && return FFALSE
    if name == unavailable_blob.name                        # dead blob: report the type it
        _, w, _ = _deref_loc(ld, -(A1 + 1))                 # stands for, not `unavailable'
        dead = deadBlobType(ld.atoms, blob_handle(_atom_value(ld, w)))
        dead === nothing || return PL_unify_atom(ld, A2, _atom_from_text(T, dead)) ? FTRUE : FFALSE
    end
    return PL_unify_atom(ld, A2, mk_sym(T, Symbol(name))) ? FTRUE : FFALSE
end

# PORT: pl-atom.c blob_released as pl_blob_released1_va
# (PRED_IMPL("blob_released", 1, blob_released, 0))
# DIVERGES: the kernel has no `PL_free_blob`, so no atom has a NULL name (`!x->name`, upstream's test of a
# released blob): the answer is failure for every term, as `blob/2` meets no released blob (`deadBlobType`).
"`blob_released(@Term)` (pl-atom.c): `Term` is a blob whose data was released; here no blob is."
function pl_blob_released1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    PL_get_atom(ld, A1) === nothing && return FFALSE        # PL_get_atom(A1, &a)
    return FFALSE                                           # atomValue(a)->name is never NULL
end

# PORT: pl-atom.c current_blob
# DIVERGES: placed after the FLI it calls (pl-atom.jl is loaded before `PL_local_data`); `type` is
# `nothing` for upstream's NULL (`current_atom/1`: the text types only, `[]` is a reserved symbol and
# no text). `call` and `state` are `PL_foreign_control` and `PL_foreign_context` of the call; the answer
# is the foreign return value (upstream returns an `atom_t` that stands for it). The type of an atom is
# its blob type's NAME, compared as text (upstream compares the name atoms); a type given as a blob or
# `[]` names no type (no blob type has an empty name, so `tname` = "" matches none). The atoms
# enumerated are those of the database's table that carry an interface symbol (`atomSymbol`, recorded
# when the atom first got a word from a symbol, `_atom_word!`: the only atoms a Prolog term can hold);
# an atom that has none is skipped. Left out with the atom GC (`bump_atom_references`,
# `PL_unregister_atom`, `ATOM_garbage_collected`, `CHK_ATOM_GARBAGE_COLLECTED`): with no AGC an atom of
# the table is never freed under the enumeration, so the walk takes no reference.
"""
The worker of `current_blob/2` and `current_atom/1`: enumerate the atoms of the table by index, `state`
the next index to try (pl-atom.c).
"""
function current_blob(
    ld::PL_local_data{T}, a::term_t, type::Union{Nothing, term_t}, call::Int, state::Int
)::foreign_t where {T}
    index = 0
    if call == FRG_FIRST_CALL
        name = PL_is_blob(ld, a)
        if name !== nothing
            if type !== nothing
                return PL_unify_atom(ld, type, mk_sym(T, Symbol(name))) ? FTRUE : FFALSE
            end
            reg = PL_find_blob_type(ld.atoms, name)
            reg === nothing && return FFALSE
            reg.type.flags & PL_BLOB_TEXT == 0 && return FFALSE
            return FTRUE
        end
        PL_is_variable(ld, a) || return FFALSE
        index = 1
    elseif call == FRG_REDO
        index = state
    else
        return FTRUE                                        # FRG_CUTTED
    end

    have_type = false
    tname = ""
    if type !== nothing && !PL_is_variable(ld, type)
        tn = PL_get_atom_ex(ld, type)
        tn === nothing && return FFALSE
        have_type = true
        tname = (is_blob(tn) || is_reserved_symbol(tn)) ? "" : sym_text(tn)
    end

    atoms = ld.atoms
    i = MSB(index)
    last = false
    while !last
        upto = 2 << i
        high = atoms.highest
        b = atoms.array[i + 1]
        if upto >= high
            upto = high
            last = true
        end

        if b === nothing
            index = max(index, upto)
        else
            while index < upto
                at = b[index - (1 << i) + 1]
                btype = at.type
                if ATOM_IS_VALID(at.references) && btype !== ATOM_TYPE_INVALID &&
                    (!have_type || tname == btype.name)
                    sym = atomSymbol(ld.atom_symbols, index)
                    if sym !== nothing
                        if type !== nothing
                            if !have_type
                                PL_unify_atom(ld, type, mk_sym(T, Symbol(btype.name))) ||
                                    return FFALSE
                            end
                        elseif btype.flags & PL_BLOB_TEXT == 0
                            index += 1
                            continue                        # isoff(btype, PL_BLOB_TEXT)
                        end
                        PL_unify_atom(ld, a, sym) || return FFALSE
                        return PL_retry(index + 1)          # ForeignRedoInt(index+1)
                    end
                end
                index += 1
            end
        end
        i += 1
    end

    return FFALSE
end

# PORT: pl-atom.c current_blob as pl_current_blob2_va
# (PRED_IMPL("current_blob", 2, current_blob, PL_FA_NONDETERMINISTIC))
"`current_blob(?Blob, ?Type)` (pl-atom.c): `Blob` is an atom of blob type `Type`, on backtracking every one."
function pl_current_blob2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return current_blob(
        ld, A1, A2, PL_foreign_control(PL__ctx), PL_foreign_context(PL__ctx)
    )
end

# PORT: pl-atom.c pl_garbage_collect_atoms as pl_garbage_collect_atoms0
# (FRG("garbage_collect_atoms", 0, pl_garbage_collect_atoms, 0), pl-ext.c:170; pl-atom.c:1419-1469 at the pin)
# DIVERGES: the body of the collection (`unmarkAtoms`, `markAtomsOnStacks`, `markAtomsInTries`, `collectAtoms`, the `agc`
# statistics `GD->atoms.gc`, `gc_time` and `collected`, the verbose `agc(start)`/`agc(done(...))` messages, `freeZombieTrieChunks`)
# is left out: no atom is ever freed (src/pl-atom.jl: with the GC step), so a collection reclaims nothing and the call
# succeeds; the `GD->halt.cleaning` and `gc_active` early returns (both `true`) have no twin (no halt, one thread). A program
# that reads `statistics(agc, N)` after the call sees 0 where swipl counts the collection.
"`garbage_collect_atoms`: run the atom garbage collector (pl-atom.c); here no atom is freed, so it succeeds."
function pl_garbage_collect_atoms0(ld::PL_local_data{T})::foreign_t where {T}
    return FTRUE
end

# PORT: pl-atom.c current_atom as pl_current_atom1_va
# (PRED_IMPL("current_atom", 1, current_atom, PL_FA_NONDETERMINISTIC))
"`current_atom(?Atom)` (pl-atom.c): `Atom` is a text atom, on backtracking every one."
function pl_current_atom1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return current_blob(
        ld, A1, nothing, PL_foreign_control(PL__ctx), PL_foreign_context(PL__ctx)
    )
end

# PORT: pl-atom.c complete_atom as pl_complete_atom3_va
# (PRED_IMPL("$complete_atom", 3, complete_atom, 0))
# DIVERGES: `PL_get_nchars(prefix, …, CVT_ALL|CVT_EXCEPTION)` is `PL_get_text` plus the refusal of a wide
# text, `representation_error(encoding)` for ISO Latin-1 as upstream's `PL_mb_text`; the code list is
# `PL_unify_text` of a canonical ISO Latin-1 text. Nothing unregisters an atom here, so `references`
# of every atom stays 1 and `global_atom` holds for all: an atom swipl has collected is still offered.
"""
`'\$complete_atom'(+Prefix, -Common, -Unique)` (pl-atom.c): `Common` is the code list of `Prefix` and the
text all atoms with that prefix share, `Unique` is `unique` or `not_unique`.
"""
function pl_complete_atom3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    t = PL_get_text(ld, A1, CVT_ALL | CVT_EXCEPTION)
    t === nothing && return FFALSE
    PL_canonicalise_text_ex(ld, t) || return FFALSE
    t.encoding === ENC_WCHAR &&
        return text_representation_error(ld, ENC_ISO_LATIN_1) ? FTRUE : FFALSE
    t.length >= LINESIZ && return FFALSE                    # len >= sizeof(buf)
    z = findfirst(==(0x00), view(t.text, 1:(t.length)))     # strcpy(buf, p): up to the first NUL
    p = z === nothing ? t.text[1:(t.length)] : t.text[1:(z - 1)]

    found, u, cmm = extendAtom(ld.atoms, p)
    found || return FFALSE
    buf = vcat(p, cmm)                                      # strcat(buf, cmm)
    out = PL_chars_t(buf, length(buf), ENC_ISO_LATIN_1, true)
    return if PL_unify_text(ld, A2, 0, out, PL_CODE_LIST) &&
        PL_unify_atom(ld, A3, mk_sym(T, u ? :unique : :not_unique))
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-atom.c blob_type_from_name
# DIVERGES: returns the registration (which holds the type); the type's name atom is compared as text
# (as `current_blob`); the error is `PL_error` with `ERR_EXISTENCE`.
"The registration of the blob type named by the atom term reference `t`, or `nothing` after raising an error (pl-atom.c)."
function blob_type_from_name(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, blob_registration} where {T}
    name = PL_get_atom_ex(ld, t)
    name === nothing && return nothing
    tname = (is_blob(name) || is_reserved_symbol(name)) ? "" : sym_text(name)
    reg = PL_find_blob_type(ld.atoms, tname)
    reg === nothing || return reg
    PL_error(ld, ERR_EXISTENCE, mk_sym(T, :blob_type), t)       # PL_existence_error("blob_type", t)
    return nothing
end

# PORT: pl-atom.c BT_NPROPS
"The number of properties of a blob type, in enumeration order (pl-atom.c)."
const BT_NPROPS = 11

# PORT: pl-atom.c unify_blob_property
# DIVERGES: `PL_unify_term(prop, PL_FUNCTOR, …, PL_INT64, value)` is `PL_unify_functor` of `Name/1` and the
# unification of its argument. `unregistered` and `non_garbage` are the atom GC's bookkeeping: always 0.
"Unify `prop` with property `i` (from 0) of the registration `reg`; false for a flag the type lacks (pl-atom.c)."
function unify_blob_property(
    ld::PL_local_data{T}, prop::term_t, reg::blob_registration, i::Int
)::Bool where {T}
    flags = reg.type.flags
    if i == 0
        return flags & PL_BLOB_UNIQUE != 0 && PL_unify_atom(ld, prop, mk_sym(T, :unique))
    elseif i == 1
        return flags & PL_BLOB_TEXT != 0 && PL_unify_atom(ld, prop, mk_sym(T, :text))
    elseif i == 2
        return flags & PL_BLOB_NOCOPY != 0 && PL_unify_atom(ld, prop, mk_sym(T, :nocopy))
    elseif i == 3
        return flags & PL_BLOB_WCHAR != 0 && PL_unify_atom(ld, prop, mk_sym(T, :wchar))
    end
    name, value = if i == 4
        :rank, reg.rank
    elseif i == 5
        :padding, reg.padding
    elseif i == 6
        :gc_margin, reg.gc_margin
    elseif i == 7
        :unregistered, reg.unregistered
    elseif i == 8
        :non_garbage, reg.non_garbage
    elseif i == 9
        :live, reg.live
    elseif i == 10
        :space, reg.space
    else
        error("unify_blob_property: no property $i")
    end
    PL_unify_functor(ld, prop, mk_sym(T, name), 1) || return false
    arg = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, prop, arg)
    return PL_unify_int64(ld, arg, value)
end

# PORT: pl-atom.c blob_type_property as pl_blob_type_property2_va
# (PRED_IMPL("blob_type_property", 2, blob_type_property, PL_FA_NONDETERMINISTIC))
"`blob_type_property(?Type, ?Property)` (pl-atom.c): the registered blob type `Type` has `Property`."
function pl_blob_type_property2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    state = 0
    call = PL_foreign_control(PL__ctx)

    if call == FRG_FIRST_CALL
        if !PL_is_variable(ld, A1) && !PL_is_variable(ld, A2)
            # Both given: answer once rather than leaving a choice point on the remaining properties.
            reg = blob_type_from_name(ld, A1)
            reg === nothing && return FFALSE
            for i in 0:(BT_NPROPS - 1)
                unify_blob_property(ld, A2, reg, i) && return FTRUE
            end
            return FFALSE
        end
    elseif call == FRG_REDO
        state = PL_foreign_context(PL__ctx)
    else
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    fid == 0 && return FFALSE
    types = ld.atoms.types
    while true
        ti = state ÷ BT_NPROPS
        ti >= length(types) && break
        reg = types[ti + 1]
        if PL_unify_atom(ld, A1, mk_sym(T, Symbol(reg.type.name))) &&
            unify_blob_property(ld, A2, reg, state % BT_NPROPS)
            PL_close_foreign_frame(ld, fid)
            return PL_retry(state + 1)                      # ForeignRedoInt(state+1)
        end
        PL_rewind_foreign_frame(ld, fid)
        state += 1
    end
    PL_close_foreign_frame(ld, fid)
    return FFALSE
end

# PORT: pl-atom.c set_blob_type as pl_set_blob_type2_va
# (PRED_IMPL("set_blob_type", 2, set_blob_type, 0))
"`set_blob_type(+Type, +Property)` (pl-atom.c): set `gc_margin(Units)` of the registered blob type `Type`."
function pl_set_blob_type2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    reg = blob_type_from_name(ld, A1)
    reg === nothing && return FFALSE

    na = PL_get_name_arity(ld, A2)
    if na === nothing || na[2] != 1
        return PL_type_error(ld, "blob_type_property", A2) ? FTRUE : FFALSE
    end
    pname = na[1]

    arg = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, A2, arg)

    if !(is_blob(pname) || is_reserved_symbol(pname)) && sym_text(pname) == "gc_margin"
        margin = PL_get_size_ex(ld, arg)
        margin === nothing && return FFALSE
        reg.gc_margin = margin
        return FTRUE
    end
    return PL_domain_error(ld, "blob_type_property", A2) ? FTRUE : FFALSE
end

# PORT: pl-atom.c PL_register_atom
# DIVERGES: refused by name: the atom reference counts belong to the atom GC family (audit D-0634 D5); the
# kernel's atoms are never collected, so a reference count has no reader.
"Raise the named refusal of `PL_register_atom` (pl-atom.c)."
function PL_register_atom(ld::PL_local_data{T}, a::T)::Nothing where {T}
    throw(
        NotPortedError{T}(
            a, "PL_register_atom (pl-atom.c:1591)", "atom GC family, D-0634 D5"
        )
    )
end

# PORT: pl-atom.c PL_unregister_atom
# DIVERGES: refused by name, as `PL_register_atom`.
"Raise the named refusal of `PL_unregister_atom` (pl-atom.c)."
function PL_unregister_atom(ld::PL_local_data{T}, a::T)::Nothing where {T}
    throw(
        NotPortedError{T}(
            a, "PL_unregister_atom (pl-atom.c:1751)", "atom GC family, D-0634 D5"
        )
    )
end

# PORT: pl-atom.c _PL_debug_register_atom
# DIVERGES: refused by name: the O_DEBUG_ATOMGC build's tracing of atom references, atom GC family.
"Raise the named refusal of `_PL_debug_register_atom` (pl-atom.c)."
function _PL_debug_register_atom(
    ld::PL_local_data{T}, a::T, file::String, line::Int, func::String
)::Nothing where {T}
    throw(
        NotPortedError{T}(
            a, "_PL_debug_register_atom (pl-atom.c:1071)", "atom GC family, D-0634 D5"
        )
    )
end

# PORT: pl-atom.c _PL_debug_unregister_atom
# DIVERGES: refused by name, as `_PL_debug_register_atom`.
"Raise the named refusal of `_PL_debug_unregister_atom` (pl-atom.c)."
function _PL_debug_unregister_atom(
    ld::PL_local_data{T}, a::T, file::String, line::Int, func::String
)::Nothing where {T}
    throw(
        NotPortedError{T}(
            a, "_PL_debug_unregister_atom (pl-atom.c:1090)", "atom GC family, D-0634 D5"
        )
    )
end

# ORIGINAL: pl-atom.c BeginPredDefs(atom) as PL_predicates_from_atom
# DIVERGES: the entries ported, in upstream's order; `$atom_references/2` and `$atom_completions/2` are the
# dict and arithmetic steps', `$track_atom/2` exists in the debug build only.
"pl-atom.c's registration table (`BeginPredDefs(atom)`): the ported entries."
const PL_predicates_from_atom = (
    PL_extension(
        "blob_type_property", 2, pl_blob_type_property2_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("set_blob_type", 2, pl_set_blob_type2_va, PL_FA_VARARGS),
    PL_extension(
        "current_blob", 2, pl_current_blob2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "current_atom", 1, pl_current_atom1_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("blob", 2, pl_blob2_va, PL_FA_VARARGS),
    PL_extension("blob_released", 1, pl_blob_released1_va, PL_FA_VARARGS),
    PL_extension("\$complete_atom", 3, pl_complete_atom3_va, PL_FA_VARARGS)
)

# PORT: pl-fli.h PL_is_atomic
# DIVERGES: on the WORDS (L1e e2): an atom word or a value word (`isAtomic(w)`: neither a variable nor a
# compound).
"Whether term reference `t` holds an atomic term (pl-fli.h)."
function PL_is_atomic(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_VALUE && return true
    k == DU_WORD && return isAtomW(w)
    return false
end

# PORT: pl-fli.h PL_is_number
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a tagged integer, or a value-table word whose entry is a number
# (upstream's indirect).
"Whether term reference `t` holds a number (pl-fli.h)."
function PL_is_number(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isNumber(w)
        return isTaggedIntW(w) || isNumber(_indirect_value(ld, w))
    end
    return false
end

# PORT: pl-fli.c PL_is_inf
# DIVERGES: on the WORDS (as `PL_get_atom`): the atom word is compared with `ATOM_inf`'s and
# `ATOM_infinite`'s.
"Whether term reference `t` holds the atom `inf` or `infinite` (pl-fli.c)."
function PL_is_inf(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # PL_get_atom(t, &a)
    (k == DU_WORD && isAtomW(w)) || return false
    return w == _atom_word!(ld, mk_sym(T, :inf)) ||         # a == ATOM_inf
           w == _atom_word!(ld, mk_sym(T, :infinite))       # a == ATOM_infinite
end

# PORT: pl-fli.c PL_unify
# DIVERGES: no `ALLOW_GC|ALLOW_SHIFT`: the kernel's `unify_ptrs` takes no flags, as the binding store
# and the trail cannot overflow during a unification (its DIVERGES). On the CELLS since L1c
# sub-commit 4: the two slots are locations (`unify_ptrs_cells`), as upstream's `valTermRef`s.
"Unify the terms `t1` and `t2` reference (pl-fli.c `PL_unify`); does not undo on failure."
PL_unify(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    unify_ptrs_cells(ld, -(t1 + 1), -(t2 + 1))

# PORT: pl-fli.c PL_unify_atomic
# DIVERGES: `w` is an atomic TERM (no words); "the same word" and `equalIndirect` are the standard
# order's identity of two atomic terms (`compare_primitives` in equality mode) — `1` is not `1.0`.
"Unify the term `t` references with the atomic term `w` (pl-fli.c `PL_unify_atomic`)."
function PL_unify_atomic(ld::PL_local_data{T}, t::term_t, w::T)::Bool where {T}
    k, c, q = _deref_loc(ld, -(t + 1))                      # deRef2(valHandleP(t), p) (L1e e3: the cells)
    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*p) (an attributed variable: AV1)
        bindConst(ld, q, _word_of!(ld, w))                  # bindConst(p, w): the word made only here
        return true
    elseif k == DU_WORD                                     # *p == w: an atom's word, never a compound's
        return isAtomW(c) && kind(w) === SYM && c == _atom_word!(ld, w)
    elseif k == DU_VALUE                                    # *p == w || equalIndirect(w, *p)
        return compare_primitives(_value_term(ld, c), w, CMP_MODE_EQUAL) == CMP_EQUAL
    end
    return false
end

# PORT: pl-fli.c PL_unify_atom
"Unify the term `t` references with the atom `a` (pl-fli.c `PL_unify_atom`)."
PL_unify_atom(ld::PL_local_data{T}, t::term_t, a::T) where {T} = PL_unify_atomic(ld, t, a)

# PORT: pl-fli.c PL_unify_bool
# DIVERGES: on the term reference's atom (`PL_get_atom`), where upstream compares the word with the words of
# `true`/`on` and `false`/`off`: the same atoms (`atom_to_bool`).
"Unify the term `t` references with the Boolean `val`: a variable gets `true` or `false`, an atom must say `val` (`true`/`on`, `false`/`off`) (pl-fli.c)."
function PL_unify_bool(ld::PL_local_data{T}, t::term_t, val::Bool)::Bool where {T}
    if PL_is_variable(ld, t)                                # canBind(*p): bindConst(p, val ? ATOM_true : ATOM_false)
        return PL_unify_atom(ld, t, mk_sym(T, val ? Symbol("true") : Symbol("false")))
    end
    a = PL_get_atom(ld, t)
    a === nothing && return false
    return atom_to_bool(ld, a) === val                      # w == ATOM_true || w == ATOM_on (or false/off)
end

# PORT: pl-fli.c PL_unify_float
# DIVERGES: on the standard order's identity of two atomic terms (`PL_unify_atomic`), where upstream reads
# `isFloat(*p) && valFloat(*p) == f`: they differ for `0.0` against `-0.0` and for a NaN, neither of which
# a flag holds.
"Unify the term `t` references with the float `f` (pl-fli.c)."
PL_unify_float(ld::PL_local_data{T}, t::term_t, f::Float64) where {T} =
    PL_unify_atomic(ld, t, mk_gnd(T, f))

# PORT: pl-fli.c PL_unify_integer
# (upstream: `unify_int64_ex(t, i, false)` — on the cells since L1d step 7a; L1e e3 drops the term detour)
"Unify the term `t` references with the integer `i` (pl-fli.c `PL_unify_integer`)."
PL_unify_integer(ld::PL_local_data{T}, t::term_t, i::Int) where {T} =
    unify_int64_ex(ld, t, i, false)

# PORT: pl-fli.c unify_int64_ex
# DIVERGES: on the WORDS (`valHandleP(t)`, `_deref_loc`, L1d step 7a): an integer past the tagged range
# (or in a term type holding no `Int64`) is a value-table word (`put_int64`: upstream's indirect).
"Unify the term `t` references with the integer `i`; with `ex`, a non-integer is a type error (pl-fli.c)."
function unify_int64_ex(ld::PL_local_data{T}, t::term_t, i::Int, ex::Bool)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))
    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*p) (AV1b)
        if PLMINTAGGEDINT <= i <= PLMAXTAGGEDINT && _holds_payload(T, Int64)
            bindConst(ld, p, consInt(i))                    # valInt(w) == i: bindConst(p, w)
        else
            bindConst(ld, p, _gnd_word!(ld, mk_gnd(T, i)))  # put_int64(&w, i); bindConst
        end
        return true
    elseif k == DU_VALUE
        isTaggedIntW(w) && return valInt(w) == i            # w == *p && valInt(w) == i
        v = _indirect_value(ld, w)
        (isInteger(v) && integer_is_int64(v)) && return int64_value(v) == i   # get_int64
        isInteger(v) && return false
    end
    ex && return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)   # !isInteger(*p)
    return false
end

# PORT: pl-fli.c PL_unify_int64
"Unify the term `t` references with the integer `i` (pl-fli.c `PL_unify_int64`)."
PL_unify_int64(ld::PL_local_data{T}, t::term_t, i::Int) where {T} =
    unify_int64_ex(ld, t, i, false)

# PORT: pl-fli.c PL_unify_int64_ex
"Unify the term `t` references with the integer `i`; a non-integer is a type error (pl-fli.c)."
PL_unify_int64_ex(ld::PL_local_data{T}, t::term_t, i::Int) where {T} =
    unify_int64_ex(ld, t, i, true)

# PORT: pl-fli.c PL_unify_pointer
# DIVERGES: a pointer is a `UInt` (see `PL_put_pointer`).
"Unify the term `t` references with the pointer `ptr` as an integer (pl-fli.c)."
PL_unify_pointer(ld::PL_local_data{T}, t::term_t, ptr::UInt) where {T} =
    unify_int64_ex(ld, t, reinterpret(Int, ptr), false)      # unify_int64_ex(t, (int64_t)pointerToInt(ptr), false)

# PORT: pl-fli.c PL_unify_uint64
# DIVERGES: a value past `Int64` is unified through `PL_unify_number` with a `V_MPZ` number, where upstream builds
# the word with `put_uint64` (a variable: `PL_unify_atomic`) or compares `mpz_to_uint64` of the bound big integer;
# the outcomes agree: a variable binds to the big integer, a bound integer is equal by value, any other term fails.
"Unify the term `t` references with the unsigned integer `i`; a value above `typemax(Int64)` is a big integer (pl-fli.c)."
function PL_unify_uint64(ld::PL_local_data{T}, t::term_t, i::UInt64)::Bool where {T}
    if reinterpret(Int64, i) >= 0                           # (int64_t)i >= 0
        return unify_int64_ex(ld, t, Int(i), true)
    end
    n = _number_alloc!(ld)                                  # number n (a bigint: V_MPZ)
    n.type = V_MPZ
    n.mpz = BigInt(i)
    rc = PL_unify_number(ld, t, n)                          # put_uint64 + PL_unify_atomic / the V_MPZ compare
    _number_free!(ld, 1)
    return rc
end

# PORT: pl-fli.c PL_put_uint64
# DIVERGES: a value past `Int64` is put as a fresh variable unified (`PL_unify_uint64`) with the big integer, where
# upstream builds the word with `put_uint64`; the term the reference holds is the same integer.
"Make term reference `t` hold the unsigned integer `i`; a value above `typemax(Int64)` is a big integer (pl-fli.c)."
function PL_put_uint64(ld::PL_local_data{T}, t::term_t, i::UInt64)::Bool where {T}
    if reinterpret(Int64, i) >= 0                           # (int64_t)i >= 0
        return PL_put_int64(ld, t, Int(i))
    end
    PL_put_variable(ld, t)
    return PL_unify_uint64(ld, t, i)
end

# PORT: pl-fli.c get_float
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `f` and returns a Bool; the
# number is read into a `number` (`PL_get_number`), not from the word.
"""
The float term reference `t` holds — a float, or a rational (an integer included) promoted to one — or
`nothing`; with `ex`, a term that is neither raises `type_error(float, T)` first, and a rational too big for a
float keeps its `float_overflow` (pl-fli.c).
"""
function get_float(
    ld::PL_local_data{T}, t::term_t, ex::Bool
)::Union{Nothing, Float64} where {T}
    n = number()
    if PL_get_number(ld, t, n)
        n.type === V_FLOAT && return n.f                    # isFloat(w)
        if promoteToFloatNumber(ld, n)                      # isRational(w): promoteToFloatNumber(&n)
            return n.f
        end
        ex || PL_clear_exception(ld)
        return nothing
    end
    ex && PL_type_error(ld, "float", t)
    return nothing
end

# PORT: pl-fli.c PL_get_float
# DIVERGES: returns the value, or `nothing` (see `get_float`).
"The float term reference `t` holds (a rational is promoted), or `nothing` (pl-fli.c)."
PL_get_float(ld::PL_local_data{T}, t::term_t) where {T} = get_float(ld, t, false)

# PORT: pl-fli.c PL_get_float_ex
# DIVERGES: returns the value, or `nothing` after raising (see `get_float`).
"The float term reference `t` holds (a rational is promoted), or `nothing` after raising `type_error(float, T)` (pl-fli.c)."
PL_get_float_ex(ld::PL_local_data{T}, t::term_t) where {T} = get_float(ld, t, true)

# PORT: pl-fli.h PL_put_intptr
# DIVERGES: `PL_put_int64`'s work, inline: the reference holds the integer — its word since L1e e1 (a tagged
# integer, or a value-table word under `_slot_store!`'s older-slot rule).
"Make term reference `t` hold the integer `i` (pl-fli.h `PL_put_intptr`)."
function PL_put_intptr(ld::PL_local_data{T}, t::term_t, i::Int)::Bool where {T}
    setSlotValue!(ld, t + 1, mk_gnd(T, i))
    return true
end

# PORT: pl-fli.c PL_compare
"The standard order of the terms `t1` and `t2` reference: -1, 0 or 1 (pl-fli.c `PL_compare`)."
PL_compare(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    compareStandard_cells(ld, -(t1 + 1), -(t2 + 1), false)    # on the cells (L1d step 1)

# PORT: pl-fli.c PL_clear_exception
"Drop the pending exception, if any (pl-fli.c `PL_clear_exception`)."
function PL_clear_exception(ld::PL_local_data{T})::Nothing where {T}
    if ld.exception_term != 0
        resumeAfterException(ld, true, ld.outofstack)
        ld.outofstack = nothing                     # LD->outofstack = NULL
    end
    return nothing
end

# PORT: pl-fli.c PL_clear_foreign_exception
# DIVERGES: nothing is printed — the kernel has no `Serror` (decision 1: no messages); upstream
# prints "Foreign predicate … did not clear exception" and the ball.
"A foreign predicate succeeded with an exception pending: drop it (pl-fli.c)."
function PL_clear_foreign_exception(ld::PL_local_data{T}, fr::Int)::Nothing where {T}
    PL_clear_exception(ld)
    return nothing
end

# ── the return of a non-deterministic foreign predicate (pl-fli.c, pl-builtin.h; NF1) ──────────────
# PORT: pl-fli.c _PL_retry as PL_retry
# DIVERGES: returns the value (upstream's macro `PL_retry(n)` is `return _PL_retry(n)`).
"Succeed, to be called again with `FRG_REDO` and context `v` (pl-fli.c; `ForeignRedoInt`)."
PL_retry(v::Int)::foreign_t = (reinterpret(UInt, v) << FRG_REDO_BITS) | REDO_INT

# PORT: pl-fli.c _PL_retry_address as PL_retry_address
# DIVERGES: `i` is the index of a state in its built-in's pool (`foreign_state_pool`), where upstream's
# is an address — encoded the same way (`ForeignRedoPtr`); an index is never 0, as an address is not.
"Succeed, to be called again with `FRG_REDO` and the state at pool index `i` (pl-fli.c)."
function PL_retry_address(i::Int)::foreign_t
    @assert i >= 1 "PL_retry_address: no state"
    return UInt(i) << FRG_REDO_BITS             # ForeignRedoPtr(v): (uintptr_t)v|REDO_PTR
end

# PORT: pl-fli.c PL_foreign_control
"How a non-deterministic foreign predicate is called: `FRG_FIRST_CALL`, `FRG_REDO` or `FRG_CUTTED` (pl-fli.c)."
PL_foreign_control(h::control_t)::Int = h.control

# PORT: pl-fli.c PL_foreign_context
"The integer a `PL_retry` gave (pl-fli.c; `ForeignContextInt`)."
PL_foreign_context(h::control_t)::Int = reinterpret(Int, h.context)

# PORT: pl-fli.c PL_foreign_context_address
# DIVERGES: the pool index a `PL_retry_address` gave, where upstream's is the address.
"The state index a `PL_retry_address` gave (pl-fli.c; `ForeignContextPtr`)."
PL_foreign_context_address(h::control_t)::Int = Int(h.context >> FRG_REDO_BITS)

# ORIGINAL (NF1, design D3): upstream's `allocForeignState`/`freeForeignState` on a typed pool.
"A state record of `pool` for a new enumeration: its index (≥ 1); the record keeps its old values."
function alloc_foreign_state!(pool::foreign_state_pool{S})::Int where {S}
    pool.live += 1
    isempty(pool.free) || return pop!(pool.free)
    push!(pool.states, S())
    return length(pool.states)
end

"Give the state at index `i` back to `pool`."
function free_foreign_state!(pool::foreign_state_pool, i::Int)::Nothing
    @assert pool.live > 0 && i ∉ pool.free "free_foreign_state!: index $i is not live"
    push!(pool.free, i)
    pool.live -= 1
    return nothing
end

# ORIGINAL (NF1; audit D-0136 Q8): tests only, not exported — a leaked state (a missing
# `FRG_CUTTED`, an exception after a redo) shows as a count that does not return to 0.
"How many states of the non-deterministic built-ins are live in `ld` (a white-box count)."
live_states(ld::PL_local_data)::Int =
    ld.between_states.live + ld.retract_contexts.live + ld.clause_contexts.live +
    ld.op_enums.live +
    ld.prolog_flag_enums.live + ld.module_enums.live + ld.gvar_enums.live +
    ld.recorded_states.live + ld.cur_pred_enums.live + ld.cur_enums.live +
    ld.trie_gens.live + ld.transaction_enums.live +
    ld.coverage.states.live + ld.mutex_enums.live + ld.queue_enums.live

# ── the recorded database's C interface (pl-fli.c; F1a) ─────────────────────────────────────────
# PORT: pl-fli.c PL_record
# DIVERGES: `compileTermToHeap` takes no `R_DUPLICATE` flag (the kernel's record has no reference count).
"Record the term `t` references, so that it survives backtracking and the stacks (pl-fli.c)."
PL_record(ld::PL_local_data{T}, t::term_t) where {T} = compileTermToHeap(ld, t)

# PORT: pl-fli.c PL_recorded
"Make term reference `t` hold the term of record `r`, its variables fresh; false, the overflow raised, when it does not fit (pl-fli.c)."
PL_recorded(ld::PL_local_data{T}, r::record{T}, t::term_t) where {T} =
    copyRecordToGlobal(ld, t, r, ALLOW_GC)   # G1-GC safe point: copyRecordToGlobal

# PORT: pl-fli.c PL_erase
# DIVERGES: nothing to free — a record is freed by Julia's GC (`freeRecord`, src/pl-rec.jl).
"Erase the record `r` (pl-fli.c)."
PL_erase(r::record)::Nothing = nothing

# PORT: pl-fli.c PL_duplicate_record
# DIVERGES: the record itself, as upstream returns it with its reference count raised: a record is
# immutable here and freed by Julia's GC, so one value serves every holder.
"A second reference to the record `r` (pl-fli.c)."
PL_duplicate_record(r::record) = r

# PORT: pl-fli.c PL_qualify
# DIVERGES: the database and local data are arguments; the module is an index into `gd`'s table
# (`PL_strip_module`'s); no `valid_term_t` checks (`O_DEBUG` only).
"Put `Module:Plain` into `qualified`: the term in `raw` stripped of its qualifiers and the module they name, or the context module, `user` (pl-fli.c)."
function PL_qualify(
    gd::PL_global_data{T}, ld::PL_local_data{T}, raw::term_t, qualified::term_t
)::Bool where {T}
    mname = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, raw, 0, qualified)
    ok || return false

    PL_put_atom(ld, mname, gd.modules[m].atom)          # setHandle(mname, m->name)

    colon2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)
    return PL_cons_functor(ld, qualified, colon2, mname, qualified)   # FUNCTOR_colon2
end

# PORT: pl-fli.c PL_call_predicate
# DIVERGES: the database and local data are arguments, the context module a module or `nothing`
# (NULL); no `valid_term_t` checks of the arguments (`O_DEBUG` only).
"""
    PL_call_predicate(gd, ld, ctx, flags, pred, h0) -> Bool

Call procedure `pred` once on the term references `h0, h0+1, …` in a query of its own with `flags`,
keeping the bindings of its answer (pl-fli.c). False when it fails or raises.
"""
function PL_call_predicate(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ctx::Union{Nothing, module_t{T}},
    flags::UInt32, pred::Procedure{T}, h0::term_t
)::Bool where {T}
    qid = PL_open_query(gd, ld, ctx, flags, pred, h0)
    if qid != 0
        r1 = PL_next_solution(gd, ld, qid)
        r2 = PL_cut_query(ld, qid)

        rval = r1 != 0 && r2 != 0               # do not inline; we *must* execute PL_cut_query()
    else
        rval = false
    end

    return rval
end

# PORT: pl-fli.c ucs_atom
# DIVERGES: flags and name only (`PL_blob_t`, src/SWI-Prolog.jl); its hooks (`compareUCSAtom`,
# `blob_write_usc_atom`, the qlf `saveUCSAtom`/`loadUCSAtom`) are the functions of FLI-API group D below,
# not slots of this value.
"The blob type of a wide-character text atom (pl-fli.c): unique, text, `pl_wchar_t` code points."
const ucs_atom = PL_blob_t(PL_BLOB_UNIQUE | PL_BLOB_TEXT | PL_BLOB_WCHAR, "ucs_text")

# PORT: pl-fli.c lookupUCSAtom
# DIVERGES: the table is an argument (`GD->atoms`). The key is upstream's: the code points as
# `pl_wchar_t` — 4 bytes each on Linux, in the machine's byte order — and the length in BYTES
# (`len * sizeof(pl_wchar_t)`).
"The wide text atom of the first `len` code points of `s` (pl-fli.c), created if new."
function lookupUCSAtom(
    atoms::atoms_t, s::AbstractVector{UInt32}, len::Int=length(s)
)::UInt64
    bytes = Vector{UInt8}(reinterpret(UInt8, Vector{UInt32}(view(s, 1:len))))
    return first(lookupBlob(atoms, bytes, len * sizeof(UInt32), ucs_atom))
end

# PORT: pl-text.h PL_chars_t
# DIVERGES: the text is a byte vector in its encoding — ISO Latin-1, or UTF-8 (ENC_UTF8) where
# upstream holds `pl_wchar_t` (ENC_WCHAR), as the term interface's texts are UTF-8; no storage
# class (`storage`, `buf`: Julia's GC owns the bytes). A UTF-8 text is NEVER canonical, as
# upstream's never is: `PL_canonicalise_text` recodes it to ISO Latin-1 or `ENC_WCHAR` (since L1b
# stage A, an `ENC_WCHAR` text is upstream's buffer: native 4-byte `pl_wchar_t`s).
"A text and its encoding (pl-text.h)."
mutable struct PL_chars_t
    text::Vector{UInt8}             # the text
    length::Int                     # its length, in characters
    encoding::IOENC                 # how it is encoded
    canonical::Bool                 # true: ENC_ISO_LATIN_1 or ENC_WCHAR, never ENC_UTF8
end

# ── FLI-API group 2 (pl-fli.c): atoms and functors ───────────────────────────────────────────────
# ORIGINAL (FLI-API): the interface symbol of the text atom `w`, recorded in the database's store (what
# `_atom_word!` does for a symbol it is given); the symbol is made of the characters of `text`.
"The interface symbol of the text atom `w` made of `text`, recorded in `ld.atom_symbols` where it is new."
function _record_atom_symbol!(
    ld::PL_local_data{T}, w::word, text::PL_chars_t
)::T where {T}
    v = mk_sym(T, Symbol(_text_string(text)))
    i = indexAtom(w)
    atomSymbol(ld.atom_symbols, i) === nothing && setAtomSymbol!(ld.atom_symbols, i, v)
    return v
end

# ORIGINAL (FLI-API): `strlen` of a byte vector: the bytes before the first 0, or all of them.
_c_strlen(s::AbstractVector{UInt8})::Int = something(findfirst(iszero, s), length(s) + 1) - 1

# PORT: pl-fli.c PL_new_atom
# DIVERGES: the local data is an argument (upstream's `lookupAtom` on `GD->atoms`, after `initAtoms` where the
# system is not initialised: the kernel's atom table exists); the text is a byte vector, cut at the first 0 as
# `strlen` cuts it, and the answer is the atom's interface symbol.
"The text atom of the ISO Latin-1 bytes of `s` before the first 0, created if new; its symbol (pl-fli.c)."
function PL_new_atom(ld::PL_local_data{T}, s::AbstractVector{UInt8})::T where {T}
    n = _c_strlen(s)
    bytes = Vector{UInt8}(view(s, 1:n))
    w = lookupAtom(ld.atoms, bytes, n)                      # lookupAtom(s, strlen(s))
    return _record_atom_symbol!(ld, w, PL_chars_t(bytes, n, ENC_ISO_LATIN_1, true))
end

# PORT: pl-fli.c PL_new_atom_mbchars
# DIVERGES: the local data is an argument; the text is a byte vector, `len` -1 for `strlen`; `nothing` for
# upstream's 0 (a text that cannot be canonicalised). A text holding the character 0 raises
# `AtomNotRepresentableError` before the atom is made (a symbol cannot hold it, `_atom_word!`). `REP_MB`
# (`ENC_ANSI`) is refused by name.
"The text atom of `len` bytes of `s` in the encoding `flags` names (`REP_UTF8`, else ISO Latin-1); its symbol (pl-fli.c)."
function PL_new_atom_mbchars(
    ld::PL_local_data{T}, flags::Int, len::Int, s::AbstractVector{UInt8}
)::Union{Nothing, T} where {T}
    len == -1 && (len = _c_strlen(s))
    if (flags & REP_UTF8) == 0 && (flags & REP_MB) != 0
        throw(
            NotPortedError{Nothing}(
                nothing, "PL_new_atom_mbchars with REP_MB", "ENC_ANSI is unwritten"
            )
        )
    end
    enc = (flags & REP_UTF8) != 0 ? ENC_UTF8 : ENC_ISO_LATIN_1
    text = PL_chars_t(Vector{UInt8}(view(s, 1:len)), len, enc, false)
    PL_canonicalise_text(text) == 1 || return nothing       # textToAtom(&text) == 0
    codes = if text.encoding === ENC_WCHAR
        UInt32[reinterpret(UInt32, view(text.text, 1:(4 * text.length)))...]
    else
        UInt32[text.text[j] for j in 1:(text.length)]
    end
    any(iszero, codes) && throw(AtomNotRepresentableError(codes))
    w = textToAtom(ld.atoms, text)                          # a = textToAtom(&text)
    w == 0 && return nothing
    return _record_atom_symbol!(ld, w, text)
end

# PORT: pl-fli.c PL_new_functor_sz
# DIVERGES: the local data is an argument (`DECL_LD`); the name is an interface symbol, the answer a functor word.
"The functor word of the name `f` and `arity` (pl-fli.c `PL_new_functor_sz`), created if new."
PL_new_functor_sz(ld::PL_local_data{T}, f::T, arity::Int)::word where {T} =
    lookupFunctorDef(ld.functors, _atom_word!(ld, f), arity)

# PORT: pl-fli.c PL_new_functor
# DIVERGES: the local data is an argument; the name is an interface symbol; upstream's `fatalError("Arity out of
# range: %d")` for a negative arity is `error` (a negative `int`, or one past `typemax(Int32)`, is out of range).
"The functor word of the name `f` and the `int` `arity` (pl-fli.c); an arity out of `int`'s range is an error."
function PL_new_functor(ld::PL_local_data{T}, f::T, arity::Int)::word where {T}
    (arity < 0 || arity > typemax(Int32)) && error("Arity out of range: $arity")
    return PL_new_functor_sz(ld, f, arity)
end

# PORT: pl-fli.c PL_functor_name
# DIVERGES: the local data is an argument; the name is its interface symbol (the `$expr` atom as
# `PL_get_compound_name_arity` names it); no `valid_functor_t` check (`O_VALIDATE_API`, owner FLI1).
"The name, an atom, of functor word `f` (pl-fli.c)."
function PL_functor_name(ld::PL_local_data{T}, f::word)::T where {T}
    name = nameFunctor(ld.functors, f)
    name == ld.atom_dexpr && return mk_sym(T, Symbol("\$expr"))
    return _atom_value(ld, name)
end

# PORT: pl-fli.c PL_functor_arity_sz as PL_functor_arity
# PORT: pl-fli.c PL_functor_arity
# DIVERGES: the local data is an argument; no `valid_functor_t` check (`O_VALIDATE_API`, owner FLI1); `VALID_INT_ARITY`'s
# `fatalError` is `error`.
"The arity of functor word `f`, as an `int` (pl-fli.c `PL_functor_arity`; `PL_functor_arity_sz` is the same here)."
function PL_functor_arity(ld::PL_local_data, f::word)::Int
    arity = arityFunctor(ld.functors, f)
    (arity < 0 || arity > typemax(Int32)) && error("Arity out of range: $arity")  # VALID_INT_ARITY(arity)
    return arity
end

# PORT: pl-fli.c get_atom_ptr_text
# DIVERGES: the atom is an argument and the answer the text or `nothing` (upstream returns a Bool and fills a `PL_chars_t`
# it is given); the text is a COPY of the atom's name (upstream points into the atom): a wide text atom is
# `ENC_WCHAR` with its length in code points, any other text atom ISO Latin-1; both canonical.
"The canonical text of the text atom `a`, `nothing` for a non-textual atom (pl-fli.c `get_atom_ptr_text`)."
function get_atom_ptr_text(a::atom)::Union{Nothing, PL_chars_t}
    (a.type.flags & PL_BLOB_TEXT) == 0 && return nothing    # isoff(a->type, PL_BLOB_TEXT): non-textual atom
    bytes = Vector{UInt8}(view(a.name, 1:(a.length)))
    if a.type === ucs_atom
        return PL_chars_t(bytes, a.length ÷ sizeof(UInt32), ENC_WCHAR, true)
    end
    return PL_chars_t(bytes, a.length, ENC_ISO_LATIN_1, true)
end

# ── FLI-API group D (pl-fli.c): the wide-atom blob type's hooks and the text of atoms, strings and values ────────────

# PORT: pl-fli.c blob_write_usc_atom
# DIVERGES: the wide atom's text and the write options are the arguments (upstream's `atom_t a` and the `void *context`
# that holds the options); the options are untyped here, as pl-write.jl is included after this file.
"Write the wide atom with text `name` under `options` (`writeUCSAtom`): 1 for success, -1 for failure (pl-fli.c)."
function blob_write_usc_atom(name::String, options)::Int
    rc = writeUCSAtom(name, options)
    return rc ? 1 : -1
end

# PORT: pl-fli.c initUCSAtoms
# DIVERGES: the atom table is an argument (upstream registers the blob type once per process); registering is idempotent.
"Register the blob type of wide text atoms `ucs_atom` in the atom table `atoms` (pl-fli.c)."
function initUCSAtoms(atoms::atoms_t)::Nothing
    PL_register_blob_type(atoms, ucs_atom)
    return nothing
end

# PORT: pl-fli.c isUCSAtom
# DIVERGES: the atom is a value (`atom`, src/pl-atom.jl), its type compared by identity.
"Is the atom `a` of the blob type of wide text atoms (pl-fli.c)?"
isUCSAtom(a::atom)::Bool = a.type === ucs_atom

# PORT: pl-fli.c get_atom_text
# DIVERGES: the atom table is an argument and the answer is the text or `nothing` (upstream returns a Bool and fills
# the `PL_chars_t` it is given).
"The canonical text of the atom with word `w`, `nothing` for a non-textual atom (pl-fli.c)."
get_atom_text(atoms::atoms_t, w::word)::Union{Nothing, PL_chars_t} =
    get_atom_ptr_text(atomValue(atoms, w))

# PORT: pl-fli.c get_string_text
# DIVERGES: the argument is the interface value of the string (upstream's string word); the answer is the text (upstream
# fills a `PL_chars_t` and returns true); the bytes are a COPY (no `PL_CHARS_PROLOG_STACK`); a value that is no string
# raises an error (upstream reads a cell it checked the caller for).
"The canonical text of the string `s`: ISO Latin-1 where every character is below 0x100, else `ENC_WCHAR` (pl-fli.c)."
function get_string_text(s::T)::PL_chars_t where {T}
    isString(s) || error("get_string_text: not a string")
    codes = UInt32[UInt32(c) for c in string_value(s)]
    if all(c -> c < 0x00000100, codes)                        # isBString(w)
        return PL_chars_t(UInt8[UInt8(c) for c in codes], length(codes), ENC_ISO_LATIN_1, true)
    end
    return PL_chars_t(Vector{UInt8}(reinterpret(UInt8, codes)), length(codes), ENC_WCHAR, true)
end

# PORT: pl-fli.c compareUCSAtom
# DIVERGES: the atoms are values (`atom`); `get_wchar` is the plain dereference of a 32-bit `pl_wchar_t`.
"The order of two wide text atoms by code point, then by length in bytes: -1, 0 or 1 (pl-fli.c)."
function compareUCSAtom(a1::atom, a2::atom)::Int
    s1 = reinterpret(UInt32, view(a1.name, 1:(a1.length)))
    s2 = reinterpret(UInt32, view(a2.name, 1:(a2.length)))
    for i in 1:min(length(s1), length(s2))
        c1, c2 = Int(s1[i]), Int(s2[i])
        c1 != c2 && return Int(c1 > c2) - Int(c1 < c2)                  # SCALAR_TO_CMP(c1, c2)
    end
    return Int(a1.length > a2.length) - Int(a1.length < a2.length)      # SCALAR_TO_CMP(a1->length, a2->length)
end

# PORT: pl-fli.c saveUCSAtom
# DIVERGES: refused by name; owner LD2 (the QLF reader and writer, src/pl-qlf.jl, are refused by name: `qlfPutStringW`).
"Refused by name: the QLF writer of a wide atom (pl-fli.c `saveUCSAtom`), owner LD2."
function saveUCSAtom(a::atom, fd)::Bool
    throw(
        NotPortedError{Nothing}(
            nothing, "saveUCSAtom (qlfPutStringW)", "LD2: the QLF writer is refused by name"
        )
    )
end

# PORT: pl-fli.c loadUCSAtom
# DIVERGES: refused by name; owner LD2 (`qlfGetStringW`, as `saveUCSAtom`).
"Refused by name: the QLF reader of a wide atom (pl-fli.c `loadUCSAtom`), owner LD2."
function loadUCSAtom(fd)::UInt64
    throw(
        NotPortedError{Nothing}(
            nothing, "loadUCSAtom (qlfGetStringW)", "LD2: the QLF reader is refused by name"
        )
    )
end

# PORT: pl-fli.c is_text_value
# DIVERGES: the value's type is the argument (upstream reads it from the `pl_value_t`: `PL_get_arg_values` is owner
# FLI1); `flags` is the `UInt32` of the `CVT_*` bits.
"Is a value of type `type` (`PL_STRING`, `PL_ATOM`, `PL_INTEGER`, `PL_RATIONAL`) converted as text under `flags` (pl-fli.c)?"
function is_text_value(type::Int, flags::UInt32)::Bool
    if type == PL_STRING
        return true
    elseif type == PL_ATOM
        return (flags & CVT_ATOM) != 0
    elseif type == PL_INTEGER || type == PL_RATIONAL
        return (flags & CVT_FLOAT) == 0
    end
    return false
end

# PORT: pl-fli.c get_value_text
# DIVERGES: the local data is an argument; the answer is `(bytes, length)` or `nothing` (upstream writes `v->value.s` and
# `v->length` of a `pl_value_t`, owner FLI1); no `PL_save_text` (Julia's GC owns the vector); as `PL_mb_text`, only
# `REP_UTF8` is written: any other target raises `NotPortedError`.
"The bytes and their count of the text the term reference `tmp` holds, converted by `cvt` where `flags` set the rest (pl-fli.c)."
function get_value_text(
    ld::PL_local_data{T}, tmp::term_t, cvt::UInt32, flags::UInt32
)::Union{Nothing, Tuple{Vector{UInt8}, Int}} where {T}
    flags = (flags & ~CVT_MASK) | cvt
    text = PL_get_text(ld, tmp, flags)
    text === nothing && return nothing
    PL_mb_text(text, flags) || return nothing
    bytes = Vector{UInt8}(text.text)
    return (bytes, length(bytes))
end

# ORIGINAL (FLI-API): the code points of the canonical text `text`, in order.
"The code points of the canonical text `text`."
function _fli_text_codes(text::PL_chars_t)::Vector{UInt32}
    if text.encoding === ENC_WCHAR
        return UInt32[reinterpret(UInt32, view(text.text, 1:(4 * text.length)))...]
    end
    return UInt32[text.text[j] for j in 1:(text.length)]
end

# ORIGINAL (FLI-API): whether the canonical text `text` holds the character 0 (an atom's symbol cannot).
"Does the canonical text `text` hold a 0 character?"
_fli_text_has_nul(text::PL_chars_t)::Bool = any(iszero, _fli_text_codes(text))

# PORT: pl-fli.c PL_get_text_as_atom
# DIVERGES: the local data is an argument; the answer is the atom's interface symbol or `nothing` (upstream writes `*a`);
# a text with the character 0 raises `AtomNotRepresentableError` (a symbol cannot hold it); no `PL_STRINGS_MARK`, no
# `valid_term_t` check.
"The atom term reference `t` holds, else the atom of the text it holds as `flags` (`CVT_*`) allow, else `nothing` (pl-fli.c)."
function PL_get_text_as_atom(
    ld::PL_local_data{T}, t::term_t, flags::UInt32
)::Union{Nothing, T} where {T}
    a = PL_get_atom(ld, t)
    a === nothing || return a                               # isAtom(w): *a = (atom_t) w
    text = PL_get_text(ld, t, flags)
    text === nothing && return nothing
    PL_canonicalise_text(text) == 1 || return nothing       # textToAtom canonicalises first, 0 where it cannot
    _fli_text_has_nul(text) && throw(AtomNotRepresentableError(_fli_text_codes(text)))
    w = textToAtom(ld.atoms, text)                          # ta = textToAtom(&text)
    w == 0 && return nothing
    return _record_atom_symbol!(ld, w, text)
end

# PORT: pl-fli.c PL_atom_chars
# DIVERGES: the local data is an argument; a COPY of the atom's name bytes (upstream's `stringAtom(a)`, a pointer
# to them) without the terminating 0; no `valid_atom_t` check (`O_VALIDATE_API`, owner FLI1).
"The bytes of the name of atom `a` (pl-fli.c): ISO Latin-1 for a text atom, 4 bytes a code point for a wide one."
function PL_atom_chars(ld::PL_local_data{T}, a::T)::Vector{UInt8} where {T}
    x = atomValue(ld.atoms, _atom_word!(ld, a))
    return Vector{UInt8}(view(x.name, 1:(x.length)))
end

# PORT: pl-fli.c PL_atom_nchars
# DIVERGES: the local data is an argument; `(bytes, length)` or `nothing` (upstream's NULL), the bytes a COPY.
"The name bytes and their count of atom `a`, `nothing` for a wide text atom (pl-fli.c)."
function PL_atom_nchars(
    ld::PL_local_data{T}, a::T
)::Union{Nothing, Tuple{Vector{UInt8}, Int}} where {T}
    x = atomValue(ld.atoms, _atom_word!(ld, a))
    x.type === ucs_atom && return nothing
    return (Vector{UInt8}(view(x.name, 1:(x.length))), x.length)
end

# PORT: pl-fli.c PL_atom_wchars
# DIVERGES: the local data is an argument; `(chars, length)` or `nothing` (upstream's NULL), the code points a COPY
# with the terminating 0 (upstream's stack buffer for a narrow atom, its own name for a wide one); the length is
# in code points.
"The code points and their count of text atom `a`, `nothing` for a non-textual atom (pl-fli.c)."
function PL_atom_wchars(
    ld::PL_local_data{T}, a::T
)::Union{Nothing, Tuple{Vector{UInt32}, Int}} where {T}
    x = atomValue(ld.atoms, _atom_word!(ld, a))
    if x.type === ucs_atom
        n = x.length ÷ sizeof(UInt32)
        ws = Vector{UInt32}(reinterpret(UInt32, Vector{UInt8}(view(x.name, 1:(x.length)))))
        push!(ws, UInt32(0))
        return (ws, n)
    elseif (x.type.flags & PL_BLOB_TEXT) != 0
        ws = UInt32[x.name[j] for j in 1:(x.length)]        # addBuffer(b, *s, wchar_t)
        push!(ws, UInt32(0))                                # addBuffer(b, 0, wchar_t)
        return (ws, x.length)
    end
    return nothing
end

# PORT: pl-fli.c PL_get_atom_chars
# DIVERGES: the local data is an argument; the name bytes (a COPY) or `nothing`, where upstream writes a pointer
# through `s`; no `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"The name bytes of the text atom term reference `t` holds, else `nothing` (pl-fli.c): a reserved symbol is none."
function PL_get_atom_chars(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Vector{UInt8}} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD && isAtomW(w)                           # isAtom(w)
        a = atomValue(ld.atoms, w)
        if (a.type.flags & PL_BLOB_TEXT) != 0               # ison(a->type, PL_BLOB_TEXT)
            return Vector{UInt8}(view(a.name, 1:(a.length)))
        end
    end
    return nothing
end

# PORT: pl-fli.c PL_atom_mbchars
# DIVERGES: the local data is an argument; `(bytes, length)` or `nothing` (upstream's false), the bytes a COPY,
# `PL_save_text` and the `PL_STRINGS_MARK` buffers are unwritten. A target other than `REP_UTF8` is refused
# (`PL_mb_text` refuses it by name, `NotPortedError`). With `CVT_EXCEPTION`, a non-textual atom raises
# `type_error(atom, A)`.
"The text of atom `a` recoded as `flags` asks (`REP_UTF8`): the bytes and their count, `nothing` for no text (pl-fli.c)."
function PL_atom_mbchars(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, Tuple{Vector{UInt8}, Int}} where {T}
    text = get_atom_ptr_text(atomValue(ld.atoms, _atom_word!(ld, a)))
    if text === nothing
        if (flags & CVT_EXCEPTION) != 0
            t = PL_new_term_ref(ld)
            PL_put_atom(ld, t, a)
            PL_type_error(ld, "atom", t)
        end
        return nothing
    end
    PL_mb_text(text, flags) || return nothing
    return (text.text, text.length)
end

# ── FLI-API group E1 (pl-fli.c): putting and unifying text — atoms, strings, code and character lists ──────────────

# ORIGINAL (FLI-API): the `PL_chars_t` of `len` bytes of `s` that `PL_put_chars` makes from its
# `flags` (pl-fli.c: the `text.encoding = REP_UTF8 ? ENC_UTF8 : REP_MB ? ENC_ANSI : ENC_ISO_LATIN_1` lines), and the
# `flags` left once the representation bits are cleared. `len` -1 is `strlen`; `REP_MB` (`ENC_ANSI`) is refused by name.
"The not yet canonical text of `len` bytes of `s` as `flags` name its encoding, and the type bits of `flags` (pl-fli.c)."
function _fli_chars_text(
    flags::Int, len::Int, s::AbstractVector{UInt8}, who::String
)::Tuple{PL_chars_t, Int}
    if len == -1                                            # if ( len == (size_t)-1 )
        len = _c_strlen(s)                                  #   len = strlen(s)
    end
    if (flags & REP_MB) != 0 && (flags & REP_UTF8) == 0
        throw(NotPortedError{Nothing}(nothing, "$who with REP_MB", "ENC_ANSI is unwritten"))
    end
    enc = (flags & REP_UTF8) == 0 ? ENC_ISO_LATIN_1 : ENC_UTF8
    text = PL_chars_t(Vector{UInt8}(view(s, 1:len)), len, enc, false)
    return (text, flags & ~(REP_UTF8 | REP_MB | REP_ISO_LATIN_1))  # flags &= ~(REP_UTF8|REP_MB|REP_ISO_LATIN_1)
end

# ORIGINAL (FLI-API): the string of `len` ISO Latin-1 bytes of `s` (upstream's `globalString(len, s)`); `len` -1 is
# `strlen`, as in `PL_new_atom_mbchars`.
"The `String` of `len` ISO Latin-1 bytes of `s`, `len` -1 for the bytes before the first 0 (pl-fli.c `globalString`)."
function _latin1_string(len::Int, s::AbstractVector{UInt8})::String
    if len == -1
        len = _c_strlen(s)
    end
    return _text_string(PL_chars_t(Vector{UInt8}(view(s, 1:len)), len, ENC_ISO_LATIN_1, true))
end

# PORT: pl-fli.c PL_put_atom_chars
# DIVERGES: the local data is an argument; the text is a byte vector cut at the first 0 (`PL_new_atom`); no
# `PL_unregister_atom` (no atom GC).
"Make term reference `t` hold the atom of the ISO Latin-1 bytes of `s` before the first 0 (pl-fli.c)."
function PL_put_atom_chars(
    ld::PL_local_data{T}, t::term_t, s::AbstractVector{UInt8}
)::Bool where {T}
    PL_put_atom(ld, t, PL_new_atom(ld, s))                  # a = lookupAtom(s, strlen(s)); setHandle(t, a)
    return true
end

# PORT: pl-fli.c PL_put_atom_nchars
# DIVERGES (forced): `len` -1 is `strlen` (upstream passes the -1 to `lookupAtom`, then fixes `len` after the
# fact); a 0 byte inside the text raises `AtomNotRepresentableError` (a symbol cannot hold it, `PL_new_atom_mbchars`);
# no `PL_unregister_atom`.
"Make term reference `t` hold the atom of `len` ISO Latin-1 bytes of `s` (pl-fli.c)."
function PL_put_atom_nchars(
    ld::PL_local_data{T}, t::term_t, len::Int, s::AbstractVector{UInt8}
)::Bool where {T}
    a = PL_new_atom_mbchars(ld, 0, len, s)                  # a = lookupAtom(s, len)
    a === nothing && return false
    return PL_put_atom(ld, t, a)                            # setHandle(t, a)
end

# PORT: pl-fli.c PL_put_string_chars
# DIVERGES: the local data is an argument; the text is a byte vector cut at the first 0; the string is a grounded
# value of the term type, stored as `PL_put_float` stores one (`setSlotValue!`); it cannot fail (no `globalString`
# allocation to refuse).
"Make term reference `t` hold the string of the ISO Latin-1 bytes of `s` before the first 0 (pl-fli.c)."
function PL_put_string_chars(
    ld::PL_local_data{T}, t::term_t, s::AbstractVector{UInt8}
)::Bool where {T}
    setSlotValue!(ld, t + 1, mk_gnd(T, _latin1_string(-1, s)))     # w = globalString(strlen(s), s); setHandle(t, w)
    return true
end

# PORT: pl-fli.c PL_put_string_nchars
# DIVERGES: as `PL_put_string_chars`; `len` -1 is `strlen`.
"Make term reference `t` hold the string of `len` ISO Latin-1 bytes of `s` (pl-fli.c)."
function PL_put_string_nchars(
    ld::PL_local_data{T}, t::term_t, len::Int, s::AbstractVector{UInt8}
)::Bool where {T}
    setSlotValue!(ld, t + 1, mk_gnd(T, _latin1_string(len, s)))    # w = globalString(len, s); setHandle(t, w)
    return true
end

# PORT: pl-fli.c PL_put_chars
# DIVERGES: the local data is an argument; the text is a byte vector, `len` -1 for `strlen`; `REP_MB` (`ENC_ANSI`) is
# refused by name (`NotPortedError`); an atom is the term type's symbol of the text (`_atom_from_text`, so a text
# holding the character 0 is refused as in every atom), a string its grounded value (`setSlotValue!`); the error of a
# text that cannot be canonicalised is raised for a string as `PL_unify_text` raises it; an unknown type is `error`
# (upstream's `assert(0)`); no `PL_free_text`.
"Make term reference `t` hold the text of `len` bytes of `s` as `flags` say: a type (`PL_ATOM`, `PL_STRING`, `PL_CODE_LIST`, `PL_CHAR_LIST`) and a representation (pl-fli.c)."
function PL_put_chars(
    ld::PL_local_data{T}, t::term_t, flags::Int, len::Int, s::AbstractVector{UInt8}
)::Bool where {T}
    text, flags = _fli_chars_text(flags, len, s, "PL_put_chars")
    if flags == PL_ATOM
        PL_canonicalise_text(text) == 1 || return false     # w = textToAtom(&text): 0
        return PL_put_atom(ld, t, _atom_from_text(T, _text_string(text)))
    elseif flags == PL_STRING
        rc = PL_canonicalise_text(text)                     # w = textToString(&text)
        rc == 1 || return text_error(ld, rc)
        setSlotValue!(ld, t + 1, mk_gnd(T, _text_string(text)))
        return true
    elseif flags == PL_CODE_LIST || flags == PL_CHAR_LIST
        PL_put_variable(ld, t)
        return PL_unify_text(ld, t, 0, text, flags)         # rc = PL_unify_text(t, 0, &text, flags)
    else
        error("PL_put_chars: unknown type $flags")          # assert(0)
    end
end

# PORT: pl-fli.c PL_put_list_ncodes
# DIVERGES: the local data is an argument; the codes are the bytes of a vector (`*chars & 0xff`); no global space to
# ensure, so it cannot fail; the cells are laid out as `PL_cons_list_v` lays them.
"Make term reference `t` hold the list of the `len` bytes of `chars`, as integer codes (pl-fli.c)."
function PL_put_list_ncodes(
    ld::PL_local_data{T}, t::term_t, len::Int, chars::AbstractVector{UInt8}
)::Bool where {T}
    if len == 0
        ld.slots[t + 1] = ld.atom_nil_w                     # setHandle(t, ATOM_nil)
    else
        p = allocGlobalCells!(ld, 3 * len)                  # p = allocGlobal(len*3)
        ld.slots[t + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)    # setHandle(t, consCompound(p))
        for i in 0:(len - 1)
            q = p + 3 * i
            ld.gstack[q] = ld.functor_dot2                  # *p++ = FUNCTOR_dot2
            ld.gstack[q + 1] = consInt(Int64(chars[i + 1])) # *p++ = consInt(*chars & 0xff)
            ld.gstack[q + 2] =
                i + 1 < len ? consPtr(q + 3, TAG_COMPOUND | STG_GLOBAL) : ld.atom_nil_w    # *p = consCompound(p+1); p[-1] = ATOM_nil
        end
    end
    return true
end

# PORT: pl-fli.c PL_put_list_codes
"Make term reference `t` hold the list of the bytes of `chars` before the first 0, as integer codes (pl-fli.c)."
PL_put_list_codes(ld::PL_local_data{T}, t::term_t, chars::AbstractVector{UInt8}) where {T} =
    PL_put_list_ncodes(ld, t, _c_strlen(chars), chars)

# PORT: pl-fli.c PL_put_list_nchars
# DIVERGES: as `PL_put_list_ncodes`; each head is the one-character atom of the byte (`codeToAtom`, which refuses
# the byte 0 by name).
"Make term reference `t` hold the list of the `len` bytes of `chars`, as one-character atoms (pl-fli.c)."
function PL_put_list_nchars(
    ld::PL_local_data{T}, t::term_t, len::Int, chars::AbstractVector{UInt8}
)::Bool where {T}
    if len == 0
        ld.slots[t + 1] = ld.atom_nil_w                     # setHandle(t, ATOM_nil)
    else
        p = allocGlobalCells!(ld, 3 * len)                  # p = allocGlobal(len*3)
        ld.slots[t + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)    # setHandle(t, consCompound(p))
        for i in 0:(len - 1)
            q = p + 3 * i
            ld.gstack[q] = ld.functor_dot2                  # *p++ = FUNCTOR_dot2
            ld.gstack[q + 1] = _atom_word!(ld, codeToAtom(T, Int(chars[i + 1])))   # *p++ = codeToAtom(*chars & 0xff)
            ld.gstack[q + 2] =
                i + 1 < len ? consPtr(q + 3, TAG_COMPOUND | STG_GLOBAL) : ld.atom_nil_w
        end
    end
    return true
end

# PORT: pl-fli.c PL_put_list_chars
"Make term reference `t` hold the list of the bytes of `chars` before the first 0, as one-character atoms (pl-fli.c)."
PL_put_list_chars(ld::PL_local_data{T}, t::term_t, chars::AbstractVector{UInt8}) where {T} =
    PL_put_list_nchars(ld, t, _c_strlen(chars), chars)

# PORT: pl-fli.c PL_unify_atom_chars
# DIVERGES: the local data is an argument; the text is a byte vector cut at the first 0 (`PL_new_atom`); no
# `PL_unregister_atom`.
"Unify the term `t` references with the atom of the ISO Latin-1 bytes of `chars` before the first 0 (pl-fli.c)."
PL_unify_atom_chars(
    ld::PL_local_data{T}, t::term_t, chars::AbstractVector{UInt8}
) where {T} = PL_unify_atom(ld, t, PL_new_atom(ld, chars))

# PORT: pl-fli.c PL_unify_atom_nchars
# DIVERGES: as `PL_put_atom_nchars` (`len` -1 is `strlen`; a 0 byte inside the text raises
# `AtomNotRepresentableError`).
"Unify the term `t` references with the atom of `len` ISO Latin-1 bytes of `chars` (pl-fli.c)."
function PL_unify_atom_nchars(
    ld::PL_local_data{T}, t::term_t, len::Int, chars::AbstractVector{UInt8}
)::Bool where {T}
    a = PL_new_atom_mbchars(ld, 0, len, chars)              # a = lookupAtom(chars, len)
    a === nothing && return false
    return PL_unify_atom(ld, t, a)
end

# PORT: pl-fli.c PL_unify_string_chars
# DIVERGES: the local data is an argument; the text is a byte vector cut at the first 0; the string is a grounded
# value of the term type (`PL_unify_atomic`); no `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"Unify the term `t` references with the string of the ISO Latin-1 bytes of `s` before the first 0 (pl-fli.c)."
PL_unify_string_chars(ld::PL_local_data{T}, t::term_t, s::AbstractVector{UInt8}) where {T} =
    PL_unify_atomic(ld, t, mk_gnd(T, _latin1_string(-1, s)))

# PORT: pl-fli.c PL_unify_string_nchars
# DIVERGES: as `PL_unify_string_chars`; `len` -1 is `strlen`.
"Unify the term `t` references with the string of `len` ISO Latin-1 bytes of `s` (pl-fli.c)."
PL_unify_string_nchars(
    ld::PL_local_data{T}, t::term_t, len::Int, s::AbstractVector{UInt8}
) where {T} = PL_unify_atomic(ld, t, mk_gnd(T, _latin1_string(len, s)))

# PORT: pl-fli.c PL_unify_list_ncodes
# DIVERGES: the local data is an argument; the codes are the bytes of a vector (`*chars & 0xff`); the early `false`
# leaves the term references it made, as upstream does.
"Unify the term `l` references with the list of the `len` bytes of `chars`, as integer codes (pl-fli.c)."
function PL_unify_list_ncodes(
    ld::PL_local_data{T}, l::term_t, len::Int, chars::AbstractVector{UInt8}
)::Bool where {T}
    if PL_is_variable(ld, l)
        tmp = PL_new_term_ref(ld)
        return PL_put_list_ncodes(ld, tmp, len, chars) && PL_unify(ld, l, tmp)
    else
        head = PL_new_term_ref(ld)
        t = PL_copy_term_ref(ld, l)
        for i in 1:len
            (PL_unify_list(ld, t, head, t) && PL_unify_integer(ld, head, Int(chars[i]))) ||
                return false
        end
        rval = PL_unify_nil(ld, t)
        PL_reset_term_refs(ld, head)
        return rval
    end
end

# PORT: pl-fli.c PL_unify_list_codes
"Unify the term `l` references with the list of the bytes of `chars` before the first 0, as integer codes (pl-fli.c)."
PL_unify_list_codes(ld::PL_local_data{T}, l::term_t, chars::AbstractVector{UInt8}) where {T} =
    PL_unify_list_ncodes(ld, l, _c_strlen(chars), chars)

# PORT: pl-fli.c PL_unify_list_nchars
# DIVERGES: as `PL_unify_list_ncodes`; each element is the one-character atom of the byte (`codeToAtom`, which
# refuses the byte 0 by name).
"Unify the term `l` references with the list of the `len` bytes of `chars`, as one-character atoms (pl-fli.c)."
function PL_unify_list_nchars(
    ld::PL_local_data{T}, l::term_t, len::Int, chars::AbstractVector{UInt8}
)::Bool where {T}
    if PL_is_variable(ld, l)
        tmp = PL_new_term_ref(ld)
        return PL_put_list_nchars(ld, tmp, len, chars) && PL_unify(ld, l, tmp)
    else
        head = PL_new_term_ref(ld)
        t = PL_copy_term_ref(ld, l)
        for i in 1:len
            (
                PL_unify_list(ld, t, head, t) &&
                PL_unify_atom(ld, head, codeToAtom(T, Int(chars[i])))
            ) || return false
        end
        rval = PL_unify_nil(ld, t)
        PL_reset_term_refs(ld, head)
        return rval
    end
end

# PORT: pl-fli.c PL_unify_list_chars
"Unify the term `l` references with the list of the bytes of `chars` before the first 0, as one-character atoms (pl-fli.c)."
PL_unify_list_chars(ld::PL_local_data{T}, l::term_t, chars::AbstractVector{UInt8}) where {T} =
    PL_unify_list_nchars(ld, l, _c_strlen(chars), chars)

# ── FLI-API group E2 (pl-fli.c): getting text, the cvt_i family, the code-to-atom cache (PL_get_wchars, PL_unify_wchars
# and PL_unify_wchars_diff are wip/clib-uri's) ─────────────────────────────────────────────────────────────────────

# ORIGINAL (FLI-API): the sp_encoding of pl-fli.c (`static int sp_encoding = REP_UTF8`).
const _sp_encoding = Ref{UInt32}(REP_UTF8)

# PORT: pl-fli.c PL_cvt_encoding
# DIVERGES: the value is a `UInt32`, the type of the `REP_*` constants; `PL_cvt_set_encoding` (the only writer of
# `sp_encoding`) is unwritten, so it is `REP_UTF8`.
"The encoding the `PL_cvt_i_string` family of conversions uses, `REP_UTF8` (pl-fli.c)."
PL_cvt_encoding()::UInt32 = _sp_encoding[]

# PORT: pl-fli.c _PL_cvt_i_char
# DIVERGES: the local data is an argument; returns the byte stored through `c` (a `UInt8`, the C `char`'s bit
# pattern: the caller reads it signed or unsigned), `nothing` after the error where upstream returns false;
# `PL_get_text` gives the kernel's non-canonical UTF-8 text, so it is canonicalised first (upstream's is canonical
# already: an `ENC_ISO_LATIN_1` text of one character); no `PL_STRINGS_MARK`; `PL_representation_error` is
# `PL_error(..., ERR_REPRESENTATION, ...)`; no `valid_term_t` check.
"The C `char` of the term reference `p`: an integer in `mn..mx` or a one-character ISO Latin-1 text, else `nothing` after an error (pl-fli.c)."
function _PL_cvt_i_char(
    ld::PL_local_data{T}, p::term_t, mn::Int, mx::Int
)::Union{Nothing, UInt8} where {T}
    i = PL_get_integer(ld, p)
    if i !== nothing && i >= mn && i <= mx
        return UInt8(i & 0xff)                              # *c = (char)i
    end
    txt = PL_get_text(ld, p, CVT_ATOM | CVT_STRING | CVT_LIST)
    if txt !== nothing && PL_canonicalise_text(txt) == 1 && txt.length == 1 &&
       txt.encoding === ENC_ISO_LATIN_1
        return txt.text[1]                                  # *c = txt.text.t[0]
    end
    if PL_is_integer(ld, p)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, mn < 0 ? :char : :uchar))
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), p)
    return nothing
end

# PORT: pl-fli.c PL_cvt_i_schar
# DIVERGES: returns the `Int8`, or `nothing` after the error, where upstream writes it through `c`.
"The C `signed char` term reference `p` holds, or `nothing` after an error (pl-fli.c)."
function PL_cvt_i_schar(ld::PL_local_data{T}, p::term_t)::Union{Nothing, Int8} where {T}
    c = _PL_cvt_i_char(ld, p, -128, 127)                    # SCHAR_MIN, SCHAR_MAX
    c === nothing && return nothing
    return reinterpret(Int8, c)                             # (char *)c written as a signed char
end

# PORT: pl-fli.c PL_cvt_i_uchar
# DIVERGES: returns the `UInt8`, or `nothing` after the error, where upstream writes it through `c`.
"The C `unsigned char` term reference `p` holds, or `nothing` after an error (pl-fli.c)."
function PL_cvt_i_uchar(ld::PL_local_data{T}, p::term_t)::Union{Nothing, UInt8} where {T}
    return _PL_cvt_i_char(ld, p, 0, 255)                    # 0, UCHAR_MAX
end

# PORT: pl-fli.c _PL_cvt_i_short
# DIVERGES: returns the value `i` (the `short` or `unsigned short` it narrows to, as the range `mn..mx` says), or
# `nothing` after the error, where upstream writes it through `s`; no `valid_term_t` check.
"The C `short` (or `unsigned short`, by `mn`) term reference `p` holds, or `nothing` after an error (pl-fli.c)."
function _PL_cvt_i_short(
    ld::PL_local_data{T}, p::term_t, mn::Int, mx::Int
)::Union{Nothing, Int} where {T}
    i = PL_get_integer(ld, p)
    if i !== nothing && i >= mn && i <= mx
        return i                                            # *s = (short)i
    end
    if PL_is_integer(ld, p)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, mn < 0 ? :short : :ushort))
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), p)
    return nothing
end

# PORT: pl-fli.c PL_cvt_i_int64
# DIVERGES: returns the value, or `nothing` after the error, where upstream writes it through `c`.
"The `int64_t` term reference `p` holds, or `nothing` after an error (pl-fli.c)."
PL_cvt_i_int64(ld::PL_local_data{T}, p::term_t) where {T} = PL_get_int64_ex(ld, p)

# ORIGINAL (FLI-API): pl-error.c `PL_get_uint64_ex`, which the kernel has not written; as `PL_get_size_ex` above it
# with the range of `uint64_t`: a non-negative integer up to `typemax(UInt64)`, else the error.
"The `uint64_t` term reference `t` holds, or `nothing` after `domain_error(not_less_than_zero, T)`, `representation_error(uint64_t)` or `type_error(integer, T)`."
function _fli_get_uint64_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, UInt64} where {T}
    k, x, _ = _deref_loc(ld, -(t + 1))
    if k != DU_VALUE                                        # a variable, an atom, a compound
        PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
        return nothing
    end
    p = isTaggedIntW(x) ? nothing : _value_term(ld, x)
    v = if p === nothing
        BigInt(valInt(x))
    elseif isInteger(p)
        integer_is_int64(p) ? BigInt(int64_value(p)) : bigint_value(p)
    else
        PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
        return nothing
    end
    if v < 0
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)
        return nothing
    elseif v > typemax(UInt64)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :uint64_t))
        return nothing
    end
    return UInt64(v)
end

# PORT: pl-fli.c PL_cvt_i_uint64
# DIVERGES: returns the value, or `nothing` after the error, where upstream writes it through `c`;
# `PL_get_uint64_ex` is `_fli_get_uint64_ex`.
"The `uint64_t` term reference `p` holds, or `nothing` after an error (pl-fli.c)."
PL_cvt_i_uint64(ld::PL_local_data{T}, p::term_t) where {T} = _fli_get_uint64_ex(ld, p)

# PORT: pl-fli.c PL_get_list_nchars
# DIVERGES: the local data is an argument; `(bytes, length)` or `nothing` (upstream's false), the ISO Latin-1 bytes a
# fresh vector without the terminating 0; `flags` has no `BUF_MALLOC` to read (no buffer ring); no
# `valid_term_t` check.
"The ISO Latin-1 bytes and their count of the code or character list `l` holds, else `nothing` (pl-fli.c)."
function PL_get_list_nchars(
    ld::PL_local_data{T}, l::term_t, flags::UInt32
)::Union{Nothing, Tuple{Vector{UInt8}, Int}} where {T}
    b, _ = codes_or_chars_to_buffer(ld, l, false)           # codes_or_chars_to_buffer(l, flags, false, &result)
    b === nothing && return nothing
    return (b, length(b))                                   # len = entriesBuffer(b, char)
end

# PORT: pl-fli.c PL_get_nchars
# DIVERGES: the local data is an argument; `(bytes, length)` or `nothing` (upstream's false), the bytes a fresh
# vector without the terminating 0, the length in bytes (`PL_mb_text` leaves the length of a UTF-8 text the kernel
# gives in characters: the byte count is the bytes' own); no `PL_save_text`, no `PL_STRINGS_MARK_IF_MALLOC`; as
# `PL_mb_text`, only `REP_UTF8` is written: any other target of `flags` raises `NotPortedError`; no `valid_term_t` check.
"The bytes and their count of the text term reference `l` holds as `flags` (`CVT_*`, `REP_UTF8`) say, else `nothing` (pl-fli.c)."
function PL_get_nchars(
    ld::PL_local_data{T}, l::term_t, flags::UInt32
)::Union{Nothing, Tuple{Vector{UInt8}, Int}} where {T}
    text = PL_get_text(ld, l, flags)
    text === nothing && return nothing
    PL_mb_text(text, flags) || return nothing
    return (Vector{UInt8}(text.text), length(text.text))    # *length = text.length, in bytes
end

# PORT: pl-fli.c PL_get_chars
# DIVERGES: returns the bytes (the length is not asked for: `PL_get_nchars(t, NULL, s, flags)`), or `nothing`.
"The bytes of the text term reference `t` holds as `flags` say, else `nothing` (pl-fli.c)."
function PL_get_chars(
    ld::PL_local_data{T}, t::term_t, flags::UInt32
)::Union{Nothing, Vector{UInt8}} where {T}
    r = PL_get_nchars(ld, t, flags)
    r === nothing && return nothing
    return r[1]
end

# ── modules and predicates (FLI-API group H): PL_context, PL_new_module, PL_pred, PL_predicate, PL_predicate_info
# (pl-fli.c; resolveModule is wip/clib1's) ───────────────────────────────────────────────────────────────────────────

# PORT: pl-fli.c PL_context
# DIVERGES: the database and the local data are arguments; the module is an INDEX into `gd`'s module table
# (`PL_strip_module`'s convention), `MODULE_user`'s outside a frame.
"The context module, an index into the module table: that of the environment frame, `user` outside one (pl-fli.c)."
function PL_context(gd::PL_global_data{T}, ld::PL_local_data{T})::Int where {T}
    return ld.environment_frame != 0 ? contextModule(gd, ld, ld.environment_frame) : MODULE_user(gd).index
end

# PORT: pl-fli.c PL_new_module
# DIVERGES: the database is an argument; the name is an interface symbol, the answer the module's index; no
# `valid_atom_t` check (`O_VALIDATE_API`, owner FLI1).
"The index of the module named `name`, created if there is none (pl-fli.c)."
PL_new_module(gd::PL_global_data{T}, name::T)::Int where {T} = lookupModule(gd, name).index

# PORT: pl-fli.c PL_pred
# DIVERGES: the database and the local data are arguments; the module is an index (0 for upstream's NULL, the
# context module); upstream's `PL_api_error("invalid arity %d (out of range)")` is `error` (the kernel has no
# `PL_api_error`; both end the call, upstream by an abort in a debug build); the functor is its name and arity
# (`lookupProcedure`); no `valid_functor_t` check (`O_VALIDATE_API`, owner FLI1).
"The procedure of functor word `functor` in module `module_` (0: the context module), created if new (pl-fli.c)."
function PL_pred(
    gd::PL_global_data{T}, ld::PL_local_data{T}, functor::word, module_::Int
)::Procedure{T} where {T}
    arity = arityFunctor(ld.functors, functor)
    (arity < 0 || arity > MAXARITY) && error("invalid arity $arity (out of range)")
    module_ == 0 && (module_ = PL_context(gd, ld))          # if ( module == NULL ) module = PL_context()
    return lookupProcedure(PL_functor_name(ld, functor), arity, gd.modules[module_])
end

# PORT: pl-fli.c PL_predicate
# DIVERGES: the database and the local data are arguments; the name and the module are byte vectors, cut at
# the first 0 as `strlen` cuts them; both go to `PL_new_atom_mbchars` with the flag word `ENC_UTF8`, as upstream passes it (`nothing` for upstream's NULL module); `PL_api_error` is `error` (see
# `PL_pred`); the arity is range-checked before the name, as upstream; `PL_unregister_atom` is left out (the
# kernel has no atom garbage collection, so the atoms need no reference).
"The procedure `name/arity` of module `module_` (`nothing`: the context module), `name` and `module_` byte vectors (pl-fli.c)."
function PL_predicate(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::AbstractVector{UInt8}, arity::Int,
    module_::Union{Nothing, AbstractVector{UInt8}}
)::Procedure{T} where {T}
    (arity < 0 || arity > MAXARITY) && error("invalid arity $arity (out of range)")
    a = PL_new_atom_mbchars(ld, Int(ENC_UTF8), -1, name)
    if a === nothing
        PL_clear_exception(ld)
        error("invalid predicate name $(String(Vector{UInt8}(view(name, 1:_c_strlen(name))))) (invalid UTF-8)")
    end
    f = PL_new_functor_sz(ld, a, arity)                     # lookupFunctorDef(a, arity)
    if module_ !== nothing
        b = PL_new_atom_mbchars(ld, Int(ENC_UTF8), -1, module_)
        if b === nothing
            PL_clear_exception(ld)
            error("invalid module name $(String(Vector{UInt8}(view(module_, 1:_c_strlen(module_))))) (invalid UTF-8)")
        end
        m = lookupModule(gd, b).index                       # m = lookupModule(a)
    else
        m = PL_context(gd, ld)
    end
    return PL_pred(gd, ld, f, m)
end

# PORT: pl-fli.c PL_predicate_info
# DIVERGES: the three outputs are the answer `(true, name, arity, module)` (upstream's pointer arguments, each
# optional); the name is the definition's interface symbol, the module its index (`definition.module_`).
"`(true, name, arity, module)` of the predicate `pred`: its name symbol, its arity, its module's index (pl-fli.c)."
function PL_predicate_info(pred::Procedure{T})::Tuple{Bool, T, Int, Int} where {T}
    def = pred.definition
    return (true, def.name, def.arity, def.module_)
end

# ── FLI-API group F (pl-fli.c): building terms from a tagged argument list, atomic words, the term type ───────────

# PORT: pl-fli.c PL_get_module
# DIVERGES: the database is an argument; the answer is the module's index (see `PL_context`), `nothing` for
# upstream's `false`; no `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"The index of the module named by the atom term reference `t` holds (created if new), `nothing` if `t` holds no atom (pl-fli.c)."
function PL_get_module(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    a = PL_get_atom(ld, t)                                  # if ( PL_get_atom(t, &a) )
    a === nothing && return nothing
    return lookupModule(gd, a).index                        # *m = lookupModule(a)
end

# PORT: pl-fli.c _PL_get_atomic
# DIVERGES: the local data is an argument; the answer is the word of the dereferenced term (`_deref_loc`; 0 for an
# unbound variable, whose cell word is never read); no `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"The word the term reference `t` holds, dereferenced: `PL_atomic_t` (pl-fli.c)."
function _PL_get_atomic(ld::PL_local_data{T}, t::term_t)::word where {T}
    _, w, _ = _deref_loc(ld, -(t + 1))                      # return valHandle(t)
    return w
end

# PORT: pl-fli.c _PL_put_atomic
# DIVERGES: the local data is an argument; no `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"Make term reference `t` hold the word `a` (`PL_atomic_t`, pl-fli.c)."
function _PL_put_atomic(ld::PL_local_data{T}, t::term_t, a::word)::Nothing where {T}
    ld.slots[t + 1] = a                                     # setHandle(t, a)
    return nothing
end

# ORIGINAL (FLI-API): pl-fli.c's `xpceref_t` (SWI-Prolog.h): an XPCE object reference, an integer or an atom.
"An XPCE reference: `type` is `PL_INTEGER` (the integer `i`) or `PL_ATOM` (the atom `a`) (SWI-Prolog.h `xpceref_t`)."
struct xpceref_t{T}
    type::Int
    i::Int64
    a::Union{Nothing, T}
end

# PORT: pl-fli.c put_xpce_ref_arg
# DIVERGES: the local data is an argument; the answer is the word for the argument cell, 0 after the
# representation error (upstream returns the `false` of `PL_representation_error`, as a word).
"The word of the XPCE reference `ref` as the argument of `@/1`: a tagged integer, or the atom's word (pl-fli.c)."
function put_xpce_ref_arg(ld::PL_local_data{T}, ref::xpceref_t{T})::word where {T}
    if ref.type == PL_INTEGER                               # if ( ref->type == PL_INTEGER )
        w = consInt(ref.i)                                  # word w = consInt(ref->value.i)
        if valInt(w) != ref.i                               # if ( valInt(w) != ref->value.i)
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :pce_reference))
            return word(0)                                  # return PL_representation_error("pce_reference")
        end
        return w
    end
    return _atom_word!(ld, ref.a::T)                        # return ref->value.a
end

# PORT: pl-fli.c PL_term_type
# DIVERGES: the local data is an argument; on the WORDS (`_deref_loc`): an unbound or attributed variable
# `PL_VARIABLE`, a tagged integer or an integer value `PL_INTEGER`, other rationals `PL_RATIONAL`; no
# `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"The type of the term reference `t` holds: `PL_VARIABLE`, `PL_ATOM`, `PL_NIL`, `PL_BLOB`, `PL_INTEGER`, `PL_RATIONAL`, `PL_FLOAT`, `PL_STRING`, `PL_TERM`, `PL_LIST_PAIR`, `PL_DICT` (pl-fli.c)."
function PL_term_type(ld::PL_local_data{T}, t::term_t)::Int where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t); t0 = type_map[tag(w)]
    (k == DU_CELL || k == DU_ATTVAR) && return PL_VARIABLE
    if k == DU_WORD
        if isAtomW(w)                                       # case PL_ATOM
            isTextAtom(_atom_value(ld, w)) && return PL_ATOM    # isTextAtom(w)
            w == ld.atom_nil_w && return PL_NIL             # w == ATOM_nil
            return PL_BLOB
        end
        f = ld.gstack[valPtr(w)]                            # case PL_TERM: f = word2functor(valueTerm(w)->definition)
        f == ld.functor_dot2 && return PL_LIST_PAIR         # f == FUNCTOR_dot2
        nameFunctor(ld.functors, f) == ATOM_dict && return PL_DICT   # fd->name == ATOM_dict
        return PL_TERM
    end
    isTaggedIntW(w) && return PL_INTEGER                    # case PL_INTEGER
    v = _indirect_value(ld, w)
    isInteger(v) && return PL_INTEGER                       # isInteger(w) ? PL_INTEGER : PL_RATIONAL
    isRational(v) && return PL_RATIONAL
    isFloat(v) && return PL_FLOAT
    isString(v) && return PL_STRING
    error("PL_term_type: unknown value word")
end

# PORT: pl-fli.c PL_unify_output
# DIVERGES: the local data is an argument; the fast path is taken where the value is an atom or a compound word
# (`bindConst(p1, *p2)`), a value-table word goes through `PL_unify`: the same binding; `hasGlobalSpace(0)` is
# true (the global stack grows).
"Unify the output argument `t1` with `t2`: a variable bound to a non-variable is bound directly (pl-fli.c)."
function PL_unify_output(ld::PL_local_data{T}, t1::term_t, t2::term_t)::Bool where {T}
    k1, _, q1 = _deref_loc(ld, -(t1 + 1))                   # deRef(p1)
    k2, w2, _ = _deref_loc(ld, -(t2 + 1))                   # deRef(p2)
    if (k1 == DU_CELL || k1 == DU_ATTVAR) && k2 == DU_WORD  # canBind(*p1) && !canBind(*p2) && hasGlobalSpace(0)
        bindConst(ld, q1, w2)                               # bindConst(p1, *p2)
        return true
    end
    return PL_unify(ld, t1, t2)                             # unify_ptrs(p1, p2, ALLOW_GC|ALLOW_SHIFT)
end

# ORIGINAL (FLI-API): pl-fli.c's agenda entry `work` of PL_unify_termv: `is_list` false is `w_term` (`ref` the
# term, `n` its arity, `arg` the current argument), true is `w_list` (`ref` the tail, `n` the elements left).
mutable struct _unify_work
    is_list::Bool
    ref::term_t
    n::Int
    arg::Int
end

# PORT: pl-fli.c PL_unify_termv
# DIVERGES: the argument list is a vector holding each tag and its values in order (`va_arg`): atoms as the
# interface symbol, texts as byte vectors (`PL_NWCHARS`: `UInt32` code points), pointers `UInt`, floats
# `Float64`, a `PL_FUNCTOR` as the functor word, a `_PL_PREDICATE_INDICATOR` as the `Procedure`; the database is
# an argument; the multibyte tags (`PL_MBCHARS`...) reach the refusal of `PL_unify_chars` (`REP_MB`); the text
# tags call `PL_unify_chars` (wip/clib-uri, wip/clib1) and the wide-text tags (`PL_NWCHARS`, `PL_NWCODES`,
# `PL_NWSTRING`) call `PL_unify_wchars` (wip/clib-uri, whose code points are `Int`s: converted here): NEITHER is
# in this branch (duplicates of those branches), so this function only checks, runs or passes JET once a clib
# branch is merged under it; the agenda
# is a vector of `_unify_work`; the warning of an unknown tag ("Format error in PL_unify_term()") goes through
# `PL_warning` (group I) and the call fails; a `PL_LIST` whose `PL_unify_list` fails
# with elements left fails the call (forced: repeating the same call cannot end).
"Unify the term `t` references with the term the tagged `args` describe (`PL_unify_term`'s variadic list) (pl-fli.c)."
function PL_unify_termv(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, args::AbstractVector
)::Bool where {T}
    tsave = PL_new_term_refs(ld, 0)                         # save for reclaim
    agenda = _unify_work[]
    t = PL_copy_term_ref(ld, t)                             # if ( !(t = PL_copy_term_ref(t)) )
    t == 0 && return false
    ai = 0
    ok = true
    while true                                              # cont:
        op = Int(args[ai += 1]::Integer)                    # switch((op=va_arg(args, int)))
        rval = true
        if op == PL_VARIABLE                                # rval = true
        elseif op == PL_ATOM
            rval = PL_unify_atom(ld, t, args[ai += 1]::T)
        elseif op == PL_BOOL
            v = args[ai += 1]
            b = v isa Bool ? v : v != 0                     # v ? ATOM_true : ATOM_false
            rval = PL_unify_atom(ld, t, mk_sym(T, b ? Symbol("true") : Symbol("false")))
        elseif op == PL_SHORT || op == PL_INT || op == PL_INTEGER || op == PL_LONG
            rval = PL_unify_integer(ld, t, Int(args[ai += 1]::Integer))
        elseif op == PL_INT64 || op == PL_INTPTR || op == PL_SWORD
            rval = PL_unify_int64(ld, t, Int(args[ai += 1]::Integer))
        elseif op == PL_POINTER
            rval = PL_unify_pointer(ld, t, UInt(args[ai += 1]::Integer))
        elseif op == PL_FLOAT || op == PL_DOUBLE
            rval = PL_unify_float(ld, t, Float64(args[ai += 1]::Real))
        elseif op == PL_STRING
            rval = PL_unify_string_chars(ld, t, args[ai += 1]::AbstractVector{UInt8})
        elseif op == PL_TERM
            rval = PL_unify(ld, t, args[ai += 1]::term_t)
        elseif op == PL_CHARS
            rval = PL_unify_atom_chars(ld, t, args[ai += 1]::AbstractVector{UInt8})
        elseif op == PL_NCHARS
            len = Int(args[ai += 1]::Integer)
            rval = PL_unify_atom_nchars(ld, t, len, args[ai += 1]::AbstractVector{UInt8})
        elseif op == PL_UTF8_CHARS || op == PL_UTF8_STRING
            rval = PL_unify_chars(                          # PL_unify_text(t, 0, &txt, PL_STRING or PL_ATOM)
                ld, t, (op == PL_UTF8_STRING ? PL_STRING : PL_ATOM) | Int(REP_UTF8), -1,
                args[ai += 1]::AbstractVector{UInt8}
            )
        elseif op == PL_NUTF8_CHARS || op == PL_NUTF8_CODES || op == PL_NUTF8_STRING
            len = Int(args[ai += 1]::Integer)
            ty = op == PL_NUTF8_CHARS ? PL_ATOM : op == PL_NUTF8_CODES ? PL_CODE_LIST : PL_STRING
            rval = PL_unify_chars(ld, t, ty | Int(REP_UTF8), len, args[ai += 1]::AbstractVector{UInt8})
        elseif op == PL_NWCHARS || op == PL_NWCODES || op == PL_NWSTRING
            len = Int(args[ai += 1]::Integer)
            ty = op == PL_NWCHARS ? PL_ATOM : op == PL_NWCODES ? PL_CODE_LIST : PL_STRING
            ws = args[ai += 1]::AbstractVector{UInt32}      # wip/clib-uri's PL_unify_wchars takes the code points as `Int`s
            rval = PL_unify_wchars(ld, t, ty, len, Int[Int(c) for c in ws])
        elseif op == PL_MBCHARS || op == PL_MBCODES || op == PL_MBSTRING
            ty = op == PL_MBCHARS ? PL_ATOM : op == PL_MBCODES ? PL_CODE_LIST : PL_STRING
            rval = PL_unify_chars(ld, t, ty | Int(REP_MB), -1, args[ai += 1]::AbstractVector{UInt8})
        elseif op == PL_FUNCTOR_CHARS || op == PL_FUNCTOR
            if op == PL_FUNCTOR_CHARS
                a = PL_new_atom(ld, args[ai += 1]::AbstractVector{UInt8})   # atom_t a = PL_new_atom(s)
                arity = Int(args[ai += 1]::Integer)         # arity = va_arg(args, int)
                ft = PL_new_functor(ld, a, arity)           # ft = PL_new_functor(a, arity)
            else
                ft = args[ai += 1]::word                    # ft = va_arg(args, functor_t)
                arity = arityFunctor(ld.functors, ft)       # arity = arityFunctor(ft)
            end
            if PL_unify_functor(ld, t, PL_functor_name(ld, ft), arity)   # common_f: PL_unify_functor(t, ft)
                c = PL_copy_term_ref(ld, t)
                c == 0 && return false
                push!(agenda, _unify_work(false, c, arity, 0))
            else
                rval = false
            end
        elseif op == PL_LIST
            c = PL_copy_term_ref(ld, t)
            c == 0 && return false
            push!(agenda, _unify_work(true, c, Int(args[ai += 1]::Integer), 0))
        elseif op == _PL_PREDICATE_INDICATOR
            proc = args[ai += 1]::Procedure{T}
            rval = unify_definition(
                gd, ld, MODULE_user(gd), t, proc.definition, 0, GP_HIDESYSTEM | GP_NAMEARITY
            )
        else                                                # default: PL_warning("Format error in PL_unify_term()")
            PL_warning(gd, ld, "Format error in PL_unify_term()")
            rval = false                                    # goto failout
        end
        if !rval
            ok = false                                      # failout
            break
        end
        more = false
        while !isempty(agenda)                              # while( tos > 0 )
            w = agenda[end]
            if !w.is_list
                if w.arg < w.n                              # w->value.term.arg < w->value.term.arity
                    w.arg += 1
                    _PL_get_arg(ld, w.arg, w.ref, t)        # _PL_get_arg(++w->value.term.arg, w->value.term.term, t)
                    more = true                             # goto cont
                    break
                end
                pop!(agenda)                                # tos--
            elseif w.n > 0                                  # w->value.list.len > 0
                if PL_unify_list(ld, w.ref, t, w.ref)       # PL_unify_list(tail, t, tail)
                    w.n -= 1
                    more = true                             # goto cont
                    break
                end
                ok = false
                break
            elseif PL_unify_nil(ld, w.ref)                  # else if ( PL_unify_nil(w->value.list.tail) )
                pop!(agenda)                                # tos--
            else
                ok = false                                  # goto failout
                break
            end
        end
        ok || break
        more || break
    end
    PL_reset_term_refs(ld, tsave)                           # PL_reset_term_refs(tsave)
    return ok
end

# PORT: pl-fli.c PL_unify_term
# DIVERGES: the tagged arguments are the rest of the call (see `PL_unify_termv`); the database is an argument.
"Unify the term `t` references with the term the tagged `args` describe (pl-fli.c)."
PL_unify_term(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, args...) where {T} =
    PL_unify_termv(gd, ld, t, Any[args...])

# ── FLI-API group G (pl-fli.c): blobs ─────────────────────────────────────────────────────────────

# ORIGINAL (FLI-API): what `PL_unify_blob` and `PL_put_blob` check before `lookupBlob`, for the blob types a
# term of the interface can name. The text blob type `text_atom` (an ISO Latin-1 text atom) is a plain text atom:
# its payload cannot hold the character 0 (a symbol cannot, as in `PL_new_atom_mbchars`). Any other type with
# `PL_BLOB_TEXT` (a user type whose text is not the kernel's, `ucs_atom` included) and `reserved_symbol` (made by
# its own constructor, `mk_reserved_symbol`) are refused by name, owner FLI1.
"Refuse the blob types the interface cannot give a symbol; a 0 byte in a text atom's payload raises (ORIGINAL)."
function _fli_blob_check(type::PL_blob_t, blob::AbstractVector{UInt8}, len::Int)::Nothing
    if type === reserved_symbol
        throw(
            NotPortedError{Nothing}(
                nothing, "a blob of the type reserved_symbol",
                "FLI1: a reserved symbol is made by mk_reserved_symbol"
            )
        )
    end
    if (type.flags & PL_BLOB_TEXT) != 0
        if type !== text_atom
            throw(
                NotPortedError{Nothing}(
                    nothing, "a blob of the text type $(type.name)",
                    "FLI1: only the text atom of ISO Latin-1 has a symbol"
                )
            )
        end
        any(iszero, view(blob, 1:len)) &&
            throw(AtomNotRepresentableError(UInt32[blob[j] for j in 1:len]))
    end
    return nothing
end

# ORIGINAL (FLI-API): the interface symbol of the blob atom `w`: the one the database's store holds, else a text
# atom's symbol (made of its characters, as `_record_atom_symbol!` makes it), else the blob term of the atom
# (`_blob_term!`: the handle is the word, the rank the type's registration rank).
"The interface symbol of the atom word `w` of a blob type, recorded in `ld.atom_symbols` where it is new."
function _fli_blob_symbol!(ld::PL_local_data{T}, w::word)::T where {T}
    v = atomSymbol(ld.atom_symbols, indexAtom(w))
    v === nothing || return v
    x = atomValue(ld.atoms, w)
    if (x.type.flags & PL_BLOB_TEXT) != 0
        return _record_atom_symbol!(ld, w, get_atom_ptr_text(x)::PL_chars_t)
    end
    return _blob_term!(ld.atoms, ld.atom_symbols, T, w)
end

# PORT: pl-fli.c PL_unify_blob
# DIVERGES: the local data is an argument; the payload is a byte vector and `len` its length (a `PL_BLOB_NOCOPY` type
# keeps the vector itself); the blob's atom is its interface symbol (`_fli_blob_symbol!`). The blob types
# `_fli_blob_check` names are refused or raise before `lookupBlob`. Left out: `PL_unregister_atom` (the kernel keeps its
# atoms: owner D-0634 D5) and the `valid_term_t` check (`O_VALIDATE_API`, owner FLI1).
"Unify the term `t` references with the blob of `len` bytes of `blob` and the blob type `type`, made if new (pl-fli.c)."
function PL_unify_blob(
    ld::PL_local_data{T}, t::term_t, blob::AbstractVector{UInt8}, len::Int, type::PL_blob_t
)::Bool where {T}
    _fli_blob_check(type, blob, len)
    w, _ = lookupBlob(ld.atoms, blob, len, type)            # atom_t a = lookupBlob(blob, len, type, &new)
    return PL_unify_atom(ld, t, _fli_blob_symbol!(ld, w))   # rval = PL_unify_atom(t, a)
end

# PORT: pl-fli.c PL_put_blob
# DIVERGES: as `PL_unify_blob`; the `valid_user_term_t` check is left out (`O_VALIDATE_API`, owner FLI1).
"Make the term reference `t` hold the blob of `len` bytes of `blob` and the blob type `type`; true if it was made (pl-fli.c)."
function PL_put_blob(
    ld::PL_local_data{T}, t::term_t, blob::AbstractVector{UInt8}, len::Int, type::PL_blob_t
)::Bool where {T}
    _fli_blob_check(type, blob, len)
    w, new = lookupBlob(ld.atoms, blob, len, type)          # atom_t a = lookupBlob(blob, len, type, &new)
    PL_put_atom(ld, t, _fli_blob_symbol!(ld, w))            # setHandle(t, a)
    return new
end

# PORT: pl-fli.c PL_get_blob
# DIVERGES: `nothing` for upstream's false; else the triple `(blob, len, type)` upstream writes through its three
# optional pointers: the atom's own name vector, its length in bytes and its blob type. The `valid_term_t` check of the
# API_STUB is left out (`O_VALIDATE_API`, owner FLI1).
"The atom `t` references as `(name, length, type)`, `nothing` where it holds no atom (pl-fli.c)."
function PL_get_blob(
    ld::PL_local_data, t::term_t
)::Union{Nothing, Tuple{Vector{UInt8}, Int, PL_blob_t}}
    k, w, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    (k == DU_WORD && isAtomW(w)) || return nothing          # isAtom(w)
    a = atomValue(ld.atoms, w)
    return (a.name, a.length, a.type)
end

# PORT: pl-fli.c PL_blob_data
# DIVERGES: the local data is an argument and the atom is its interface symbol; the answer is the triple
# `(data, len, type)` upstream returns and writes through its two optional pointers: for a slot that holds no atom
# (`ATOM_TYPE_IS_INVALID`) the data and the type are `nothing` and the length the slot's. No `valid_atom_t` check
# (`O_VALIDATE_API`, owner FLI1).
"The `(data, length, type)` of the blob atom `a` (pl-fli.c); `(nothing, length, nothing)` for an invalid atom."
function PL_blob_data(
    ld::PL_local_data{T}, a::T
)::Tuple{Union{Nothing, Vector{UInt8}}, Int, Union{Nothing, PL_blob_t}} where {T}
    x = atomValue(ld.atoms, _atom_word!(ld, a))             # Atom x = atomValue(a)
    x.type === ATOM_TYPE_INVALID && return (nothing, x.length, nothing)   # ATOM_TYPE_IS_INVALID(x->type)
    return (x.name, x.length, x.type)
end

# ── FLI-API group I (pl-fli.c): throwing, warnings and fatal errors ─────────────────────────────────────────────

# PORT: pl-fli.c PL_throw
# DIVERGES (forced, decision 1 of docs/architecture.md, "Exceptions crossing Julia"): the exception is raised and the call
# returns false; upstream's `longjmp` to the `setjmp` in `PL_next_solution` (`LD->exception.throw_environment`) is the false
# return, which the running foreign predicate hands to the VM with the exception pending. The local data is an argument.
"Raise the exception the term `exception` references; false, the exception pending (pl-fli.c)."
function PL_throw(ld::PL_local_data{T}, exception::term_t)::Bool where {T}
    PL_raise_exception(ld, exception)                       # PL_raise_exception(exception)
    return false                                            # no throw_environment: `return false`
end

# PORT: pl-fli.c PL_rethrow
# DIVERGES (forced): as `PL_throw`: the pending exception stays and the call returns false.
"Deliver the exception already pending again; false (pl-fli.c)."
PL_rethrow(ld::PL_local_data{T}) where {T} = false           # no throw_environment: `return false`

# ORIGINAL (FLI-API15): upstream's `Sfprintf(Suser_error, "%s", text)`: the code points of `text` on `s` (nothing: no stream).
function _fli_stream_text(s::Union{Nothing, IOSTREAM}, text::AbstractString)::Nothing
    s === nothing && return nothing
    for c in text
        Sputcode(Int(c), s)
    end
    return nothing
end

# ORIGINAL (FLI-API15): the print_message/2 branch of `vwarning` (pl-init.c:2358-2394): the message split at each newline into
# a list of strings, `error` and `message_lines(Lines)` as the arguments. False where upstream takes `goto nospace`.
function _fli_warning_message(gd::PL_global_data{T}, ld::PL_local_data{T}, msg::AbstractString)::Bool where {T}
    cid = PL_open_foreign_frame(ld)
    cid == 0 && return false                                # if ( !(cid = PL_open_foreign_frame()) ) goto nospace
    av = PL_new_term_refs(ld, 2)
    tail = PL_copy_term_ref(ld, av + 1)
    head = PL_new_term_ref(ld)
    bytes = codeunits(msg)
    pos = 1
    while true
        eol = findnext(==(0x0a), bytes, pos)                # strchr(s, '\n')
        if eol !== nothing
            if !PL_unify_list(ld, tail, head, tail) ||
               !PL_unify_string_nchars(ld, head, eol - pos, view(bytes, pos:(eol - 1)))
                PL_discard_foreign_frame(ld, cid)           # nospace: if ( cid ) PL_discard_foreign_frame(cid)
                return false
            end
            pos = eol + 1
        else
            if pos <= length(bytes)                         # if ( *s )
                if !PL_unify_list(ld, tail, head, tail) ||
                   !PL_unify_string_chars(ld, head, view(bytes, pos:length(bytes)))
                    PL_discard_foreign_frame(ld, cid)
                    return false
                end
            end
            if !PL_unify_nil(ld, tail)
                PL_discard_foreign_frame(ld, cid)
                return false
            end
            break
        end
    end
    if !PL_cons_functor(ld, av + 1, PL_new_functor(ld, mk_sym(T, :message_lines), 1), av + 1)
        PL_discard_foreign_frame(ld, cid)
        return false
    end
    PL_put_atom(ld, av, mk_sym(T, :error))                  # PL_put_atom(av, ATOM_error)
    PL_call_predicate(gd, ld, nothing, PL_Q_NODEBUG, gd.procedures_print_message2, av)
    PL_discard_foreign_frame(ld, cid)
    return true
end

# ORIGINAL (FLI-API15): pl-init.c `vwarning` (:2348), the function `PL_warning` calls, written here with it.
# DIVERGES: (a) the message is the formatted text (`Svsnprintf(message, LINESIZ, fm, args)` is the caller's, not cut at
# LINESIZ), and the `fm[0] != '$'` test reads the text; (b) `GD->initialised` is a field this kernel lacks: `print_message/2`
# being defined (`isDefinedProcedure`) stands for it, as `printMessage` does; (c) the `pl_trace()` that `debug_on_error` asks for
# after the message (the interactive debugger) is left to DBG1; (d) `Suser_error` is `nothing` where the host set no stream:
# then the fallback text has nowhere to go and is dropped.
# (e) when building the line list fails midway the fallback prints the whole text, upstream's the text from the line it
# stopped at (`s` is advanced as the lines are taken); the case needs a full global stack and is not distinguished here.
function _fli_vwarning(gd::PL_global_data{T}, ld::PL_local_data{T}, msg::AbstractString)::Bool where {T}
    toldString(ld)                                          # play safe
    if truePrologFlag(ld, PLFLAG_REPORT_ERROR)
        done = false
        if !gd.bootsession && isDefinedProcedure(gd, gd.procedures_print_message2) &&
           !ld.outofstack && !startswith(msg, "\$")
            done = _fli_warning_message(gd, ld, msg)
        end
        if !done                                            # nospace:
            _fli_stream_text(Suser_error(ld), "ERROR: " * msg * "\n")
            Pause(0.2)
        end
    end
    return false
end

# PORT: pl-fli.c PL_warning
# DIVERGES: the message is the formatted text, not a format and its arguments (see `_fli_vwarning`); the database and the local
# data are arguments.
"Print the warning `msg` through print_message/2 (to `user_error` where that cannot be called); false (pl-fli.c)."
PL_warning(gd::PL_global_data{T}, ld::PL_local_data{T}, msg::AbstractString) where {T} = _fli_vwarning(gd, ld, msg)

"`vfatalError`'s `static int active`: a second fatal error while one is reported ends the process by `abort()` alone."
const _FLI_FATAL_ACTIVE = Ref(0)

# ORIGINAL (FLI-API15): pl-init.c `vfatalError` (:2305), the function `PL_fatal_error` calls, written here with it.
# DIVERGES: (a) the message is the formatted text; (b) the report goes to `Suser_error` (upstream's `Serror`, the same stream
# until the host redirects it); (c) where the seam of `PL_abort_process` returns (a test that embeds the kernel:
# `gd.halt_exit = false`) the `active` count is reset, as the process upstream never returns from.
function _fli_vfatal_error(gd::PL_global_data{T}, ld::PL_local_data{T}, msg::AbstractString)::Nothing where {T}
    active = _FLI_FATAL_ACTIVE[]
    _FLI_FATAL_ACTIVE[] = active + 1                        # if ( active++ )
    if active != 0
        _halt_exit!(gd, 128 + 6)                            # abort()
        _FLI_FATAL_ACTIVE[] = 0
        return nothing
    end
    tbuf = Libc.strftime("%a %b %e %H:%M:%S %Y", time())    # ctime_r(), without its newline
    s = Suser_error(ld)
    _fli_stream_text(s, "[FATAL ERROR: at " * tbuf * "\n\t" * msg * "]\n")
    s === nothing || Sflush(s)
    PL_abort_process(gd, ld)
    _FLI_FATAL_ACTIVE[] = 0
    return nothing
end

# PORT: pl-fli.c PL_fatal_error
# DIVERGES: the message is the formatted text (see `_fli_vfatal_error`); the database and the local data are arguments.
"Report the fatal error `msg` on `user_error` and end the process as `abort()` does (pl-fli.c)."
PL_fatal_error(gd::PL_global_data{T}, ld::PL_local_data{T}, msg::AbstractString) where {T} =
    _fli_vfatal_error(gd, ld, msg)

# ── halting (HALT1): PL_halt, haltProlog, PL_abort_process (pl-fli.c) ───────────────────────────
# PORT: pl-fli.c haltProlog
# DIVERGES: left out: the `GC_DEBUG`/`O_DEBUG`/ASAN line that keeps the memory reclaim (a build option) and the
# `run_on_halt(&GD->os.exit_hooks, status)` (the kernel has no exit hook list). The database and the local
# data are arguments (the clean-up is `PL_cleanup`, src/pl-init.jl).
"Clean up for a halt: true where the halt goes ahead, false where a hook cancelled it or a clean-up runs already (pl-fli.c)."
function haltProlog(
    gd::PL_global_data{T}, ld::PL_local_data{T}, status::Int
)::Bool where {T}
    status |= PL_CLEANUP_NO_RECLAIM_MEMORY
    status &= ~PL_HALT_WITH_EXCEPTION

    rc = PL_cleanup(gd, ld, status)
    if rc == PL_CLEANUP_CANCELED || rc == PL_CLEANUP_RECURSIVE
        return false
    end
    gd.halt_cleaning = CLN_ATEXIT                       # (run_on_halt(&GD->os.exit_hooks, status): none)
    return true
end

# PORT: pl-fli.c PL_halt
# DIVERGES (HALT1, for the audit): (a) upstream's `exit(status)` is `_halt_exit!(gd, status)`, the seam
# `gd.halt_exit` (src/pl-global.jl; true, the real `exit`); where the seam is off — a test that embeds the kernel —
# the halt state is reset (`CLN_NORMAL`, as after a cancel) and `PL_halt` returns false, where upstream never
# returns. (b) One thread: the `O_PLMT` branch that forwards the halt to the main thread (`GD->halt.thread != 1`,
# `PL_thread_raise`, `Pause(halt_grace_time())`) is never taken; `halt_thread` is 1. The database and local data
# are arguments. Returns true where the halt was cancelled (`halt/1` then succeeds), false otherwise.
"""
    PL_halt(gd, ld, status) -> Bool

Halt the system with `status` (its low 16 bits the exit status; `PL_HALT_WITH_EXCEPTION` and `PL_CLEANUP_NO_CANCEL`
are flags): raise `unwind(halt(Status))` where the running query handles it (and return false, the exception
pending); else clean up and end the process through `gd.halt_exit`. True where a hook cancelled the halt (pl-fli.c).
"""
function PL_halt(gd::PL_global_data{T}, ld::PL_local_data{T}, status::Int)::Bool where {T}
    gd.halt_status = status
    gd.halt_thread = 1                                  # PL_thread_self(): the one thread

    if (status & PL_HALT_WITH_EXCEPTION) != 0 && raise_halt_exception(ld, status, false)
        return false
    end

    if haltProlog(gd, ld, status)
        _halt_exit!(gd, status)                         # exit(status)
        gd.halt_cleaning = CLN_NORMAL                   # the seam returned (DIVERGES (a))
        gd.halt_status = 0
        gd.halt_thread = 0
        return false
    end

    gd.halt_status = 0                                  # cancelled
    gd.halt_thread = 0

    return true
end

# PORT: pl-fli.c PL_prompt_next
# DIVERGES: the local data is an argument (upstream's `LD`).
"The next read from `in` prompts, where `in` is `user_input` (pl-fli.c)."
function PL_prompt_next(ld::PL_local_data, in::IOSTREAM)::Nothing
    if in === Suser_input(ld)
        ld.prompt_next = true
    end
    return nothing
end

# PORT: pl-fli.c PL_ttymode
# (swipl-devel cbf4e189, src/pl-fli.c:5329-5341)
# DIVERGES: the local data is an argument (upstream's `LD`).
"The terminal mode of `s`: `PL_NOTTY` unless it is `user_input` with `tty_control` on, then `PL_RAWTTY` or `PL_COOKEDTTY` (pl-fli.c)."
function PL_ttymode(ld::PL_local_data, s::IOSTREAM)::Int
    if s === Suser_input(ld)
        truePrologFlag(ld, PLFLAG_TTY_CONTROL) || return PL_NOTTY   # -tty in effect
        Sttymode(s) == TTY_RAW && return PL_RAWTTY                  # get_single_char/1 and friends

        return PL_COOKEDTTY                                         # cooked (readline) input
    end

    return PL_NOTTY
end

# PORT: pl-fli.c PL_prompt_is_continuation
# (swipl-devel cbf4e189, src/pl-fli.c:5364-5371)
# DIVERGES: the local data is an argument (upstream's `LD`).
"Does the prompt that comes next continue an input started earlier: `in` is `user_input` and `prompt1/1`'s prompt was handed out (pl-fli.c)?"
function PL_prompt_is_continuation(ld::PL_local_data, in::IOSTREAM)::Bool
    return in === Suser_input(ld) && ld.prompt_first !== nothing && ld.prompt_first_used
end

# PORT: pl-fli.c PL_prompt_string
# (swipl-devel cbf4e189, src/pl-fli.c:5374-5398)
# DIVERGES: the local data is an argument (upstream's `LD`); the text is a `String` (UTF-8, `REP_UTF8`), `nothing` for
# upstream's NULL: there is no `char *` and no `PL_save_text` buffer (`PL_STRINGS_MARK_IF_MALLOC` has no counterpart).
"The text of the prompt for the next read from `in`, a `String`; `nothing` unless `in` is `user_input` and there is a prompt (pl-fli.c)."
function PL_prompt_string(
    ld::PL_local_data{T}, in::IOSTREAM
)::Union{Nothing, String} where {T}
    if in === Suser_input(ld)
        a = PrologPrompt(ld)
        if a !== nothing && isTextAtom(a)                           # get_atom_text(a, &text)
            return sym_text(a)
        end
    end

    return nothing
end

# PORT: pl-fli.c PL_dispatch
# (swipl-devel cbf4e189, src/pl-fli.c:5484-5506)
# DIVERGES: the no-hook form. `GD->foreign.dispatch_events` is NULL (the kernel has `PL_dispatch_hook` nowhere, no
# embedding event loop), so `PL_DISPATCH_INSTALLED` answers false and every other mode returns true at once, as upstream
# does with no hook; the `input_on_stream`/`PL_handle_signals` loop and the exception test after the hook are
# unreachable. Owner of the hook form: the embedding step (`PL_dispatch_hook`).
"Dispatch events while waiting for input on `in`: with no hook installed, true at once (false for `PL_DISPATCH_INSTALLED`) (pl-fli.c)."
PL_dispatch(in::IOSTREAM, wait::Int)::Bool = wait != PL_DISPATCH_INSTALLED

# PORT: pl-fli.c PL_abort_process
# DIVERGES: upstream's `abort()` (SIGABRT, exit 134 under a shell) is the call of the seam with 134 (`128+SIGABRT`);
# `PL_abort_process` returns where the seam does. `SIGABRT` is Linux's, 6.
"Clean up with status `128+SIGABRT` and no cancel, then end the process as `abort()` does (pl-fli.c)."
function PL_abort_process(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    haltProlog(gd, ld, (128 + 6) | PL_CLEANUP_NO_CANCEL)
    _halt_exit!(gd, 128 + 6)                            # abort()
    gd.halt_cleaning = CLN_NORMAL                       # the seam returned
    return nothing
end

# ── state, actions, queries, version (FLI-API16): SP_set_state, SP_get_state, PL_action, PL_query, PL_version_info (pl-fli.c) ──

# PORT: pl-fli.c SP_set_state
# (swipl-devel 18168e62, src/pl-fli.c:1115-1120)
# DIVERGES: the local data is an argument (upstream's `GET_LD`).
"Store the Quintus/SICStus state `state` in the engine `ld` (`LD->fli.SP_state`, pl-fli.c)."
function SP_set_state(ld::PL_local_data, state::Int)::Nothing
    ld.fli_SP_state = state                             # LD->fli.SP_state = state
    return nothing
end

# PORT: pl-fli.c SP_get_state
# (swipl-devel 18168e62, src/pl-fli.c:1123-1128)
# DIVERGES: the local data is an argument (upstream's `GET_LD`).
"The Quintus/SICStus state stored in the engine `ld` (0 until `SP_set_state`; pl-fli.c)."
function SP_get_state(ld::PL_local_data)::Int
    return ld.fli_SP_state                              # return LD->fli.SP_state
end

"`vsysError`'s `static int active`: a second system error while one is reported ends the process by `abort()` alone."
const _FLI_SYS_ACTIVE = Ref(0)

# ORIGINAL (FLI-API16): pl-init.c `vsysError` (:2241-2284), the function `sysError` (:2111-2121) calls and `PL_action`'s and
# `PL_query`'s default arms use, written here with them; same cut as `_fli_vfatal_error`.
# DIVERGES: (a) the message is the formatted text; (b) the report goes to `Suser_error` (upstream's `Serror`, unbuffered: flushed
# here); (c) left out: the 30 s timer (`set_cleanup_timeout`), `save_backtrace`, `printCrashContext`, and the interactive branch
# ("Action?" prompt, taken when `user_input` and `user_error` are terminals and the system is not booting): the process always
# ends as the non-interactive branch ends it; (d) where the seam of `PL_abort_process` returns (`gd.halt_exit = false`) the
# `active` count is reset, as the process upstream never returns from. Returns false, as `sysError`.
function _fli_sys_error(gd::PL_global_data{T}, ld::PL_local_data{T}, msg::AbstractString)::Bool where {T}
    active = _FLI_SYS_ACTIVE[]
    _FLI_SYS_ACTIVE[] = active + 1                          # if ( active++ )
    if active != 0
        _halt_exit!(gd, 128 + 6)                            # abort()
        _FLI_SYS_ACTIVE[] = 0
        return false
    end
    s = Suser_error(ld)
    _fli_stream_text(s, "\nERROR: system error: " * msg * "\n")    # Sfprintf(Serror, "\nERROR: %s error: ", errtype) ...
    s === nothing || Sflush(s)
    PL_abort_process(gd, ld)                                # non-interactive or booting
    _FLI_SYS_ACTIVE[] = 0
    return false
end

# ORIGINAL (FLI-API16): pl-stream.c `Sfputs` (:2395-2402), which `PL_action(PL_ACTION_WRITE, ...)` calls: every byte of the text up to
# the first 0 is one code point (`*q&0xff`, so UTF-8 bytes are Latin-1 characters) written by `Sputcode`; 0, or -1 (`EOF`) on an
# error. DIVERGES: `nothing` for a missing stream (upstream would dereference NULL) is -1.
function _fli_sfputs(s::Union{Nothing, IOSTREAM}, text::AbstractString)::Int
    s === nothing && return -1
    for b in codeunits(text)
        b == 0x00 && break                                  # for( ; *q; q++)
        Sputcode(Int(b), s) < 0 && return -1                # if ( Sputcode(*q&0xff, s) < 0 ) return EOF
    end
    return 0
end

# PORT: pl-fli.c PL_action
# (swipl-devel 18168e62, src/pl-fli.c:5934-6039)
# DIVERGES: (a) the database, the local data and the varargs are arguments (`args...`: the one `int` or `char *` an action
# takes); the text of WRITE is a `String`. (b) PL_ACTION_BACKTRACE: `gc_status.active` and `GD->initialised` have no field
# (the collector never runs inside a foreign call, the database exists): the "initialising" message is `gd.bootsession`'s;
# PL_backtrace is DBG1's: `NotPortedError`. (c) PL_ACTION_GUIAPP: `GD->os.gui_app` is Win32's and has no field: accepted, true.
# (d) PL_ACTION_TRADITIONAL: `NotPortedError` (the kernel is SWI-7 only, owner R2 LB7, as the `--traditional` option,
# src/pl-init.jl). (e) PL_GMP_SET_ALLOC_FUNCTIONS: `GD->gmp.initialised` is always true once a database exists (`initGMP` runs
# in `setupProlog`, pl-setup.c:166): false, as upstream's else-branch. (f) PL_ACTION_ATTACH_CONSOLE is `attachConsole()`
# (pl-thread.c:7027, the O_PLMT build the pin is) written in place. (g) The default arm is `_fli_sys_error`; where the seam
# returns, the answer is false.
"""
    PL_action(gd, ld, action, args...) -> Bool

Perform `action` (`PL_ACTION_*`, `PL_GMP_SET_ALLOC_FUNCTIONS`): TRACE and DEBUG switch the modes, BACKTRACE (`depth`), BREAK runs a nested
toplevel, HALT (`status`) halts, ABORT raises `unwind(abort)`, WRITE (`text`) and FLUSH go to the current output, ATTACH_CONSOLE calls
`user:attach_console/0`; any other action is a system error (pl-fli.c).
"""
function PL_action(
    gd::PL_global_data{T}, ld::PL_local_data{T}, action::Int, args...
)::Bool where {T}
    rval = true

    if action == PL_ACTION_TRACE
        rval = tracemode(ld, true, nothing)                 # rval = (bool)pl_trace()
    elseif action == PL_ACTION_DEBUG
        debugmode(ld, true, nothing, DBG_ALL)               # debugmode(NULL, true, NULL, DBG_ALL)
    elseif action == PL_ACTION_BACKTRACE
        depth = Int(args[1])                                # int a = va_arg(args, int)
        if gd.bootsession                                   # GD->bootsession || !GD->initialised
            _fli_stream_text(Suser_error(ld), "\n[Cannot print stack while initialising]\n")
            rval = false
        else
            throw(
                NotPortedError{Nothing}(
                    nothing, "PL_action(PL_ACTION_BACKTRACE): PL_backtrace($depth, 0)", "DBG1"
                )
            )
        end
    elseif action == PL_ACTION_BREAK
        rval = pl_break(gd, ld)                             # rval = (bool)pl_break()
    elseif action == PL_ACTION_HALT
        PL_halt(gd, ld, Int(args[1]))                       # PL_halt(a)
        rval = false
    elseif action == PL_ACTION_ABORT
        rval = abortProlog(ld)                              # rval = abortProlog()
    elseif action == PL_ACTION_GUIAPP
        nothing                                             # GD->os.gui_app = guiapp (no field)
    elseif action == PL_ACTION_TRADITIONAL
        throw(
            NotPortedError{Nothing}(
                nothing,
                "PL_action(PL_ACTION_TRADITIONAL): setTraditional, resetListAtoms: the kernel is SWI-7 only",
                "R2 LB7"
            )
        )
    elseif action == PL_ACTION_WRITE
        rval = _fli_sfputs(Scurout(ld), args[1]) == 0       # rval = Sfputs(s, Scurout) == 0
    elseif action == PL_ACTION_FLUSH
        out = Scurout(ld)
        rval = out !== nothing && Sflush(out) == 0          # rval = Sflush(Scurout) == 0
    elseif action == PL_ACTION_ATTACH_CONSOLE
        fid = PL_open_foreign_frame(ld)                     # attachConsole() (pl-thread.c:7027)
        pred = PL_predicate(gd, ld, codeunits("attach_console"), 0, codeunits("user"))
        rval = PL_call_predicate(gd, ld, nothing, PL_Q_NODEBUG, pred, 0)
        PL_discard_foreign_frame(ld, fid)
    elseif action == PL_GMP_SET_ALLOC_FUNCTIONS
        rval = false                                        # GD->gmp.initialised is true: `else { rval = false; }`
    else
        _fli_sys_error(gd, ld, "PL_action(): Illegal action: $action")
        rval = false
    end

    return rval
end

# PORT: pl-fli.c PL_query
# (swipl-devel 18168e62, src/pl-fli.c:6045-6098)
# DIVERGES: (a) the database and the local data are arguments. (b) PL_QUERY_ARGV is a `char **`: `NotPortedError` (owner FLI1;
# the vector is `gd.cmdline.appl_argv`); PL_QUERY_ARGC is its length (`GD->cmdline.appl_argc`). (c) PL_QUERY_GETC: `PopTty`
# (restoring the terminal mode from `ttytab`) has no counterpart: the character is `Sgetchar()`, `Sgetc(Sinput)`, -1 where
# `user_input` is `nothing`. (d) PL_QUERY_ENCODING: `LD->encoding` is the flag `encoding`, `utf8` (src/os/pl-prologflag.jl:2182;
# `setEncoding` is refused, :1375): `ENC_UTF8`. (e) The one-thread O_PLMT build: PL_QUERY_MAX_THREADS prints the message of the
# O_PLMT branch (on `Suser_error`, flushed as `Sdprintf` does) and answers 100000. (f) The default arm is `_fli_sys_error`; where
# the seam returns, 0.
"""
    PL_query(gd, ld, query) -> Int

Information about the system: `PL_QUERY_ARGC`, `PL_QUERY_MAX_TAGGED_INT` and `_MIN_`, `PL_QUERY_GETC`, `PL_QUERY_VERSION`,
`PL_QUERY_MAX_THREADS`, `PL_QUERY_ENCODING`, `PL_QUERY_USER_CPU` (milliseconds), `PL_QUERY_HALTING`; 0 for `_MAX_INTEGER` and
`_MIN_INTEGER` (not representable); any other query is a system error (pl-fli.c).
"""
function PL_query(gd::PL_global_data{T}, ld::PL_local_data{T}, query::Int)::Int where {T}
    if query == PL_QUERY_ARGC
        return length(gd.cmdline.appl_argv)                 # (intptr_t) GD->cmdline.appl_argc
    elseif query == PL_QUERY_ARGV
        throw(
            NotPortedError{Nothing}(
                nothing, "PL_query(PL_QUERY_ARGV): a char** (gd.cmdline.appl_argv is the vector)", "FLI1"
            )
        )
    elseif query == PL_QUERY_MAX_INTEGER || query == PL_QUERY_MIN_INTEGER
        return 0                                            # return false; /* cannot represent (anymore) */
    elseif query == PL_QUERY_MAX_TAGGED_INT
        return PLMAXTAGGEDINT                               # (SIZEOF_WORD > SIZEOF_VOIDP is false)
    elseif query == PL_QUERY_MIN_TAGGED_INT
        return PLMINTAGGEDINT
    elseif query == PL_QUERY_GETC
        s = Suser_input(ld)                                 # (PopTty: no counterpart)
        return s === nothing ? -1 : Sgetc(s)                # (intptr_t) Sgetchar()
    elseif query == PL_QUERY_VERSION
        return PLVERSION
    elseif query == PL_QUERY_MAX_THREADS
        s = Suser_error(ld)
        _fli_stream_text(s, "PL_query(PL_QUERY_MAX_THREADS) is no longer supported\n")    # Sdprintf(...)
        s === nothing || Sflush(s)
        return 100000
    elseif query == PL_QUERY_ENCODING
        return Int(ENC_UTF8)                                # return LD->encoding
    elseif query == PL_QUERY_USER_CPU
        return trunc(Int, CpuTime(CPU_USER) * 1000.0)       # (intptr_t)(cpu*1000.0)
    elseif query == PL_QUERY_HALTING
        return gd.halt_cleaning != CLN_NORMAL ? 1 : 0       # (GD->halt.cleaning != CLN_NORMAL)
    end

    _fli_sys_error(gd, ld, "PL_query: Illegal query: $query")
    return 0
end

# PORT: pl-fli.c PL_version_info
# (swipl-devel 18168e62, src/pl-fli.c:6166-6178)
# DIVERGES: PL_VERSION_VM (`VM_SIGNATURE`) and PL_VERSION_BUILT_IN (`GD->foreign.signature`) are hashes of upstream's instruction
# table and built-in predicate table (the flag `abi_version`, src/os/pl-prologflag.jl): `NotPortedError` (owner FLI1).
"The version number `which` (`PL_VERSION_*`): the system's, the FLI's, record's, QLF's, the oldest loadable QLF; 0 for any other (pl-fli.c)."
function PL_version_info(which::Int)::UInt32
    which == PL_VERSION_SYSTEM && return UInt32(PLVERSION)
    which == PL_VERSION_FLI && return UInt32(PL_FLI_VERSION)
    which == PL_VERSION_REC && return UInt32(PL_REC_VERSION)
    which == PL_VERSION_QLF && return UInt32(PL_QLF_VERSION)
    which == PL_VERSION_QLF_LOAD && return UInt32(PL_QLF_LOADVERSION)
    if which == PL_VERSION_VM || which == PL_VERSION_BUILT_IN
        throw(
            NotPortedError{Nothing}(
                nothing, "PL_version_info($which): the VM and built-in signatures (abi_version)", "FLI1"
            )
        )
    end
    return UInt32(0)
end
