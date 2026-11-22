# UPSTREAM: swipl-devel src/pl-coverage.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-coverage.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2023-2024, SWI-Prolog Solutions b.v.
# (src/pl-coverage.h, the second upstream file, carries Copyright (c)  2022, University of Amsterdam, VU University Amsterdam and SWI-Prolog Solutions b.v.)
# allow-new-artifact: a port of the pin's src/pl-coverage.c, read in full from the pin (git show 18168e62) for this file
#
# COVERAGE (pl-coverage.c), lane F: the data layer of the low-level coverage collection (library(prolog_coverage) reads it
# with '$cov_data'/3 and writes it with '$cov_add'/3) and its six foreign predicates. A SITE is a clause (`clause(Ref)`:
# entered, exited) or a call site (`call_site(Ref, PC)`: the pc is an offset into the clause's code); each has an enter and
# an exit counter. The sites are in a hash table of src/os/pl-table.jl, keyed by the clause SERIAL and the pc offset
# (src/pl-incl.jl, the block `pl-coverage`: the structs and the DIVERGES of the keys).
#
# THE COLLECTION. Upstream counts through the VM: `Coverage(FR, port)` (pl-coverage.h) at the call, unify and exit ports,
# behind `ALERT_COVERAGE` in `updateAlerted` and the run mode `'$cov_start'/1` clears. Since COV1 the kernel has all three:
# the functions the VM's hooks call, `record_coverage`, `call_site`, `clref_site`, `bump`, `running_static_predicate` and
# `Coverage`, are written here (piece A), `updateAlerted` sets `ALERT_COVERAGE`, and the run loop calls `Coverage` at
# `i_enter_alerted`, `depart_alerted`, `i_exit_alerted` and `I_EXITFACT` (src/pl-wam.jl, piece B). `'$cov_start'/1` is the
# port. The redo port is not counted by upstream either. NOT PORTED: the child thread's copy of `coverage.active`
# (pl-thread.c; no thread start). The pc offsets are the kernel's, 0-based indices into the clause's `codes`, not swipl's
# code layout (evidence/R2/cov1_design.md Q2): a test compares counts, never pcs.
#
# DIVERGES (file-wide):
#   1. KEYS AND OBJECTS: see src/pl-incl.jl (the serial and offset key, the object vector the table's values index).
#      A pc offset outside 0..2^32-2 has no key: it is a `NotPortedError` (a real clause's code is far smaller).
#   2. MEMORY: no `malloc`/`PL_free`, no atom reference counts (`PL_unregister_atom`: no atom GC, src/pl-dbref.jl),
#      no atomic increments (one engine: a plain `+=`; `COMPARE_AND_SWAP_PTR` is a plain store).
#   3. THREADS: `share_coverage_data` keeps the reference count; no thread copies it (src/pl-thread.jl has no thread start).
#   4. TWO CASES where upstream runs on with an unset value are answered with a failure here (the error, if any, is
#      pending): '$cov_add' after `PL_get_clref` raised (its `cl` is unset at the pin), and '$cov_data' called with a
#      first argument that is neither unbound, `call_site/2` nor `clause/1` on a table that exists (its `state` is unset).

# PORT: pl-coverage.c free_cov_symbol
# DIVERGES: file-wide 2: the objects are in `coverage.objs` and need no free; there is no atom to unregister.
"The table's `free_symbol` hook (pl-coverage.c): nothing is left to release."
free_cov_symbol(name::UInt64, value::UInt64)::Nothing = nothing

# PORT: pl-coverage.c newCoverageData
# DIVERGES: file-wide 2; the term type is the argument (the objects hold a clause blob of it).
"A new, empty coverage record: a table of 1024 buckets, one reference, tracking child threads (pl-coverage.c)."
function newCoverageData(::Type{T})::coverage{T} where {T}
    t = newHTable(1024, nothing, free_cov_symbol)        # t->free_symbol = free_cov_symbol
    return coverage{T}(t, cov_obj{T}[], 1, COV_TRACK_THREADS)
end

# PORT: pl-coverage.c share_coverage_data
# DIVERGES: the argument and the result are `Union{Nothing, coverage}`, with no type parameter `T`: a `T` that only the
# `coverage{T}` arm of the union binds is an unbound type parameter for Aqua when the argument is `nothing`, and a result
# type built from it is a run-time `convert` for JET (the value returned is `cov` itself).
"Count one more user of `cov` (a `nothing` is passed through); `cov` (pl-coverage.c)."
function share_coverage_data(cov::Union{Nothing, coverage})::Union{Nothing, coverage}
    cov === nothing || (cov.references += 1)           # ATOMIC_INC(&cov->references)
    return cov
