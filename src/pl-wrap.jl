# UPSTREAM: swipl-devel src/pl-wrap.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-wrap.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2019-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-wrap.c (the upstream file was read at the pin; capability search in evidence/TAB1MIN/handoff.md)
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-wrap.c: cell-tag access behind pl-data.h macros, no change of value, order, error or side effect.
# WRAPPING PREDICATES (pl-wrap.c), TAB1-min step T4: what `'$wrap_predicate'/5` (boot/syspred.pl:1717-1732) needs while a
# `:- table` directive LOADS. A wrapped predicate P gets a new supervisor that calls a clause of `'$wrap$P'`; the
# clause calls `call(Closure, Arg ...)`, `Closure` being a blob that holds a copy of P's definition. This file holds
# the closure blob type, `skipWrapperPrefix`, `find_wrapper`, `assert_wrapper`, `unify_wrapped`, `wrapper_vmi` and
# `'$c_wrap_predicate'/5`. The supervisor opcodes (`S_CALLWRAPPER`, `S_TABLED`, `S_WRAP`) and the shared `wrapper` block
# are T3's (src/pl-vmi.jl, src/pl-supervisor.jl): this file is written against those names.
#
# REPRESENTATION (DIVERGES, audit D-0388 item 5 Q1 (a), owner WRAP1). Upstream's closure blob holds a COPY of the whole
# `struct definition` (memcpy), with the `impl` union's `wrapped` member (`predicate`, `supervisor`) over the clause list. A
# Julia record (`closure{T}`, src/pl-incl.jl) holds the copy and the `wrapped` member as fields; the blob's payload is the
# record's number in `gd.closure_refs`, as the clause blob's (src/pl-dbref.jl). A wrapper supervisor is the code vector
# `[<prefix>, S_CALLWRAPPER-or-S_TABLED, 1, <closure atom word>, <wrapper name atom word>]` with the side table
# `codes_crefs = [<wrapper clause ref>]` (operand 1 indexes it, as `S_TRUSTME`'s in src/pl-supervisor.jl). The kernel keeps no
# `PL_register_atom` counts on the two atoms (atoms live for ever here), so `unregisterWrappedSupervisor` of upstream is
# a no-op and the blob's `release`/`acquire`/`save`/`load` hooks are not slots of `PL_blob_t`. The written form
# `<closure>(m:p/1)` of `write_closure` is a hook in the writer (`writeAtom`, src/pl-write.jl), which finds the closure by
# `closure_of_word` (a DIVERGES row in docs/architecture.md). The closure's definition (the copy) carries the closure's
# number in `impl_foreign_function` (WRAP1: upstream's `impl.closure` is a member of the `impl` union).
# Since WRAP1 the file also holds `unwrap_predicate/2`, `$wrapped_predicate/2`, `$wrapped_implementation/3` and
# `$closure_predicate/2` (pl-wrap.c:406-556), and the two helpers `supervisor_crefs` and `innermost_supervisor` the
# kernel's side-table representation of supervisor operands needs.

# PORT: pl-wrap.c _PL_closure_blob as closure_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the file header.
"The blob type of a closure (pl-wrap.c `_PL_closure_blob`): unique by payload, non-text, named `closure`."
const closure_blob = PL_blob_t(PL_BLOB_UNIQUE, "closure")

# ORIGINAL: the payload of a closure blob (upstream: the bytes of the `struct closure`).
"The 8 bytes of a closure blob: the closure's number in `gd.closure_refs`, little-endian."
_closure_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# ORIGINAL: upstream's `PL_blob_data(aref, NULL, NULL)` of a closure blob, with the type test of its callers
# (`type == &_PL_closure_blob`), as `recref_record` (src/pl-dbref.jl); the atom is the atom WORD a supervisor holds.
"The closure the blob atom word `w` names, or `nothing` when `w` is no closure blob."
function closure_of_word(
    gd::PL_global_data{T}, w::word
)::Union{Nothing, closure{T}} where {T}
    at = atomValue(gd.atoms, w)
    at.type === closure_blob || return nothing
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.closure_refs[Int(serial)]
end

