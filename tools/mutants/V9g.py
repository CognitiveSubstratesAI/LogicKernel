# ORIGINAL: V9g's mutant list — no swipl-devel counterpart.
# tools/mutants/V9g.py — the mutation battery of step V9g (the cleanup family, the bags, copy_term),
# run ONCE, at the step's close, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# V9g-a, the cleanup family (MG1–MG24). V9g-b, the bags (MB1–MB31). copy_term (CT1–CT10: the list
# of its own battery of 2026-10-13, run then on the branch — 8 caught, CT9 and CT10 recorded
# equivalent). Carried from V9e-1: MC17 (caught since V9f-b; it must stay caught).
#
# The targets, smallest first (a run started by a push to `mutants/V9g` reads them from here).
TARGETS = [
    "test/core_lang/test_copyterm_swipl.jl",
    "test/core_lang/test_findall_swipl.jl",
    "test/core_lang/test_sortlist_swipl.jl",
    "test/core_lang/test_bagof_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl",
    "test/core_lang/test_det_swipl.jl",
]
W = "src/pl-wam.jl"
PRO = "src/pl-pro.jl"
REC = "src/pl-rec.jl"
BAG = "src/pl-bag.jl"
LST = "src/pl-list.jl"
P = "src/pl-prims.jl"
E = "src/pl-ext.jl"
CP = "src/pl-copyterm.jl"
T_CLEAN = ["test/core_lang/test_cleanup_swipl.jl"]
T_FIND = ["test/core_lang/test_findall_swipl.jl"]
T_SORT = ["test/core_lang/test_sortlist_swipl.jl"]
T_BAGOF = ["test/core_lang/test_bagof_swipl.jl"]
T_COPY = ["test/core_lang/test_copyterm_swipl.jl"]
T_DET = ["test/core_lang/test_det_swipl.jl"]
MUTANTS = [
    # ── V9g-a: I_CALLCLEANUP, I_EXITCLEANUP ──
    dict(id="MG1 I_CALLCLEANUP does not mark the frame FR_CLEANUP", file=W, targets=T_CLEAN,
         old='''    icc_f.flags |= FR_CLEANUP                       # set(FR, FR_CLEANUP)''',
         new='''    nothing'''),
    dict(id="MG2 I_CALLCLEANUP pushes no CHP_CATCH choice point", file=W, targets=T_CLEAN,
         old='''    newChoice(ld, CHP_CATCH, FR)
    icc_f.flags |= FR_CLEANUP''',
         new='''    icc_f.flags |= FR_CLEANUP'''),
    dict(id="MG3 I_CALLCLEANUP takes the goal from the wrong argument (the Setup of the /3 and /4)", file=W, targets=T_CLEAN,
         old='''    icc_arg_goal = icc_arity == 2 ? 1 : 2''',
         new='''    icc_arg_goal = 1'''),
    dict(id="MG4 I_EXITCLEANUP does not run the handler", file=W, targets=T_CLEAN,
         old='''        frameFinished(ld, FR, FINISH_EXITCLEANUP)''',
         new='''        nothing'''),
    # ── callCleanupHandler ──
    dict(id="MG5 callCleanupHandler ignores FR_CAUGHT (the handler runs again)", file=W, targets=T_CLEAN,
         old='''    if (f.flags & FR_CAUGHT) == 0                   # from handler''',
         new='''    if true'''),
    dict(id="MG6 callCleanupHandler does not set FR_CAUGHT", file=W, targets=T_CLEAN,
         old='''        f.flags |= FR_CAUGHT

        # Unify the catcher''',
         new='''        # Unify the catcher'''),
    dict(id="MG7 the cleanup goal runs with the exception pending (no saveWakeup)", file=W, targets=T_CLEAN,
         old='''            wstate = saveWakeup(ld, false)
            if wstate !== nothing
                rval = call_term(_query_gd(ld), ld, clean)''',
         new='''            wstate = nothing
            call_term(_query_gd(ld), ld, clean)
            if wstate !== nothing
                rval = false'''),
    dict(id="MG8 an exception of the cleanup goal never replaces a pending one (no WAKEUP_KEEP_URGENT_EXCEPTION)", file=W, targets=T_CLEAN,
         old='''                        wstate.flags | WAKEUP_KEEP_URGENT_EXCEPTION''',
         new='''                        wstate.flags'''),
    dict(id="MG9 the catcher of the /4 is read from the Goal argument", file=W, targets=T_CLEAN,
         old='''            arg_catcher = 3''',
         new='''            arg_catcher = 2'''),
    # ── unify_finished ──
    dict(id="MG10 unify_finished swaps exception and external_exception", file=W, targets=T_CLEAN,
         old='''        f = reason == FINISH_EXCEPT ? :exception : :external_exception''',
         new='''        f = reason == FINISH_EXCEPT ? :external_exception : :exception'''),
    dict(id="MG11 unify_finished reports a cut as `cut`", file=W, targets=T_CLEAN,
         old='''        elseif reason == FINISH_CUT
            :!''',
         new='''        elseif reason == FINISH_CUT
            :cut'''),
    dict(id="MG12 unify_finished reports a plain FINISH_EXIT", file=W, targets=T_CLEAN,
         old='''    elseif reason == FINISH_EXIT
        return false''',
         new='''    elseif false
        return false''',
         equivalent="src/pl-wam.jl callCleanupHandler reaches unify_finished only while FR_CAUGHT is clear, and FINISH_EXIT is passed by one caller, exit_continue's `leave`, which asserts FR_CAUGHT set (the handler ran at I_EXITCLEANUP): unify_finished is never called with FINISH_EXIT"),
    # ── the callers of frameFinished ──
    dict(id="MG13 discardChoicesAfter skips a watched frame (a cut does not run the handler)", file=W, targets=T_CLEAN,
         old='''                if (f2.flags & FR_WATCHED) != 0
                    if !me_undone && is_exception_finish(reason)''',
         new='''                if false
                    if !me_undone && is_exception_finish(reason)'''),
    dict(id="MG14 discardChoicesAfter does not undo before an exception's handler", file=W, targets=T_CLEAN,
         old='''                        me_undone = true
                        Undo!(ld, mec.mark)''',
         new='''                        me_undone = true'''),
    dict(id="MG15 c_cut does not run the handler of a frame it discards", file=W, targets=T_CLEAN,
         old='''                frameFinished(ld, cc_fr2, FINISH_CUT)''',
         new='''                nothing'''),
    dict(id="MG16 b_throw_unwind does not run the handler of a frame it unwinds", file=W, targets=T_CLEAN,
         old='''            frameFinished(ld, FR, FINISH_EXCEPT)''',
         new='''            nothing'''),
    dict(id="MG17 backtracking into the CHP_CATCH of a cleanup frame does not run the handler", file=W, targets=T_CLEAN,
         old='''                callCleanupHandler(ld, FR, FINISH_FAIL)''',
         new='''                nothing'''),
    dict(id="MG18 backtracking into a watched CHP_CATCH does not lower lTop", file=W, targets=T_CLEAN,
         old='''            setLTop!(ld, db_c.base + SIZEOF_CHOICE) # lTop = (LocalFrame)(BFR+1)''',
         new='''            nothing'''),
    dict(id="MG19 discard_query does not run the handler of the query's own frame", file=W, targets=T_CLEAN,
         old='''        frameFinished(ld, q.frame, FINISH_CUT)''',
         new='''        nothing'''),
    # ── calling the goal ──
    dict(id="MG20 call_term calls a control construct directly, not through call/1", file=W, targets=T_CLEAN,
         old='''            if isTextAtom(h) && !_is_control(p, gd.functors_control) &&''',
         new='''            if isTextAtom(h) &&'''),
    dict(id="MG21 callProlog has no shortcut for `true`", file=PRO, targets=T_CLEAN,
         old='''    if isTextAtom(p) && sym_key(p) == gd.subclause_names.atom_true     # fd == FUNCTOR_true0
        return true
    end
''',
         new='''''',
         equivalent="src/pl-pro.jl callProlog: without the shortcut `true` is called as the predicate true/0 (src/pl-prims.jl pl_true, registered by src/pl-ext.jl foreigns), which succeeds once and leaves no choice point; the query is cut and its term references reset either way"),
    dict(id="MG22 callProlog closes its query (the Setup goal's bindings are undone)", file=PRO, targets=T_CLEAN,
         old='''    PL_cut_query(ld, qid)
    if rval && ld.exception_term != 0''',
         new='''    PL_close_query(ld, qid)
    if rval && ld.exception_term != 0'''),
    dict(id="MG23 call_term closes its query (the cleanup goal's bindings are undone)", file=W, targets=T_CLEAN,
         old='''        rval = PL_next_solution(gd, ld, qid) != 0
        PL_cut_query(ld, qid)''',
         new='''        rval = PL_next_solution(gd, ld, qid) != 0
        PL_close_query(ld, qid)'''),
    dict(id="MG24 mustBeCallable accepts any bound term", file=W, targets=T_CLEAN,
         old='''    (isTerm(ap) || isTextAtom(ap)) || return PL_type_error(ld, "callable", call)

    return true''',
         new='''    return true'''),
    # ── V9g-b: recorded terms ──
    dict(id="MB1 compileTermToHeap drops the cyclic references", file=REC, targets=T_FIND,
         old='''        push!(cycles, (key, deRef(ld, mk_var(T, key))))''',
         new='''        nothing'''),
    dict(id="MB2 compileTermToHeap leaves the cyclic copies' bindings on the trail", file=REC, targets=T_FIND,
         old='''    Undo!(ld, m)
    return record{T}(c, cycles, false)''',
         new='''    return record{T}(c, cycles, false)'''),
    dict(id="MB3 copyRecordToGlobal does not bind the cyclic references", file=REC, targets=T_FIND,
         old='''            Trail!(ld, var_key(w), _rec_copy(vars, v))''',
         new='''            nothing'''),
    dict(id="MB4 _rec_copy gives the top compound's variables no keys first (first-visit order)", file=REC, targets=T_FIND,
         old='''    _rec_block!(vars, t)
    stack = Tuple{T, Vector{T}}[(t, T[])]''',
         new='''    stack = Tuple{T, Vector{T}}[(t, T[])]'''),
    dict(id="MB5 _rec_copy gives a nested compound's variables no keys first", file=REC, targets=T_FIND,
         old='''            _rec_block!(vars, c)
            push!(stack, (c, T[]))''',
         new='''            push!(stack, (c, T[]))'''),
    dict(id="MB6 a record's variable met twice gets two fresh variables", file=REC, targets=T_FIND,
         old='''    vars[key] = v
    return v''',
         new='''    return v'''),
    # ── the bag ──
    dict(id="MB7 '$add_findall_bag'/1 succeeds", file=BAG, targets=T_FIND,
         old='''    else
        return FFALSE
    end
end''',
         new='''    else
        return FTRUE
    end
end'''),
    dict(id="MB8 an added answer is not counted", file=BAG, targets=T_FIND,
         old='''    bag.solutions += 1''',
         new='''    nothing'''),
    dict(id="MB9 '$collect_findall_bag'/2 takes the first answer where the last is due", file=BAG, targets=T_FIND,
         old='''            r = bag.answers[end]''',
         new='''            r = bag.answers[1]'''),
    dict(id="MB10 '$destroy_findall_bag'/0 leaves the bag open", file=BAG, targets=T_FIND,
         old='''    pop!(ld.bags)                                   # LD->bags->bags = bag->parent''',
         new='''    nothing'''),
    dict(id="MB11 '$add_findall_bag' with no bag fails silently", file=BAG, targets=T_FIND,
         old='''    if bag === nothing
        cbag = mk_sym(T, Symbol("findall-bag"))
''',
         new='''    if bag === nothing
        return FFALSE
        cbag = mk_sym(T, Symbol("findall-bag"))
'''),
    # ── the sorts ──
    dict(id="MB12 sort/2 keeps duplicates", file=LST, targets=T_SORT,
         old='''    return pl_nat_sort(ld, A1, A2, true, SORT_ASC, false) ? FTRUE : FFALSE''',
         new='''    return pl_nat_sort(ld, A1, A2, false, SORT_ASC, false) ? FTRUE : FFALSE'''),
    dict(id="MB13 msort/2 removes duplicates", file=LST, targets=T_SORT,
         old='''    return pl_nat_sort(ld, A1, A2, false, SORT_ASC, false) ? FTRUE : FFALSE''',
         new='''    return pl_nat_sort(ld, A1, A2, true, SORT_ASC, false) ? FTRUE : FFALSE'''),
    dict(id="MB14 keysort/2 compares the whole pair", file=LST, targets=T_SORT,
         old='''    return pl_nat_sort(ld, A1, A2, false, SORT_ASC, true) ? FTRUE : FFALSE''',
         new='''    return pl_nat_sort(ld, A1, A2, false, SORT_ASC, false) ? FTRUE : FFALSE'''),
    dict(id="MB15 nat_sort's first merge takes the later run first on equal keys (not stable)", file=LST, targets=T_SORT,
         old='''                if c <= 0
                    next[r] = q
                    r = q
                    q = next[q]
                    if c == rd''',
         new='''                if c < 0
                    next[r] = q
                    r = q
                    q = next[q]
                    if c == rd'''),
    dict(id="MB16 nat_sort does not swap a descending first pair of a run", file=LST, targets=T_SORT,
         old='''            if c > 0
                r = q
                q = p
                p = r
                next[p] = q''',
         new='''            if false
                r = q
                q = p
                p = r
                next[p] = q'''),
    dict(id="MB17 a partial list is a type error to the sorts", file=LST, targets=T_SORT,
         old='''        if kind(tail) === VAR
            PL_error(ld, ERR_INSTANTIATION)
        else''',
         new='''        if false
            PL_error(ld, ERR_INSTANTIATION)
        else'''),
    dict(id="MB18 sort/2 refuses a cyclic list", file=LST, targets=T_SORT,
         old='''(is_pair(tail) && remove_dups))''',
         new='''(false && remove_dups))'''),
    dict(id="MB19 keysort/2 takes one element without looking for its key", file=LST, targets=T_SORT,
         old='''    if len == 1 && !pair && !is_pair(tail)''',
         new='''    if len == 1 && !is_pair(tail)'''),
    dict(id="MB20 '$length'/2 answers [] for a negative length", file=LST, targets=T_SORT,
         old='''        elseif len == 0
            return PL_unify_nil(ld, A1) ? FTRUE : FFALSE
        else
            return FFALSE''',
         new='''        elseif len == 0
            return PL_unify_nil(ld, A1) ? FTRUE : FFALSE
        else
            return PL_unify_nil(ld, A1) ? FTRUE : FFALSE'''),
    # ── functor/3, term_variables/2,3 ──
    dict(id="MB21 functor/3 gives an atomic term arity 1", file=P, targets=T_SORT,
         old='''        return (PL_unify(ld, A2, A1) && PL_unify_integer(ld, A3, 0)) ? FTRUE : FFALSE''',
         new='''        return (PL_unify(ld, A2, A1) && PL_unify_integer(ld, A3, 1)) ? FTRUE : FFALSE'''),
    dict(id="MB22 functor/3 does not check that the name is atomic", file=P, targets=T_SORT,
         old='''    if !PL_is_atomic(ld, A2)
        return PL_error(ld, ERR_TYPE, mk_sym(T, :atomic), A2) ? FTRUE : FFALSE
    end''',
         new=''''''),
    dict(id="MB23 term_variables lists a variable every time it is met", file=P, targets=T_SORT,
         old='''            push!(visitedv, k)

            count += 1''',
         new='''            count += 1'''),
    # ── '$free_variable_set'/3 ──
    dict(id="MB24 free_variables_loop collects the variables left of ^", file=P, targets=T_BAGOF,
         old='''                existential || push!(vars, t)''',
         new='''                push!(vars, t)'''),
    dict(id="MB25 free_variables_loop never enters the existential part", file=P, targets=T_BAGOF,
         old='''                    existential = true
                    continue''',
         new='''                    continue'''),
    dict(id="MB26 the mark does not end the existential part", file=P, targets=T_BAGOF,
         old='''        if t === mark
            existential = false
            continue''',
         new='''        if t === mark
            continue'''),
    dict(id="MB27 '$free_variable_set'/3 drops the module of the goal", file=P, targets=T_BAGOF,
         old='''        if mname !== nothing            # PL_cons_functor(goal, FUNCTOR_colon2, m, goal)''',
         new='''        if false'''),
    dict(id="MB28 a goal that is a compound met before is not taken as the goal", file=P, targets=T_BAGOF,
         old='''            if haskey(visitedf, t)                      # visited(f)
                if !in_goal && !existential
                    goal = t
                    in_goal = true
                end
                continue''',
         new='''            if haskey(visitedf, t)                      # visited(f)
                continue'''),
    # ── the boot clauses ──
    dict(id="MB29 findall/4 hands cleanup_bag/2 an unqualified findall_loop/4", file=E, targets=T_BAGOF,
         old='''                _boot_term(
                    :(:), T[sys, _boot_term(:findall_loop, T[Templ, Goal, List, Tail])]
                ),''',
         new='''                _boot_term(:findall_loop, T[Templ, Goal, List, Tail]),'''),
    dict(id="MB30 setof/3 always takes the ground-witness path", file=E, targets=T_BAGOF,
         old='''_boot_ite(T, _boot_term(:ground, T[Answers]), ground_keys, bound_keys)''',
         new='''ground_keys'''),
    dict(id="MB31 bagof/3 does not make the variables of equal witnesses one", file=E, targets=T_BAGOF,
         old='''            alloc, keyed, bind, _boot_term(:keysort, T[Answers, Sorted]),''',
         new='''            alloc, keyed, _boot_term(:keysort, T[Answers, Sorted]),'''),
    # ── copy_term (its battery of 2026-10-13; records are its copies, so findall/3 is a target too) ──
    dict(id="CT1 a ground compound is never shared", file=CP, targets=T_COPY,
         old='''    r = (st.share && f.same) ? f.orig : mk_expr(T, f.kids)''',
         new='''    r = mk_expr(T, f.kids)'''),
    dict(id="CT2 duplicate_term shares like copy_term", file=CP, targets=T_COPY,
         old='''    copy = copy_term_refs(ld, A1, cp_options(false))''',
         new='''    copy = copy_term_refs(ld, A1, cp_options(true))'''),
    dict(id="CT3 a variable met twice gets two fresh variables", file=CP, targets=T_COPY,
         old='''        w = get!(() -> mk_var(T, fresh_var_keys!(1)), st.vars, var_key(t))''',
         new='''        w = mk_var(T, fresh_var_keys!(1))'''),
    dict(id="CT4 a compound with a variable below is shared (`same` never cleared)", file=CP, targets=T_COPY,
         old='''                r === c || (f.same = false)''',
         new='''                nothing'''),
    dict(id="CT5 the cyclic copy is not bound (no Trail!)", file=CP, targets=T_COPY,
         old='''            Trail!(ld, var_key(w), r)                   # the cyclic copy: w = r, and r holds w''',
         new='''            nothing'''),
    dict(id="CT6 a cycle's placeholder is a fresh variable that is not remembered", file=CP, targets=T_COPY,
         old='''            w = get!(() -> mk_var(T, fresh_var_keys!(1)), st.cyclic, k)
            return _cp_chain_done!(st, chain, w)''',
         new='''            return _cp_chain_done!(st, chain, mk_var(T, fresh_var_keys!(1)))'''),
    dict(id="CT7 a bound variable is not seen through (the variable itself is copied)", file=CP, targets=T_COPY,
         old='''        b === nothing && break
        if haskey(st.done, k)''',
         new='''        b === nothing && break
        break
        if haskey(st.done, k)'''),
    dict(id="CT8 the copy's last child of a compound is dropped to the original's", file=CP, targets=T_COPY,
         old='''                f.kids[i] = r
                r === c || (f.same = false)''',
         new='''                f.kids[i] = i == length(f.kids) ? c : r
                r === c || (f.same = false)'''),
    dict(id="CT9 a copied bound variable is not remembered (the `done` memo)", file=CP, targets=T_COPY + T_FIND,
         old='''    for k in chain
        st.done[k] = r
    end
    return r''',
         new='''    return r''',
         equivalent="src/pl-copyterm.jl _cp_chain_done!: `done` only lets a bound variable met again reuse its copy — recopying gives an equal term, and a cycle is caught by `inprogress` before `done` is asked"),
    dict(id="CT10 copy_term/2 has no atomic shortcut", file=CP, targets=T_COPY,
         old='''    if _cp_atomic(ld, A1)
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
    copy = copy_term_refs(ld, A1, cp_options(true))
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c copy_term_nat''',
         new='''    copy = copy_term_refs(ld, A1, cp_options(true))
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c copy_term_nat''',
         equivalent="src/pl-copyterm.jl pl_copy_term2_va: the copy of an atomic term is the term itself (`_cp_visit!` returns it unchanged), so `PL_unify(copy, A2)` and `PL_unify(A1, A2)` are the same"),
    # ── carried from V9e-1: it must stay caught ──
    dict(id="MC17 mcall_cont does not set the next frame's flags", file=W, targets=T_DET,
         old='''    @label mcall_cont
    setNextFrameFlags(ld.frames[NFR], ld.frames[FR])''',
         new='''    @label mcall_cont
    nothing'''),
]
