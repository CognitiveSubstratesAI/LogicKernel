# ORIGINAL: V9f's mutant list — no swipl-devel counterpart.
# tools/mutants/V9f.py — the mutation battery of step V9f (exceptions: catch/3, then `$/1`), run ONCE,
# at the step's close, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# V9f-a, catch/3 (MK1–MK18, MK21, MK22): the new path only. V9f-b, `$/1` and `$/0` (MD1–MD22).
# Carried from V9e-1 (the meta-call): MC17, declared equivalent there and rerun at each later step's
# close; MC19, equivalent until catch/3 existed — its kill test is test_catch_swipl.jl's `cp5`.
#
# Targets, smallest first:
#   test/core_lang/test_catch_swipl.jl test/core_lang/test_det_swipl.jl
#   test/compile/test_body_code_swipl.jl
W = "src/pl-wam.jl"
C = "src/pl-comp.jl"
F = "src/pl-fli.jl"
P = "src/pl-prims.jl"
A = "src/pl-attvar.jl"
E = "src/pl-ext.jl"
R = "src/pl-error.jl"
MUTANTS = [
    # ── findCatcher ──
    dict(id="MK1 findCatcher ignores FR_CAUGHT (a ball from the recovery is caught by the same catch/3)", file=W,
         old='''            (f.flags & FR_CAUGHT) == 0 &&               # not thrown from recover''',
         new='''            true &&'''),                    # kill: t22 (rg/2's clause choice keeps `fr <= ch` true)
    dict(id="MK2 findCatcher ignores `fr <= ch` (the call port of catch/3)", file=W,
         old='''            f.base <= chpos                              # not call-port of catch/3''',
         new='''            true'''
         # PENDING AUDIT, not declared (the battery's verdict decides): probably EQUIVALENT. Between
         # the frame becoming the environment (I_ENTER) and I_CATCH's newChoice nothing can raise
         # (the debugger's call port is not ported); after it CHP_CATCH at argFrameP(FR, 3) lies
         # above the frame until the catch itself discards it (findCatcher has set FR_CAUGHT first),
         # I_EXITCATCH drops it (FR_CAUGHT set) or deep_backtrack pops it (the frame is left).
         ),
    dict(id="MK3 findCatcher does not set FR_CAUGHT on a match", file=W,
         old='''                PL_put_term(ld, ld.exception_term, ex)
                f.flags |= FR_CAUGHT
                return fr''',
         new='''                PL_put_term(ld, ld.exception_term, ex)
                return fr'''),                      # kill: t22
    dict(id="MK4 findCatcher runs with the exception pending (no saveWakeup)", file=A,
         old='''            ld.slots[s + 1] = ld.slots[ld.exception_term + 1]
            ld.exception_term = 0''',
         new='''            ld.slots[s + 1] = ld.slots[ld.exception_term + 1]'''),   # kill: the occurs_check testset (t24)
    dict(id="MK5 an exception from the catcher's unification does not become the ball", file=W,
         old='''            elseif ld.exception_term != 0               # Exception from PL_unify()
                PL_put_term(ld, ex, ld.exception_term)
            end''',
         new='''            end'''),                        # kill: the occurs_check testset (t24, t25)
    dict(id="MK6 restoreWakeup does not make the saved exception pending again", file=A,
         old='''                elseif (state.flags & WAKEUP_STATE_SKIP_EXCEPTION) == 0
                    restore_exception(ld, p)''',
         new='''                elseif false
                    restore_exception(ld, p)'''),   # exception_term stays 0: PL_put_term(0, ex) — every caught ball
    # ── b_throw_unwind / b_throw_resume ──
    dict(id="MK7 b_throw_unwind does not stop at the catcher", file=W,
         old='''    while FR != 0 && (bt_catchfr == 0 || ld.frames[FR].base > ld.frames[bt_catchfr].base)''',
         new='''    while FR != 0 && (true || ld.frames[FR].base > ld.frames[bt_catchfr].base)'''),
    dict(id="MK8 b_throw_resume does not unify the catcher again", file=W,
         old='''        PL_unify(ld, argFrameP(br_base, 1), ld.exception_term)      # re-unify''',
         new='''        nothing'''),                        # kill: t1 (E unbound)
    dict(id="MK9 the recover goal runs above lTop = argFrameP(FR, 5)", file=W,
         old='''        setLTop!(ld, argFrameP(br_base, 3))                         # above the catch/3''',
         new='''        setLTop!(ld, argFrameP(br_base, 5))'''),   # kill: cp4 (the recover goal's frame position)
    dict(id="MK10 findCatchExit answers catch/3's first code (the goal is called again after the recovery)", file=W,
         old='''    return Code{T}(cl.codes, cl.literals, n)''',
         new='''    return Code{T}(cl.codes, cl.literals, 1)'''),
    dict(id="MK11 the catcher branch does not clear the exception", file=W,
         old='''        resumeAfterException(ld, true, bt_outofstack)
        @LOAD_REGISTERS(QID)
        @goto I_CALL1''',
         new='''        resumeAfterException(ld, false, bt_outofstack)
        @LOAD_REGISTERS(QID)
        @goto I_CALL1'''),
    # ── I_EXITCATCH, deep_backtrack ──
    dict(id="MK12 I_EXITCATCH leaves its CHP_CATCH on the chain (the last answer not deterministic)", file=W,
         old='''        ld.BFR = ld.choices[iec_b].parent
        ld.choices[iec_b].unlinked = true''',
         new='''        ld.choices[iec_b].unlinked = true'''),
    dict(id="MK13 I_EXITCATCH does not mark the record unlinked (the pool check)", file=W,
         old='''        ld.BFR = ld.choices[iec_b].parent
        ld.choices[iec_b].unlinked = true''',
         new='''        ld.BFR = ld.choices[iec_b].parent'''),
    dict(id="MK14 deep_backtrack has no CHP_CATCH case", file=W,
         old='''    elseif db_c.type == CHP_CATCH                   # catch/3 & setup_call_cleanup/3''',
         new='''    elseif false'''),
    # ── the compiler, the predicates, the ball ──
    dict(id="MK15 `$catch` compiles to I_CATCH alone", file=C,
         old='''            Output_0!(ci, I_CATCH)
            Output_0!(ci, I_EXITCATCH)''',
         new='''            Output_0!(ci, I_CATCH)'''),
    dict(id="MK16 I_CATCH decompiles to `true`", file=C,
         old='''            push!(di.argp, mk_sym(T, Symbol("\\$catch")))''',
         new='''            push!(di.argp, mk_sym(T, :true))'''),
    dict(id="MK17 true/0 the predicate fails", file=P,
         old='''pl_true(ld::PL_local_data{T}) where {T} = FTRUE''',
         new='''pl_true(ld::PL_local_data{T}) where {T} = FFALSE'''),
    dict(id="MK18 fail/0 the predicate succeeds", file=P,
         old='''pl_fail(ld::PL_local_data{T}) where {T} = FFALSE''',
         new='''pl_fail(ld::PL_local_data{T}) where {T} = FTRUE'''),
    # (MK19, MK20 — the ball's variable renaming — went with V9f-a's own copy routine: since the
    # copy_term merge the ball copy IS `copy_term` without sharing, whose mutants are V9g's)
    dict(id="MK22 copy_exception keeps the copy's trail entries (a cyclic ball loses its cycle at the unwind)", file=F,
         old='''    resize!(ld.trail, tt)                       # frozen: the copy's own bindings keep no trail entry''',
         new='''    nothing'''),                         # kill: t29
    dict(id="MK21 catch/3 is not locked", file=E,
         old='''    def.flags |= P_ISO | P_LOCKED''',
         new='''    def.flags |= P_ISO'''),                  # kill: t23 (assertz into catch/3)
    # ── V9f-b: `$/1`, `$/0` (kill tests: test_det_swipl.jl unless said) ──
    dict(id="MD1 I_DET does not mark the frame as the one that ran `$` (FR_DETGUARD_SET)", file=W,
         old='''    ld.frames[FR].flags |= FR_DETGUARD | FR_DETGUARD_SET       # set(FR, FR_DETGUARD|FR_DETGUARD_SET)''',
         new='''    ld.frames[FR].flags |= FR_DETGUARD'''),      # kill: d19, d23 (`guard`)
    dict(id="MD2 I_DET sets no guard", file=W,
         old='''    ld.frames[FR].flags |= FR_DETGUARD | FR_DETGUARD_SET       # set(FR, FR_DETGUARD|FR_DETGUARD_SET)''',
         new='''    nothing'''),
    dict(id="MD3 C_DETTRUE leaves the block's choice-point record linked in the pool", file=W,
         old='''        ld.choices[cdt_ch].unlinked = true
''',
         new=''''''),                                # kill: the pools at d13's answers
    dict(id="MD4 C_DETTRUE takes every goal for deterministic", file=W,
         old='''    if cdt_parent != 0 && ld.choices[cdt_parent].base == cdt_och    # ch->parent == och''',
         new='''    if cdt_parent != 0'''),
    dict(id="MD5 C_DETTRUE reports a failure where the goal left a choice point", file=W,
         old='''    det_goal_error(ld, FR, PC - 1, :nondet)''',
         new='''    det_goal_error(ld, FR, PC - 1, :fail)'''),
    dict(id="MD6 C_DETFALSE reports a choice point where the goal failed", file=W,
         old='''    det_goal_error(ld, FR, PC - 1, :fail)''',
         new='''    det_goal_error(ld, FR, PC - 1, :nondet)'''),
    dict(id="MD7 a nondeterministic exit of a guarded frame is not checked", file=W,
         old='''            determinism_error(ld, FR, ld.BFR, :nondet)''',
         new='''            nothing'''),
    dict(id="MD8 a guarded frame left by failure is not reported", file=W,
         old='''            frameFailed(ld, FR)''',
         new='''            nothing'''),
    dict(id="MD9 S_STATIC pushes no CHP_DEBUG for a guarded frame no clause matches", file=W,
         old='''            newChoice(ld, CHP_DEBUG, FR)            # (`debugstatus.debugging`: no debugger)''',
         new='''            nothing'''),             # kill: `warning` — t21(c) reports twice
    dict(id="MD10 backtracking into a guarded frame's CHP_DEBUG reports nothing", file=W,
         old='''            db_rc = ssu_or_det_failed(ld, FR)''',
         new='''            db_rc = true'''),         # kill: `warning` — t21(c) reports twice
    dict(id="MD11 determinism_error: the frame a last call reused reports `guard`", file=W,
         old='''                decl = :guard_in_caller''',
         new='''                decl = :guard'''),
    dict(id="MD12 determinism_error ignores `silent`", file=W,
         old='''    a = ld.prolog_flag_determinism_error
    a === :silent && return true

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        f = ld.frames[fr]''',
         new='''    a = ld.prolog_flag_determinism_error

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        f = ld.frames[fr]'''),
    dict(id="MD13 determinism_error raises under `warning`", file=W,
         old='''        if a === :warning
            gd = _query_gd(ld)''',
         new='''        if false
            gd = _query_gd(ld)'''),
    dict(id="MD14 det_goal_error ignores `silent`", file=C,
         old='''    pc_det = start_of_cdet(cl, pc_error)
    a = ld.prolog_flag_determinism_error
    a === :silent && return true''',
         new='''    pc_det = start_of_cdet(cl, pc_error)
    a = ld.prolog_flag_determinism_error'''),
    dict(id="MD15 det_goal_error decompiles a failed goal over stale frame cells", file=C,
         old='''        clearUninitialisedVarsFrame(ld, fr, cl.codes, pc_det)''',
         new='''        nothing'''),                  # kill: d38 (`q3(A,g2,g3)`)
    dict(id="MD16 start_of_cdet takes the outer block for an inner C_DETTRUE", file=C,
         old='''                        found = false                           # goto continue_outer''',
         new='''                        found = true'''),   # kill: d7, and the white-box test
    dict(id="MD17 the goal atom `$` compiles to a plain cut", file=C,
         old='''            Output_0!(ci, I_DET)''',
         new='''            Output_0!(ci, I_CUT)'''),
    dict(id="MD18 `$(Goal)` is compiled without the fresh variables of its failure exit", file=C,
         old='''        else                                                   # $(Goal)
            balanceVars(vsave, ci.used_var, ci)''',
         new='''        else                                                   # $(Goal)
            nothing'''),                           # kill: test_body_code_swipl.jl (`$ sets a variable`)
    dict(id="MD19 the decompiler rebuilds `$(Goal)` as `\\+ Goal`", file=C,
         old='''            build_term!(di, mk_sym(T, Symbol("\\$")), 1)''',
         new='''            build_term!(di, mk_sym(T, Symbol("\\\\+")), 1)'''),
    dict(id="MD20 the goal clauses' predicate is `$call`, not upstream's `<meta-call>`", file=E,
         old='''Symbol("<meta-call>")''',
         new='''Symbol("\\$call")'''),               # kill: d32's context
    dict(id="MD21 ERR_DET_GOAL declares `guard`", file=R,
         old='''            found,
            mk_sym(T, :goal)
        ]''',
         new='''            found,
            mk_sym(T, :guard)
        ]'''),
    dict(id="MD22 frameFailed does not move lTop over the failed frame's arguments", file=W,
         old='''    setLTop!(ld, argFrameP(f.base, (f.predicate::Definition{T}).arity))

    if (f.flags & (FR_SSU_DET | FR_DET | FR_DETGUARD)) != 0''',
         new='''    if (f.flags & (FR_SSU_DET | FR_DET | FR_DETGUARD)) != 0'''
         # PENDING AUDIT, not declared (the battery's verdict decides): upstream sets lTop so the
         # foreign frame PL_error opens cannot overwrite the frame's arguments; here the frame is
         # read only for its predicate and flags after that, so this may be EQUIVALENT.
         ),
    # ── carried from V9e-1 ──
    dict(id="MC17 mcall_cont does not set the next frame's flags", file=W,
         old='''    @label mcall_cont
    setNextFrameFlags(ld.frames[NFR], ld.frames[FR])''',
         new='''    @label mcall_cont
    nothing''',
         equivalent="src/pl-wam.jl mcall_cont: setNextFrameFlags writes the new frame's level and flags, and nothing reads them yet — `level` is read nowhere in src/, the flags only by asserts that they are CLEAR (FR_WATCHED, FR_INRESET); the debugger, depth_limit and prolog_frame_attribute are not ported (the same for I_CALL's own call)"),
    dict(id="MC19 the stripModule failure raises lTop over the frame before THROW_EXCEPTION", file=W,
         old='''    mc_ok || @goto b_throw                          # THROW_EXCEPTION''',
         new='''    if !mc_ok
        setLTop!(ld, argFrameP(mc_nb, 1))
        @goto b_throw
    end'''),                                     # kill: cp5 (a frame position after the caught error)
]
