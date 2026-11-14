# UPSTREAM: swipl-devel src/pl-dbref.c @ 18168e629eab
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
# NOT PORTED: `save_clause_ref`/`load_clause_ref` (the QLF hooks: LB3), `GD->clauses.db_erased_refs` (a counter
# nothing reads) and the type's hooks as slots (`PL_blob_t` has none: `acquire_clause_blob` is called by
# `lookup_clref` for a new atom, `release_clause_blob` has no caller without atom GC).
#
# Synced to cf6960c2 (notes only; the kernel has one thread, so every change below is a layout, locking or
# thread-local-atom change that alters no answer here). The payload of both blobs is the `Clause` or
# `RecordRef` ITSELF (the types are `PL_BLOB_UNIQUE|PL_BLOB_NOCOPY|PL_BLOB_LOCAL`: the atom table hashes the
# pointer, a lookup needs no key copy; `clause_ref` and `recref` are gone): the number in `gd.clause_refs`
# and `gd.record_refs` stays this port's payload, one atom per clause or record as before. `PL_BLOB_LOCAL` (a
# reference starts as a local atom of the creating thread and is promoted when it escapes, "Thread-local
# blobs" of pl-atom.c) is the multi-thread atom table's: unwritten here, every atom is shared. Unwritten
# new functions, each with the reason: `compare_dbref` (the new `compare` hook of both types, an order by
# the address of the clause or record: the kernel has no addresses, its order is that of the blob's
# creation, the known difference above, so the earlier sentence that the type has no `compare` hook holds
# for this port only); `lookup_shared_clref` (`lookup_clref` followed by `promoteAtomIfLocal`: the same
# function here, as no atom is local); `foreignLocalClause` and `foreign_local_clause_error` (a clause of
# another thread's thread-local predicate gives `permission_error(access, thread_local_clause, Ref)`; with
# one thread `P_LOCALISED` never names a foreign definition, so the test is always false). The target's
# `write_clause_ref` and `write_record_ref` print the pointer itself instead of through `clause_ref`, as the
# written form `<clause>(0x...)` here is the term interface's; the `save_clause_ref` warning likewise. The C
# `int` results of `PL_put_clref`, `PL_unify_recref`, `PL_is_dbref` and `PL_get_recref` became `bool`: this
# port returns `Bool` already.

# PORT: pl-dbref.h db_ref_type as DB_REF_CLAUSE
# DIVERGES: Int constants (the repo's precedent, `when_status`: an `@enum` would need a `_enum_hash`
# entry in the static-analysis manifest for two values).
"`PL_get_dbref`'s answer: the reference names a clause (pl-dbref.h `DB_REF_CLAUSE`)."
const DB_REF_CLAUSE = 0
"`PL_get_dbref`'s answer: the reference names a record (pl-dbref.h `DB_REF_RECORD`)."
const DB_REF_RECORD = 1

# PORT: pl-dbref.c clause_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the
# file header. `compare` is NULL upstream as here. Synced to cf6960c2: the target's flags are
# `PL_BLOB_UNIQUE|PL_BLOB_NOCOPY|PL_BLOB_LOCAL` and its `compare` is `compare_dbref` (the order of the
# addresses); the kernel's order is that of the blob's creation, see the file header: no answer differs
# that a program may rely on, as an address order is not stable.
"The blob type of a clause reference (pl-dbref.c `clause_blob`): unique by payload, non-text, named `clause`."
const clause_blob = PL_blob_t(PL_BLOB_UNIQUE, "clause")

# ORIGINAL: the payload of a clause blob (upstream: the 24 bytes of a `clause_ref` with `value.clause` set).
"The 8 bytes of a clause blob: the clause's number in `gd.clause_refs`, little-endian."
_clref_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# PORT: pl-dbref.c record_blob
# DIVERGES: no `release`, `write` or `acquire` slots (`PL_blob_t` has none): `acquire_record` is called by
# `PL_unify_recref` for a new atom, `release_record` has no caller without atom GC. `compare` is NULL
# upstream as here. Synced to cf6960c2: as `clause_blob`, flags `PL_BLOB_UNIQUE|PL_BLOB_NOCOPY|PL_BLOB_LOCAL`,
# `compare` is `compare_dbref`; the same note (file header).
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
# reference of a removed record keeps `record === nothing`, src/pl-rec.jl `freeRecordRef`). Synced to
# cf6960c2: the target takes `L_RECORD` with `PL_TRYLOCK` (`freeRecordRef` tests `R_DBREF` under it, and the
# caller may hold `L_REHASH_ATOMS`) and returns false, to be called again, when the lock is busy; one thread
# always gets the lock, so this body is the target's with the lock granted.
"A record blob is released: its record has no database reference any more (pl-dbref.c)."
function release_record(ref::RecordRef{T})::Bool where {T}
    if ref.record !== nothing                                   # if ( ref->record->record )
        ref.flags &= ~R_DBREF                                   #   clear(ref->record->record, R_DBREF)
    end                                                         # else unallocRecordRef(ref->record)
    return true
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
# DIVERGES: the clause blob is the argument (`PL_blob_data(aref, NULL, NULL)->value.clause`); called by
# `lookup_clref` for an atom it has just created, where upstream's `lookupBlob` calls the hook.
"A clause blob was created: mark its clause as having a database reference (pl-dbref.c)."
function acquire_clause_blob(gd::PL_global_data{T}, aref::T)::Nothing where {T}
    clause = clause_clref(gd, aref)::Clause{T}
    clause.flags |= DBREF_CLAUSE
    return nothing
end

