# UPSTREAM: swipl-devel src/pl-srcfile.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2014-2026, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SOURCE FILES (R1f): the administration consulting a file keeps — the source-file record of each
# loaded file (`lookupSourceFile`, numbered as upstream numbers them), the procedures a file defines
# (`addProcedureSourceFile`), adding a clause on behalf of a file (`assertProcedureSource`), the
# start and end of a consult (`startConsult`, `endConsult`) and a predicate attribute set from a
# file (`setAttrProcedureSource`). Since R2 LB6a the RELOAD half is here as code that nothing reaches yet:
# the reload context (`startReconsultFile`, `reloadContext`), the clause matching (`find_clause`,
# `keep_clause`, `equal_clause`, ...), the reload arms of `assertProcedureSource`, `setAttrProcedureSource`
# and `setMetapredicateSource`, and the fixes applied at the end (`fix_attributes`, `fix_metapredicate`,
# `fix_det`, `fix_ssu`, `check_ssu`). `startConsult` still refuses a second consult (`NotPortedError`): LB6b re-points it
# and ports `endReconsult` with `delete_old_predicates`, `unloadFile` and `destroySourceFile`; the module files and the
# locks are not here either. Since R2 LB2 the `$source_file…`/`$start_consult`/`$end_consult` predicates are here (below).

# PORT: pl-srcfile.c GEN_RELOAD
# (swipl-devel cbf4e189, src/pl-srcfile.c:892-896)
# DIVERGES: the value of upstream's non-threaded `#else` branch, `GEN_MAX-1`, a constant; the per-thread value of the threaded build is owned by TH1.
"The magic generation a file being reloaded marks the clauses it may replace with (pl-srcfile.c `GEN_RELOAD`)."
const GEN_RELOAD = GEN_MAX - gen_t(1)

# PORT: pl-srcfile.c registerSourceFile as registerSourceFile!
# DIVERGES: the files are a vector, and no hole is ever made in it (no source file is destroyed), so
# the first free index is the next one; `no_hole_before` is kept as upstream keeps it.
"Give `sf` the first free index of the database's file table and enter it there (pl-srcfile.c)."
function registerSourceFile!(gd::PL_global_data{T}, sf::SourceFile{T})::Nothing where {T}
    gd.files_no_hole_before == 0 && (gd.files_no_hole_before = 1)
    push!(gd.files_array, sf)
    sf.index = length(gd.files_array)
    gd.files_no_hole_before = sf.index + 1
    return nothing
end

# PORT: pl-srcfile.c indexToSourceFile
"The source file with index `index`, or `nothing` (pl-srcfile.c)."
function indexToSourceFile(
    gd::PL_global_data{T}, index::Integer
)::Union{Nothing, SourceFile{T}} where {T}
    (index > 0 && index <= length(gd.files_array)) || return nothing
    return gd.files_array[index]
end

# PORT: pl-srcfile.c lookupSourceFile_unlocked
# DIVERGES: the table is keyed by the name's `sym_key` and made with the database (src/pl-global.jl);
# no mutex. Since R2 LB2 the boot session is `gd.bootsession` (pl-srcfile.c:296-311).
"The source file named `name`, created if `create`; else `nothing` (pl-srcfile.c)."
function lookupSourceFile_unlocked(
    gd::PL_global_data{T}, name::T, create::Bool
)::Union{Nothing, SourceFile{T}} where {T}
    file = get(gd.files_table, sym_key(name), nothing)
    if file === nothing && create
        boot = gd.bootsession                       # GD->bootsession&1: system, from_state, resource
        file = SourceFile{T}(
            name, 0.0, 0.0, Procedure{T}[], nothing, SF_MAGIC, 0, UInt32(0), 0, UInt32(0),
            false, boot, boot, boot, module_t{T}[], nothing     # reload: NULL
        )
        registerSourceFile!(gd, file)
        gd.files_table[sym_key(name)] = file
    end
    return file
end

# PORT: pl-srcfile.c lookupSourceFile
# DIVERGES: no lock (no threads).
"The source file named `name` (created if `create`), acquired; or `nothing` (pl-srcfile.c)."
function lookupSourceFile(
    gd::PL_global_data{T}, name::T, create::Bool
)::Union{Nothing, SourceFile{T}} where {T}
    sf = lookupSourceFile_unlocked(gd, name, create)
    sf === nothing || acquireSourceFile(sf)
    return sf
end

# PORT: pl-srcfile.c acquireSourceFile
"Count a reference to `sf` (pl-srcfile.c)."
function acquireSourceFile(sf::SourceFile)::Nothing
    sf.references += UInt32(1)
    return nothing
end

# PORT: pl-srcfile.c acquireSourceFileNo
# (swipl-devel cbf4e189, src/pl-srcfile.c:353-359)
"Count a reference to the source file with index `index`, if there is one (pl-srcfile.c)."
function acquireSourceFileNo(gd::PL_global_data, index::Integer)::Nothing
    sf = indexToSourceFile(gd, index)
    sf === nothing || acquireSourceFile(sf)
    return nothing
end

# PORT: pl-srcfile.c releaseSourceFile
# DIVERGES (TEMPORARY, until LB6: destroySourceFile; audit D-0248): an unreferenced, empty file is NOT destroyed
# (`destroySourceFile` and `clearSourceAdmin` are not ported), so this only counts: an empty file consulted once
# keeps load_count 1 and is listed by `$time_source_file` (swipl: no record; pinned in test_source_file_swipl.jl); a release with no reference — upstream
# prints "Oops" and repairs the count — is raised as the internal error it is.
"Drop a reference to `sf` (pl-srcfile.c)."
function releaseSourceFile(sf::SourceFile)::Bool
    sf.references <= 0 && error("releaseSourceFile: no reference to release (Oops)")
    sf.references -= UInt32(1)
    return true
