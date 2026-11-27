# UPSTREAM: swipl-devel src/pl-dbref.c @ af9e2e7ed0be
# UPSTREAM: swipl-devel src/pl-dbref.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2010-2019, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: All rights reserved.
# allow-new-artifact: a port of upstream src/pl-dbref.c (read at the pin cbf4e189 with git show), at its mirrored path
#
# DATABASE REFERENCES (pl-dbref.c), since R2's D1 (D-0227 item 6; design evidence/r2/design/flags_rest.md
# §4 D11): a CLAUSE REFERENCE is an atom of the non-text blob type `clause` (`clause_blob`:
# `PL_BLOB_UNIQUE`), made by `lookup_clref`/`PL_unify_clref`/`PL_put_clref` and read back by
# `clause_clref`, `PL_get_dbref` and `PL_get_clref`. `assert/2`, `asserta/2`, `assertz/2`, the `Ref` of
# `'$record_clause'/4` and `erase/1` (src/pl-rec.jl) are its first users; `clause/3`, `nth_clause/3`,
# `instance/2` and the rest of pl-comp.c's `PL_unify_clref` callers come with their own steps.
#
# DIVERGES, representation only. Upstream's payload is a `clause_ref` holding the `Clause` POINTER
# (`lookup_clref`: `ref.value.clause = clause`); a Julia object has no stable address, so the
# payload is the clause's NUMBER in the database's table of referenced clauses (`gd.clause_refs`, its
# inverse `gd.clause_serials`): 8 bytes, one atom per clause (`PL_BLOB_UNIQUE`), the number given the
# first time a reference to the clause is made. The table keeps the clause alive for as long as its
# atom lives, which is for ever (no atom garbage collection, as the stream blobs of S1): upstream's
# `DBREF_ERASED_CLAUSE` (a clause erased while referenced is freed by the blob's release) has no
# counterpart, Julia's GC frees what nothing names. Two clause references compare in the standard
# order by creation of the BLOB (BLOB's known difference, D-0200: upstream's order is the address).
# The written form `<clause>(0x…)` is the term interface's (`write_clause_ref`'s `%p` of the clause is
# the blob's handle there); `clause_blob` has no `compare` hook, so the backport 2db0c03ac (a blob
# compare callback's result normalised in `compareAtoms`) does not touch it.
#
# Since R2's D2, a RECORD REFERENCE is an atom of the blob type `record` (`record_blob`: `PL_BLOB_UNIQUE`),
# made by `PL_unify_recref` and read back by `PL_get_dbref` and `PL_get_recref`, for `recorda/3`, `recordz/3`,
# `recorded/3`, `instance/2` and `erase/1` (src/pl-rec.jl). Its payload is the reference's number in
# `gd.record_refs` (`RecordRef.serial`), as the clause blob's; upstream's is the `RecordRef` pointer.
#
# SYNC3: the payload of a reference stays the serial number and the types stay `PL_BLOB_UNIQUE` (the precedent of
# src/pl-undo.jl): `PL_BLOB_NOCOPY` hashes a pointer and `PL_BLOB_LOCAL` (thread-local atoms, promoted by
# `promoteAtomIfLocal`) needs pl-atom.c's thread-local-blob work, HELD behind G1; there is one thread, so the flags are a
# representation matter. The standard order of two references stays by creation of the blob (the known difference above),
# `compare_dbref` has no slot. What IS ported: `release_clause_blob`'s flag handling, `clause_dbref` (renamed from
# `clause_clref`) and the `foreignLocalClause` tests of `PL_get_dbref` and `PL_get_clref` (a DIVERGES stub: no
# thread-local predicate has local atoms here).
#
# NOT PORTED: `save_clause_ref`/`load_clause_ref` (the QLF hooks: LB3), `GD->clauses.db_erased_refs` (a counter
# nothing reads) and the type's hooks as slots (`PL_blob_t` has none: `acquire_clause_blob` is called by
# `lookup_clref` for a new atom, `release_clause_blob` has no caller without atom GC).