# PORT: pl-wrap.c initWrap
# DIVERGES: the database's atom table is the argument; the type's name atom is made by `PL_register_blob_type` (upstream:
# `PL_new_atom(type->name)`). Called by the database's constructor where pl-setup.c:152 calls it, after `initDBRef!`.
"Register the closure blob type of pl-wrap.c in `atoms` (pl-wrap.c)."
function initWrap!(atoms::atoms_t)::Nothing
    PL_register_blob_type(atoms, closure_blob)
    return nothing
end

# PORT: pl-wrap.c unify_closure
# DIVERGES: the closure is a record (see the file header): the copy of `def` has an empty clause list (carrying the
# argument masks), the wrapper block as its supervisor and `def` and `supervisor` as its `wrapped` member; the database and
# the local data are arguments. The copy keeps `tabling` and `events` of `def` (the struct copy of upstream does).
"Unify `t` with a new closure blob holding a copy of `def`, wrapping `supervisor` (pl-wrap.c)."
function unify_closure(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, def::Definition{T},
    supervisor::Vector{code}, supervisor_crefs::Vector{ClauseRef{T}}
)::Bool where {T}
    cl = ClauseList{T}()                                        # c.def.lingering = NULL; the union's clause list is not read
    cl.args = def.impl_clauses.args
    cdef = definition{T}(                                       # c.def = *def
        def.functor_name, def.arity, cl, def.flags, def.name,
        def.code_data.wrapper,                                  # c.def.codes = SUPERVISOR(wrapper)
        ClauseRef{T}[], def.code_data, def.impl_foreign_function, def.module_, def.shared
    )
    cdef.tabling = def.tabling
    cdef.events = def.events
    c = closure{T}(cdef, def, supervisor, supervisor_crefs)    # impl.wrapped.predicate / .supervisor
    push!(gd.closure_refs, c)
    # DIVERGES (WRAP1, docs/architecture.md): upstream's `impl` union holds `impl.closure` (the `wrapped` member) in the
    # copy, so `impl.any.defined` is true for a closure definition; here the copy's `impl_foreign_function` is the closure's
    # number in `gd.closure_refs`, which `_impl_any_defined` reads (`!= 0`) and `S_WRAP` uses to find the closure.
    cdef.impl_foreign_function = length(gd.closure_refs)
    bytes = _closure_bytes(length(gd.closure_refs))
    w, _ = lookupBlob(gd.atoms, bytes, length(bytes), closure_blob)   # PL_unify_blob(t, &c, sizeof(c), &_PL_closure_blob)
    a = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
    return PL_unify_atomic(ld, t, a)
end

# PORT: pl-wrap.c get_closure_predicate
# DIVERGES: the database and the local data are arguments; returns the predicate or `nothing` (upstream: a Bool and `*def`).
"The predicate the closure in `t` wraps, or `nothing` when `t` is no closure (pl-wrap.c)."
function get_closure_predicate(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Definition{T}} where {T}
    a = PL_get_atom(ld, t)
    a === nothing && return nothing
    is_blob(a) || return nothing
    c = closure_of_word(gd, blob_handle(a))
    return c === nothing ? nothing : c.predicate                # c->def.impl.wrapped.predicate
end

# PORT: pl-wrap.h isCallWrapper
# DIVERGES: a function of the opcode (upstream: a macro).
"Whether the opcode `c` starts a wrapper supervisor: `S_CALLWRAPPER` or `S_TABLED` (pl-wrap.h)."
isCallWrapper(c::code)::Bool = c == S_CALLWRAPPER || c == S_TABLED

# PORT: pl-wrap.c skipWrapperPrefix
# DIVERGES: `codes` and the index of the first instruction (1-based) replace the program counter; the result is the index of
# the first instruction that is no prefix. `S_DET` is left out until the opcode is declared (`chainPredicateSupervisor`
# never emits it, `P_DET` cannot be set: src/pl-supervisor.jl).
"The index in `codes` of the first instruction after the prefix `chainPredicateSupervisor` prepends (pl-wrap.c)."
function skipWrapperPrefix(codes::Vector{code}, pc::Int=1)::Int
    while true
        op = codes[pc]                                          # fetchop(PC)
        if op == S_MQUAL || op == S_LMQUAL
            pc += 2                                             # stepPC(PC): the opcode and the argument offset
        elseif op == S_SSU_DET
            pc += 1                                             # stepPC(PC): the opcode
        else
            return pc
        end
    end
