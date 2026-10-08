# UPSTREAM: swipl-devel src/pl-srcfile.c @ bae881a2
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
# `$source_file…`/`$start_consult`/`$end_consult` predicates (boot/init.pl's, R2), locks.

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
# no boot session (`system`, `from_state` and `resource` false), no mutex.
"The source file named `name`, created if `create`; else `nothing` (pl-srcfile.c)."
function lookupSourceFile_unlocked(
    gd::PL_global_data{T}, name::T, create::Bool
)::Union{Nothing, SourceFile{T}} where {T}
    file = get(gd.files_table, sym_key(name), nothing)
    if file === nothing && create
        file = SourceFile{T}(
            name, 0.0, 0.0, Procedure{T}[], nothing, SF_MAGIC, 0, UInt32(0), 0, UInt32(0),
            false, false, false, false
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
# DIVERGES: an unreferenced, empty file is NOT destroyed (no unloading: `destroySourceFile` and
# `clearSourceAdmin` are not ported), so this only counts; a release with no reference — upstream
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
# the end of the predicate.
"Add `clause` to `proc` on behalf of the source file `sf` (pl-srcfile.c)."
function assertProcedureSource(
    gd::PL_global_data{T}, sf::Union{Nothing, SourceFile{T}}, proc::Procedure{T},
    clause::Clause{T}
)::ClauseRef{T} where {T}
    sf === nothing || (sf.number_of_clauses += UInt32(1))
    return assertProcedure!(gd, proc, clause, CL_END)
end

# PORT: pl-srcfile.c associateSource
# DIVERGES: no system mode; the `debuginfo` flag is upstream's default, on, so `HIDE_CHILDS` is
# cleared.
"Associate `proc` with `sf` if no file holds it yet (pl-srcfile.c)."
function associateSource(sf::SourceFile{T}, proc::Procedure{T})::Nothing where {T}
    def = proc.definition
    if (def.flags & FILE_ASSIGNED) == 0
        addProcedureSourceFile(sf, proc)
        def.flags &= ~HIDE_CHILDS                   # truePrologFlag(PLFLAG_DEBUGINFO)
    end
    return nothing
end

# PORT: pl-srcfile.c setAttrProcedureSource
# DIVERGES: no reload context.
"Set (or clear) attribute `attr` of `proc` while loading the source file `sf` (pl-srcfile.c)."
function setAttrProcedureSource(
    sf::SourceFile{T}, proc::Procedure{T}, attr::UInt64, val::Bool
)::Bool where {T}
    val && (attr & PROC_DEFINED) != 0 && associateSource(sf, proc)
    return setAttrDefinition(proc.definition, attr, val)
end

# PORT: pl-srcfile.c startConsult
# DIVERGES: a RE-consult — the file was consulted before — is refused (`NotPortedError`):
# `startReconsultFile` and its reload context are not ported (R2).
"Start consulting the source file `sf` (pl-srcfile.c)."
function startConsult(sf::SourceFile{T})::Bool where {T}
    acquireSourceFile(sf)
    sf.ltime = time()                               # WallTime()
    if (sf.count += 1) > 1                          # This is a re-consult
        releaseSourceFile(sf)
        throw(NotPortedError{T}(sf.name, "consulting a file again (reconsult)", "R2"))
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