# PORT: pl-dbref.h db_ref_type as DB_REF_CLAUSE
# DIVERGES: Int constants (the repo's precedent, `when_status`: an `@enum` would need a `_enum_hash`
# entry in the static-analysis manifest for two values).
"`PL_get_dbref`'s answer: the reference names a clause (pl-dbref.h `DB_REF_CLAUSE`)."
const DB_REF_CLAUSE = 0
"`PL_get_dbref`'s answer: the reference names a record (pl-dbref.h `DB_REF_RECORD`)."
const DB_REF_RECORD = 1

# PORT: pl-dbref.c clause_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the
# file header. SYNC3: upstream's flags are `PL_BLOB_UNIQUE|PL_BLOB_NOCOPY|PL_BLOB_LOCAL` and its `compare` slot is
# `compare_dbref` (`PL_blob_data` of both atoms, pointer order); here `PL_BLOB_UNIQUE` only, no `compare` slot (file header).
"The blob type of a clause reference (pl-dbref.c `clause_blob`): unique by payload, non-text, named `clause`."
const clause_blob = PL_blob_t(PL_BLOB_UNIQUE, "clause")

# ORIGINAL: the payload of a clause blob (upstream: the 24 bytes of a `clause_ref` with `value.clause` set).
"The 8 bytes of a clause blob: the clause's number in `gd.clause_refs`, little-endian."
_clref_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# PORT: pl-dbref.c record_blob
# DIVERGES: no `release`, `write` or `acquire` slots (`PL_blob_t` has none): `acquire_record` is called by
# `PL_unify_recref` for a new atom, `release_record` has no caller without atom GC. `compare` is NULL
# upstream as here. SYNC3: upstream's flags are `PL_BLOB_UNIQUE|PL_BLOB_NOCOPY|PL_BLOB_LOCAL` and its `compare` slot
# `compare_dbref`; here `PL_BLOB_UNIQUE` only (see `clause_blob` and the file header).
"The blob type of a record reference (pl-dbref.c `record_blob`): unique by payload, non-text, named `record`."
const record_blob = PL_blob_t(PL_BLOB_UNIQUE, "record")

# ORIGINAL: the payload of a record blob (upstream: the 8 bytes of a `recref`, the `RecordRef` pointer).
"The 8 bytes of a record blob: the reference's number in `gd.record_refs`, little-endian."
_recref_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# ORIGINAL: upstream's `((recref*)PL_blob_data(aref, NULL, NULL))->record` with the type test of its
# callers (`type == &record_blob`), as `clause_clref` for the clause blob.
"The record reference the blob `aref` names, or `nothing` when `aref` is no record blob."
function recref_record(
    gd::PL_global_data{T}, aref::T
)::Union{Nothing, RecordRef{T}} where {T}
    is_blob(aref) || return nothing
    at = atomValue(gd.atoms, blob_handle(aref))
    at.type === record_blob || return nothing                   # type == &record_blob
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.record_refs[Int(serial)]
end

# PORT: pl-dbref.c acquire_record
# DIVERGES: the reference is the argument (`PL_blob_data(aref, NULL, NULL)->record`); called by
# `PL_unify_recref` for an atom it has just created, where upstream's `lookupBlob` calls the hook.
"A record blob was created: mark its record as having a database reference (pl-dbref.c)."
function acquire_record(ref::RecordRef{T})::Nothing where {T}
    ref.flags |= R_DBREF                                        # set(ref->record->record, R_DBREF)
    return nothing
end

# PORT: pl-dbref.c release_record
# DIVERGES: no caller (no atom GC); the reference is the argument; `unallocRecordRef` is Julia's GC (the
# reference of a removed record keeps `record === nothing`, src/pl-rec.jl `freeRecordRef`). No lock is taken.
"A record blob is released: its record has no database reference any more (pl-dbref.c)."
function release_record(ref::RecordRef{T})::Bool where {T}
    # if ( !PL_TRYLOCK(L_RECORD) ) return false                 # (one thread: never busy)
    if ref.record !== nothing                                   # if ( r->record )
        ref.flags &= ~R_DBREF                                   #   clear(r->record, R_DBREF)
    end                                                         # else unallocRecordRef(r)
    return true                                                 # PL_UNLOCK(L_RECORD)