end

# PORT: pl-wrap.c unregisterWrappedSupervisor
# DIVERGES: a no-op. Upstream drops the references the supervisor holds on the closure atom and the wrapper name
# (`PL_unregister_atom`); atoms live for ever here (see the file header).
"Release the atoms a wrapper supervisor `codes` references (pl-wrap.c; a no-op here, see above)."
unregisterWrappedSupervisor(codes::Vector{code})::Nothing = nothing

# PORT: pl-wrap.c resetWrappedSupervisor
# DIVERGES: the database is an argument (the closures are found from their atom words); the innermost closure's `wrapped`
# supervisor is replaced by the shared `S_VIRGIN` and an empty side table (upstream: `impl.wrapped.supervisor =
# SUPERVISOR(virgin)`).
"""
Called from `freeCodesDefinition!` to reset the eventually wrapped supervisor to `S_VIRGIN` after a change to the wrapped
predicate. `S_WRAP` will eventually trap this and re-create an appropriate new supervisor (pl-wrap.c).
"""
function resetWrappedSupervisor(
    gd::PL_global_data{T}, def0::Definition{T}, do_linger::Bool
)::Nothing where {T}
    codes = def0.codes
    cw = skipWrapperPrefix(codes)
    c = nothing
    while isCallWrapper(codes[cw])
        c = closure_of_word(gd, codes[cw + 2])::closure{T}      # PL_blob_data(cw[2], NULL, NULL)
        codes = c.supervisor                                    # c->def.impl.wrapped.supervisor
        cw = skipWrapperPrefix(codes)
    end
    @assert c !== nothing                                       # assert(def != def0): def is the definition inside the closure
    c.supervisor = def0.code_data.virgin                        # def->impl.wrapped.supervisor = SUPERVISOR(virgin)
    c.supervisor_crefs = ClauseRef{T}[]
    freeSupervisor(c.def, codes, do_linger)
    return nothing
end

# PORT: pl-wrap.c find_wrapper
# DIVERGES: the database is an argument (the closure is found from its atom word); returns the supervisor holding the
# wrapper (its code, its side table) and the index of the wrapper instruction in the code, or `nothing` (upstream: the `Code`
# pointer of the instruction).
"The wrapper of `def` named by the atom word `name`: `(codes, crefs, index)`, or `nothing` (pl-wrap.c)."
function find_wrapper(
    gd::PL_global_data{T}, def::Definition{T}, name::word
)::Union{Nothing, Tuple{Vector{code}, Vector{ClauseRef{T}}, Int}} where {T}
    codes = def.codes
    crefs = def.codes_crefs
    i = skipWrapperPrefix(codes)
    while isCallWrapper(codes[i])
        codes[i + 3] == name && return (codes, crefs, i)        # codes[3] == (code)name
        c = closure_of_word(gd, codes[i + 2])::closure{T}       # PL_blob_data(codes[2], NULL, NULL)
        codes = c.supervisor                                    # c->def.impl.wrapped.supervisor
        crefs = c.supervisor_crefs
        i = skipWrapperPrefix(codes)
    end
    return nothing
end

# ORIGINAL (WRAP1; upstream's supervisor operands hold the clause reference itself, `code2ptr(ClauseRef, *PC)`)
# DIVERGES: a supervisor operand here indexes a side table (`definition.codes_crefs`, `closure.supervisor_crefs`), and after
# `S_WRAP` the frame's predicate is the wrapped one while the supervisor that runs is the closure's, not `def.codes`. This
# finds the side table of the running supervisor `codes`: `def.codes_crefs` when `codes === def.codes` (the hot path: no
# wrapper), else the table of the wrapper-chain member (from `def.codes` inward) whose `supervisor` is `codes`.
"The clause-reference side table of the supervisor `codes` running for `def` (a wrapped predicate: the closure's)."
function supervisor_crefs(
    gd::PL_global_data{T}, def::Definition{T}, codes::Vector{code}
)::Vector{ClauseRef{T}} where {T}
    codes === def.codes && return def.codes_crefs
    cur = def.codes
    i = skipWrapperPrefix(cur)
    while isCallWrapper(cur[i])
        c = closure_of_word(gd, cur[i + 2])::closure{T}
        c.supervisor === codes && return c.supervisor_crefs
        cur = c.supervisor
        i = skipWrapperPrefix(cur)
    end
    error(
        "supervisor_crefs: the running supervisor of ",
        def.name,
        " is not in its wrapper chain"
    )
