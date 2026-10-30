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
# D-0230 item 1 adds D1-70…D1-98 (clause/3, '$clause'/4, '$rule'/3: unify_definition's bound branch, decompile_bindings!, clause_ndet's
# by-reference branch and the loop). Declared EQUIVALENT with their code reasons: D1-95 (protected_predicate in the by-reference
# branch) and D1-96 (the CLAUSE_TYPE_MASK test; row c37 decided). D1-90/D1-91 (the garbage third/fourth argument of clause/2) may
# survive in a quiet test: a survivor is then reported, not declared equivalent.
# D-0230 piece (d) adds D1-100...D1-119 (instance/2 and fixup_ssu, pl-rec.c; rows n01-n20). Declared EQUIVALENT with their code reasons:
# D1-117 (GOAL_CLAUSE: no goal clause has a reference), D1-118 (visibleClause: CL_ERASED is set with generation_erased) and D1-119 (the
# reference type: PL_get_dbref answers DB_REF_CLAUSE only until D2). Not run yet: a survivor among D1-105...D1-109 (the reference
# arithmetic) is reported, not declared equivalent.
# D-0238 item 4: every test file that exercises the mutated code, not only the step's own file. T: the files that make or erase a
# clause reference or read a blob (assert/retract/retractall rows, the blob ranks, the loader's message encoder); T8: + the
# clause/3 family's other readers (clause/2 rows, the module-path rows) for the pl-comp.jl clause/3 mutants (D1-70...).
T = ["test/db/test_clause_ref_swipl.jl", "test/db/test_assert_swipl.jl", "test/db/test_retract_swipl.jl",
     "test/db/test_retractall_swipl.jl", "test/core_lang/test_blob.jl", "test/files/test_load_swipl.jl"]
T8 = T + ["test/db/test_clause_swipl.jl", "test/core_lang/test_module_path.jl"]
TARGETS = T8
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
         old='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    return record_clause''',
         new='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 1, PL__t0 + 3
    return record_clause'''),
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
         old='''ERR_PERMISSION, mk_sym(T, :clause), mk_sym(T, :erase), ref''',
         new='''ERR_PERMISSION, mk_sym(T, :erase), mk_sym(T, :clause), ref'''),
    dict(id="D1-53 the permission error has the caller as context", file=R, targets=T,
         old='''ld, "erase", 1, "", ERR_PERMISSION,''',
         new='''ld, "", 0, "", ERR_PERMISSION,'''),
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
         old='''const PL_predicates_from_rec = (
    PL_extension("erase", 1, pl_erase1_va, PL_FA_VARARGS),
    PL_extension("instance", 2, pl_instance2_va, PL_FA_VARARGS)
)''',
         new='''const PL_predicates_from_rec = (
    PL_extension("instance", 2, pl_instance2_va, PL_FA_VARARGS),
)'''),
    # ---- clause/3, '$clause'/4, '$rule'/3 (D-0230 item 1; rows c01-c38; pl-comp.c unify_definition's bound branch, decompile_bindings!, clause_ndet)
    dict(id="D1-70 the bound head's module is not checked as a super module of the clause's", file=K, targets=T8,
         old='''(mm === nothing || !isSuperModule(gd.modules, m, mm)) && return false''',
         new='''(mm === nothing || !isSuperModule(gd.modules, mm, m)) && return false'''),
    dict(id="D1-71 a bound module qualifier that is no atom is not turned away", file=K, targets=T8,
         old='''                a === nothing && return false           # !PL_get_atom(h, &a)
''',
         new=''''''),
    dict(id="D1-72 the bound head's qualifier is not stripped", file=K, targets=T8,
         old='''            _PL_get_arg(ld, 2, head, h)
        end
        unify_functor(ld, h, def, how) || return false''',
         new='''        end
        unify_functor(ld, h, def, how) || return false'''),
    dict(id="D1-73 the bound branch does not hand back the plain head", file=K, targets=T8,
         old='''        thehead != 0 && PL_put_term(ld, thehead, h)
        return true
''',
         new='''        return true
'''),
    dict(id="D1-74 the bound branch ignores the functor unify", file=K, targets=T8,
         old='''        unify_functor(ld, h, def, how) || return false
        thehead''',
         new='''        unify_functor(ld, h, def, how)
        thehead'''),
    dict(id="D1-75 the bindings list numbers its variables from 1", file=K, targets=T8,
         old='''        PL_unify_integer(ld, a, n) || return false''',
         new='''        PL_unify_integer(ld, a, n + 1) || return false'''),
    dict(id="D1-76 every binding names the first variable", file=K, targets=T8,
         old='''        PL_unify(ld, a, variables + n) || return false''',
         new='''        PL_unify(ld, a, variables) || return false'''),
    dict(id="D1-77 the bindings list is not closed", file=K, targets=T8,
         old='''    return PL_unify_nil(ld, tail)