end

# PORT: pl-coverage.c unshare_coverage_data
"Count one user less of `cov`; the last one destroys its table (pl-coverage.c)."
function unshare_coverage_data(cov::coverage{T})::Nothing where {T}
    cov.references -= 1                                 # ATOMIC_DEC(&cov->references) == 0
    if cov.references == 0
        destroyHTable(cov.table)
        # free(cov): the objects stay with `cov.objs` (an open cov_data enumeration holds them) until it is collected
    end
    return nothing
end

# ORIGINAL: the table key of a clause site (`COV_KEY_CLAUSE` in the low half) or, with `offset`, of a call site.
"The table key of the clause with number `serial`, or of its call site at `offset` (src/pl-incl.jl, the key's layout)."
_cov_key(serial::Int, offset::Int)::UInt64 = (UInt64(serial) << 32) | UInt64(offset)

# PORT: pl-coverage.c pc_call_site
# DIVERGES: file-wide 1 and 2; the pc is an `offset` into `cl`'s code, the database `gd` an argument. Another engine
# that adds the same key first (`obj2 != obj`) cannot exist here: the branch is kept, the object is dropped.
"The record of the call site at `offset` in `cl`, made if there is none (pl-coverage.c)."
function pc_call_site(
    gd::PL_global_data{T}, cov::coverage{T}, cl::Clause{T}, offset::Int
)::cov_obj{T} where {T}
    cref = lookup_clref(gd, cl)                         # lookup_clref(cl): the clause gets its number here
    if offset < 0 || offset >= COV_KEY_CLAUSE
        throw(
            NotPortedError{T}(
                cref,
                "a coverage call site at pc offset $offset (outside 0..2^32-2)",
                "COV1"
            )
        )
    end
    serial = gd.clause_serials[cl]
    key = _cov_key(serial, offset)
    v = lookupHTable(cov.table, key)                    # lookupHTablePP(cov->table, pc)
    if v == NULL_VALUE
        push!(cov.objs, cov_obj{T}(COV_PC, cref, serial, offset, 0, 0))
        mine = UInt64(length(cov.objs))
        v2 = addHTable(cov.table, key, mine)            # cov_obj *obj2 = addHTablePP(cov->table, pc, obj)
        if v2 != mine
            pop!(cov.objs)                              # PL_free(obj)
            v = v2
        else
            v = mine
        end
    end
    return cov.objs[Int(v)]
end

# PORT: pl-coverage.c clause_site
# DIVERGES: file-wide 1 and 2; a `nothing` stands for upstream's NULL `cov` (returns `nothing`).
"The record of the clause `cl`, made if there is none (pl-coverage.c)."
function clause_site(
    gd::PL_global_data{T}, cov::Union{Nothing, coverage{T}}, cl::Clause{T}
)::Union{Nothing, cov_obj{T}} where {T}
    cov === nothing && return nothing
    cref = lookup_clref(gd, cl)
    serial = gd.clause_serials[cl]
    key = _cov_key(serial, COV_KEY_CLAUSE)
    v = lookupHTable(cov.table, key)                    # lookupHTablePP(cov->table, cl)
    if v == NULL_VALUE
        push!(cov.objs, cov_obj{T}(COV_CLAUSE, cref, serial, -1, 0, 0))
        mine = UInt64(length(cov.objs))
        v2 = addHTable(cov.table, key, mine)
        if v2 != mine
            pop!(cov.objs)
            v = v2
        else
            v = mine
        end
    end
    return cov.objs[Int(v)]
end

# PORT: pl-coverage.c running_static_predicate
# DIVERGES: the frame record is the argument; a frame with no predicate (a record not yet filled) is not a running static predicate.
"Whether frame `fr` runs a static, non-foreign predicate: `isoff(def, P_DYNAMIC|P_FOREIGN)` (pl-coverage.c)."
function running_static_predicate(fr::localFrame)::Bool
    def = fr.predicate
    def === nothing && return false
    return (def.flags & (P_DYNAMIC | P_FOREIGN)) == 0
end

