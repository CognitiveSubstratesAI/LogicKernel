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
# file (`setAttrProcedureSource`). A FIRST load only: NOT PORTED — reconsult (`startReconsultFile`,
# the reload context and its clause matching, `endReconsult`'s work: a second consult of a file is
# refused, `NotPortedError`), unloading (`unloadFile`, `destroySourceFile`), module files, the
# locks. Since R2 LB2 the `$source_file…`/`$start_consult`/`$end_consult` predicates are here (below).

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
            false, boot, boot, boot, module_t{T}[]
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
# DIVERGES: no reload (`sf->reload` is always NULL); `COMPARE_AND_SWAP` is a plain test (no threads).
"Associate `proc` with the source file `sf` (pl-srcfile.c); a procedure may have several."
function addProcedureSourceFile(sf::SourceFile{T}, proc::Procedure{T})::Nothing where {T}
    if !(sf.index == proc.source_no)
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

# PORT: pl-srcfile.c assertProcedureSource
# DIVERGES: no reload context — the path of a first load: the file counts the clause, which goes at
# the end of the predicate; `nothing` is upstream's NULL (since SSU1: `assertProcedure!` refused a
# clause that mixes SSU and normal clauses, its error raised in `ld`, which is an argument for it).
"Add `clause` to `proc` on behalf of the source file `sf` (pl-srcfile.c); `nothing` when refused."
function assertProcedureSource(
    gd::PL_global_data{T}, ld::PL_local_data{T}, sf::Union{Nothing, SourceFile{T}},
    proc::Procedure{T}, clause::Clause{T}
)::Union{Nothing, ClauseRef{T}} where {T}
    sf === nothing || (sf.number_of_clauses += UInt32(1))
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

# PORT: pl-srcfile.c setAttrProcedureSource
# DIVERGES: no reload context; `ld` is an argument (see `associateSource`).
"Set (or clear) attribute `attr` of `proc` while loading the source file `sf` (pl-srcfile.c)."
function setAttrProcedureSource(
    ld::PL_local_data{T}, sf::SourceFile{T}, proc::Procedure{T}, attr::UInt64, val::Bool
)::Bool where {T}
    val && (attr & PROC_DEFINED) != 0 && associateSource(ld, sf, proc)
    return setAttrDefinition(ld, proc.definition, attr, val)
end

# PORT: pl-srcfile.c startConsult
# DIVERGES: a RE-consult — the file was consulted before — is refused (`NotPortedError`):
# `startReconsultFile` and its reload context are not ported (LB6, loader_boot H9).
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

# Is the atom `a` the atom named `s`?
_atom_is(a::T, s::Symbol) where {T} = sym_key(a) == sym_key(mk_sym(T, s))

# PORT: pl-srcfile.c unify_src_file_time
"Unify `t` with the modification time of `f`, or 0 if it is no real file (pl-srcfile.c)."
function unify_src_file_time(ld::PL_local_data{T}, t::term_t, f::SourceFile{T})::Bool where {T}
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
                rc && (rc = unify_definition(gd, ld, MODULE_user(gd), head, proc.definition, 0, GP_QUALIFY))
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
        if !(f === nothing || f.count == 0)
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
    if _atom_is(property, :load_count)
        rc = PL_unify_integer(ld, A3, sf === nothing ? 0 : sf.count)
    elseif _atom_is(property, :reloading)
        rc = PL_unify_bool(ld, A3, false)               # sf ? sf->reload != NULL : 0
    elseif _atom_is(property, :number_of_clauses)
        rc = PL_unify_integer(ld, A3, sf === nothing ? 0 : Int(sf.number_of_clauses))
    elseif _atom_is(property, :resource)
        rc = PL_unify_bool(ld, A3, sf === nothing ? false : sf.resource)
    elseif _atom_is(property, :from_state)
        rc = PL_unify_bool(ld, A3, sf === nothing ? false : sf.from_state)
    elseif _atom_is(property, :loaded)
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
        if _atom_is(property, :resource)
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
    PL_extension("\$source_file_predicates", 2, pl_source_file_predicates2_va, PL_FA_VARARGS),
    PL_extension(
        "\$time_source_file", 3, pl_time_source_file3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("\$source_file_property", 3, pl_source_file_property3_va, PL_FA_VARARGS),
    PL_extension("\$set_source_file", 3, pl_set_source_file3_va, PL_FA_VARARGS),
    PL_extension("\$start_consult", 2, pl_start_consult2_va, PL_FA_VARARGS),
    PL_extension("\$end_consult", 1, pl_end_consult1_va, PL_FA_VARARGS),
    PL_extension("\$fixup_reconsult", 1, pl_fixup_reconsult1_va, PL_FA_VARARGS)
)