end

# PORT: pl-dbref.c initDBRef
# DIVERGES: the database's atom table is the argument; the types' name atoms are the built-in
# `ATOM_record` and `ATOM_clause`, no new atom. Called by the database's constructor where pl-setup.c:146
# calls it, so the types exist before the first reference is made and their ranks in the standard order
# are upstream's (stream < clause < record < mutex, measured on swipl 10.1.19: the later a type is
# registered, the lower its rank, `blob_registration`; audit D-0230 item 2): `record_blob` FIRST, as
# upstream. A lazily registered type would rank by first use.
"Register the database blob types of pl-dbref.c in `atoms` (pl-dbref.c)."
function initDBRef!(atoms::atoms_t)::Nothing
    PL_register_blob_type(atoms, record_blob, builtin_atom("record"))
    PL_register_blob_type(atoms, clause_blob, builtin_atom("clause"))
    return nothing
end

# PORT: pl-dbref.c acquire_clause_blob
# DIVERGES: the clause blob is the argument (`Clause cl = PL_blob_data(aref, NULL, NULL)`); called by
# `lookup_clref` for an atom it has just created, where upstream's `lookupBlob` calls the hook.
"A clause blob was created: mark its clause as having a database reference (pl-dbref.c)."
function acquire_clause_blob(gd::PL_global_data{T}, aref::T)::Nothing where {T}
    clause = clause_dbref(gd, aref)::Clause{T}
    clause.flags |= DBREF_CLAUSE                                # set(cl, DBREF_CLAUSE)
    return nothing
end

# PORT: pl-dbref.c release_clause_blob
# DIVERGES: no caller (no atom GC); `GD->clauses.db_erased_refs` and `unallocClause` are not ported
# (see the file header); the white-box tests call it. The flags are read once and written once (one thread,
# `COMPARE_AND_SWAP_UINT` is a plain store, as in src/pl-atom.jl).
"A clause blob is released: its clause has no database reference any more (pl-dbref.c)."
function release_clause_blob(gd::PL_global_data{T}, aref::T)::Bool where {T}
    cl = clause_dbref(gd, aref)::Clause{T}
    flags = cl.flags                                            # do { flags = cl->flags;
    cl.flags = flags & ~DBREF_CLAUSE                            # } while ( !COMPARE_AND_SWAP_UINT(&cl->flags, flags, flags&~DBREF_CLAUSE) )
    # if ( (flags&CL_ERASED) ) ATOMIC_DEC(&GD->clauses.db_erased_refs)      (not ported)
    # if ( (flags&DBREF_ERASED_CLAUSE) ) unallocClause(cl)                  (not ported: Julia's GC)
    return true
end

# PORT: pl-dbref.c lookup_clref
# DIVERGES: the database and its tables are the arguments; the clause gets its number on its first
# reference (the payload, see the file header; upstream, SYNC3 0fa79d80: `lookupBlob((const char*)clause, sizeof(*clause),
# &clause_blob, &new)`, the clause itself as a NOCOPY payload, no `clause_ref`, plus `DEBUG(CHK_SECURE,
# assert(!onStackArea(local, clause)))`, no counterpart); returns the blob TERM of type `T` (`_blob_term!`), where
# upstream returns the `atom_t`.
"The clause blob of `clause`: one atom per clause, made if there is none (pl-dbref.c)."
function lookup_clref(gd::PL_global_data{T}, clause::Clause{T})::T where {T}
    serial = get(gd.clause_serials, clause, 0)
    if serial == 0
        push!(gd.clause_refs, clause)
        serial = length(gd.clause_refs)
        gd.clause_serials[clause] = serial
    end
    bytes = _clref_bytes(serial)
    w, new = lookupBlob(gd.atoms, bytes, length(bytes), clause_blob)
    a = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
    new && acquire_clause_blob(gd, a)
    return a
end