# PORT: pl-coverage.c call_site
# DIVERGES: file-wide 1 and 2; the frame is an index and the pc an offset (the frame's `programPointer.pc` is 1-based: `- 1`).
# Two guards upstream does not have: a frame without a parent (a query's top frame) and a parent without a clause have no site
# (upstream would dereference NULL). The parent of a goal frame is the query's top frame, whose clause is `gd.clauses_top_cref`.
"The record of the call site `fr` was called from (its RETURN pc in the parent's clause), made if there is none; `nothing` when the parent is dynamic or foreign (pl-coverage.c)."
function call_site(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fr::localFrame{T}
)::Union{Nothing, cov_obj{T}} where {T}
    fr.parent == 0 && return nothing
    parent = ld.frames[fr.parent]
    cov = ld.coverage.data
    if cov !== nothing && running_static_predicate(parent)      # (cov=LD->coverage.data) && running_static_predicate(parent)
        cref = parent.clause
        cref === nothing && return nothing
        cl = cref.clause                                        # parent->clause->value.clause
        cl === nothing && return nothing
        return pc_call_site(gd, cov, cl, fr.programPointer.pc - 1)
    end
    return nothing
end

# PORT: pl-coverage.c clref_site
# DIVERGES: the database and the local data are arguments; a clause reference without a clause has no site.
"The record of the clause of `cref`, made if there is none (pl-coverage.c)."
function clref_site(
    gd::PL_global_data{T}, ld::PL_local_data{T}, cref::ClauseRef{T}
)::Union{Nothing, cov_obj{T}} where {T}
    cl = cref.clause                                            # cref->value.clause
    cl === nothing && return nothing
    return clause_site(gd, ld.coverage.data, cl)
end

# PORT: pl-coverage.c bump
# DIVERGES: file-wide 2 (a plain `+=`); the argument is `Union{Nothing, cov_obj}` without a type parameter, as `share_coverage_data`'s.
"Count one call (`CALL_PORT`) or one exit (`EXIT_PORT`) at `obj`; a `nothing` is no site (pl-coverage.c)."
function bump(obj::Union{Nothing, cov_obj}, port::Int)::Nothing
    if obj !== nothing
        if port == CALL_PORT
            obj.enter += 1                                      # ATOMIC_INC(&cov->enter)
        elseif port == EXIT_PORT
            obj.exits += 1                                      # ATOMIC_INC(&cov->exits)
        else
            error("bump: port $port is neither the call nor the exit port")     # assert(0)
        end
    end
    return nothing
end

# PORT: pl-coverage.c record_coverage
# DIVERGES: `fr` is the frame's index (the VM's `FR`) and the database and local data are arguments; a static predicate's frame
# without a clause (upstream dereferences it) records no clause site.
"Record `port` at frame `fr`: the call port counts its call site, the unify port the clause's entry, the exit port the clause's exit and the call site's (pl-coverage.c)."
function record_coverage(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fr::Int, port::Int
)::Nothing where {T}
    f = ld.frames[fr]
    if port == CALL_PORT
        bump(call_site(gd, ld, f), port)
    elseif port == UNIFY_PORT
        if running_static_predicate(f) && f.clause !== nothing
            bump(clref_site(gd, ld, f.clause), CALL_PORT)
        end
    elseif port == EXIT_PORT
        if running_static_predicate(f) && f.clause !== nothing
            bump(clref_site(gd, ld, f.clause), port)
        end
        bump(call_site(gd, ld, f), port)
    end
    return nothing
end

# PORT: pl-coverage.h Coverage
# DIVERGES: the database and local data are arguments; `fr` is the frame's index.
"The VM's hook: `record_coverage` while the collection is active (pl-coverage.h `Coverage`)."
@inline function Coverage(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fr::Int, port::Int
)::Nothing where {T}
    ld.coverage.active != 0 && record_coverage(gd, ld, fr, port)
    return nothing
end

# ── the Prolog binding ───────────────────────────────────────────────────────────────────────────────────────────────────