# PORT: pl-dbref.c release_clause_blob
# DIVERGES: no caller (no atom GC); `GD->clauses.db_erased_refs` and `unallocClause` are not ported
# (see the file header); the white-box tests call it. Synced to cf6960c2: the target clears `DBREF_CLAUSE` and
# reads the old flags in one atomic step (`COMPARE_AND_SWAP_UINT`: `freeClause` tests the first flag and sets
# `DBREF_ERASED_CLAUSE` on another thread), then acts on the OLD flags (`CL_ERASED`: the erased-reference
# counter, `DBREF_ERASED_CLAUSE`: `unallocClause`); the same result for one thread, the effects of the two
# tests stay unwritten as above.
"A clause blob is released: its clause has no database reference any more (pl-dbref.c)."
function release_clause_blob(gd::PL_global_data{T}, aref::T)::Bool where {T}
    clause = clause_clref(gd, aref)::Clause{T}
    clause.flags &= ~DBREF_CLAUSE
    return true
end

# PORT: pl-dbref.c lookup_clref
# DIVERGES: the database and its tables are the arguments; the clause gets its number on its first
# reference (the payload, see the file header); returns the blob TERM of type `T` (`_blob_term!`), where
# upstream returns the `atom_t`. Synced to cf6960c2: the target's key is the `Clause` pointer itself
# (`lookupBlob(clause, sizeof(*clause), &clause_blob)`, a `PL_BLOB_NOCOPY` blob) and `GET_LD` replaces the
# local `clause_ref`; `lookup_shared_clref` is its variant for a reference other threads may reach (file header).
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

# PORT: pl-dbref.c clause_clref
# DIVERGES: returns the CLAUSE (`ref->value.clause`) or `nothing`, where upstream returns the `ClauseRef`
# holding it or NULL. Note that the clause may be erased. Synced to cf6960c2: the target names it
# `clause_dbref` and returns the `Clause` itself (the `ClauseRef` layer is gone), as this function does; the
# clause may also belong to another thread (`foreignLocalClause`, file header: always false here).
"The clause the blob `aref` names, or `nothing` when `aref` is no clause blob (pl-dbref.c)."
function clause_clref(gd::PL_global_data{T}, aref::T)::Union{Nothing, Clause{T}} where {T}
    is_blob(aref) || return nothing
    at = atomValue(gd.atoms, blob_handle(aref))
    at.type === clause_blob || return nothing                   # type == &clause_blob
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.clause_refs[Int(serial)]
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
# DIVERGES: as `PL_unify_clref`. Synced to cf6960c2: the C result is `bool` (was `int`).
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
# `lookupBlob`, the type's `acquire` hook). Synced to cf6960c2: the target's key is the `RecordRef` itself
# (`PL_unify_blob(t, r, sizeof(*r), &record_blob)`, no `recref` wrapper) and the C result is `bool`.
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
# DIVERGES: Synced to cf6960c2: the C result is `bool` (was `int`); this port returns `Bool`.
"Whether the term reference `t` holds a database reference (pl-dbref.c)."
function PL_is_dbref(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t)::Bool where {T}
    a = PL_get_atom(ld, t)
    a === nothing && return false
    return clause_clref(gd, a) !== nothing ||                   # type == &clause_blob ||
           recref_record(gd, a) !== nothing                     # type == &record_blob
end

# PORT: pl-dbref.c PL_get_dbref
# DIVERGES: returns `(type, clause)` or `(type, record reference)` where upstream returns the `ClauseRef` or
# the `RecordRef` and writes `*type_ptr`; `nothing` is NULL, with the error raised when `t` is no database
# reference (`type_error(db_reference, T)`) and WITHOUT one when the clause or the record is erased (erase/1
# of an erased reference fails). Synced to cf6960c2: for a clause that is not erased the target first asks
# `foreignLocalClause` and, for a clause of another thread's thread-local predicate, raises
# `permission_error(access, thread_local_clause, Ref)` and returns NULL; with one thread the test is false
# and the answer is as before. The record arm returns the `RecordRef` itself (no `recref` wrapper).
"The database reference in `t`: `(DB_REF_CLAUSE, clause)` or `(DB_REF_RECORD, ref)`; `nothing` for an erased one or after the error (pl-dbref.c)."
function PL_get_dbref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{Int, Clause{T}}, Tuple{Int, RecordRef{T}}} where {T}
    a = PL_get_atom(ld, t)
    clause = a === nothing ? nothing : clause_clref(gd, a)
    if clause !== nothing                                       # type == &clause_blob
        if (clause.flags & CL_ERASED) == 0
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
# an existing clause, -1: an erased clause) and `clause` its `*cl`, `nothing` after the error. Synced to
# cf6960c2: after the erased test (-1 first, so an erased foreign clause answers -1) the target returns the
# `foreignLocalClause` permission error for a clause of another thread's thread-local predicate; with one
# thread never reached (file header).
"The clause reference in `t`: `(1, clause)`, `(-1, clause)` when it is erased, `(0, nothing)` after the error (pl-dbref.c)."
function PL_get_clref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Tuple{Int, Union{Nothing, Clause{T}}} where {T}
    a = PL_get_atom(ld, t)
    clause = a === nothing ? nothing : clause_clref(gd, a)
    if clause === nothing
        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return (0, nothing)
    end
    (clause.flags & CL_ERASED) != 0 && return (-1, clause)
    return (1, clause)
end

# PORT: pl-dbref.c PL_get_recref
# DIVERGES: returns the reference or `nothing`, where upstream writes `*rec` and returns a Bool; `nothing`
# after the error (`t` is no record reference) and, WITHOUT one, for an erased record. Synced to cf6960c2: the
# C result is `bool` (was `int`) and `recref` is gone, the payload is the `RecordRef` (file header).
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