end

# ORIGINAL (WRAP1; upstream's choice point holds the code pointer itself, `ch->value.PC`)
# DIVERGES: the kernel re-derives the code of a `P_FOREIGN` frame's retry as `DEF.codes` (src/pl-wam.jl, `shallow_backtrack`
# and `deep_backtrack`); for a wrapped foreign predicate `DEF.codes` is the wrapper supervisor, so this returns the innermost
# supervisor (the one `S_WRAP` ran, holding the foreign call) and its crefs.
"The innermost supervisor of `def` under its wrapper chain: `(codes, crefs)`; `def`'s own when it has no wrapper."
function innermost_supervisor(
    gd::PL_global_data{T}, def::Definition{T}
)::Tuple{Vector{code}, Vector{ClauseRef{T}}} where {T}
    codes = def.codes
    crefs = def.codes_crefs
    i = skipWrapperPrefix(codes)
    while isCallWrapper(codes[i])
        c = closure_of_word(gd, codes[i + 2])::closure{T}
        codes = c.supervisor
        crefs = c.supervisor_crefs
        i = skipWrapperPrefix(codes)
    end
    return codes, crefs
end

# PORT: pl-wrap.c assert_wrapper
# DIVERGES: the database and the local data are arguments; no `acquire_def`/`release_def` (threads only: left out, as
# `getClauses`). `pushPredicateAccessObj!` cannot fail here (upstream's NULL is its reference-stack limit).
"Assert the clause in `clause` at the end of its predicate; its clause reference (pl-wrap.c)."
function assert_wrapper(
    gd::PL_global_data{T}, ld::PL_local_data{T}, clause::term_t
)::Union{Nothing, ClauseRef{T}} where {T}
    cl = assert_term!(gd, ld, clause, 0, CL_END, nothing, nothing, 0)   # assert_term(clause, NULL, CL_END, NULL_ATOM, NULL, 0)
    cl === nothing && return nothing
    def = cl.predicate
    pushPredicateAccessObj!(ld, gd, def)
    cref = def.impl_clauses.first_clause
    while cref !== nothing
        cref.clause === cl && break
        cref = cref.next
    end
    popPredicateAccess!(ld, def)
    @assert cref !== nothing                                    # assert(cref && cref->value.clause == cl)
    return cref
end

# PORT: pl-wrap.c unify_wrapped
# DIVERGES: built through the FLI (`PL_unify_functor` of the closure blob as the functor's name, then the arguments
# linked one by one), where upstream allocates the compound on the global stack directly; no `ensureGlobalSpace` retry.
"Unify `wrapped` with `<closure>(Args...)`: the compound of the same arguments as `head`, named by the closure blob (pl-wrap.c)."
function unify_wrapped(
    ld::PL_local_data{T}, wrapped::term_t, clo::T, head::term_t
)::Bool where {T}
    if PL_is_compound(ld, head)                                 # isTerm(*from)
        na = PL_get_name_arity(ld, head)
        na === nothing && return false
        arity = na[2]
        t = PL_new_term_ref(ld)
        PL_unify_functor(ld, t, clo, arity) || return false  # *to++ = PL_new_functor(closure, arity)
        a = PL_new_term_ref(ld)
        for i in 1:arity
            _PL_get_arg(ld, i, head, a)                         # *to++ = linkValI(f++)
            PL_unify_arg(ld, i, t, a) || return false
        end
        return PL_unify(ld, wrapped, t)                         # PL_unify_atomic(wrapped, w)
    end
    return PL_unify_atom(ld, wrapped, clo)
end