# PORT: pl-coverage.c cov_add as pl_cov_add3_va
# (PRED_IMPL("$cov_add", 3, cov_add, 0))
# DIVERGES: file-wide 1 and 4 (`PL_get_clref` raising: the type error is returned as the failure; an erased clause is
# `existence_error(db_reference, Ref)` as upstream).
"""
    '\$cov_add'(+Site, +EnterCount, +ExitCount)

Add `EnterCount` and `ExitCount` to the statistics of `Site`, `call_site(ClauseRef, PC)` or `clause(ClauseRef)` (pl-coverage.c).
"""
function pl_cov_add3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    gd = _query_gd(ld)
    pc_offset = -1
    tmp = PL_new_term_ref(ld)

    enter = PL_get_int64_ex(ld, A2)
    enter === nothing && return FFALSE
    leave = PL_get_int64_ex(ld, A3)
    leave === nothing && return FFALSE

    if PL_is_functor(ld, A1, mk_sym(T, :call_site), 2)
        _PL_get_arg(ld, 2, A1, tmp)
        pc = PL_get_int64_ex(ld, tmp)
        pc === nothing && return FFALSE
        pc_offset = pc
    elseif !PL_is_functor(ld, A1, mk_sym(T, :clause), 1)
        return PL_domain_error(ld, "cov_data", A1) ? FTRUE : FFALSE
    end

    _PL_get_arg(ld, 1, A1, tmp)
    rc, cl = PL_get_clref(gd, ld, tmp)
    rc == 0 && return FFALSE                            # (file-wide 4: upstream runs on with `cl` unset)
    if rc == -1
        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :db_reference), tmp) ? FTRUE : FFALSE
    end
    cl = cl::Clause{T}

    cov = ld.coverage.data
    if cov === nothing                                  # !cov
        cov = ld.coverage.data = newCoverageData(T)
    end

    if pc_offset != -1
        obj = pc_call_site(gd, cov, cl, pc_offset)
    else
        obj = clause_site(gd, cov, cl)
    end

    if obj !== nothing
        obj.enter += enter                              # ATOMIC_ADD(&obj->enter, enter)
        obj.exits += leave
    end

    return FTRUE
end

# PORT: pl-coverage.c unify_cov
# DIVERGES: the database `gd` is an argument; the term is built on a new reference and unified (upstream's
# `PL_unify_term(t, PL_FUNCTOR, …)`).
"Unify `t` with the site of `obj`, `call_site(Ref, PC)` or `clause(Ref)`; false when its clause is gone (pl-coverage.c)."
function unify_cov(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, obj::cov_obj{T}
)::Bool where {T}
    if obj.type == COV_PC
        clause_clref(gd, obj.cref) === nothing && return false     # clause_clref(cov->cref) == NULL
        r = PL_new_term_ref(ld)
        PL_cons_functor(
            ld, r, _err_functor(ld, :call_site, 2), _err_atom(ld, obj.cref),
            _err_int(ld, obj.pc)
        )
        return PL_unify(ld, t, r)
    elseif obj.type == COV_CLAUSE
        r = PL_new_term_ref(ld)
        PL_cons_functor(ld, r, _err_functor(ld, :clause, 1), _err_atom(ld, obj.cref))
        return PL_unify(ld, t, r)
    end
    return false                                        # default: assert(0)
end

# PORT: pl-coverage.c free_state
"Release the enumerator of `state` (pl-coverage.c; the pool record itself is released by the caller)."
function free_state(state::cov_data_state)::Nothing
    freeTableEnum(state.e)
    state.e = nothing
    return nothing
end

# PORT: pl-coverage.c is_candidate
# DIVERGES: the clause is compared by its serial (`cov->cref != state->cref`: one atom per clause).
"Whether `obj` is an answer of the enumeration `state` (type, clause, and some count not zero; pl-coverage.c)."
function is_candidate(state::cov_data_state, obj::cov_obj)::Bool
    state.type != COV_ANY && obj.type != state.type && return false
    state.serial != 0 && obj.serial != state.serial && return false
    obj.enter == 0 && obj.exits == 0 && return false
    return true
end