end

# PORT: pl-srcfile.c releaseSourceFileNo
# (swipl-devel cbf4e189, src/pl-srcfile.c:407-415)
"Drop a reference to the source file with index `index`, if there is one (pl-srcfile.c)."
function releaseSourceFileNo(gd::PL_global_data, index::Integer)::Bool
    sf = indexToSourceFile(gd, index)
    sf === nothing && return true
    return releaseSourceFile(sf)
end

# PORT: pl-srcfile.c hasProcedureSourceFile
"Is `proc` one of the procedures `sf` defines (pl-srcfile.c)?"
function hasProcedureSourceFile(sf::SourceFile{T}, proc::Procedure{T})::Bool where {T}
    if (proc.definition.flags & FILE_ASSIGNED) != 0
        for p in sf.procedures
            p === proc && return true
        end
    end
    return false
end

# PORT: pl-srcfile.c addProcedureSourceFile
# (swipl-devel cbf4e189, src/pl-srcfile.c:436-457)
# DIVERGES: `COMPARE_AND_SWAP` is a plain test (no threads); no lock.
"Associate `proc` with the source file `sf` (pl-srcfile.c); a procedure may have several."
function addProcedureSourceFile(sf::SourceFile{T}, proc::Procedure{T})::Nothing where {T}
    if !(sf.index == proc.source_no && sf.reload === nothing)
        if !hasProcedureSourceFile(sf, proc)
            push!(sf.procedures, proc)
            proc.definition.flags |= FILE_ASSIGNED
            if proc.source_no == 0
                proc.source_no = UInt32(sf.index)
                acquireSourceFile(sf)
            else
                proc.flags |= PROC_MULTISOURCE
            end
        end
    end
    return nothing
end

# ── reconsult: the clause-matching leaf functions (R2 LB6a; pl-srcfile.c:955-1062) ─────────────────
# PORT: pl-srcfile.c find_clause
# (swipl-devel cbf4e189, src/pl-srcfile.c:955-964)
# DIVERGES: `nothing` is upstream's NULL.
"The first clause reference from `cref` on whose clause is globally visible in `generation` (pl-srcfile.c)."
function find_clause(
    cref::Union{Nothing, ClauseRef{T}}, generation::gen_t
)::Union{Nothing, ClauseRef{T}} where {T}
    while cref !== nothing
        GLOBALLY_VISIBLE_CLAUSE(cref.clause::Clause{T}, generation) && break
        cref = cref.next
    end
    return cref
end

# PORT: pl-srcfile.c advance_clause
# (swipl-devel cbf4e189, src/pl-srcfile.c:966-981)
# DIVERGES: no `acquire_def`/`release_def` (threads only).
"Move the reload's current clause to the next globally visible clause of its generation (pl-srcfile.c)."
function advance_clause(r::p_reload{T})::Nothing where {T}
    cref = r.current_clause
    if cref !== nothing
        cref = find_clause(cref.next, r.generation)
        r.current_clause = cref
    end
    return nothing
end

# PORT: pl-srcfile.c copy_clause_source
# (swipl-devel cbf4e189, src/pl-srcfile.c:983-999)
# DIVERGES: the database is an argument (the source-file table).
"Give clause `dest` the source position and files of clause `src`, moving the file references (pl-srcfile.c)."
function copy_clause_source(
    gd::PL_global_data{T}, dest::Clause{T}, src::Clause{T}
)::Nothing where {T}
    dest.line_no = src.line_no
    if dest.source_no != src.source_no || dest.owner_no != src.owner_no
        acquireSourceFileNo(gd, src.owner_no)
        src.source_no != src.owner_no && acquireSourceFileNo(gd, src.source_no)
        releaseSourceFileNo(gd, dest.owner_no)
        dest.source_no != dest.owner_no && releaseSourceFileNo(gd, dest.source_no)
        dest.source_no = src.source_no
        dest.owner_no = src.owner_no
    end
    return nothing
end

# PORT: pl-srcfile.c keep_clause
# (swipl-devel cbf4e189, src/pl-srcfile.c:1001-1013)
"Keep the old clause `r.current_clause` for the equal new `clause`: it is live again, takes the new source position; the new one is freed (pl-srcfile.c)."
function keep_clause(
    gd::PL_global_data{T}, r::p_reload{T}, clause::Clause{T}
)::ClauseRef{T} where {T}
    cref = r.current_clause::ClauseRef{T}
    keep = cref.clause::Clause{T}
    keep.generation_erased = GEN_MAX
    copy_clause_source(gd, keep, clause)
    freeClause!(gd, clause)
    advance_clause(r)
    return cref
end

