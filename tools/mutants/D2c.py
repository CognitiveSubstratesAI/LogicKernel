# ORIGINAL: D2's mutant list — no swipl-devel counterpart.
# tools/mutants/D2c.py — the mutation battery of D2 (R2: the recorded database, pl-rec.c recorda/recordz/recorded/erase/instance/
# current_key and the record blob of pl-dbref.c; FLG §7 row D2, §4 D11; audit D-0230 item 2, D-0252 item 2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's (as D1c.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. One mutant per decision of the step: the lists and their
# links and the freed record (D2-1…D2-12), the erase/1 and instance/2 record branches (D2-13…D2-17; the branch tests are D1c.py's D1-56 and D1-119), the state of recorded/2,3 and its references
# (D2-18…D2-27), current_key/1 (D2-28, D2-29), the keys (D2-30…D2-35), the arguments (D2-36…D2-39), the blob and its readers
# (D2-40…D2-45).
# NOT RUN YET (written edit-only, 2026-10-31): the KILL rows named in each id are what the rows are DESIGNED to kill (r01-r101 of
# test/db/test_record_swipl.jl; "wb" = its white-box testsets: lists and references, key words, references of a list); the first
# hand-run (tools/mutate.sh, one tree each) replaces this header with the true result. A survivor is reported, not declared equivalent.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT
# any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur exactly
# once in the source at wip/d2 (a text count, no Julia).
# EQUIVALENT, with its reason:
#   * `release_record`'s clearing of R_DBREF (D2-45): the function has no caller (no atom GC, src/pl-dbref.jl:86-88), so no test can
#     reach it.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code. test_record_swipl.jl is the only file that
# names a record predicate; test_clause_ref_swipl.jl (erase/1, instance/2 and the references of clauses go through the same branch
# test), test_blob.jl (the blob ranks and the registration) and test_assert_swipl.jl (clause references read by PL_get_dbref) are listed
# for the code they share (pl-dbref.jl, erase/1, instance/2).
TR = ["test/db/test_record_swipl.jl"]
TD = TR + ["test/db/test_clause_ref_swipl.jl", "test/core_lang/test_blob.jl", "test/db/test_assert_swipl.jl"]
TARGETS = TD
R = "src/pl-rec.jl"
B = "src/pl-dbref.jl"
MUTANTS = [
    # ---- the lists and their links: lookupRecordList, PL_record_az, remove_record, cleanRecordList
    dict(id="D2-1 a new record list is not entered in the enumeration order (KILL r53-r55, r63, wb)", file=R, targets=TR,
         old='''    push!(gd.record_lists_order, l)''',
         new='''    nothing'''),
    dict(id="D2-2 recorda appends like recordz (KILL r02, r03)", file=R, targets=TR,
         old='''    elseif az == RECORDA''',
         new='''    elseif az == RECORDZ'''),
    dict(id="D2-3 recorda does not link the old first record back (KILL wb: rr1.prev === rr2)", file=R, targets=TR,
         old='''        first.prev = r''',
         new='''        nothing'''),
    dict(id="D2-4 recordz does not link the old last record forward (KILL r01, r03)", file=R, targets=TR,
         old='''        last.next = r''',
         new='''        nothing'''),
    dict(id="D2-5 recorda/3 never unifies the reference (KILL r04, r07, wb)", file=R, targets=TR,
         old='''PL__ac == 3 ? PL__t0 + 2 : 0, RECORDA)''',
         new='''0, RECORDA)'''),
    dict(id="D2-6 recordz/3 never unifies the reference (KILL r05, r06, r08, wb)", file=R, targets=TR,
         old='''PL__ac == 3 ? PL__t0 + 2 : 0, RECORDZ)''',
         new='''0, RECORDZ)'''),
    dict(id="D2-7 a record that is not erased is not first (firstRecordRecordList ignores R_ERASED) (KILL r58, r90, wb)", file=R, targets=TR,
         old='''        (record.flags & R_ERASED) == 0 && return record''',
         new='''        true && return record'''),
    dict(id="D2-8 isCurrentRecordList answers a list without a record (KILL r58, r72, wb)", file=R, targets=TR,
         old='''        return record !== nothing ? rl : nothing''',
         new='''        return rl'''),
    dict(id="D2-9 remove_record leaves the next record's back link (KILL wb: third.prev === rr2)", file=R, targets=TR,
         old='''        next.prev = prev''',
         new='''        nothing'''),
    dict(id="D2-10 remove_record leaves the list's last record (KILL wb: l.lastRecord === nothing)", file=R, targets=TR,
         old='''        l.lastRecord = prev''',
         new='''        nothing'''),
    dict(id="D2-11 cleanRecordList removes nothing (KILL wb: l.firstRecord === third)", file=R, targets=TR,
         old='''        (r.flags & R_ERASED) != 0 && remove_record(r)''',
         new='''        false && remove_record(r)'''),
    dict(id="D2-12 a removed record keeps its term (freeRecordRef) (KILL r66, wb: rr1.record === nothing)", file=R, targets=TR,
         old='''    r.record = nothing                                          # freeRecord(r->record); r->record = NULL''',
         new='''    nothing'''),

    # ---- erase/1's record branch (pl-rec.c:2464-2480)
    dict(id="D2-13 erase/1 does not mark a record a recorded/3 runs over (KILL r89, r90, wb: R_ERASED)", file=R, targets=TD,
         old='''            rref.flags |= R_ERASED''',
         new='''            nothing'''),
    dict(id="D2-14 erase/1 does not mark the list dirty (KILL wb: RL_DIRTY)", file=R, targets=TD,
         old='''            l.flags |= RL_DIRTY''',
         new='''            nothing'''),
    dict(id="D2-15 erase/1 marks when no recorded/3 runs and unlinks when one does (KILL wb: the two erase cases, r87-r89)",
         file=R, targets=TD,
         old='''        if l.references != 0 ''',
         new='''        if l.references == 0 '''),
    dict(id="D2-16 erase/1 of a record answers false (KILL r67, r72, wb)", file=R, targets=TD,
         old='''        return rc ? FTRUE : FFALSE
    end
end

# PORT: pl-rec.c fixup_ssu''',
         new='''        return FFALSE
    end
end

# PORT: pl-rec.c fixup_ssu'''),
    dict(id="D2-17 instance/2 of a record answers true without unifying (KILL r74)", file=R, targets=TD,
         old='''            return PL_unify(ld, term, t) ? FTRUE : FFALSE''',
         new='''            return FTRUE'''),

    # ---- recorded/2,3: the state and the references of the list (pl-rec.c:2125-2340)
    dict(id="D2-18 a recorded/3 cut does not give its list's reference back (free_state) (KILL wb: references == 0)", file=R, targets=TR,
         old='''        rl = r.list
        rl.references -= 1
        (rl.references == 0 && (rl.flags & RL_DIRTY) != 0) && cleanRecordList(rl)
    end
    state.r = nothing
    state.e = 0''',
         new='''        rl = r.list
        (rl.references == 0 && (rl.flags & RL_DIRTY) != 0) && cleanRecordList(rl)
    end
    state.r = nothing
    state.e = 0'''),
    dict(id="D2-19 a recorded/3 that leaves its list does not give the reference back (advance_state) (KILL wb: references == 0)",
         file=R, targets=TR,
         old='''            rl = r.list
            rl.references -= 1
            (rl.references == 0 && (rl.flags & RL_DIRTY) != 0) && cleanRecordList(rl)
            r = nothing''',
         new='''            rl = r.list
            (rl.references == 0 && (rl.flags & RL_DIRTY) != 0) && cleanRecordList(rl)
            r = nothing'''),
    dict(id="D2-20 recorded/2,3 with a bound key does not take a reference on the list (KILL wb: references == 0, r87-r89)",
         file=R, targets=TR,
         old='''            rl.references += 1
            state.r = rl.firstRecord''',
         new='''            state.r = rl.firstRecord'''),
    dict(id="D2-21 recorded/2,3 starts on an erased first record (KILL r94, r98)", file=R, targets=TR,
         old='''            ((state.r::RecordRef{T}).flags & R_ERASED) != 0 && advance_state(state)''',
         new='''            nothing'''),
    dict(id="D2-22 advance_state does not skip an erased record (KILL r99)", file=R, targets=TR,
         old='''        (r.flags & R_ERASED) != 0 || break''',
         new='''        break'''),
    dict(id="D2-23 recorded/3 with an unbound key never unifies the key (KILL r47, r53, r54, r64)", file=R, targets=TR,
         old='''if state.e != 0 && !unifyKey(ld, key, rec.list.key)''',
         new='''if false && !unifyKey(ld, key, rec.list.key)'''),
    dict(id="D2-24 recorded/3 with a bound reference does not match the key (KILL r48)", file=R, targets=TR,
         old='''            if unifyKey(ld, key, rec.list.key)''',
         new='''            if true'''),
    dict(id="D2-25 recorded/2,3 with a bound key takes a list without a record (KILL r65, r72)", file=R, targets=TR,
         old='''            rl = isCurrentRecordList(gd, kw, true)''',
         new='''            rl = isCurrentRecordList(gd, kw, false)'''),
    dict(id="D2-26 recorded/3 with an unbound key takes no reference on the list it enters (KILL wb: references == 0)",
         file=R, targets=TR,
         old='''                    if r !== nothing
                        rl.references += 1''',
         new='''                    if r !== nothing
                        nothing'''),
    dict(id="D2-27 a recorded/3 answer is the last one but leaves a state (KILL wb: live == 0)", file=R, targets=TR,
         old='''                    free_state(ld, k)
                    return FTRUE''',
         new='''                    return FTRUE'''),

    # ---- current_key/1
    dict(id="D2-28 current_key/1 with a bound key takes a key without a record (KILL r58)", file=R, targets=TR,
         old='''isCurrentRecordList(gd, k, true) !== nothing) && return FTRUE''',
         new='''isCurrentRecordList(gd, k, false) !== nothing) && return FTRUE'''),
    dict(id="D2-29 current_key/1 with an unbound key enumerates an emptied key (KILL r100)", file=R, targets=TR,
         old='''            if record !== nothing && unifyKey(ld, A1, rl.key)''',
         new='''            if unifyKey(ld, A1, rl.key)'''),

    # ---- the keys: getKeyEx, unifyKey
    dict(id="D2-30 getKeyEx takes any non-atom, non-integer word as a compound", file=R, targets=TR,
         old='''    elseif k == DU_WORD && _is_gcompound(w)''',
         new='''    elseif k == DU_WORD''',
         equivalent="_deref_loc answers DU_WORD only for an atom or a compound (src/pl-prims.jl:697, :713) and getKeyEx's first branch (src/pl-rec.jl:584) takes every atom, so the elseif sees a compound only"),
    dict(id="D2-31 getKeyEx refuses a small integer (KILL r14, r15, r53)", file=R, targets=TR,
         old='''(k == DU_VALUE && isTaggedIntW(w))''',
         new='''false'''),
    dict(id="D2-32 getKeyEx refuses an atom (KILL r01-r03)", file=R, targets=TR,
         old='''if (k == DU_WORD && isAtomW(w)) ||''',
         new='''if false ||'''),
    dict(id="D2-33 unifyKey answers a small integer key off by one (KILL r53, r54, r55)", file=R, targets=TR,
         old='''        return PL_unify_integer(ld, key, Int(valInt(val)))''',
         new='''        return PL_unify_integer(ld, key, Int(valInt(val)) + 1)'''),
    dict(id="D2-34 unifyKey answers a compound key with the wrong arity (KILL r53, r55, r60)", file=R, targets=TR,
         old='''        return PL_unify_functor(ld, key, name, arityFunctor(ld.functors, val))''',
         new='''        return PL_unify_functor(ld, key, name, arityFunctor(ld.functors, val) + 1)'''),
    dict(id="D2-35 unifyKey answers an atom key as an integer (KILL r53-r55)", file=R, targets=TR,
         old='''        return PL_unify_atomic(ld, key, _atom_value(ld, val))''',
         new='''        return PL_unify_integer(ld, key, 0)'''),

    # ---- the arguments: record_term, PL_record_az
    dict(id="D2-36 recorda/3 and recordz/3 take a bound reference (KILL r32, r33, r34)", file=R, targets=TR,
         old='''    if ref != 0 && !PL_is_variable(ld, ref)
        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION''',
         new='''    if false
        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION'''),
    dict(id="D2-37 PL_record_az does not unify the reference (KILL r04-r10, wb)", file=R, targets=TR,
         old='''    if ref != 0 && !PL_unify_recref(gd, ld, ref, r)''',
         new='''    if false && !PL_unify_recref(gd, ld, ref, r)'''),
    dict(id="D2-38 recorda/recordz do not stop at a key error (KILL r20-r24)", file=R, targets=TR,
         old='''    k === nothing && return false
    if ref != 0''',
         new='''    if ref != 0'''),
    dict(id="D2-39 a list is made for a key per record (lookupRecordList does not find the list) (KILL r01-r03, r30, wb)",
         file=R, targets=TR,
         old='''    l = get(gd.record_lists, key, nothing)                      # lookupHTableWP(…, key)
    l !== nothing && return l''',
         new='''    l = nothing
    l !== nothing && return l'''),

    # ---- the blob and its readers (pl-dbref.jl)
    dict(id="D2-40 a record blob is not marked as having a database reference (KILL wb: R_DBREF)", file=B, targets=TD,
         old='''    ref.flags |= R_DBREF ''',
         new='''    nothing '''),
    dict(id="D2-41 recref_record accepts a blob of another type (KILL r51, r85, r50, r83)", file=B, targets=TD,
         old='''    at.type === record_blob || return nothing ''',
         new='''    nothing '''),
    dict(id="D2-42 PL_get_dbref answers a marked-erased record (KILL wb: the second erase false, r66, r76)", file=B, targets=TD,
         old='''        if ref.record !== nothing && (ref.flags & R_ERASED) == 0 ''',
         new='''        if ref.record !== nothing '''),
    dict(id="D2-43 PL_get_recref answers a marked-erased record (KILL wb: recorded(_, _, Ref) false, r49)", file=B, targets=TD,
         old='''
    if ref.record !== nothing && (ref.flags & R_ERASED) == 0 ''',
         new='''
    if ref.record !== nothing '''),
    dict(id="D2-44 PL_get_recref raises no type error for a blob of another type (KILL r50, r51)", file=B, targets=TD,
         old='''    if ref === nothing                                          # !PL_get_blob(…) || type != &record_blob
        PL_error(ld, ERR_TYPE, mk_sym(T, :db_reference), t)
        return nothing''',
         new='''    if ref === nothing                                          # !PL_get_blob(…) || type != &record_blob
        return nothing'''),
    dict(id="D2-45 release_record keeps the database-reference mark", file=B, targets=TD,
         old='''        ref.flags &= ~R_DBREF ''',
         new='''        nothing ''',
         equivalent="release_record has no caller (no atom GC; src/pl-dbref.jl:86-88, the comment above the function)"),
]
