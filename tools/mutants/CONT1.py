# ORIGINAL: CONT1's mutant list — an LK-only list (the oracle half is the run rows of test_cont_run_swipl.jl, pinned from swipl 10.1.19).
# tools/mutants/CONT1.py — the mutation battery of CONT1 (continuations at run time): src/pl-wam.jl I_RESET, I_EXITRESET, I_CALLCONT,
# I_SHIFT / shift_common / I_SHIFTCP, I_YIELD and the FR_INRESET branch of i_metacall_common (pl-vmi.c:5529-5535, 5754-5915, 2410-2418),
# src/pl-cont.jl findReset, put_environment, put_continuation, shift, push_continuation (pl-cont.c:74-548), src/pl-gc.jl walk_and_mark
# and mark_active_environment (pl-gc.c:1866-2287). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's (as TOP1.py and AUTOLOAD1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and
# `targets`. Verdicts: written by the battery, not yet run. Every `old` was counted EXACTLY once in its file at the commit that adds this
# list (a text count by a python3 -I checker, no Julia); the anchors are short single-line substrings, RE-FIT any `old` that `tools/warm.sh
# fmt` rewraps. NOTHING here has run on the kernel: each KILL names the row EXPECTED to kill it (read in the row's goal and pin), the
# battery's verdict decides.
# KILL: test/core_lang/test_cont_run_swipl.jl (43 rows r_*, case lines 135-177, pins from evidence/CONT1/cr_rows.out) and
# test/core_lang/test_cont_boot_swipl.jl (rows c_reset .. c_yield, case lines 140-145).
# TARGETS (audit D-0238): the mutated code is reached through the booted system's reset/3, shift/1, shift_for_copy/1 and
# call_continuation/1; a grep over test/*/*.jl for `reset(`, `shift(`, `call_continuation`, `shift_for_copy` finds the two files above and
# test/compile/test_analyse_variables_swipl.jl, test/compile/test_body_code_swipl.jl, which only COMPILE those words as program text and
# never run them (so no mutant here is reachable from them). The FR_INRESET branch of i_metacall_common is also run by every
# control-construct call of test/core_lang/test_metacall_control.jl (it holds @testset and @test), listed for that mutant. Each listed file
# holds @testset and @test.
# NOT LISTED (each with its reason):
#   * the choice-slot restore of push_continuation (src/pl-cont.jl: the `ld.choices[chp].base == ichp` compare, the `> ichp` chain walk,
#     the `isTaggedIntW(c)` test), the `for_copy` arm of put_environment (the word 0 against `ld.slots[...]`), `sh_copy = true` of I_SHIFTCP,
#     and the choice-slot arms of walk_and_mark (clear_choice_mark, mark_choice_mark and the C_OR, C_NOT, C_IFTHEN, C_SOFTIF arms, whose
#     work is to decide which slots are active): swipl answers the SAME for a slot restored to its choice and a slot made the newest choice
#     (t_r_ite_cut for shift and t_r_ite_copy for shift_for_copy both answer [b]; t_r_twice and t_r_twice_fc agree), so no row of the
#     two files separates them. A row would need a program whose cut after the resume depends on an older choice point still standing.
#   * the attributed-variable arm of I_EXITRESET (`ier_k == DU_ATTVAR`): no row binds Cont to an attributed variable.
#   * the `PL_exception(ld, 0) == 0` uninstantiation error of shift (src/pl-cont.jl): no row shifts to a reset/3 whose Cont is already
#     bound (r_cont_bound reaches I_EXITRESET, not shift).
#   * walk_and_mark's mark/clear order for a variable written first and then read after the shift (mark_frame_var ignoring `clear`,
#     clear_frame_var a no-op): the only row printing slots (r_slots) writes its first variable BEFORE the shift.
#   * the C_JMP step and the control-construct arms of walk_and_mark: the shifting frames of the rows hold no control construct after
#     the shift (their remaining code is straight line up to I_EXIT).
#   * `ensureLocalSpace` and `ensureGlobalSpace` failures of push_continuation / put_environment: no row fills a stack.
RUN = ["test/core_lang/test_cont_run_swipl.jl", "test/core_lang/test_cont_boot_swipl.jl"]
RUNMC = RUN + ["test/core_lang/test_metacall_control.jl"]
RUN_ROWS = "test_cont_run_swipl.jl"
BOOT_ROWS = "test_cont_boot_swipl.jl"
W = "src/pl-wam.jl"
C = "src/pl-cont.jl"
G = "src/pl-gc.jl"
MUTANTS = [
    # ── pl-vmi.c I_CALL1 FR_INRESET branch, I_RESET, I_EXITRESET ──
    dict(id="CONT1-R1 I_RESET does not set FR_INRESET on the reset/3 frame (KILL test_cont_run_swipl.jl:157 r_meta_len, :148 r_meta_shift)",
         file=W, targets=RUN,
         old="ld.frames[FR].flags |= FR_INRESET",
         new="nothing"),
    dict(id="CONT1-R2 a control construct under FR_INRESET is compiled to a temporary clause, not called through $meta_call (KILL test_cont_run_swipl.jl:157 r_meta_len, :149 r_meta_resume)",
         file=W, targets=RUNMC,
         old="if (ld.frames[FR].flags & FR_INRESET) != 0",
         new="if false"),
    dict(id="CONT1-R3 I_RESET does not test for an unbound goal (KILL test_cont_run_swipl.jl:156 r_var_goal_ctx: the error context becomes call/1's)",
         file=W, targets=RUN,
         old="if _slot_is_var(ld, ir_p + 1)",
         new="if false"),
    dict(id="CONT1-R4 I_EXITRESET binds Cont to 1 (KILL test_cont_run_swipl.jl:135 r_noshift, :162 r_iter, test_cont_boot_swipl.jl:140 c_reset)",
         file=W, targets=RUN,
         old="bindConst(ld, ier_p, consInt(Int64(0)))",
         new="bindConst(ld, ier_p, consInt(Int64(1)))"),
    dict(id="CONT1-R5 I_EXITRESET never binds Cont (always the uninstantiation error) (KILL test_cont_run_swipl.jl:135 r_noshift, :163 r_iter_empty, test_cont_boot_swipl.jl:140 c_reset)",
         file=W, targets=RUN,
         old="if ier_k == DU_CELL || ier_k == DU_ATTVAR",
         new="if false"),
    dict(id="CONT1-R6 I_EXITRESET binds Cont also when it is bound (KILL test_cont_run_swipl.jl:139 r_cont_bound)",
         file=W, targets=RUN,
         old="if ier_k == DU_CELL || ier_k == DU_ATTVAR",
         new="if true"),
    # ── pl-vmi.c I_CALLCONT, I_SHIFT / shift_common, I_YIELD ──
    dict(id="CONT1-V1 I_CALLCONT does not take the call(Goal) shortcut (KILL test_cont_run_swipl.jl:158 r_catch_shift, :160 r_nested_resume: their list holds call(catch(..)))",
         file=W, targets=RUN,
         old="ld.gstack[valPtr(cc_w)] == _cont_functor(ld, :call, 1)",
         new="ld.gstack[valPtr(cc_w)] == _cont_functor(ld, :call, 2)"),
    dict(id="CONT1-V2 I_YIELD raises its permission error only INSIDE an engine (KILL test_cont_run_swipl.jl:177 r_yield_out, test_cont_boot_swipl.jl:145 c_yield: the engine branch refuses by name instead)",
         file=W, targets=RUN,
         old="PL_Q_ALLOW_YIELD) == 0",
         new="PL_Q_ALLOW_YIELD) != 0"),
    dict(id="CONT1-V3 shift_common does not raise lTop to the foreign frame before closing it (KILL test_cont_run_swipl.jl:313 t_lt_shift, :314 t_lt_copy, :317 t_lt_cont (the lTop white-box rows: lowerLTop! asserts p <= lTop, so the shifting row ends in an error where swipl answers `same`), also :148 r_meta_shift, :162 r_iter)",
         file=W, targets=RUN,
         old="if ld.lTop < sh_fid",
         new="if false"),
    # ── pl-cont.c findReset, shift ──
    dict(id="CONT1-S1 findReset does not stop at a findall_loop/4 frame (KILL test_cont_run_swipl.jl:144 r_shift_findall, :143 r_shift_findall_msg)",
         file=C, targets=RUN,
         old="f.predicate === proc_fl.definition && return",
         new="false && return"),
    dict(id="CONT1-S2 findReset takes the first reset/3 frame without unifying the ball (KILL test_cont_run_swipl.jl:145 r_nested, :146 r_nested_inner)",
         file=C, targets=RUN,
         old="rc = PL_unify(ld, argFrameP(f.base, 1), ball)",
         new="rc = true"),
    dict(id=r"CONT1-S3 findReset reports the findall message when no reset/3 frame exists (KILL test_cont_run_swipl.jl:142 r_shift_out_msg)",
         file=C, targets=RUN,
         old="return (FRESET_NO_FRAME, 0)",
         new="return (FRESET_FINDALL, 0)"),
    dict(id="CONT1-S4 findReset looks for the tabled '$tbl_reset'/6 frame no more (EQUIVALENT until TAB1)",
         file=C, targets=RUN,
         old="if f.predicate === reset3 || f.predicate === reset6",
         new="if f.predicate === reset3",
         equivalent="no frame of '$tbl_reset'/6 is ever entered: src/pl-wam.jl I_RESET (the `procedures_dtbl_reset6` test, ~3306) throws NotPortedError owner TAB1 before the goal runs, and no clause of the booted system calls '$tbl_reset'/6 without tabling; TAB1 re-runs it"),
    dict(id="CONT1-S5 shift returns into the reset/3 frame itself, not its parent (KILL test_cont_run_swipl.jl:148 r_meta_shift, :162 r_iter)",
         file=C, targets=RUN,
         old="ld.environment_frame = rf.parent",
         new="ld.environment_frame = resetfr"),
    # ── pl-cont.c put_environment, put_continuation ──
    dict(id="CONT1-E1 put_environment stores the PC without subtracting 1 (KILL test_cont_run_swipl.jl:162 r_iter, :164 r_effect, :165 r_twice: the clause resumes one word late)",
         file=C, targets=RUN,
         old="consInt(Int64(pc - 1))",
         new="consInt(Int64(pc))"),
    dict(id="CONT1-E2 put_environment stores [] for a TRANSPARENT frame (KILL test_cont_run_swipl.jl:173 r_ctx: context_module/1 after the resume)",
         file=C, targets=RUN,
         old="flags & P_TRANSPARENT == 0",
         new="flags & P_TRANSPARENT != 0"),
    dict(id="CONT1-E3 put_environment marks every slot active (KILL test_cont_run_swipl.jl:172 r_slots: the pin holds <inactive> for X and W)",
         file=C, targets=RUN,
         old="if active[i + 1]   ",
         new="if true   "),
    dict(id="CONT1-E4 put_environment marks no slot active (KILL test_cont_run_swipl.jl:172 r_slots, :155 r_late: Y = f(X) must see X = 1)",
         file=C, targets=RUN,
         old="if active[i + 1]   ",
         new="if false   "),
    dict(id="CONT1-E5 put_continuation adds the '$cont$' of a frame with a LAST call (KILL test_cont_run_swipl.jl:171 r_lco: the list is empty)",
         file=C, targets=RUN,
         old="if !is_last_call(pc)",
         new="if true"),
    dict(id="CONT1-E6 put_continuation treats a catch/3 or reset/3 frame as an ordinary frame (KILL test_cont_run_swipl.jl:159 r_catch_len, :158 r_catch_shift)",
         file=C, targets=RUN,
         old="if env_f != word(0)",
         new="if false"),
    # ── pl-cont.c push_continuation ──
    dict(id="CONT1-P1 push_continuation accepts one slot fewer (KILL test_cont_run_swipl.jl:175 r_type_arity; every resume raises type_error: :162 r_iter)",
         file=C, targets=RUN,
         old="arity != Int(cl.variables) + 3",
         new="arity != Int(cl.variables) + 2"),
    dict(id="CONT1-P2 push_continuation swaps the nil test of the context (KILL test_cont_run_swipl.jl:173 r_ctx)",
         file=C, targets=RUN,
         old="if is_nil(mname)",
         new="if !is_nil(mname)"),
    dict(id="CONT1-P3 push_continuation resumes at the offset itself, not the offset + 1 (KILL test_cont_run_swipl.jl:162 r_iter, :164 r_effect, :165 r_twice)",
         file=C, targets=RUN,
         old="pcoffset + 1)",
         new="pcoffset)"),
    # ── pl-gc.c walk_and_mark, mark_active_environment ──
    dict(id="CONT1-W1 mark_frame_var marks nothing (KILL test_cont_run_swipl.jl:172 r_slots: the pin holds f(V0,1) and V1, not <inactive>)",
         file=G, targets=RUN,
         old="state.clear[i] || (state.active[i] = true)  # if",
         new="nothing  # if"),
    dict(id="CONT1-W2 walk_and_mark leaves out B_UNIFY_VAR, the read of a variable by Var = Term (KILL test_cont_run_swipl.jl:172 r_slots: Z = g(Y) must keep Z active)",
         file=G, targets=RUN,
         old="elseif op == B_UNIFY_VAR ",
         new="elseif op == B_UNIFY_VAR && false "),
    dict(id="CONT1-W3 mark_active_environment walks on past I_EXIT (KILL test_cont_run_swipl.jl:148 r_meta_shift, :162 r_iter: the walk leaves the clause's code)",
         file=G, targets=RUN,
         old="walk_and_mark(state, codes, pc, I_EXIT)",
         new="walk_and_mark(state, codes, pc, I_EXITFACT)"),
]