# PORT: pl-srcfile.c equal_clause
# (swipl-devel cbf4e189, src/pl-srcfile.c:1015-1026)
# DIVERGES (representation): upstream compares the code words with `memcmp`, and these words hold the atoms and functors
# (by handle), the numbers and strings (inline, by their bytes) and the procedures the clause refers to. A kernel clause's code words
# index its `literals` and `procedures` tables, so the clauses are equal when the code vectors are equal, the literal tables are equal
# element by element by IDENTITY (`atomic_compare`: atoms and functors by key, strings by content, integers by value, floats by their
# bits: `1` and `1.0` differ, `0.0` and `-0.0` differ, a NaN equals a NaN of the same bits), and the procedure tables hold the same
# procedures. Not the standard order. Equal codes with different literals: not equal.
"Do the clauses `cl1` and `cl2` hold the same code (pl-srcfile.c)?"
function equal_clause(cl1::Clause{T}, cl2::Clause{T})::Bool where {T}
    length(cl1.codes) == length(cl2.codes) || return false
    cl1.codes == cl2.codes || return false
    length(cl1.literals) == length(cl2.literals) || return false
    for i in eachindex(cl1.literals)
        atomic_compare(cl1.literals[i], cl2.literals[i]) == 0 || return false
    end
    length(cl1.procedures) == length(cl2.procedures) || return false
    for i in eachindex(cl1.procedures)
        cl1.procedures[i] === cl2.procedures[i] || return false
    end
    return true
end

# PORT: pl-srcfile.c reloadHasClauses
# (swipl-devel cbf4e189, src/pl-srcfile.c:1027-1038)
# DIVERGES: the reload's procedure table is an `IdDict` (see `sf_reload`).
"Has the reload of `sf` seen a clause of `proc` so far (pl-srcfile.c)?"
function reloadHasClauses(sf::SourceFile{T}, proc::Procedure{T})::Bool where {T}
    rl = sf.reload
    if rl !== nothing
        reload = get(rl.procedures, proc, nothing)
        reload === nothing || return reload.number_of_clauses > 0
    end
    return false
end

# PORT: pl-srcfile.c isRedefinedProcedure
# (swipl-devel cbf4e189, src/pl-srcfile.c:1044-1062)
# DIVERGES: no `acquire_def`/`release_def` (threads only).
"True if `proc` has at least one clause globally visible in generation `gen` (pl-srcfile.c)."
function isRedefinedProcedure(proc::Procedure{T}, gen::gen_t)::Bool where {T}
    c = proc.definition.impl_clauses.first_clause
    while c !== nothing
        GLOBALLY_VISIBLE_CLAUSE(c.clause::Clause{T}, gen) && return true
        c = c.next
    end
    return false
end

# PORT: pl-srcfile.c startReconsultFile
# (swipl-devel cbf4e189, src/pl-srcfile.c:900-953)
# DIVERGES: no `acquire_def`/`release_def`, no allocation failure (`PL_no_memory`); the database and the local data are arguments. Dead until LB6b
# re-points `startConsult` (R2 LB6a): the rows call it directly.
"Start reloading `sf`: its clauses are marked erased at the reload generation, a reload context is made (pl-srcfile.c)."
function startReconsultFile(
    gd::PL_global_data{T}, ld::PL_local_data{T}, sf::SourceFile{T}
)::Bool where {T}
    r = sf_reload{T}(
        IdDict{Procedure{T}, p_reload{T}}(), GEN_RELOAD, popNPredicateAccess!(ld, 0),
        IdDict{module_t{T}, m_reload{T}}(), UInt32(0)
    )
    sf.reload = r

    ld.reload_generation = r.reload_gen
    gd.reload_generation = r.reload_gen                 # DIVERGES (representation): the global field standing in for LD->reload.generation, owner TH1
    ld.reload_nesting += 1

    for proc in sf.procedures
        def = proc.definition

        if (def.flags & (P_FOREIGN | P_THREAD_LOCAL)) == 0
            c = def.impl_clauses.first_clause
            while c !== nothing
                cl = c.clause::Clause{T}
                if GLOBALLY_VISIBLE_CLAUSE(cl, global_generation(gd)) && (cl.flags & CL_ERASED) == 0 &&
                    !((def.flags & P_MULTIFILE) != 0 && cl.owner_no != sf.index) &&
                    !((def.flags & P_DYNAMIC) != 0 && cl.owner_no == 0)
                    cl.generation_erased = r.reload_gen
                end
                c = c.next
            end
            def.flags |= P_RELOADING
            def.flags &= ~P_DISCONTIGUOUS                   # will be reinstantiated
        end
        if (def.flags & P_AUTOLOAD) != 0
            def.flags &= ~P_AUTOLOAD                        # should be be more selective?
        end
    end

    return true
end

# PORT: pl-srcfile.c reloadContext
# (swipl-devel cbf4e189, src/pl-srcfile.c:1065-1104)
# DIVERGES: the table is an `IdDict` (see `sf_reload`); no `acquire_def`/`release_def`; `nothing` for the failure upstream reports as
# `PL_no_memory()` (never here); `pushPredicateAccessObj!` has no depth limit. The debug messages are not kept.
"The reload record of `proc` in the reload of `sf`, made on first use (pl-srcfile.c)."
function reloadContext(
    gd::PL_global_data{T}, ld::PL_local_data{T}, sf::SourceFile{T}, proc::Procedure{T}
)::p_reload{T} where {T}
    rl = sf.reload::sf_reload{T}
    reload = get(rl.procedures, proc, nothing)
    if reload === nothing
        def = proc.definition
        reload = p_reload{T}(def, gen_t(0), nothing, nothing, UInt64(0), UInt32(0))
        if (def.flags & (P_THREAD_LOCAL | P_FOREIGN)) != 0
            reload.flags |= P_NO_CLAUSES
        elseif isRedefinedProcedure(proc, global_generation(gd))
            dref = pushPredicateAccessObj!(ld, gd, def)
            reload.generation = dref.generation
            reload.current_clause = find_clause(def.impl_clauses.first_clause, reload.generation)
        else
            reload.flags |= P_NEW
        end
        rl.procedures[proc] = reload
    end
    return reload
end