# PORT: pl-dbref.c clause_dbref
# DIVERGES: returns the clause or `nothing` (NULL), the clause being a table entry, not the blob's data. SYNC3 (0fa79d80):
# upstream renamed `clause_clref` (which returned the `ClauseRef` holding the clause) to `clause_dbref`, which returns the
# `Clause` itself. Note that the clause may be erased or belong to another thread (see `foreignLocalClause`).
"The clause the blob `aref` names, or `nothing` when `aref` is no clause blob (pl-dbref.c)."
function clause_dbref(gd::PL_global_data{T}, aref::T)::Union{Nothing, Clause{T}} where {T}
    is_blob(aref) || return nothing
    at = atomValue(gd.atoms, blob_handle(aref))
    at.type === clause_blob || return nothing                   # type == &clause_blob
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.clause_refs[Int(serial)]
end

# ORIGINAL: the name `clause_clref` kept for its callers in src/pl-cont.jl, pl-wam.jl and pl-tabling.jl (it also has a row in
# test/static_analysis_manifest.jl); to be renamed to `clause_dbref` there and removed.
"Alias of `clause_dbref` (pl-dbref.c's name before swipl-devel 0fa79d80)."
clause_clref(gd::PL_global_data{T}, aref::T) where {T} = clause_dbref(gd, aref)

# PORT: pl-dbref.c foreignLocalClause
# DIVERGES: upstream (3c127226, 9ad989e1) is true for a clause of a thread-local predicate (`P_LOCALISED`) of ANOTHER
# thread: `def->functor`'s current procedure's definition for `LD->thread.info->pl_tid` is not `cl->predicate`. Only the
# owner may access such a clause, which lets its atoms stay local atoms of the owner. The kernel has one thread, no
# `P_LOCALISED` flag (set by pl-proc.c's thread-local predicates, pl-proc.jl: P06/P07) and no local atoms, so a clause is
# never foreign: `isoff(def, P_LOCALISED)` is the only case that occurs and returns false.
"True if `cl` is a clause of a thread-local predicate of another thread (pl-dbref.c): never, one thread."
function foreignLocalClause(cl::Clause{T})::Bool where {T}
    return false                                                # likely(isoff(def, P_LOCALISED)) -> return false
end

# PORT: pl-dbref.c foreign_local_clause_error
"Raise `permission_error(access, thread_local_clause, ref)` (pl-dbref.c)."
function foreign_local_clause_error(ld::PL_local_data{T}, ref::term_t)::Bool where {T}
    return PL_error(
        ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :access),
        mk_sym(T, :thread_local_clause), ref
    )                                                           # ERR_PERMISSION, ATOM_access, ATOM_thread_local_clause, ref
end

# PORT: pl-dbref.c PL_unify_clref
# DIVERGES: the database and the local data are arguments; no `PL_unregister_atom` (no atom GC).
"Unify the term reference `t` with the reference to `clause` (pl-dbref.c)."
function PL_unify_clref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, clause::Clause{T}
)::Bool where {T}
    a = lookup_clref(gd, clause)
    return PL_unify_atomic(ld, t, a)
end

# PORT: pl-dbref.c PL_put_clref
# DIVERGES: as `PL_unify_clref`.
"Make the term reference `t` hold the reference to `clause` (pl-dbref.c)."
function PL_put_clref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, clause::Clause{T}
)::Bool where {T}
    a = lookup_clref(gd, clause)
    PL_put_atom(ld, t, a)                                       # _PL_put_atomic(t, a)
    return true
end

# PORT: pl-dbref.c PL_unify_recref
# DIVERGES: the database and the local data are arguments; the reference gets its number on its first blob
# (the payload, see the file header), and `acquire_record` is called for a new atom (upstream: by
# `lookupBlob`, the type's `acquire` hook).
"Unify the term reference `t` with the reference to the record `r` (pl-dbref.c)."
function PL_unify_recref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, r::RecordRef{T}
)::Bool where {T}
    if r.serial == 0                                            # ref.record = r
        push!(gd.record_refs, r)
        r.serial = length(gd.record_refs)
    end
    bytes = _recref_bytes(r.serial)
    w, new = lookupBlob(gd.atoms, bytes, length(bytes), record_blob)   # PL_unify_blob(t, &ref, sizeof(ref), &record_blob)
    a = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
    new && acquire_record(r)
    return PL_unify_atomic(ld, t, a)