# PORT: pl-coverage.c cov_data as pl_cov_data3_va
# (PRED_IMPL("$cov_data", 3, cov_data, PL_FA_NONDETERMINISTIC))
# DIVERGES: file-wide 1, 3 and 4; the state is a record of `ld.coverage.states` (`REDO_PTR`'s index); the foreign frame
# is closed before a retry as upstream's. The pc of a `call_site(Ref, PC)` with both bound is looked up by key, as upstream.
"""
    '\$cov_data'(?Obj, -Entered, -Exited)

Read the coverage information: `Obj` is `clause(ClauseRef)` or `call_site(ClauseRef, PC)`; partial information narrows the
search, ground information is answered by one lookup (pl-coverage.c). Fails when there is no data.
"""
function pl_cov_data3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    gd = _query_gd(ld)
    pool = ld.coverage.states

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        cov = ld.coverage.data
        cov === nothing && return FFALSE                # !(cov=LD->coverage.data) || !(cov_table=cov->table)
        idx = 0
        if PL_is_variable(ld, A1)
            idx = alloc_foreign_state!(pool)
            st = pool.states[idx]
            st.type = COV_ANY
            st.serial = 0
        elseif PL_is_functor(ld, A1, mk_sym(T, :call_site), 2)
            a = PL_new_term_ref(ld)
            cl = nothing
            pc_offset = -1

            _PL_get_arg(ld, 1, A1, a)
            if !PL_is_variable(ld, a)
                rc, cl = PL_get_clref(gd, ld, a)
                rc == 0 && return FFALSE                # !PL_get_clref(a, &cl): the error is raised
            end
            _PL_get_arg(ld, 2, A1, a)
            if !PL_is_variable(ld, a)
                pc = PL_get_int64_ex(ld, a)
                pc === nothing && return FFALSE
                pc_offset = pc
            end

            if cl !== nothing && pc_offset != -1
                (pc_offset < 0 || pc_offset >= COV_KEY_CLAUSE) && return FFALSE   # no such key (file-wide 1)
                v = lookupHTable(cov.table, _cov_key(gd.clause_serials[cl], pc_offset))
                v == NULL_VALUE && return FFALSE
                obj = cov.objs[Int(v)]
                return if (
                    unify_cov(gd, ld, A1, obj) && PL_unify_int64(ld, A2, obj.enter) &&
                    PL_unify_int64(ld, A3, obj.exits)
                )
                    FTRUE
                else
                    FFALSE
                end
            end

            idx = alloc_foreign_state!(pool)
            st = pool.states[idx]
            st.serial = cl === nothing ? 0 : gd.clause_serials[cl]
            st.type = COV_PC
        elseif PL_is_functor(ld, A1, mk_sym(T, :clause), 1)
            if ground_cells(ld, -(A1 + 1)) == 0         # PL_is_ground(A1)
                a = PL_new_term_ref(ld)
                if _PL_get_arg(ld, 1, A1, a)
                    rc2, cl2 = PL_get_clref(gd, ld, a)
                    rc2 == 0 && return FFALSE
                    v = lookupHTable(
                        cov.table,
                        _cov_key(gd.clause_serials[cl2::Clause{T}], COV_KEY_CLAUSE)
                    )
                    v == NULL_VALUE && return FFALSE
                    obj = cov.objs[Int(v)]
                    return if (
                        PL_unify_int64(ld, A2, obj.enter) &&
                        PL_unify_int64(ld, A3, obj.exits)
                    )
                        FTRUE
                    else
                        FFALSE
                    end
                else
                    return FFALSE
                end
            else
                idx = alloc_foreign_state!(pool)
                st = pool.states[idx]
                st.type = COV_CLAUSE
                st.serial = 0
            end
        else
            return FFALSE                               # (file-wide 4)
        end
        st.e = newTableEnum(cov.table)                  # newTableEnumPP(cov_table)
        st.objs = cov.objs
    elseif ctl == FRG_REDO
        idx = PL_foreign_context_address(PL__ctx)       # state = CTX_PTR
        st = pool.states[idx]
    else                                                # FRG_CUTTED
        idx = PL_foreign_context_address(PL__ctx)
        free_state(pool.states[idx])
        free_foreign_state!(pool, idx)
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    if fid == 0
        free_state(st)
        free_foreign_state!(pool, idx)
        return FFALSE
    end
    while st.e !== nothing
        found, _, value = advanceTableEnum(st.e::TableEnum)
        found || break
        obj = st.objs[Int(value)]
        if is_candidate(st, obj) && unify_cov(gd, ld, A1, obj) &&
            PL_unify_int64(ld, A2, obj.enter) && PL_unify_int64(ld, A3, obj.exits)
            PL_close_foreign_frame(ld, fid)
            return PL_retry_address(idx)                # ForeignRedoPtr(save_state(state))
        elseif ld.exception_term != 0                   # PL_exception(0)
            break
        else
            PL_rewind_foreign_frame(ld, fid)
        end
    end
    PL_close_foreign_frame(ld, fid)
    free_state(st)
    free_foreign_state!(pool, idx)
    return FFALSE
end