# PORT: pl-srcfile.c fix_det
# (swipl-devel cbf4e189, src/pl-srcfile.c:1302-1310)
# DIVERGES: the database is an argument (`freeCodesDefinition!`).
"At the first clause of a reload: a predicate that was `det` and is not declared so again loses `P_DET` and its supervisor (pl-srcfile.c)."
function fix_det(gd::PL_global_data{T}, r::p_reload{T})::Nothing where {T}
    def = r.predicate
    if (def.flags & P_DET) != 0 && (r.flags & P_DET) == 0
        def.flags &= ~P_DET
        freeCodesDefinition!(gd, def, true)
    end
    return nothing
end

# PORT: pl-srcfile.c fix_ssu
# (swipl-devel cbf4e189, src/pl-srcfile.c:1313-1330)
"At the first clause of a reload: the SSU-ness of the predicate follows the new first clause, `P_CHECK_SSU` records a change (pl-srcfile.c)."
function fix_ssu(r::p_reload{T}, clause::Clause{T})::Nothing where {T}
    def = r.predicate
    if (def.flags & (P_DYNAMIC | P_MULTIFILE)) == 0
        if (clause.flags & (SSU_COMMIT_CLAUSE | SSU_CHOICE_CLAUSE)) != 0
            if (def.flags & P_SSU_DET) == 0
                def.flags |= P_SSU_DET
                r.flags |= P_CHECK_SSU
            end
        else
            if (def.flags & P_SSU_DET) != 0
                def.flags &= ~P_SSU_DET
                r.flags |= P_CHECK_SSU
            end
        end
    end
    return nothing
end

# PORT: pl-srcfile.c assertProcedureSource
# (swipl-devel cbf4e189, src/pl-srcfile.c:1108-1204)
# DIVERGES: `nothing` is upstream's NULL (since SSU1: `assertProcedure!` refused a clause that mixes SSU and normal clauses, its error
# raised in `ld`, which is an argument for it), and the database is an argument; the debug messages (`DEBUG(MSG_RECONSULT_CLAUSE, ...)`,
# and the loop upstream runs over the deleted clauses only to print them) are not kept; `assert(proc == sf->current_procedure)` is not
# kept (a debug-build assertion, and the white-box rows call this function without a loader); `reloadContext` cannot fail here (upstream's
# `PL_no_memory` branch, which frees the clause, is not reachable). No `acquire_def`/`release_def` around the walk (no threads).
"Add `clause` to `proc` on behalf of the source file `sf` (pl-srcfile.c); during a reload it is matched with the old clauses; `nothing` when refused."
function assertProcedureSource(
    gd::PL_global_data{T}, ld::PL_local_data{T}, sf::Union{Nothing, SourceFile{T}},
    proc::Procedure{T}, clause::Clause{T}
)::Union{Nothing, ClauseRef{T}} where {T}
    if sf !== nothing && sf.reload !== nothing
        rl = sf.reload::sf_reload{T}
        def = proc.definition

        rl.number_of_clauses += UInt32(1)

        reload = reloadContext(gd, ld, sf, proc)

        isfirst = reload.number_of_clauses == 0                   # reload->number_of_clauses++ == 0
        reload.number_of_clauses += UInt32(1)
        if isfirst
            fix_det(gd, reload)
            fix_ssu(reload, clause)
        end

        if (reload.flags & (P_NEW | P_NO_CLAUSES)) != 0
            return assertProcedure!(gd, ld, proc, clause, CL_END)
        end

        cref = reload.current_clause
        if cref !== nothing
            if equal_clause(cref.clause::Clause{T}, clause) && ((cref.clause::Clause{T}).flags & CL_ERASED) == 0
                return keep_clause(gd, reload, clause)
            end

            reload.flags |= P_MODIFIED

            cref2 = cref.next
            while cref2 !== nothing
                c2 = cref2.clause::Clause{T}
                if GLOBALLY_VISIBLE_CLAUSE(c2, reload.generation) && (c2.flags & CL_ERASED) == 0 &&
                    !((def.flags & P_MULTIFILE) != 0 && c2.owner_no != sf.index) &&
                    equal_clause(c2, clause)
                    # the clauses from `cref` up to `cref2` stay at GEN_RELOAD: `endReconsult` (LB6b) deletes them
                    reload.current_clause = cref2
                    return keep_clause(gd, reload, clause)
                end
                cref2 = cref2.next
            end

            cref3 = assertProcedure!(gd, ld, proc, clause, cref)       # inserted before the current clause
            cref3 === nothing || ((cref3.clause::Clause{T}).generation_created = rl.reload_gen)
            return cref3
        else
            cref3 = assertProcedure!(gd, ld, proc, clause, CL_END)
            cref3 === nothing || ((cref3.clause::Clause{T}).generation_created = rl.reload_gen)

            reload.flags |= P_MODIFIED

            return cref3
        end
    elseif sf !== nothing
        sf.number_of_clauses += UInt32(1)
    end

    return assertProcedure!(gd, ld, proc, clause, CL_END)
end

# PORT: pl-srcfile.c associateSource
# DIVERGES: `ld` is an argument (`SYSTEM_MODE` reads it); the `debuginfo` flag is upstream's default, on, so
# `HIDE_CHILDS` is cleared (the `set(def, HIDE_CHILDS)` branch needs the flag to be settable: F1b).
"Associate `proc` with `sf` if no file holds it yet (pl-srcfile.c); in system mode the predicate is locked."
function associateSource(
    ld::PL_local_data{T}, sf::SourceFile{T}, proc::Procedure{T}
)::Nothing where {T}
    def = proc.definition
    if (def.flags & FILE_ASSIGNED) == 0
        addProcedureSourceFile(sf, proc)
        if SYSTEM_MODE(ld)
            def.flags |= P_LOCKED | HIDE_CHILDS
        else
            def.flags &= ~HIDE_CHILDS               # truePrologFlag(PLFLAG_DEBUGINFO)
        end
    end
    return nothing