end

# PORT: pl-dbref.c PL_is_dbref
"Whether the term reference `t` holds a database reference (pl-dbref.c)."
function PL_is_dbref(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t)::Bool where {T}
    a = PL_get_atom(ld, t)
    a === nothing && return false
    return clause_dbref(gd, a) !== nothing ||                   # type == &clause_blob ||
           recref_record(gd, a) !== nothing                     # type == &record_blob
end

# PORT: pl-dbref.c PL_get_dbref
# DIVERGES: returns `(type, clause)` or `(type, record reference)` where upstream returns the `ClauseRef` or
# the `RecordRef` and writes `*type_ptr`; `nothing` is NULL, with the error raised when `t` is no database
# reference (`type_error(db_reference, T)`) or the clause belongs to another thread (`foreignLocalClause`, never here;
# SYNC3 3c127226) and WITHOUT one when the clause or the record is erased (erase/1 of an erased reference fails).
"The database reference in `t`: `(DB_REF_CLAUSE, clause)` or `(DB_REF_RECORD, ref)`; `nothing` for an erased one or after the error (pl-dbref.c)."
function PL_get_dbref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{Int, Clause{T}}, Tuple{Int, RecordRef{T}}} where {T}
    a = PL_get_atom(ld, t)
    clause = a === nothing ? nothing : clause_dbref(gd, a)
    if clause !== nothing                                       # type == &clause_blob
        if (clause.flags & CL_ERASED) == 0                      # isoff(cl, CL_ERASED)
            if foreignLocalClause(clause)
                foreign_local_clause_error(ld, t)
                return nothing
            end
            return (DB_REF_CLAUSE, clause)
        end
        return nothing
    end
    ref = a === nothing ? nothing : recref_record(gd, a)
    if ref !== nothing                                          # type == &record_blob
        if ref.record !== nothing && (ref.flags & R_ERASED) == 0   # ref->record->record && isoff(…, R_ERASED)
            return (DB_REF_RECORD, ref)
        end
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)         # no blob, or one of another type: goto error
    return nothing
end

# PORT: pl-dbref.c PL_get_clref
# DIVERGES: returns `(rc, clause)`: `rc` is upstream's return value (0 false: the error is raised, 1 true:
# an existing clause, -1: an erased clause) and `clause` its `*cl`, `nothing` after the error (a clause of another thread's
# thread-local predicate raises `permission_error(access, thread_local_clause, T)`, never here: `foreignLocalClause`).
"The clause reference in `t`: `(1, clause)`, `(-1, clause)` when it is erased, `(0, nothing)` after the error (pl-dbref.c)."
function PL_get_clref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Tuple{Int, Union{Nothing, Clause{T}}} where {T}
    a = PL_get_atom(ld, t)
    clause = a === nothing ? nothing : clause_dbref(gd, a)
    if clause === nothing
        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return (0, nothing)
    end
    (clause.flags & CL_ERASED) != 0 && return (-1, clause)      # if ( ison(clause, CL_ERASED) ) return -1
    if foreignLocalClause(clause)                               # SYNC3 3c127226
        foreign_local_clause_error(ld, t)                       # return foreign_local_clause_error(t)
        return (0, nothing)
    end
    return (1, clause)
end

# PORT: pl-dbref.c PL_get_recref
# DIVERGES: returns the reference or `nothing`, where upstream writes `*rec` and returns a Bool; `nothing`
# after the error (`t` is no record reference) and, WITHOUT one, for an erased record.
"The record reference in `t`, or `nothing`: an erased record, or the error raised (pl-dbref.c)."
function PL_get_recref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, RecordRef{T}} where {T}
    a = PL_get_atom(ld, t)
    ref = a === nothing ? nothing : recref_record(gd, a)
    if ref === nothing                                          # !PL_get_blob(…) || type != &record_blob
        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return nothing
    end
    if ref.record !== nothing && (ref.flags & R_ERASED) == 0    # ref->record->record && isoff(…, R_ERASED)
        return ref
    end
    return nothing
end