# PORT: pl-wrap.c wrapper_vmi
# DIVERGES: `wname` is the wrapper name's symbol; `ATOM_table` is the symbol `table`.
"The opcode of a wrapper named `wname` for `def`: `S_TABLED` for the `table` wrapper of a variant tabled predicate, else `S_CALLWRAPPER` (pl-wrap.c)."
function wrapper_vmi(def::Definition{T}, wname::T)::code where {T}
    if sym_key(wname) == sym_key(mk_sym(T, :table)) &&
        def.tabling !== nothing && (def.tabling.flags & TP_VARIANT) != 0
        return S_TABLED                                         # encode(S_TABLED)
    end
    return S_CALLWRAPPER                                        # encode(S_CALLWRAPPER)
end

# PORT: pl-wrap.c c_wrap_predicate as pl_c_wrap_predicate5_va
# (PRED_IMPL("$c_wrap_predicate", 5, c_wrap_predicate, PL_FA_TRANSPARENT))
# DIVERGES: the wrapper supervisor is the code vector and side table of the file header, installed by assigning
# `def.codes`/`def.codes_crefs` where upstream calls `allocCodes`, `chainPredicateSupervisor` and `setSupervisor`; the
# closure's supervisor is the definition's current one (`def.codes`, `def.codes_crefs`), taken before the install.
"`'\$c_wrap_predicate'(:Head, +Name, -Closure, -Wrapped, +Body)`: install a wrapper named `Name` for the predicate `Head` (pl-wrap.c)."
function pl_c_wrap_predicate5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    head = PL_new_term_ref(ld)
    clo = A3

    wname = PL_get_atom_ex(ld, A2)
    wname === nothing && return FFALSE
    proc = get_procedure(gd, ld, A1, GP_DEFINE, head)
    proc === nothing && return FFALSE
    def = proc.definition
    wnamew = _atom_word!(ld, wname)

    found = find_wrapper(gd, def, wnamew)
    if found !== nothing
        codes, crefs, i = found
        aref = _atom_value(ld, codes[i + 2])                    # atom_t aref = (atom_t)codes[2]
        PL_unify_atom(ld, clo, aref) || return FFALSE
        unify_wrapped(ld, A4, aref, head) || return FFALSE

        cref = assert_wrapper(gd, ld, A5)
        if cref !== nothing
            old = crefs[Int(codes[i + 1])].clause::Clause{T}   # code2ptr(ClauseRef, codes[1])->value.clause
            crefs[Int(codes[i + 1])] = cref                     # codes[1] = ptr2code(cref)
            codes[i] = wrapper_vmi(def, wname)
            retractClauseDefinition!(gd, old.predicate, old, false)
            return FTRUE
        end
    else
        if unify_closure(gd, ld, clo, def, def.codes, def.codes_crefs)
            aref = PL_get_atom_ex(ld, clo)
            aref === nothing && return FFALSE
            unify_wrapped(ld, A4, aref, head) || return FFALSE  # something really wrong

            cref = assert_wrapper(gd, ld, A5)
            if cref !== nothing
                codes = code[
                    wrapper_vmi(def, wname), code(1), _atom_word!(ld, aref), wnamew
                ]                                               # allocCodes(4): the operand 1 indexes the side table
                crefs = ClauseRef{T}[cref]
                codes, crefs = chainPredicateSupervisor(def, (codes, crefs))

                def.codes = codes                               # def->codes = SUPERVISOR(virgin); setSupervisor(def, codes)
                def.codes_crefs = crefs
                return FTRUE
            end
        end
    end
    return FFALSE
end

# ORIGINAL (WRAP1): the `get_procedure(descr, &proc, h, GP_RESOLVE)` of pl-proc.c:741-790 WITHOUT `GP_NAMEARITY` (the term is a
# HEAD: `strip module`, `get_head_functor`), as `get_procedure` (src/pl-proc.jl) does for `GP_DEFINE`; the file's two callers
# (`$wrapped_predicate/2`, `$wrapped_implementation/3`) need `GP_RESOLVE`, the kernel has it only with `GP_NAMEARITY`
# (`get_procedure_resolve_namearity`). `h` (when not 0) receives the stripped head; an undefined procedure is created.
"The procedure a dynamic call to the head in `descr` runs (created undefined when none is visible), or `nothing`; the stripped head into `h`."
function get_procedure_resolve_head(
    gd::PL_global_data{T}, ld::PL_local_data{T}, descr::term_t, h::term_t
)::Union{Nothing, Procedure{T}} where {T}
    head = h == 0 ? PL_new_term_ref(ld) : h
    ok, mi = PL_strip_module(gd, ld, descr, 0, head)
    ok || return nothing
    name, arity = get_head_functor(ld, head, 0)
    arity < 0 && return nothing
    return resolveProcedure(gd, name, arity, gd.modules[mi])