end

# PORT: pl-srcfile.c P_ATEND
# (swipl-devel cbf4e189, src/pl-srcfile.c:1230)
"The attributes `fix_attributes` copies from a reload to the definition at its end (`P_ATEND`, pl-srcfile.c)."
const P_ATEND = P_VOLATILE | P_PUBLIC | P_ISO | P_NOPROFILE | P_NON_TERMINAL

# PORT: pl-srcfile.c setAttrProcedureSource
# (swipl-devel cbf4e189, src/pl-srcfile.c:1232-1255)
# DIVERGES: the database and `ld` are arguments (see `associateSource`).
"Set (or clear) attribute `attr` of `proc` while loading the source file `sf` (pl-srcfile.c); during a reload it is recorded in the reload."
function setAttrProcedureSource(
    gd::PL_global_data{T}, ld::PL_local_data{T}, sf::SourceFile{T}, proc::Procedure{T},
    attr::UInt64, val::Bool
)::Bool where {T}
    val && (attr & PROC_DEFINED) != 0 && associateSource(ld, sf, proc)

    if sf.reload !== nothing
        reload = reloadContext(gd, ld, sf, proc)

        if val
            reload.flags |= attr
        else
            reload.flags &= ~attr
        end

        (attr & (P_ATEND | P_TRANSPARENT)) != 0 && return true
    end

    return setAttrDefinition(ld, proc.definition, attr, val)
end

# PORT: pl-srcfile.c check_ssu
# (swipl-devel cbf4e189, src/pl-srcfile.c:1256-1288)
# DIVERGES: the database and `ld` are arguments; upstream's `Sdprintf` to `Serror` is collected on the local data's `messages`
# (`_qlf_Sdprintf!`, as the boot loop's), and `predicateName` is `_autoload_predicate_name`. No `acquire_def`/`release_def`.
"After a reload: print an error when the live clauses of `r`'s predicate mix SSU (`=>`) and normal (`:-`) clauses (pl-srcfile.c)."
function check_ssu(gd::PL_global_data{T}, ld::PL_local_data{T}, r::p_reload{T})::Nothing where {T}
    def = r.predicate
    errors = 0

    cref = def.impl_clauses.first_clause
    while cref !== nothing && errors == 0
        cl = cref.clause::Clause{T}

        if (cl.flags & CL_ERASED) == 0
            if (def.flags & P_SSU_DET) != 0 && (cl.flags & (SSU_COMMIT_CLAUSE | SSU_CHOICE_CLAUSE)) == 0
                errors += 1
            end
            if (def.flags & P_SSU_DET) == 0 && (cl.flags & (SSU_COMMIT_CLAUSE | SSU_CHOICE_CLAUSE)) != 0
                errors += 1
            end
        end
        cref = cref.next
    end

    if errors != 0
        _qlf_Sdprintf!(ld, "ERROR: Mixed SSU (=> and :-) clauses in $(_autoload_predicate_name(gd, def))\n")
    end
    return nothing
end

# PORT: pl-srcfile.c fix_attributes
# (swipl-devel cbf4e189, src/pl-srcfile.c:1290-1299)
# DIVERGES: the database is an argument (`fix_metapredicate`); `sf` is unused, as upstream.
"At the end of a reload: copy the attributes the reload recorded (`P_ATEND`) to the definition, then its meta-predicate declaration (pl-srcfile.c)."
function fix_attributes(
    gd::PL_global_data{T}, sf::SourceFile{T}, def::Definition{T}, r::p_reload{T}
)::Nothing where {T}
    if (def.flags & P_MULTIFILE) == 0
        def.flags = (def.flags & ~P_ATEND) | (r.flags & P_ATEND)
    else
        def.flags |= (r.flags & P_ATEND)
    end

    fix_metapredicate(gd, r)
    return nothing
end

# PORT: pl-srcfile.c setMetapredicateSource
# (swipl-devel cbf4e189, src/pl-srcfile.c:1333-1361)
# DIVERGES: the database and `ld` are arguments (see `associateSource`); the reload's `args` is a fresh vector of `arg_info()` where upstream's
# `allocHeapOrHalt` memory is filled below, for every argument.
"Set the meta-argument masks `args` of `proc` while loading the source file `sf` (pl-srcfile.c); during a reload they are recorded in the reload."
function setMetapredicateSource(
    gd::PL_global_data{T}, ld::PL_local_data{T}, sf::SourceFile{T}, proc::Procedure{T},
    args::Vector{arg_info}
)::Bool where {T}
    associateSource(ld, sf, proc)

    if sf.reload !== nothing
        arity = proc.definition.arity

        reload = reloadContext(gd, ld, sf, proc)

        if reload.args === nothing
            reload.args = [arg_info() for _ in 1:arity]
        end
        rargs = reload.args::Vector{arg_info}
        for i in 1:arity
            rargs[i].meta = args[i].meta
        end

        if isTransparentMetamask(proc.definition, args)
            reload.flags |= P_TRANSPARENT
        else
            reload.flags &= ~P_TRANSPARENT
        end
        reload.flags |= P_META
    else
        setMetapredicateMask(proc.definition, args)
    end

    return true
end

