# ORIGINAL: D1's mutant list — no swipl-devel counterpart.
# tools/mutants/D1.py — the mutation battery of D1 (R2: clause references as blobs, pl-dbref.c; assert/2, asserta/2, assertz/2 and
# the Ref of '$record_clause'/4 in pl-comp.c; erase/1's clause branch in pl-rec.c; D-0227 item 6, design evidence/r2/design/flags_rest.md
# §4 D11), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`,
# `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. One mutant per decision of the step: the blob type
# and its registration (D1-1…D1-4, D1-60, D1-61), the payload, the clause table and the mark (D1-5…D1-15), the readers (D1-16…D1-25),
# assert/2 (D1-26…D1-33, D1-40), '$record_clause'/4 (D1-34…D1-39, D1-42), erase/1 (D1-50…D1-56).
# NOT RUN YET (written edit-only, 2026-10-29): the verdict column below is what the rows are DESIGNED to kill; the first hand-run
# (tools/mutate.sh, one tree each) replaces this header with the true result. EQUIVALENT, each with its reason:
#   * the name atom of the registration (D1-4): `PL_register_blob_type` looks `type.name` up when the name atom is 0
#     (pl-atom.jl:2312), and "clause" is the built-in ATOM_clause either way;
#   * `record_clause`'s assertion that the clause is not erased (D1-37): the clause was added by the call before it;
#   * erase/1's assertion that the reference names a clause (D1-56): `PL_get_dbref` answers `DB_REF_CLAUSE` only (the record
#     branch is D2's);
#   * erase/1 ignoring `retractClauseDefinition!`'s result (D1-54): that result is false only for an already erased clause, which
#     `PL_get_dbref` has turned away before.
TARGETS = ["test/db/test_clause_ref_swipl.jl"]
T = TARGETS
B = "src/pl-dbref.jl"
K = "src/pl-comp.jl"
R = "src/pl-rec.jl"
G = "src/pl-global.jl"
I = "src/pl-incl.jl"
MUTANTS = [
    # ---- the blob type and its registration
    dict(id="D1-1 the clause blob type is not unique", file=B, targets=T,
         old='''const clause_blob = PL_blob_t(PL_BLOB_UNIQUE, "clause")''',
         new='''const clause_blob = PL_blob_t(UInt32(0), "clause")'''),
    dict(id="D1-2 the clause blob type has another name", file=B, targets=T,
         old='''const clause_blob = PL_blob_t(PL_BLOB_UNIQUE, "clause")''',
         new='''const clause_blob = PL_blob_t(PL_BLOB_UNIQUE, "clauses")'''),
    dict(id="D1-3 initDBRef! registers nothing", file=B, targets=T,
         old='''    PL_register_blob_type(atoms, clause_blob, builtin_atom("clause"))''',
         new='''    nothing'''),
    dict(id="D1-4 the registration is given no name atom", file=B, targets=T,
         old='''    PL_register_blob_type(atoms, clause_blob, builtin_atom("clause"))''',
         new='''    PL_register_blob_type(atoms, clause_blob, UInt64(0))''',
         equivalent="PL_register_blob_type looks type.name up when the name atom is 0 (src/pl-atom.jl:2312), and \"clause\" is the "
                    "built-in ATOM_clause either way"),
    dict(id="D1-60 the database does not call initDBRef!", file=G, targets=T,
         old='''    initDBRef!(atoms)                          # initDBRef (setup:146): the clause blob type (D1)
''',
         new=''''''),
    dict(id="D1-61 DBREF_CLAUSE is CL_ERASED", file=I, targets=T,
         old='''const DBREF_CLAUSE = UInt32(0x0020)''',
         new='''const DBREF_CLAUSE = UInt32(0x0001)'''),
    # ---- the payload, the clause table and the mark
    dict(id="D1-5 acquire_clause_blob does not mark the clause", file=B, targets=T,
         old='''    clause.flags |= DBREF_CLAUSE''',
         new='''    clause.flags |= UInt32(0)'''),
    dict(id="D1-6 release_clause_blob does not clear the mark", file=B, targets=T,
         old='''    clause.flags &= ~DBREF_CLAUSE
    return true''',
         new='''    clause.flags &= ~UInt32(0)
    return true'''),
    dict(id="D1-7 release_clause_blob answers false", file=B, targets=T,
         old='''    clause.flags &= ~DBREF_CLAUSE
    return true''',
         new='''    clause.flags &= ~DBREF_CLAUSE
    return false'''),
    dict(id="D1-8 lookup_clref never acquires", file=B, targets=T,
         old='''    new && acquire_clause_blob(gd, a)''',
         new='''    nothing'''),
    dict(id="D1-9 lookup_clref acquires an atom it only found", file=B, targets=T,
         old='''    new && acquire_clause_blob(gd, a)''',
         new='''    acquire_clause_blob(gd, a)'''),
    dict(id="D1-10 the payload is not the table's number", file=B, targets=T,
         old='''collect(reinterpret(UInt8, Int64[serial]))''',
         new='''collect(reinterpret(UInt8, Int64[serial + 1]))'''),
    dict(id="D1-11 a clause's number is not remembered", file=B, targets=T,
         old='''        gd.clause_serials[clause] = serial''',
         new='''        nothing'''),
    dict(id="D1-12 every reference gets a new number", file=B, targets=T,
         old='''    serial = get(gd.clause_serials, clause, 0)''',
         new='''    serial = 0'''),
    dict(id="D1-13 clause_clref does not check the blob type", file=B, targets=T,
         old='''    at.type === clause_blob || return nothing                   # type == &clause_blob''',
         new='''    nothing'''),
    dict(id="D1-14 clause_clref does not check that it is given a blob", file=B, targets=T,
         old='''    is_blob(aref) || return nothing''',
         new='''    nothing'''),
    dict(id="D1-15 a new clause is not entered in the table", file=B, targets=T,
         old='''        push!(gd.clause_refs, clause)''',
         new='''        nothing'''),
    # ---- the readers
    dict(id="D1-16 PL_unify_clref does not unify", file=B, targets=T,
         old='''    return PL_unify_atomic(ld, t, a)''',
         new='''    return true'''),
    dict(id="D1-17 PL_put_clref does not put", file=B, targets=T,
         old='''    PL_put_atom(ld, t, a)                                       # _PL_put_atomic(t, a)''',
         new='''    nothing'''),
    dict(id="D1-18 PL_is_dbref is true for every atom", file=B, targets=T,
         old='''    return clause_clref(gd, a) !== nothing                      # type == &clause_blob || type == &record_blob''',
         new='''    return true'''),
    dict(id="D1-19 PL_get_dbref names another type in its error", file=B, targets=T,
         old='''        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return nothing''',
         new='''        PL_error(ld, ERR_TYPE, mk_sym(T, :reference), t)
        return nothing'''),
    dict(id="D1-20 PL_get_dbref answers an erased clause", file=B, targets=T,
         old='''    if (clause.flags & CL_ERASED) == 0
        return (DB_REF_CLAUSE, clause)
    end''',
         new='''    if true
        return (DB_REF_CLAUSE, clause)
    end'''),
    dict(id="D1-21 PL_get_dbref says the reference is a record's", file=B, targets=T,
         old='''        return (DB_REF_CLAUSE, clause)''',
         new='''        return (DB_REF_RECORD, clause)'''),
    dict(id="D1-22 PL_get_clref does not tell an erased clause", file=B, targets=T,
         old='''    (clause.flags & CL_ERASED) != 0 && return (-1, clause)''',
         new='''    (clause.flags & CL_ERASED) != 0 && return (1, clause)'''),
    dict(id="D1-23 PL_get_clref answers 2 for a live clause", file=B, targets=T,
         old='''    return (1, clause)''',
         new='''    return (2, clause)'''),
    dict(id="D1-24 PL_get_clref answers true after its error", file=B, targets=T,
         old='''        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return (0, nothing)''',
         new='''        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return (1, nothing)'''),
    dict(id="D1-25 PL_get_clref raises no error", file=B, targets=T,
         old='''        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return (0, nothing)''',
         new='''        return (0, nothing)'''),
    # ---- assert/2, asserta/2, assertz/2
    dict(id="D1-26 assert/2 takes a bound second argument", file=K, targets=T,
         old='''    if !PL_is_variable(ld, t)
        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 2, t)''',
         new='''    if false
        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 2, t)'''),
    dict(id="D1-27 the uninstantiation error names the first argument", file=K, targets=T,
         old='''        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 2, t)''',
         new='''        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 1, t)'''),
    dict(id="D1-28 assertz/2 adds at the start", file=K, targets=T,
         old='''    clause = assert_term!(gd, ld, A1, CL_END)''',
         new='''    clause = assert_term!(gd, ld, A1, CL_START)'''),
    dict(id="D1-29 asserta/2 adds at the end", file=K, targets=T,
         old='''    clause = assert_term!(gd, ld, A1, CL_START)''',
         new='''    clause = assert_term!(gd, ld, A1, CL_END)'''),
    dict(id="D1-30 assertz/2 does not unify the reference", file=K, targets=T,
         old='''    clause = assert_term!(gd, ld, A1, CL_END)
    clause === nothing && return FFALSE
    return PL_unify_clref(gd, ld, A2, clause) ? FTRUE : FFALSE''',
         new='''    clause = assert_term!(gd, ld, A1, CL_END)
    clause === nothing && return FFALSE
    return FTRUE'''),
    dict(id="D1-31 asserta/2 does not unify the reference", file=K, targets=T,
         old='''    clause = assert_term!(gd, ld, A1, CL_START)
    clause === nothing && return FFALSE
    return PL_unify_clref(gd, ld, A2, clause) ? FTRUE : FFALSE''',
         new='''    clause = assert_term!(gd, ld, A1, CL_START)
    clause === nothing && return FFALSE
    return FTRUE'''),
    dict(id="D1-32 assertz/2 does not check its second argument", file=K, targets=T,
         old='''    mustBeVar(ld, A2) || return FFALSE
    gd = _query_gd(ld)
    clause = assert_term!(gd, ld, A1, CL_END)''',
         new='''    gd = _query_gd(ld)
    clause = assert_term!(gd, ld, A1, CL_END)'''),
    dict(id="D1-33 asserta/2 does not check its second argument", file=K, targets=T,
         old='''    mustBeVar(ld, A2) || return FFALSE
    gd = _query_gd(ld)
    clause = assert_term!(gd, ld, A1, CL_START)''',
         new='''    gd = _query_gd(ld)
    clause = assert_term!(gd, ld, A1, CL_START)'''),
    dict(id="D1-40 assert/2 is not registered", file=K, targets=T,
         old='''    PL_extension("assert", 2, pl_assertz2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
''',
         new=''''''),
    # ---- '$record_clause'/4
    dict(id="D1-34 '$record_clause'/4 makes no reference", file=K, targets=T,
         old='''        if ref != 0
            @assert (clause.flags & CL_ERASED) == 0''',
         new='''        if false
            @assert (clause.flags & CL_ERASED) == 0'''),
    dict(id="D1-35 '$record_clause'/4 does not unify the reference", file=K, targets=T,
         old='''            return PL_unify_clref(gd, ld, ref, clause)''',
         new='''            return true'''),
    dict(id="D1-36 '$record_clause'/4 is the /3", file=K, targets=T,
         old='''    return record_clause(ld, A1, A2, A3, A4) ? FTRUE : FFALSE''',
         new='''    return record_clause(ld, A1, A2, A3, 0) ? FTRUE : FFALSE'''),
    dict(id="D1-37 '$record_clause'/4 does not check that the clause is live", file=K, targets=T,
         old='''            @assert (clause.flags & CL_ERASED) == 0''',
         new='''            nothing''',
         equivalent="the clause was added by assert_term! in the line before, so it cannot be erased (pl-comp.c:5166 asserts the "
                    "same)"),
    dict(id="D1-38 '$record_clause'/4 is not registered", file=K, targets=T,
         old=r'''    PL_extension("\$record_clause", 4, pl_record_clause4_va, PL_FA_VARARGS),
''',
         new=r''''''),
    dict(id="D1-39 '$record_clause'/4 gives the reference a source of its own", file=K, targets=T,
         old='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3''',
         new='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 1, PL__t0 + 3'''),
    dict(id="D1-42 compiler_warnings/2 gets no clause reference", file=K, targets=T,
         old='''            PL_put_clref(gd, ld, cl, clause)''',
         new='''            nothing'''),
    # ---- erase/1
    dict(id="D1-50 erase/1 of an erased clause is not turned away", file=R, targets=T,
         old='''    r === nothing && return FFALSE
    type, clause = r''',
         new='''    type, clause = r'''),
    dict(id="D1-51 erase/1 retracts a static clause", file=R, targets=T,
         old='''    if (def.flags & P_DYNAMIC) == 0''',
         new='''    if false'''),
    dict(id="D1-52 the permission error has its arguments swapped", file=R, targets=T,
         old='''ERR_PERMISSION, mk_sym(T, :clause), mk_sym(T, :erase), ref)''',
         new='''ERR_PERMISSION, mk_sym(T, :erase), mk_sym(T, :clause), ref)'''),
    dict(id="D1-53 the permission error has the caller as context", file=R, targets=T,
         old='''PL_error(ld, "erase", 1, "", ERR_PERMISSION,''',
         new='''PL_error(ld, "", 0, "", ERR_PERMISSION,'''),
    dict(id="D1-54 erase/1 ignores the result of the retract", file=R, targets=T,
         old='''    return retractClauseDefinition!(gd, def, clause, true) ? FTRUE : FFALSE''',
         new='''    retractClauseDefinition!(gd, def, clause, true)
    return FTRUE''',
         equivalent="retractClauseDefinition! answers false only for a clause that is already erased (src/pl-proc.jl retract_clause!), "
                    "which PL_get_dbref has turned away (src/pl-dbref.jl)"),
    dict(id="D1-55 erase/1 does not retract", file=R, targets=T,
         old='''    return retractClauseDefinition!(gd, def, clause, true) ? FTRUE : FFALSE''',
         new='''    return FTRUE'''),
    dict(id="D1-56 erase/1 does not check that the reference names a clause", file=R, targets=T,
         old='''    @assert type == DB_REF_CLAUSE                               # else: the record branch (D2)''',
         new='''    nothing''',
         equivalent="PL_get_dbref answers DB_REF_CLAUSE only until D2 adds the record branch (src/pl-dbref.jl)"),
    dict(id="D1-57 erase/1 is not registered", file=R, targets=T,
         old='''const PL_predicates_from_rec = (PL_extension("erase", 1, pl_erase1_va, PL_FA_VARARGS),)''',
         new='''const PL_predicates_from_rec = ()'''),
]