end

# PORT: pl-wrap.c uwrap_predicate as pl_unwrap_predicate2_va
# (PRED_IMPL("unwrap_predicate", 2, uwrap_predicate, PL_FA_TRANSPARENT))
# DIVERGES: the code pointer `cp` is the pair (`holder`, `codes`/`crefs`): `holder === nothing` is `&def->codes`, else the
# closure whose `supervisor` (`&cls->def.impl.wrapped.supervisor`) it is; the splice assigns code AND side table.
"`unwrap_predicate(:PI, ?Name)`: remove the wrapper named `Name` (an unbound `Name`: the outermost) from the predicate (pl-wrap.c)."
function pl_unwrap_predicate2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    proc = get_procedure_resolve_namearity(gd, ld, A1)          # GP_NAMEARITY|GP_RESOLVE
    proc === nothing && return FFALSE
    def = proc.definition
    holder = nothing                                            # Code *cp = &def->codes
    codes = def.codes
    crefs = def.codes_crefs
    cw = skipWrapperPrefix(codes)
    while isCallWrapper(codes[cw])
        cref = crefs[Int(codes[cw + 1])]                        # code2ptr(ClauseRef, cw[1])
        cl = cref.clause::Clause{T}
        c = closure_of_word(gd, codes[cw + 2])::closure{T}      # PL_blob_data(aref, NULL, NULL)
        wname = _atom_value(ld, codes[cw + 3])
        if !PL_unify_atom(ld, A2, wname)
            holder = c                                          # cp = &cls->def.impl.wrapped.supervisor
            codes = c.supervisor
            crefs = c.supervisor_crefs
            cw = skipWrapperPrefix(codes)
            continue
        end

        retractClauseDefinition!(gd, cl.predicate, cl, false)
        if holder === nothing                                   # *cp = cls->def.impl.wrapped.supervisor
            def.codes = c.supervisor
            def.codes_crefs = c.supervisor_crefs
        else
            holder.supervisor = c.supervisor
            holder.supervisor_crefs = c.supervisor_crefs
        end

        freeSupervisor(def, codes, true)

        return FTRUE
    end

    return FFALSE
end

# PORT: pl-wrap.c wrapped_predicate as pl_wrapped_predicate2_va
# (PRED_IMPL("wrapped_predicate", 2, wrapped_predicate, PL_FA_TRANSPARENT); PRED_DEF name `$wrapped_predicate`)
# DIVERGES: the `Name-ClauseRef` pairs are unified through `PL_unify_functor`/`PL_unify_arg` where upstream uses `PL_unify_term`.
"`'\$wrapped_predicate'(:Head, -Wrappers)`: the list `[Name-ClauseRef ...]` of the wrappers of `Head`, the outermost first (pl-wrap.c)."
function pl_wrapped_predicate2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    proc = get_procedure_resolve_head(gd, ld, A1, 0)            # get_procedure(A1, &proc, 0, GP_RESOLVE)
    proc === nothing && return FFALSE
    def = proc.definition
    codes = def.codes
    crefs = def.codes_crefs
    cw = skipWrapperPrefix(codes)

    if isCallWrapper(codes[cw])
        tail = PL_copy_term_ref(ld, A2)
        head = PL_new_term_ref(ld)
        ct = PL_new_term_ref(ld)
        nt = PL_new_term_ref(ld)

        while true
            c = closure_of_word(gd, codes[cw + 2])::closure{T}  # PL_blob_data(codes[2], NULL, NULL)
            cref = crefs[Int(codes[cw + 1])]                    # code2ptr(ClauseRef, codes[1])

            PL_put_clref(gd, ld, ct, cref.clause::Clause{T}) || return FFALSE
            PL_unify_list(ld, tail, head, tail) || return FFALSE
            PL_put_atom(ld, nt, _atom_value(ld, codes[cw + 3]))
            PL_unify_functor(ld, head, mk_sym(T, :-), 2) || return FFALSE   # PL_FUNCTOR, FUNCTOR_minus2
            PL_unify_arg(ld, 1, head, nt) || return FFALSE      # PL_ATOM, code2atom(codes[3])
            PL_unify_arg(ld, 2, head, ct) || return FFALSE      # PL_TERM, ct

            codes = c.supervisor                                # c->def.impl.wrapped.supervisor
            crefs = c.supervisor_crefs
            cw = skipWrapperPrefix(codes)
            isCallWrapper(codes[cw]) || return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-wrap.c wrapped_implementation as pl_wrapped_implementation3_va