# PORT: pl-srcfile.c equal_meta
# (swipl-devel cbf4e189, src/pl-srcfile.c:1363-1377)
# DIVERGES: `args` is `nothing` for NULL (a predicate of arity 0 has no `args` in either).
"Do the meta-argument masks of `def` equal `args` (pl-srcfile.c)? False when either is missing."
function equal_meta(
    def::Definition{T}, args::Union{Nothing, Vector{arg_info}}
)::Bool where {T}
    dargs = def.impl_clauses.args
    if dargs !== nothing && args !== nothing
        for i in 1:def.arity
            dargs[i].meta != args[i].meta && return false
        end
        return true
    end
    return false
end

# PORT: pl-srcfile.c fix_metapredicate
# (swipl-devel cbf4e189, src/pl-srcfile.c:1379-1404)
# DIVERGES: the database is an argument (`freeCodesDefinition!`).
"At the end of a reload: make the definition's meta-predicate declaration (and `P_TRANSPARENT`) the one the reload recorded (pl-srcfile.c)."
function fix_metapredicate(gd::PL_global_data{T}, r::p_reload{T})::Nothing where {T}
    def = r.predicate

    if (def.flags & P_MULTIFILE) == 0
        mfmask = P_META | P_TRANSPARENT

        if (def.flags & mfmask) != (r.flags & mfmask) || !equal_meta(def, r.args)
            if (def.flags & P_META) != 0 && (r.flags & P_META) == 0
                clear_meta_declaration(def)
            elseif (r.flags & P_META) != 0
                setMetapredicateMask(def, r.args::Vector{arg_info})
            end
            def.flags &= ~P_TRANSPARENT
            def.flags |= r.flags & P_TRANSPARENT

            freeCodesDefinition!(gd, def, true)
        end
    elseif (r.flags & P_META) != 0
        setMetapredicateMask(def, r.args::Vector{arg_info})
        freeCodesDefinition!(gd, def, true)
    elseif (r.flags & P_TRANSPARENT) != 0
        def.flags |= P_TRANSPARENT
    end
    return nothing
end

# PORT: pl-srcfile.c startConsult
# DIVERGES: a RE-consult — the file was consulted before — is refused (`NotPortedError`): `startReconsultFile` exists since LB6a, but
# `endReconsult` (delete_old_predicates, reconsultFinalizePredicate) comes with LB6b, which re-points this function (loader_boot H9).
"Start consulting the source file `sf` (pl-srcfile.c)."
function startConsult(sf::SourceFile{T})::Bool where {T}
    acquireSourceFile(sf)
    sf.ltime = time()                               # WallTime()
    if (sf.count += 1) > 1                          # This is a re-consult
        releaseSourceFile(sf)
        throw(NotPortedError{T}(sf.name, "consulting a file again (reconsult)", "LB6"))
    end
    sf.current_procedure = nothing
    return true
end

# PORT: pl-srcfile.c endConsult
# DIVERGES: `endReconsult` has nothing to do without a reload context.
"End consulting the source file `sf` (pl-srcfile.c)."
function endConsult(sf::SourceFile)::Bool
    sf.current_procedure = nothing
    rc = true                                       # endReconsult(sf): no reload
    releaseSourceFile(sf)
    return rc
end

# ── the source-file predicates (pl-srcfile.c, R2 LB2) ────────────────────────────────────────────

# PORT: pl-srcfile.c highSourceFileIndex
# DIVERGES: the table is a vector with no hole, so the highest index is one past its length.
"One past the highest source-file index in use (pl-srcfile.c)."
highSourceFileIndex(gd::PL_global_data)::Int = length(gd.files_array) + 1

# PORT: pl-srcfile.c addModuleSourceFile
# DIVERGES: `modules` is a vector (src/pl-incl.jl); no lock, no allocation failure.
"Add module `m` to the modules of `sf`, at the END, if it is not there yet (pl-srcfile.c:465)."
function addModuleSourceFile(sf::SourceFile{T}, m::module_t{T})::Bool where {T}
    for x in sf.modules
        x === m && return true
    end
    push!(sf.modules, m)
    return true
end

# PORT: pl-srcfile.c unlinkSourceFileModule
# DIVERGES: the test of upstream's loop, `lookupHTableWP(m->procedures, def->functor->functor) || PROCEDURE_dinit_goal->definition == def`,
# is its first half: the `$init_goal/3` clauses belong to the loader (L6), which adds the second; no lock.
"Remove from the procedures of `sf` those whose functor module `m` has a procedure of (pl-srcfile.c)."
function unlinkSourceFileModule(sf::SourceFile{T}, m::module_t{T})::Nothing where {T}
    filter!(sf.procedures) do proc
        def = proc.definition
        if haskey(m.procedures, (def.functor_name, def.arity))
            sf.current_procedure === proc && (sf.current_procedure = nothing)
            return false
        end
        return true
    end
    return nothing
end

# PORT: pl-srcfile.c exportProcedureSource
# DIVERGES: a source file has no `reload` (reconsult is not ported), so the recording of the exports of a module being
# reloaded - the part of upstream that tests `sf->reload` - does not run; what is left is `exportProcedure`.
"Export `proc` from module `m` while loading the source file `sf` (pl-srcfile.c)."
exportProcedureSource(sf::SourceFile{T}, m::module_t{T}, proc::Procedure{T}) where {T} =
    exportProcedure(m, proc)

# Is the atom `a` the atom named `s`?
_atom_is(ld::PL_local_data{T}, a, s::Symbol) where {T} = sym_key(a) == sym_key(mk_sym(T, s))   # (`a`'s own type may be a subtype of `T`: an AltSym)