end

# PORT: pl-comp.c decompile
''',
         new='''    return true
end

# PORT: pl-comp.c decompile
'''),
    dict(id="D1-78 the bindings list misses the last variable", file=K, targets=T8,
         old='''    for n in 0:(Int(clause.prolog_vars) - 1)''',
         new='''    for n in 0:(Int(clause.prolog_vars) - 2)'''),
    dict(id="D1-79 decompile! never builds the bindings", file=K, targets=T8,
         old='''        bindings != 0 &&
            (decompile_bindings!''',
         new='''        false &&
            (decompile_bindings!'''),
    dict(id="D1-80 an erased clause is answered by clause/3", file=K, targets=T8,
         old='''                rc1 < 0 && PL__ac < 4 && return FFALSE      # erased clause
''',
         new=''''''),
    dict(id="D1-81 the erased clause is turned away at arity 3 only after the test moved", file=K, targets=T8,
         old='''rc1 < 0 && PL__ac < 4 && return FFALSE''',
         new='''rc1 < 0 && PL__ac < 3 && return FFALSE'''),
    dict(id="D1-82 an erased clause is never answered, '$clause'/4 included", file=K, targets=T8,
         old='''rc1 < 0 && PL__ac < 4 && return FFALSE''',
         new='''rc1 < 0 && true && return FFALSE'''),
    dict(id="D1-83 the by-reference decompile is unchecked", file=K, targets=T8,
         old='''                decompile!(ld, rcl, h, b, bindings) || return FFALSE    # decompile(clause, term, bindings)''',
         new='''                decompile!(ld, rcl, h, b, bindings)    # decompile(clause, term, bindings)'''),
    dict(id="D1-84 the by-reference branch treats every clause as a goal clause", file=K, targets=T8,
         old='''                if (rcl.flags & GOAL_CLAUSE) != 0
                    tmp = head''',
         new='''                if true
                    tmp = head'''),
    dict(id="D1-85 the by-reference unify of the definition is unchecked", file=K, targets=T8,
         old='''                    unify_definition(gd, ld, MODULE_user(gd), head, def, tmp, 0) ||
                        return FFALSE''',
         new='''                    unify_definition(gd, ld, MODULE_user(gd), head, def, tmp, 0)'''),
    dict(id="D1-86 the by-reference head unify is unchecked", file=K, targets=T8,
         old='''                unify_head(gd, ld, tmp, h2) || return FFALSE
''',
         new='''                unify_head(gd, ld, tmp, h2)
'''),
    dict(id="D1-87 the by-reference body is the other side", file=K, targets=T8,
         old='''PL_unify(ld, body, (flags & IS_CLAUSE) != 0 ? b2 : term)''',
         new='''PL_unify(ld, body, (flags & IS_CLAUSE) == 0 ? b2 : term)'''),
    dict(id="D1-88 the enumeration does not unify the reference", file=K, targets=T8,
         old='''                rc2 = rc2 && (ref == 0 || PL_unify_clref(gd, ld, ref, clause))   # if ( rc2 && ref )''',
         new='''                rc2 = rc2                                       # if ( rc2 && ref )'''),
    dict(id="D1-89 the enumeration does not build the bindings", file=K, targets=T8,
         old='''            if decompile!(ld, clause, h, b, bindings)       # decompile(clause, term, bindings)''',
         new='''            if decompile!(ld, clause, h, b)       # decompile(clause, term, bindings)'''),
    dict(id="D1-90 clause/2 reads its third argument", file=K, targets=T8,
         old='''    PL__ac < 3 && (ref = 0)                                 # if ( CTX_ARITY < 3 ) ref = 0
''',
         new=''''''),
    dict(id="D1-91 clause/3 reads its fourth argument", file=K, targets=T8,
         old='''    PL__ac < 4 && (bindings = 0)                            # if ( CTX_ARITY < 4 ) bindings = 0
''',
         new=''''''),
    dict(id="D1-92 clause/3 is not registered", file=K, targets=T8,
         old='''    PL_extension(                                   # PRED_SHARE("clause", 3, clause, META|NDET|PL_FA_CREF) (D1)
        "clause", 3, pl_clauseva_va,
        PL_FA_TRANSPARENT | PL_FA_NONDETERMINISTIC | PL_FA_CREF | PL_FA_VARARGS
    ),
''',
         new=''''''),
    dict(id="D1-93 '$clause'/4 is not registered", file=K, targets=T8,
         old=r'''    PL_extension(                                   # PRED_SHARE("$clause", 4, clause, META|NDET|PL_FA_CREF) (D1)
        "\$clause", 4, pl_clauseva_va,
        PL_FA_TRANSPARENT | PL_FA_NONDETERMINISTIC | PL_FA_CREF | PL_FA_VARARGS
    ),
''',
         new=''''''),
    dict(id="D1-94 '$rule'/3 is not registered", file=K, targets=T8,
         old=r'''    ),
    PL_extension(                                   # PRED_SHARE("$rule", 3, rule, META|NDET|PL_FA_CREF) (D1)
        "\$rule", 3, pl_ruleva_va,
        PL_FA_TRANSPARENT | PL_FA_NONDETERMINISTIC | PL_FA_CREF | PL_FA_VARARGS
    )
)''',
         new=r'''    )
)'''),
    dict(id="D1-95 the by-reference branch refuses a protected predicate no more", file=K, targets=T8,
         old='''                protected_predicate(gd, ld, rcl.predicate) && return FFALSE
''',
         new='''''',
         equivalent="protected_predicate is true only for a P_FOREIGN definition here (the protect_static_code and iso flags are constants "
                    "false until R2 F1b: src/pl-comp.jl:3285-3287 and :3293-3297), and a foreign predicate holds no clause, so no "
                    "reference PL_get_clref answers names one (clauses enter by assert_term!/record_clause only, which refuse a "
                    "foreign predicate)"),
    dict(id="D1-96 the by-reference clause type is not compared with the term's", file=K, targets=T8,
         old='''                (rcl.flags & CLAUSE_TYPE_MASK) != hflags && return FFALSE
''',
         new='''''',
         equivalent="the term is built by _rule_term from the clause's own flags (src/pl-comp.jl:3506-3516): UNIT_CLAUSE gives the bare "
                    "head (get_head_and_body_clause answers UNIT_CLAUSE, :3590), otherwise the neck of clause_functor, whose flags are "
                    "the clause's own SSU bits (:3581); the compiler sets UNIT_CLAUSE only for a clause without an SSU neck "
                    "(:2929-2934, row c37: `e(1) => true` is SSU_COMMIT without UNIT_CLAUSE), so hflags == (flags & CLAUSE_TYPE_MASK) always"),
    dict(id="D1-97 clause/3's reference is its body argument", file=K, targets=T8,
         old='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    return clause_ndet(ld, A1, A2, A3, A4, PL__ac, PL__ctx, IS_CLAUSE)''',
         new='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 1, PL__t0 + 3
    return clause_ndet(ld, A1, A2, A3, A4, PL__ac, PL__ctx, IS_CLAUSE)'''),
    dict(id="D1-98 '$rule'/3's reference is its rule argument", file=K, targets=T8,
         old='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    return clause_ndet(ld, A1, A2, A3, A4, PL__ac, PL__ctx, IS_RULE)''',
         new='''    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 1, PL__t0 + 3
    return clause_ndet(ld, A1, A2, A3, A4, PL__ac, PL__ctx, IS_RULE)'''),
    # ---- instance/2 (D-0230 piece (d); rows n01-n20; pl-rec.c instance, fixup_ssu); T: only test_clause_ref_swipl.jl calls instance/2
    dict(id="D1-100 instance/2 is not registered", file=R, targets=T,
         old='''const PL_predicates_from_rec = (
    PL_extension("erase", 1, pl_erase1_va, PL_FA_VARARGS),
    PL_extension("instance", 2, pl_instance2_va, PL_FA_VARARGS)
)''',
         new='''const PL_predicates_from_rec = (
    PL_extension("erase", 1, pl_erase1_va, PL_FA_VARARGS),
)'''),
    dict(id="D1-101 instance/2 does not turn an erased or no reference away", file=R, targets=T,
         old='''    r === nothing && return FFALSE                              # if ( !(ptr=PL_get_dbref(ref, &type)) )
    type, clause = r
''',
         new='''    type, clause = r
'''),
    dict(id="D1-102 instance/2 does not wrap a fact as Head :- true", file=R, targets=T,
         old='''    if (clause.flags & UNIT_CLAUSE) != 0
        decompile!(ld, clause, h, b) || return FFALSE
        t = PL_new_term_ref(ld)''',
         new='''    if false
        decompile!(ld, clause, h, b) || return FFALSE
        t = PL_new_term_ref(ld)'''),
    dict(id="D1-103 instance/2 does not fix up an SSU ?=> clause", file=R, targets=T,
         old='''    elseif (clause.flags & SSU_CHOICE_CLAUSE) != 0''',
         new='''    elseif false'''),
    dict(id="D1-104 fixup_ssu leaves out a clause without a cut", file=R, targets=T,
         old='''    return PL_unify(ld, in, out)
end''',
         new='''    return true
end'''),
    dict(id="D1-105 fixup_ssu finds the cut by inequality", file=R, targets=T,
         old='''sym_key(a) == gd.subclause_names.atom_cut''',
         new='''sym_key(a) != gd.subclause_names.atom_cut'''),
    dict(id="D1-106 fixup_ssu starts its guard at the cut itself", file=R, targets=T,
         old='''            g -= 1
            PL_put_term(ld, guard, g) || return false''',
         new='''            PL_put_term(ld, guard, g) || return false'''),
    dict(id="D1-107 fixup_ssu's guard loop runs one goal further", file=R, targets=T,
         old='''while (g -= 1) > guard ''',
         new='''while (g -= 1) >= guard '''),
    dict(id="D1-108 fixup_ssu does not conjoin the guard goals", file=R, targets=T,
         old='''                PL_cons_functor(ld, guard, comma, g, guard) || return false
''',
         new=''''''),
    dict(id="D1-109 fixup_ssu does not append the guard to the head", file=R, targets=T,
         old='''                PL_cons_functor(ld, head, comma, head, guard) || return false
''',
         new=''''''),
    dict(id="D1-110 fixup_ssu answers an SSU ?=> neck", file=R, targets=T,
         old='''clause_functor(ld, SSU_COMMIT_CLAUSE), head, body)''',
         new='''clause_functor(ld, SSU_CHOICE_CLAUSE), head, body)'''),
    dict(id="D1-111 fixup_ssu does not unify its answer", file=R, targets=T,
         old='''            return PL_unify(ld, out, res)''',
         new='''            return true'''),
    dict(id="D1-112 a fact's wrapper has another neck", file=R, targets=T,
         old='''_err_functor(ld, Symbol(":-"), 2), h, t) || return FFALSE''',
         new='''_err_functor(ld, Symbol("=>"), 2), h, t) || return FFALSE'''),
    dict(id="D1-113 a fact's body is false", file=R, targets=T,
         old='''PL_put_atom(ld, t, mk_sym(T, Symbol("true")))''',
         new='''PL_put_atom(ld, t, mk_sym(T, Symbol("false")))'''),
    dict(id="D1-114 a rule is answered as its head", file=R, targets=T,
         old='''        return PL_unify(ld, term, _rule_term(ld, clause, h, b)) ? FTRUE : FFALSE   # decompile(clause, term, 0)''',
         new='''        return PL_unify(ld, term, h) ? FTRUE : FFALSE   # decompile(clause, term, 0)'''),
    dict(id="D1-115 instance/2's term is its reference argument", file=R, targets=T,
         old='''    ref, term = PL__t0, PL__t0 + 1                              # term_t ref = A1, term = A2''',
         new='''    ref, term = PL__t0, PL__t0                                  # term_t ref = A1, term = A2'''),
    dict(id="D1-116 a fact's answer is not unified", file=R, targets=T,
         old='''        return PL_unify(ld, term, res) ? FTRUE : FFALSE         # PL_unify_term(term, PL_FUNCTOR, FUNCTOR_prove2, …)''',
         new='''        return FTRUE                                            # PL_unify_term(term, PL_FUNCTOR, FUNCTOR_prove2, …)'''),
    dict(id="D1-117 instance/2 answers a goal clause", file=R, targets=T,
         old='''    if (clause.flags & GOAL_CLAUSE) != 0 || !visibleClause(clause, generation)''',
         new='''    if !visibleClause(clause, generation)''',
         equivalent="no goal clause has a reference: PL_unify_clref/PL_put_clref are called only for the clauses assert/2, asserta/2, assertz/2, "
                    "'$record_clause'/4 and clause/3 hand out (src/pl-comp.jl:3445, 3719, 3793, 3807, 3845), and a goal clause is a heap Clause "
                    "that no definition holds (src/pl-comp.jl:3089-3096, compileGoalClause)"),
    dict(id="D1-118 instance/2 does not test that the clause is visible", file=R, targets=T,
         old='''    if (clause.flags & GOAL_CLAUSE) != 0 || !visibleClause(clause, generation)''',
         new='''    if (clause.flags & GOAL_CLAUSE) != 0''',
         equivalent="PL_get_dbref has turned an erased clause away (src/pl-dbref.jl:161), and retractClauseDefinition! sets CL_ERASED in the "
                    "same step as generation_erased (src/pl-proc.jl:505-516); every referenced clause was created before the foreign frame "
                    "(its reference exists), so created <= generation holds: single thread, no transaction"),
    dict(id="D1-119 instance/2 does not test the reference's type", file=R, targets=T,
         old='''    if type != DB_REF_CLAUSE                                    # else: the record branch (D2)''',
         new='''    if false                                                    # else: the record branch (D2)''',
         equivalent="PL_get_dbref answers DB_REF_CLAUSE only (src/pl-dbref.jl:152-165) until D2 adds the record branch, so the NotPortedError "
                    "branch is unreachable"),
]