# (PRED_IMPL("$wrapped_implementation", 3, wrapped_implementation, PL_FA_TRANSPARENT))
# DIVERGES: the goal `Closure(Args...)` (or the atom `Closure` of arity 0) is `unify_wrapped`'s (the FLI-built compound),
# where upstream allocates it on the global stack and unifies `A3` with it.
"`'\$wrapped_implementation'(:Goal, +Name, -Wrapped)`: calling `Wrapped` calls the predicate of `Goal` as seen from the wrapper `Name` (pl-wrap.c)."
function pl_wrapped_implementation3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    head = PL_new_term_ref(ld)

    wname = PL_get_atom_ex(ld, A2)
    wname === nothing && return FFALSE
    proc = get_procedure_resolve_head(gd, ld, A1, head)
    proc === nothing && return FFALSE
    def = proc.definition

    found = find_wrapper(gd, def, _atom_word!(ld, wname))
    if found !== nothing
        codes, _, i = found
        aref = _atom_value(ld, codes[i + 2])                    # atom_t aref = codes[2]
        # arity > 0: p[0] = lookupFunctorDef(aref, arity), the head's arguments linked; else PL_unify_atom(A3, aref)
        return unify_wrapped(ld, A3, aref, head) ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-wrap.c write_closure
# DIVERGES: returns the text and the writer (`writeAtom`, src/pl-write.jl) puts it out through `PutToken`, where upstream
# `Sfprintf`s to the stream; the database is an argument (upstream: `PL_blob_data`, then `predicateName(&c->def)`).
"The text a closure blob is written as: `<closure>(m:p/1)` (pl-wrap.c)."
write_closure(gd::PL_global_data{T}, c::closure{T}) where {T} =
    "<closure>(" * _autoload_predicate_name(gd, c.def) * ")"       # Sfprintf(s, "<closure>(%s)", predicateName(&c->def))

# PORT: pl-wrap.c closure_predicate as pl_closure_predicate2_va
# (PRED_IMPL("$closure_predicate", 2, closure_predicate, 0))
# DIVERGES: the blob test is `closure_of_word` of the atom's handle (upstream: `PL_get_blob` and the type pointer).
"`'\$closure_predicate'(+Closure, -PI)`: the predicate `Closure` (a closure blob) calls, as `Module:Name/Arity` (pl-wrap.c)."
function pl_closure_predicate2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    a = PL_get_atom(ld, A1)
    if a !== nothing && is_blob(a)
        c = closure_of_word(gd, blob_handle(a))
        if c !== nothing
            return if unify_definition(
                gd, ld, MODULE_user(gd), A2, c.def, 0, GP_QUALIFY | GP_NAMEARITY
            )
                FTRUE
            else
                FFALSE
            end
        end
    end

    return PL_type_error(ld, "closure", A1) ? FTRUE : FFALSE
end

# PORT: pl-wrap.c BeginPredDefs as PL_predicates_from_wrap
# DIVERGES: none in the table (upstream's order: `META` is PL_FA_TRANSPARENT; `$closure_predicate/2` has no flags).
"pl-wrap.c's registration table (`BeginPredDefs(wrap)`)."
const PL_predicates_from_wrap = (
    PL_extension(
        "\$c_wrap_predicate", 5, pl_c_wrap_predicate5_va, PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension(
        "unwrap_predicate", 2, pl_unwrap_predicate2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension(
        "\$wrapped_predicate", 2, pl_wrapped_predicate2_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension(
        "\$wrapped_implementation", 3, pl_wrapped_implementation3_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension("\$closure_predicate", 2, pl_closure_predicate2_va, PL_FA_VARARGS)
)