# PORT: pl-srcfile.c unify_src_file_time
"Unify `t` with the modification time of `f`, or 0 if it is no real file (pl-srcfile.c)."
function unify_src_file_time(
    ld::PL_local_data{T}, t::term_t, f::SourceFile{T}
)::Bool where {T}
    f.isfile && return PL_unify_float(ld, t, f.mtime)
    return PL_unify_integer(ld, t, 0)
end

# PORT: pl-srcfile.c source_file as pl_source_file2_va
# (PRED_IMPL("$source_file", 2, source_file, PL_FA_TRANSPARENT); the TABLE says 0 — `PRED_DEF`'s flags
# win over `PRED_IMPL`'s, so the predicate is NOT transparent: an unqualified head is looked up in
# `system`, measured on the oracle.) pl-srcfile.c:586-605
# DIVERGES: `get_procedure(descr, &proc, 0, GP_FINDHERE)` is `get_procedure_findhere` (src/pl-proc.jl),
# given the context module, `system` (not transparent; `contextModule` is not ported).
"`'\$source_file'(:Head, -File)` (pl-srcfile.c): the file that defines the predicate of `Head`."
function pl_source_file2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    descr, file = PL__t0, PL__t0 + 1
    proc = get_procedure_findhere(gd, ld, descr, MODULE_system(gd))
    if proc !== nothing
        if isDefinedProcedure(gd, proc)
            sf = indexToSourceFile(gd, Int(proc.source_no))
            if sf !== nothing && sf.count > 0
                return PL_unify_atom(ld, file, sf.name) ? FTRUE : FFALSE
            end
        end
    end
    return FFALSE
end

# PORT: pl-srcfile.c source_file_predicates as pl_source_file_predicates2_va
# (PRED_IMPL("$source_file_predicates", 2, source_file_predicates, 0)) — pl-srcfile.c:608-641
# DIVERGES: upstream's `sf->procedures` is a list with the NEWEST procedure first
# (`addProcedureSourceFile` conses at the head); the kernel's is a vector with the newest LAST, so it
# is walked in reverse: the answer is in the same order. A head already bound by the caller's partial list goes
# through `unify_definition`'s bound-head branch (landed with D1), as upstream's.
"`'\$source_file_predicates'(+File, -Heads)` (pl-srcfile.c): the predicates `File` defines, `user`-qualified."
function pl_source_file_predicates2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    file, A2 = PL__t0, PL__t0 + 1
    rc = false
    name = PL_get_atom_ex(ld, file)
    name === nothing && return FFALSE
    sf = lookupSourceFile(gd, name, false)
    if sf !== nothing
        if sf.count > 0
            tail = PL_copy_term_ref(ld, A2)
            head = PL_new_term_ref(ld)
            rc = true
            for proc in Iterators.reverse(sf.procedures)
                rc || break
                rc = PL_unify_list(ld, tail, head, tail)
                rc && (
                    rc = unify_definition(
                        gd, ld, MODULE_user(gd), head, proc.definition, 0, GP_QUALIFY
                    )
                )
            end
            rc = rc && PL_unify_nil(ld, tail)
        end
        releaseSourceFile(sf)
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-srcfile.c time_source_file as pl_time_source_file3_va
# (PRED_IMPL("$time_source_file", 3, time_source_file, PL_FA_NONDETERMINISTIC)) — pl-srcfile.c:655-699;
# `ForeignRedoInt(index+1)` is `PL_retry(index + 1)` after closing the frame.
"`'\$time_source_file'(?File, ?Time, ?Type)` (pl-srcfile.c): the loaded files, their modification time and `user`/`system`."
function pl_time_source_file3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    mx = highSourceFileIndex(gd)
    file, time_, type = PL__t0, PL__t0 + 1, PL__t0 + 2
    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        index = 0
    elseif ctl == FRG_REDO
        index = PL_foreign_context(PL__ctx)
    else
        return FTRUE                                    # FRG_CUTTED
    end
    fid = PL_open_foreign_frame(ld)
    while index < mx
        f = indexToSourceFile(gd, index)
        if f !== nothing && f.count != 0                    # (not `!(f === nothing || …)`: JET cannot narrow that)
            if PL_unify_atom(ld, file, f.name) && unify_src_file_time(ld, time_, f) &&
                PL_unify_atom(ld, type, mk_sym(T, f.system ? :system : :user))
                PL_close_foreign_frame(ld, fid)
                return PL_retry(index + 1)
            end
            PL_rewind_foreign_frame(ld, fid)
        end
        index += 1
    end
    PL_close_foreign_frame(ld, fid)
    return FFALSE
end

# PORT: pl-srcfile.c source_file_property as pl_source_file_property3_va
# (PRED_IMPL("$source_file_property", 3, source_file_property, 0)) — pl-srcfile.c:702-733
# DIVERGES: `reloading` is false (no reload context). `loaded` of a file that is not known: upstream reads
# through a NULL `sf` (H10, loader_boot design); the port FAILS there, as the neighbouring properties
# answer their empty value.
"`'\$source_file_property'(+File, +Property, -Value)` (pl-srcfile.c)."
function pl_source_file_property3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    filename = PL_get_atom_ex(ld, A1)
    filename === nothing && return FFALSE
    property = PL_get_atom_ex(ld, A2)
    property === nothing && return FFALSE
    sf = lookupSourceFile(gd, filename, false)
    if _atom_is(ld, property, :load_count)
        rc = PL_unify_integer(ld, A3, sf === nothing ? 0 : sf.count)
    elseif _atom_is(ld, property, :reloading)
        rc = PL_unify_bool(ld, A3, false)               # sf ? sf->reload != NULL : 0
    elseif _atom_is(ld, property, :number_of_clauses)
        rc = PL_unify_integer(ld, A3, sf === nothing ? 0 : Int(sf.number_of_clauses))
    elseif _atom_is(ld, property, :resource)
        rc = PL_unify_bool(ld, A3, sf === nothing ? false : sf.resource)
    elseif _atom_is(ld, property, :from_state)
        rc = PL_unify_bool(ld, A3, sf === nothing ? false : sf.from_state)
    elseif _atom_is(ld, property, :loaded)
        rc = (sf === nothing || sf.ltime == 0.0) ? false : PL_unify_float(ld, A3, sf.ltime)
    else
        rc = PL_domain_error(ld, "source_file_property", A2)
    end
    sf === nothing || releaseSourceFile(sf)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-srcfile.c set_source_file as pl_set_source_file3_va