# PORT: pl-coverage.c free_coverage_data
# DIVERGES: file-wide 2 (`COMPARE_AND_SWAP_PTR` is a store).
"Stop the collection and give the thread's coverage data back (pl-coverage.c); true."
function free_coverage_data(ld::PL_local_data{T})::Bool where {T}
    if !ld.debugstatus_debugging
        setPrologRunMode!(ld, RUN_MODE_NORMAL)
    end
    ld.coverage.active = 0
    updateAlerted(ld)

    cov = ld.coverage.data
    if cov !== nothing
        ld.coverage.data = nothing
        unshare_coverage_data(cov)
    end
    return true
end

# PORT: pl-coverage.c cov_reset as pl_cov_reset0_va
# (PRED_IMPL("$cov_reset", 0, cov_reset, 0))
# DIVERGES: `PL_unify_thread_id(ex, PL_thread_self())` is the one thread's id `main` (src/pl-thread.jl `pl_thread_self`).
"`'\$cov_reset'`: reclaim the collected coverage data; a permission error while the collection is active (pl-coverage.c)."
function pl_cov_reset0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    if ld.coverage.active != 0
        ex = PL_new_term_ref(ld)
        return if (
            PL_unify_atom(ld, ex, mk_sym(T, :main)) &&
            PL_error(
                ld,
                "",
                0,
                "",
                ERR_PERMISSION,
                mk_sym(T, :clean_coverage_data),
                mk_sym(T, :thread),
                ex
            )
        )
            FTRUE
        else
            FFALSE
        end
    end
    return free_coverage_data(ld) ? FTRUE : FFALSE
end

# PORT: pl-coverage.c cov_start as pl_cov_start1_va
# (PRED_IMPL("$cov_start(-Nesting)", 1, cov_start, 0))
# Since COV1 the collection is ported: the VM's `Coverage` hooks (src/pl-wam.jl) count while `ld.coverage.active` is non-zero.
"""
    '\$cov_start'(-Nesting)

Start collecting coverage information; if it is already collected, count the nesting up (pl-coverage.c).
"""
function pl_cov_start1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    if ld.coverage.data === nothing                             # if ( !LD->coverage.data )
        PL_unify_integer(ld, PL__t0, 1) || return FFALSE
        ld.coverage.data = newCoverageData(T)
    else
        PL_unify_integer(ld, PL__t0, ld.coverage.active + 1) || return FFALSE
    end

    clearPrologRunMode!(ld, RUN_MODE_NORMAL)                    # clearPrologRunMode(RUN_MODE_NORMAL)
    ld.coverage.active += 1
    updateAlerted(ld)

    return FTRUE
end

# PORT: pl-coverage.c cov_stop as pl_cov_stop1_va
# (PRED_IMPL("$cov_stop", 1, cov_stop, 0))
"`'\$cov_stop'(+Nesting)`: leave one nesting level of the collection; fails when it is not active (pl-coverage.c)."
function pl_cov_stop1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    ld.coverage.active == 0 && return FFALSE
    active = PL_get_integer_ex(ld, A1)
    active === nothing && return FFALSE
    active -= 1

    if ld.coverage.active != active
        ld.coverage.active = active

        if active == 0
            if !ld.debugstatus_debugging
                setPrologRunMode!(ld, RUN_MODE_NORMAL)
            end
            updateAlerted(ld)
        end
    end

    return FTRUE
end

# PORT: pl-coverage.c cov_active as pl_cov_active1_va
# (PRED_IMPL("$cov_active", 1, cov_active, 0))
"`'\$cov_active'(-Nesting)`: the nesting of the active collection; fails when it is not active (pl-coverage.c)."
function pl_cov_active1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    ld.coverage.active == 0 && return FFALSE
    return PL_unify_integer(ld, PL__t0, ld.coverage.active) ? FTRUE : FFALSE
end

# PORT: pl-coverage.c BeginPredDefs as PL_predicates_from_coverage
"pl-coverage.c's registration table (`BeginPredDefs(coverage)`)."
const PL_predicates_from_coverage = (
    PL_extension("\$cov_data", 3, pl_cov_data3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("\$cov_add", 3, pl_cov_add3_va, PL_FA_VARARGS),
    PL_extension("\$cov_reset", 0, pl_cov_reset0_va, PL_FA_VARARGS),
    PL_extension("\$cov_start", 1, pl_cov_start1_va, PL_FA_VARARGS),
    PL_extension("\$cov_stop", 1, pl_cov_stop1_va, PL_FA_VARARGS),
    PL_extension("\$cov_active", 1, pl_cov_active1_va, PL_FA_VARARGS)
)
