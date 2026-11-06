# UPSTREAM: swipl-devel src/pl-wrap.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-wrap.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2019-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-wrap.c (the upstream file was read at the pin; capability search in evidence/TAB1MIN/handoff.md)
#
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
# a no-op and the blob's `release`/`acquire`/`save`/`load` hooks are not slots of `PL_blob_t`. The written
# form `<closure>(m:p/1)` of `write_closure` needs a blob write hook in the writer: it prints as the term layer's blob
# form (a DIVERGES row in docs/architecture.md; WRAP1's).
# Left out (WRAP1 / TAB1): `wrapped_predicate/2`, `unwrap_predicate/2`, `$wrapped_implementation/3`, `$closure_predicate/2`
# (pl-wrap.c:406-556): none of them runs at load time.

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

# PORT: pl-wrap.c BeginPredDefs as PL_predicates_from_wrap
# DIVERGES: the ported entry only (upstream's table also lists `unwrap_predicate/2`, `$wrapped_predicate/2`,
# `$wrapped_implementation/3` and `$closure_predicate/2`: left to WRAP1).
"pl-wrap.c's registration table (`BeginPredDefs(wrap)`): the ported entries."
const PL_predicates_from_wrap = (
    PL_extension(
        "\$c_wrap_predicate", 5, pl_c_wrap_predicate5_va, PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
)