# (PRED_IMPL("$set_source_file", 3, set_source_file, 0)) — pl-srcfile.c:736-766
"`'\$set_source_file'(+File, +Property, +Value)` (pl-srcfile.c): only `resource` can be set."
function pl_set_source_file3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    filename = PL_get_atom_ex(ld, A1)
    filename === nothing && return FFALSE
    property = PL_get_atom_ex(ld, A2)
    property === nothing && return FFALSE
    sf = lookupSourceFile(gd, filename, false)
    if sf !== nothing
        if _atom_is(ld, property, :resource)
            v = PL_get_bool_ex(ld, A3)
            if v === nothing
                rc = false
            else
                sf.resource = v                         # (unsigned)v&0x1
                rc = true
            end
        else
            rc = PL_domain_error(ld, "source_file_property", A2)
        end
        releaseSourceFile(sf)
        return rc ? FTRUE : FFALSE
    end
    return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :source_file), A1) ? FTRUE : FFALSE
end

# PORT: pl-srcfile.c start_consult as pl_start_consult2_va
# (PRED_IMPL("$start_consult", 2, start_consult, 0)) — pl-srcfile.c:1726-1757
"`'\$start_consult'(+Id, +Modified)` (pl-srcfile.c): start consulting `Id`; `Modified` is 0 or the file's time."
function pl_start_consult2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    file, modified = PL__t0, PL__t0 + 1
    name = PL_get_atom_ex(ld, file)
    name === nothing && return FFALSE
    i = PL_get_integer(ld, modified)
    if i !== nothing && i == 0
        isfile = false
        mtime = 0.0
    else
        m = PL_get_float_ex(ld, modified)
        m === nothing && return FFALSE
        isfile = true
        mtime = m
    end
    sf = lookupSourceFile(gd, name, true)::SourceFile{T}
    sf.mtime = mtime
    sf.isfile = isfile
    startConsult(sf)
    releaseSourceFile(sf)
    return FTRUE
end

# PORT: pl-srcfile.c fixup_reconsult as pl_fixup_reconsult1_va
# (PRED_IMPL("$fixup_reconsult", 1, fixup_reconsult, 0)) — pl-srcfile.c:1772-1790
# DIVERGES: `endReconsult` has nothing to do without a reload context: true. `current_procedure` is cleared
# AFTER the release, as upstream writes it.
"`'\$fixup_reconsult'(+Id)` (pl-srcfile.c): finish the reload of `Id` (a no-op without reload)."
function pl_fixup_reconsult1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    rc = false
    name = PL_get_atom_ex(ld, PL__t0)
    if name !== nothing
        sf = lookupSourceFile(gd, name, false)
        if sf !== nothing
            rc = true                                   # endReconsult(sf)
            releaseSourceFile(sf)
            sf.current_procedure = nothing
        end
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-srcfile.c end_consult as pl_end_consult1_va
# (PRED_IMPL("$end_consult", 1, end_consult, 0)) — pl-srcfile.c:1792-1808; `endConsult` releases the
# reference `startConsult` took, this the one the lookup took.
"`'\$end_consult'(+Id)` (pl-srcfile.c): end consulting `Id`."
function pl_end_consult1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    rc = false
    name = PL_get_atom_ex(ld, PL__t0)
    if name !== nothing
        sf = lookupSourceFile(gd, name, false)
        if sf !== nothing
            rc = endConsult(sf)
            releaseSourceFile(sf)
        end
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-srcfile.c BeginPredDefs as PL_predicates_from_srcfile
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order (pl-srcfile.c:1987-1999);
# NOT HERE (LB6): `$clause_from_source`/4, `$unload_file`/1, `$set_source_files`/1, `$flush_predicate`/1,
# `$flushed_predicate`/1. `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-srcfile.c's registration table (`BeginPredDefs(srcfile)`): the ported entries."
const PL_predicates_from_srcfile = (
    PL_extension("\$source_file", 2, pl_source_file2_va, PL_FA_VARARGS),
    PL_extension(
        "\$source_file_predicates", 2, pl_source_file_predicates2_va, PL_FA_VARARGS
    ),
    PL_extension(
        "\$time_source_file", 3, pl_time_source_file3_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("\$source_file_property", 3, pl_source_file_property3_va, PL_FA_VARARGS),
    PL_extension("\$set_source_file", 3, pl_set_source_file3_va, PL_FA_VARARGS),
    PL_extension("\$start_consult", 2, pl_start_consult2_va, PL_FA_VARARGS),
    PL_extension("\$end_consult", 1, pl_end_consult1_va, PL_FA_VARARGS),
    PL_extension("\$fixup_reconsult", 1, pl_fixup_reconsult1_va, PL_FA_VARARGS)
)
