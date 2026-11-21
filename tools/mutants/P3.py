# ORIGINAL: P3's mutant list — no swipl-devel counterpart.
# tools/mutants/P3.py — the mutation battery of P3 (call_with_depth_limit/3, call_with_inference_limit/3: pl-prims.c `$depth_limit*`,
# `$inference_limit*`, raiseInferenceLimitException, `$urgent_exception/3`; the limit checks of pl-vmi.c depart_alerted; pl-wam.c's
# PL_Q_NODEBUG save and restore of the depth limit). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written
# edit-only, 2026-11-11, UNTESTED: nothing was compiled): the KILL named in each id is the row that is DESIGNED to fail.
# TD = test/core_lang/test_depth_limit_swipl.jl; a row is cited by its id (dl01-dl26 depth, il01-il23 inference, ue01-ue12 urgent_exception).
# TARGETS (audit D-0238): TD is the only test that runs the limit predicates (boot/syspred.pl's call_with_depth_limit and call_with_inference_limit
# are run by no other test file; test_boot_clauses_swipl.jl and test_boot_image_swipl.jl compare their clause text only). The mutants of the run
# loop and of PL_open_query/restore_after_query also name the files that run every call through depart_or_retry_continue and PL_Q_NODEBUG queries
# (test_autoload_trap.jl, test/foreign/test_query.jl, test_catch_swipl.jl, test_cleanup_swipl.jl).
# EQUIVALENT, with the reason: P3-9 (`$depth_limit_true/5` validates its Limit again: the boot's `$depth_limit/3` has already read the same
# term with PL_get_size_ex, so the second read cannot fail there) and P3-26 (`$inference_limit_true/3` with a bound Result: the boot calls it
# only after `Result0 == inference_limit_exceeded -> !` has taken the other branch, so A3 is always unbound when it is called).
# NOT listed: resetProlog's lift of the depth limit (src/pl-pro.jl: it runs at the end of a toplevel query, no row reaches it) and the
# S_VIRGIN early exit of depart_alerted (the autoload's first call: a row would need an undefined predicate under a limit; swipl and the kernel
# agree on the answer either way, the early exit only keeps the depth count of the retried call single).
TD = ["test/core_lang/test_depth_limit_swipl.jl"]
TV = TD + [
    "test/core_lang/test_autoload_trap.jl",
    "test/foreign/test_query.jl",
    "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl",
]
P = "src/pl-prims.jl"
W = "src/pl-wam.jl"
# the union of every mutant's `targets` (mutate_ci.py plan and the pre-push hook read TARGETS; audit D-0834 era, R2 gate)
TARGETS = [
    "test/core_lang/test_depth_limit_swipl.jl",
    "test/core_lang/test_autoload_trap.jl",
    "test/foreign/test_query.jl",
    "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl",
]
MUTANTS = [
    # ---- pl-prims.c: the depth limit
    dict(id="P3-1 `inf` is not written for DEPTH_NO_LIMIT (KILL dl27: the boot-internal `$depth_limit` shows the old limit; dl01 never shows OldLimit)", file=P, targets=TD,
         old='''    depth == DEPTH_NO_LIMIT && return PL_unify_atom(ld, t, mk_sym(T, :inf))''',
         new='''    false && return PL_unify_atom(ld, t, mk_sym(T, :inf))'''),
    dict(id="P3-2 `inf` is not read back (KILL dl01: `$depth_limit_false`/`_true` get inf as the old limit)", file=P, targets=TD,
         old='''    if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :inf))''',
         new='''    if false && a !== nothing && sym_key(a) == sym_key(mk_sym(T, :inf))'''),
    dict(id="P3-3 the limit leaves out the catch/3's level (KILL dl05: the exact depth at which nonlast(5) is stopped, and dl01)", file=P, targets=TD,
         old='''        newlimit = clevel + levels + 1                      # 1 for the catch/3''',
         new='''        newlimit = clevel + levels                          # 1 for the catch/3'''),
    dict(id="P3-4 a wrapped sum is no error (KILL dl19: the kernel's pinned representation_error(depth_limit))", file=P, targets=TD,
         old='        if newlimit < clevel\n            return if PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :depth_limit))',
         new='        if false\n            return if PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :depth_limit))'),
    dict(id="P3-5 the reached depth of a new limit starts at 0 (EQUIVALENT, audit D-0919: SURVIVES the file in a fresh process; dl03/dl04 read R after the alerted calls)", file=P, targets=TD,
         old='''        ld.depth_info_limit = newlimit
        ld.depth_info_reached = clevel''',
         new='''        ld.depth_info_limit = newlimit
        ld.depth_info_reached = 0''',
         equivalent="src/pl-prims.jl pl_depth_limit3_va / pl_depth_limit_true5_va / pl_depth_limit_false3_va: every reader of "
         "`depth_info_reached` is a `$depth_limit*` frame, and depart_alerted (src/pl-wam.jl, the `da_depth > ld.depth_info_reached` record) "
         "has already recorded that frame's level, clevel+1, before the reader runs (every call path meets in depart_or_retry_continue; "
         "the limit bit is set the moment the limit is installed). So `reached = max(start, recorded levels)` reads the same value for "
         "start = clevel and start = 0: the start is always below the first recorded level. Fresh-process SURVIVED (precompile 1352 s, "
         "run 557 s, evidence/R2/p3rows/P3-5.log) and the pristine counter run (evidence/R2/p3rows/p3_cnt_result.txt) found every read "
         "on every finite-bound row at or above clevel+1. Accepted by the audit, D-0919 (3)."),
    dict(id="P3-6 the used depth is not raised to 1 (KILL dl01: `true` reaches no depth)", file=P, targets=TD,
         old='''        used < 1 && (used = 1)''',
         new='''        '''),
    dict(id="P3-7 the used depth counts one more (KILL dl03, dl04)", file=P, targets=TD,
         old='''        used = ld.depth_info_reached - clevel - 1           # intptr_t used = LD->depth_info.reached - clevel - 1''',
         new='''        used = ld.depth_info_reached - clevel               # intptr_t used = LD->depth_info.reached - clevel - 1'''),
    dict(id="P3-8 `$depth_limit_true` leaves the old limit set (KILL dl26: the unlimited recursion after a successful call)", file=P, targets=TD,
         old='''        ld.depth_info_limit = ol
        ld.depth_info_reached = or
        updateAlerted(ld)

        used < 1''',
         new='''        updateAlerted(ld)

        used < 1'''),
    dict(id="P3-9 `$depth_limit_true` does not read its Limit on the first call", file=P, targets=TD,
         equivalent="`$depth_limit/3` read the same term with PL_get_size_ex before: the second read cannot fail on the boot's path",
         old='''        l = get_depth(ld, limit)
        l === nothing && return FFALSE
        ol = get_depth''',
         new='''        ol = get_depth'''),
    dict(id="P3-10 the cut flag is not unified (KILL dl17: setup_call_cleanup's Det, il16)", file=P, targets=TD,
         old='''        PL_unify_integer(ld, res, used) || return FFALSE
        return unify_det(ld, cut)''',
         new='''        PL_unify_integer(ld, res, used) || return FFALSE
        return FTRUE'''),
    dict(id="P3-11 a redo does not install the limit again (KILL dl22: the second clause is deeper than the limit)", file=P, targets=TD,
         old='''        ld.depth_info_limit = clevel + levels + 1           # 1 for catch/3
        ld.depth_info_reached = clevel
        updateAlerted(ld)
        return FFALSE                                       # backtrack to goal''',
         new='''        updateAlerted(ld)
        return FFALSE                                       # backtrack to goal'''),
    dict(id="P3-12 `$depth_limit_false` never reports the overflow (KILL dl05, dl11)", file=P, targets=TD,
         old='''    exceeded = ld.depth_info_reached > ld.depth_info_limit''',
         new='''    exceeded = false'''),
    dict(id="P3-13 `$depth_limit_false` leaves the limit set (KILL dl24)", file=P, targets=TD,
         old='''    exceeded = ld.depth_info_reached > ld.depth_info_limit
    ld.depth_info_limit = ol
    ld.depth_info_reached = or
    updateAlerted(ld)
''',
         new='''    exceeded = ld.depth_info_reached > ld.depth_info_limit
    ld.depth_info_reached = or
    updateAlerted(ld)
'''),
    dict(id="P3-14 `$depth_limit_except` leaves the limit set (KILL dl25)", file=P, targets=TD,
         old='''    ld.depth_info_limit = ol
    ld.depth_info_reached = or
    updateAlerted(ld)
    return PL_raise_exception(ld, A3) ? FTRUE : FFALSE''',
         new='''    ld.depth_info_reached = or
    updateAlerted(ld)
    return PL_raise_exception(ld, A3) ? FTRUE : FFALSE'''),
    # ---- pl-prims.c: unify_det
    dict(id="P3-15 the foreign frame's own choice point is not skipped (KILL dl17: the cut flag is never `!`)", file=P, targets=TD,
         old='''        if ch.frame == ld.environment_frame                 #   if ( ch->frame == environment_frame ) continue (I_FOPENNDET)''',
         new='''        if false                                            #   if ( ch->frame == environment_frame ) continue (I_FOPENNDET)'''),
    dict(id="P3-16 a deterministic exit is reported as `true` (KILL dl17, il16, il02's last answer)", file=P, targets=TD,
         old='''        return PL_unify_atom(ld, t, mk_sym(T, Symbol("!"))) ? FTRUE : FFALSE    # ATOM_cut''',
         new='''        return PL_unify_atom(ld, t, mk_sym(T, Symbol("true"))) ? FTRUE : FFALSE    # ATOM_cut'''),
    dict(id="P3-17 a non-deterministic exit leaves no retry (KILL dl22: no redo, so the deeper clause is not tried; il14: the redo into `dl_nd2(2) :- dl_loop` runs without a limit, the COUNTED dl_loop ends and the answer is 2-!, not inference_limit_exceeded; measured, fresh process)", file=P, targets=TD,
         old='''        if PL_unify_atom(ld, t, mk_sym(T, Symbol("true")))
            return PL_retry(1)                              # ForeignRedoInt(1)
        end''',
         new='''        if PL_unify_atom(ld, t, mk_sym(T, Symbol("true")))
            return FTRUE
        end'''),
    # ---- pl-prims.c: the inference limit
    dict(id="P3-18 `infinite` is no limit (KILL il05)", file=P, targets=TD,
         old='''        sym_key(a) == sym_key(mk_sym(T, :infinite)) && return INFERENCE_NO_LIMIT''',
         new='''        false && return INFERENCE_NO_LIMIT'''),
    dict(id="P3-19 an atom that is not `infinite` raises nothing (KILL il07)", file=P, targets=TD,
         old='''        PL_domain_error(ld, "inference_limit", t)
        return nothing''',
         new='''        return nothing'''),
    dict(id="P3-20 a negative limit is accepted (KILL il06)", file=P, targets=TD,
         old='''    if limit < 0
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), A1)''',
         new='''    if false
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), A1)'''),
    dict(id="P3-21 a new limit replaces a lower one (KILL il19: the outer 100 stays under the inner 100000)", file=P, targets=TD,
         old='''    if nlimit < ld.inference_limit_limit
        ld.inference_limit_limit = nlimit''',
         new='''    if true
        ld.inference_limit_limit = nlimit'''),
    dict(id="P3-22 the wrapper's overhead is 3 inferences (KILL il21/il22: the boundary of dl_chain(5))", file=P, targets=TD,
         old='''const INFERENCE_LIMIT_OVERHEAD = 2''',
         new='''const INFERENCE_LIMIT_OVERHEAD = 3'''),
    dict(id="P3-23 the wrapper's overhead is 1 inference (KILL il18: limit 0 must exceed; il21)", file=P, targets=TD,
         old='''const INFERENCE_LIMIT_OVERHEAD = 2''',
         new='''const INFERENCE_LIMIT_OVERHEAD = 1'''),
    dict(id="P3-24 `$inference_limit_true` leaves the old limit set (KILL il04, il11, il12, il13: the limit left by the earlier call stops nothing or the wrong goal, the COUNTED dl_loop runs to its end and answers `!`; il04 raises; measured, fresh process; il23 and il26 still pass)", file=P, targets=TD,
         old='''        ld.inference_limit_limit = olimit
        updateAlerted(ld)
        return unify_det(ld, A3)''',
         new='''        updateAlerted(ld)
        return unify_det(ld, A3)'''),
    dict(id="P3-25 a redo of `$inference_limit_true` installs no limit (KILL il14 only: the looping clause is not stopped, the COUNTED dl_loop ends and the answer is 2-!; measured, fresh process)", file=P, targets=TD,
         old='''            ld.inference_limit_limit =
                ld.statistics.inferences + limit + INFERENCE_LIMIT_OVERHEAD
            updateAlerted(ld)''',
         new='''            ld.inference_limit_limit = INFERENCE_NO_LIMIT
            updateAlerted(ld)'''),
    dict(id="P3-26 `$inference_limit_true` with a bound Result still restores", file=P, targets=TD,
         equivalent="the boot calls it only on the branch where Result0 is unbound (`Result0 == inference_limit_exceeded -> !` takes the other)",
         old='''        PL_is_variable(ld, A3) || return FTRUE''',
         new=''''''),
    dict(id="P3-27 `$inference_limit_false` leaves the limit set (KILL il20)", file=P, targets=TD,
         old='''    olimit = get_inference_limit(ld, PL__t0)
    if olimit !== nothing
        ld.inference_limit_limit = olimit
        updateAlerted(ld)''',
         new='''    olimit = get_inference_limit(ld, PL__t0)
    if olimit !== nothing
        updateAlerted(ld)'''),
    dict(id="P3-28 `$inference_limit_except` re-throws the exceeded ball (KILL il03)", file=P, targets=TD,
         old='''    if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :inference_limit_exceeded))''',
         new='''    if false && a !== nothing && sym_key(a) == sym_key(mk_sym(T, :inference_limit_exceeded))'''),
    dict(id="P3-29 `$inference_limit_except` leaves the limit set (KILL il26: the recursion after an exceeded inner call, under a FINITE outer limit; il11's outer limit is `infinite`)", file=P, targets=TD,
         old='''    ld.inference_limit_limit = olimit
    updateAlerted(ld)

    a = PL_get_atom(ld, A2)''',
         new='''    updateAlerted(ld)

    a = PL_get_atom(ld, A2)'''),
    dict(id="P3-30 the wrapper's own predicates are not exempt (KILL il18: limit 0 trips in `$inference_limit/2`)", file=P, targets=TD,
         old='''        if lookupProcedure(mk_sym(T, Symbol(name)), arity, sysm).definition === def''',
         new='''        if false && lookupProcedure(mk_sym(T, Symbol(name)), arity, sysm).definition === def'''),
    dict(id="P3-31 catch/3 is not exempt (KILL il27: limit 0 trips at a catch/3 INSIDE the goal, before its own catch exists; il18 never reaches the line)", file=P, targets=TD,
         old='''    if gd.procedures_catch3.definition === def''',
         new='''    if false && gd.procedures_catch3.definition === def'''),
    # ---- pl-prims.c: $urgent_exception/3
    dict(id="P3-32 a tie takes the second ball (KILL ue03, ue10)", file=P, targets=TD,
         old='''    return PL_unify(ld, A3, Int(c2) > Int(c1) ? A2 : A1) ? FTRUE : FFALSE''',
         new='''    return PL_unify(ld, A3, Int(c2) >= Int(c1) ? A2 : A1) ? FTRUE : FFALSE'''),
    dict(id="P3-33 the less urgent ball wins (KILL ue01, ue04-ue09)", file=P, targets=TD,
         old='''    return PL_unify(ld, A3, Int(c2) > Int(c1) ? A2 : A1) ? FTRUE : FFALSE''',
         new='''    return PL_unify(ld, A3, Int(c2) < Int(c1) ? A2 : A1) ? FTRUE : FFALSE'''),
    # ---- pl-wam.c: updateAlerted, depart_alerted, the PL_Q_NODEBUG save and restore
    dict(id="P3-34 a depth limit sets no alert bit (KILL dl05: nothing is stopped)", file=W, targets=TV,
         old='''    ld.depth_info_limit != DEPTH_NO_LIMIT && (mask |= ALERT_DEPTHLIMIT)''',
         new='''    false && (mask |= ALERT_DEPTHLIMIT)'''),
    dict(id="P3-35 an inference limit sets no alert bit (KILL il03, il04, il11-il14, il18, il19, il21, il26: the loop is never stopped; dl_loop is COUNTED, so the rows end with `!`, not inference_limit_exceeded; measured in a fresh process, the earlier 900 s cut was the loaded machine, not a loop)", file=W, targets=TV,
         old='''    ld.inference_limit_limit != INFERENCE_NO_LIMIT && (mask |= ALERT_INFERENCELIMIT)''',
         new='''    false && (mask |= ALERT_INFERENCELIMIT)'''),
    dict(id="P3-36 a call does not look at the alert bits (KILL dl03-dl05, dl08-dl12, dl22, dl23, il03, il04, il11-il14, il18, il19, il21, il26: nothing is stopped, dl_loop is COUNTED and the rows end with `!`; measured, fresh process)", file=W, targets=TV,
         old='''    (ld.alerted & (ALERT_SIGNAL | ALERT_DEPTHLIMIT | ALERT_INFERENCELIMIT | ALERT_UNDO)) != 0 &&
        @goto depart_alerted''',
         new='''    (ld.alerted & ALERT_UNDO) != 0 &&
        @goto depart_alerted'''),
    dict(id="P3-37 the reached depth is never recorded (KILL dl03, dl04, dl10)", file=W, targets=TV,
         old='''    if da_depth > ld.depth_info_reached
        ld.depth_info_reached = da_depth
    end''',
         new='''    if false
        ld.depth_info_reached = da_depth
    end'''),
    dict(id="P3-38 the limit itself is allowed (KILL dl05, dl01: `>=` stops one level early)", file=W, targets=TV,
         old='''    if da_depth > ld.depth_info_limit''',
         new='''    if da_depth >= ld.depth_info_limit'''),
    dict(id="P3-39 a frame past the limit does not fail (KILL dl05: R is a number, not depth_limit_exceeded)", file=W, targets=TV,
         old='''        @goto deep_backtrack                        # FRAME_FAILED
    end
    # DIVERGES: upstream compares `uint64_t inferences` with `int64_t limit`, so the limit is converted to unsigned; a limit''',
         new='''    end
    # DIVERGES: upstream compares `uint64_t inferences` with `int64_t limit`, so the limit is converted to unsigned; a limit'''),
    dict(id="P3-40 the limit is reached one inference late (KILL il21/il22: the boundary of dl_chain(5))", file=W, targets=TV,
         old='''    if reinterpret(UInt64, ld.statistics.inferences) >=
        reinterpret(UInt64, ld.inference_limit_limit)''',
         new='''    if reinterpret(UInt64, ld.statistics.inferences) >
        reinterpret(UInt64, ld.inference_limit_limit)'''),
    dict(id="P3-41 the exception of an exceeded limit is not thrown (KILL il18 only: limit 0 answers `!` for inference_limit_exceeded; il03 still answers exceeded, the exception arrives anyway; measured, fresh process)", file=W, targets=TV,
         old='''        raiseInferenceLimitException(gd, ld)
        @LOAD_REGISTERS(QID)
        if ld.exception_term != 0
            @goto b_throw                           # THROW_EXCEPTION
        end''',
         new='''        raiseInferenceLimitException(gd, ld)
        @LOAD_REGISTERS(QID)'''),
    dict(id="P3-42 a PL_Q_NODEBUG query keeps the depth limit (KILL dl21: the portray hook is stopped, `dl_pt` is written)", file=W, targets=TV,
         old='''        ld.depth_info_limit = DEPTH_NO_LIMIT                # LD->depth_info.limit    = DEPTH_NO_LIMIT''',
         new='''        '''),
    dict(id="P3-43 a PL_Q_NODEBUG query does not give the depth limit back (KILL dl23: the recursion after it is no longer stopped)", file=W, targets=TV,
         old='''        ld.depth_info_limit = q.saved_depth_limit   #   LD->depth_info.limit   = qf->saved_depth_limit''',
         new='''        '''),
]
