# UPSTREAM: swipl-devel src/pl-dbref.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-dbref.h @ cbf4e1896275
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
# NOT PORTED: the record blob (`record_blob`, `PL_unify_recref`, `PL_get_recref`: the recorded database,
# D2; upstream registers it BEFORE the clause blob, `initDBRef`, so D2 puts its registration first),
# `save_clause_ref`/`load_clause_ref` (the QLF hooks: LB3), `GD->clauses.db_erased_refs` (a counter
# nothing reads) and the type's hooks as slots (`PL_blob_t` has none: `acquire_clause_blob` is called by
# `lookup_clref` for a new atom, `release_clause_blob` has no caller without atom GC).

# PORT: pl-dbref.h db_ref_type as DB_REF_CLAUSE
# DIVERGES: Int constants (the repo's precedent, `when_status`: an `@enum` would need a `_enum_hash`
# entry in the static-analysis manifest for two values).
"`PL_get_dbref`'s answer: the reference names a clause (pl-dbref.h `DB_REF_CLAUSE`)."
const DB_REF_CLAUSE = 0
"`PL_get_dbref`'s answer: the reference names a record (pl-dbref.h `DB_REF_RECORD`; D2: no record blobs yet)."
const DB_REF_RECORD = 1

# PORT: pl-dbref.c clause_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the
# file header. `compare` is NULL upstream as here.
"The blob type of a clause reference (pl-dbref.c `clause_blob`): unique by payload, non-text, named `clause`."
const clause_blob = PL_blob_t(PL_BLOB_UNIQUE, "clause")

# ORIGINAL: the payload of a clause blob (upstream: the 24 bytes of a `clause_ref` with `value.clause` set).
"The 8 bytes of a clause blob: the clause's number in `gd.clause_refs`, little-endian."
_clref_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# PORT: pl-dbref.c initDBRef
# DIVERGES: the clause blob only (the record blob is D2's, registered before it); the database's atom
# table is the argument; the type's name atom is the built-in `ATOM_clause`, no new atom. Called by the
# database's constructor where pl-setup.c:146 calls it, so the type exists before the first reference
# is made and its rank in the standard order is upstream's (stream < clause < record < mutex, measured
# on swipl 10.1.19: the later a type is registered, the lower its rank, `blob_registration`): a lazily
# registered type would rank by first use.
"Register the database blob types of pl-dbref.c in `atoms` (pl-dbref.c)."
function initDBRef!(atoms::atoms_t)::Nothing
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
# (see the file header); the white-box tests call it.
"A clause blob is released: its clause has no database reference any more (pl-dbref.c)."
function release_clause_blob(gd::PL_global_data{T}, aref::T)::Bool where {T}
    clause = clause_clref(gd, aref)::Clause{T}
    clause.flags &= ~DBREF_CLAUSE
    return true
end

# PORT: pl-dbref.c lookup_clref
# DIVERGES: the database and its tables are the arguments; the clause gets its number on its first
# reference (the payload, see the file header); returns the blob TERM of type `T` (`_blob_term!`), where
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

# PORT: pl-dbref.c clause_clref
# DIVERGES: returns the CLAUSE (`ref->value.clause`) or `nothing`, where upstream returns the `ClauseRef`
# holding it or NULL. Note that the clause may be erased.
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
# DIVERGES: as `PL_unify_clref`.
"Make the term reference `t` hold the reference to `clause` (pl-dbref.c)."
function PL_put_clref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, clause::Clause{T}
)::Bool where {T}
    a = lookup_clref(gd, clause)
    PL_put_atom(ld, t, a)                                       # _PL_put_atomic(t, a)
    return true
end

# PORT: pl-dbref.c PL_is_dbref
# DIVERGES: clause references only (the record blob is D2's).
"Whether the term reference `t` holds a database reference (pl-dbref.c)."
function PL_is_dbref(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t)::Bool where {T}
    a = PL_get_atom(ld, t)
    a === nothing && return false
    return clause_clref(gd, a) !== nothing                      # type == &clause_blob || type == &record_blob
end

# PORT: pl-dbref.c PL_get_dbref
# DIVERGES: returns `(type, clause)` where upstream returns the `ClauseRef` and writes `*type_ptr`;
# `nothing` is NULL, with the error raised when `t` is no database reference (`type_error(db_reference, T)`)
# and WITHOUT one when the clause is erased (erase/1 of an erased clause fails). The record branch is D2's.
"The database reference in `t`: `(DB_REF_CLAUSE, clause)`; `nothing` for an erased clause or after the error (pl-dbref.c)."
function PL_get_dbref(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{Int, Clause{T}}} where {T}
    a = PL_get_atom(ld, t)
    clause = a === nothing ? nothing : clause_clref(gd, a)
    if clause === nothing                                       # no blob, or one of another type: goto error
        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return nothing
    end
    if (clause.flags & CL_ERASED) == 0
        return (DB_REF_CLAUSE, clause)
    end
    return nothing
end

# PORT: pl-dbref.c PL_get_clref
# DIVERGES: returns `(rc, clause)`: `rc` is upstream's return value (0 false: the error is raised, 1 true:
# an existing clause, -1: an erased clause) and `clause` its `*cl`, `nothing` after the error.
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
