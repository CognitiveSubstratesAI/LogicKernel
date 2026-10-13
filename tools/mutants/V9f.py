# ORIGINAL: V9f's mutant list — no swipl-devel counterpart.
# tools/mutants/V9f.py — the mutation battery of step V9f (exceptions: catch/3, then `$/1`), run ONCE,
# at the step's close, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# V9f-a, catch/3 (MK1–MK21): the new path only. V9f-b adds its mutants below.
# Carried from V9e-1 (the meta-call): MC17, declared equivalent there and rerun at each later step's
# close; MC19, equivalent until catch/3 existed — its kill test is test_catch_swipl.jl's `cp5`.
#
# Targets, smallest first:
#   test/core_lang/test_catch_swipl.jl test/compile/test_body_code_swipl.jl
W = "src/pl-wam.jl"
C = "src/pl-comp.jl"
F = "src/pl-fli.jl"
P = "src/pl-prims.jl"
A = "src/pl-attvar.jl"
E = "src/pl-ext.jl"
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
    dict(id="MK19 the ball's variables keep their keys (no duplicate_term renaming)", file=F,
         old='''            push!(kids, get!(() -> mk_var(T, fresh_var_keys!(1)), fresh, var_key(c)))''',
         new='''            push!(kids, c)'''),              # kill: t26, t27, t28, and t24's shared variable
    dict(id="MK20 the ball's variables are renamed per occurrence (sharing lost)", file=F,
         old='''            push!(kids, get!(() -> mk_var(T, fresh_var_keys!(1)), fresh, var_key(c)))''',
         new='''            push!(kids, mk_var(T, fresh_var_keys!(1)))'''),   # kill: t27 (shared), t15
    dict(id="MK21 catch/3 is not locked", file=E,
         old='''    def.flags |= P_ISO | P_LOCKED''',
         new='''    def.flags |= P_ISO'''),                  # kill: t23 (assertz into catch/3)
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
