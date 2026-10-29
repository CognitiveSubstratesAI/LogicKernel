# ORIGINAL: SSU2's mutant list — no swipl-devel counterpart.
# tools/mutants/SSU2.py — the mutation battery of SSU2 (single sided unification run: pl-vmi.c I_CHP, I_SSU_CHOICE,
# I_SSU_COMMIT, S_SSU_DET and I_CUT's clear; pl-wam.c ssu_or_det_failed's FR_SSU_DET branch; pl-trace.c put_frame_goal;
# pl-supervisor.c chainPredicateSupervisor's S_SSU_DET, re-run where the calls show it), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as SSU1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_ssu_swipl.jl (rows named in each id's KILL; "D2 wb" is its query-API
# testset) and, for the asserted predicate's call, test/db/test_assert_swipl.jl. Hand-run before the commit (D-0104,
# `tools/mutate.sh run-in-tree`): verdicts in lk-channel evidence/SSU2/mutants_verdicts.tsv.
# The `old` strings are written in the repo's formatted style; RE-FIT any that `tools/warm.sh fmt` rewraps (mutate_drive.py
# refuses a string that does not occur exactly once). The two trail tests are the same line: each `old` starts at its label.
# Re-run from SSU1 (design §6: compile mutants that show only at execution): SSU1-C1 (`I_CHP` not emitted) as SSU2-R1.
# NOT LISTED:
#   * I_EXITCATCH / I_EXITCLEANUP marking the stepped-over CHP_DEBUG records `unlinked` (SSU2's representation line): EQUIVALENT
#     in effect, read not run — after I_EXITCATCH the catch frame exits deterministically (BFR is the CHP_CATCH's parent,
#     older than the frame), so `exit_continue`'s `lowerLTop!` drops every record above the frame before anything reads the
#     flag; after I_EXITCLEANUP either the same holds or a setup choice point of a callee frame stays, and the next failure
#     reaches it by `deep_backtrack` (its frame is not the failing one), whose `dropRecords!` drops them; the one reader,
#     `dropUnlinkedChoices!`'s assertion (shallow_backtrack, the LCO guard), needs the failing frame to own BFR. The marks keep
#     the pool invariant (V9d) true as stated. PENDING AUDIT.
#   * The `_no_record_above` assertion in I_SSU_COMMIT (design H3): a guard; removing it changes no verdict.
#   * The debugger branches (not ported).
TS = ["test/core_lang/test_ssu_swipl.jl"]
TB = ["test/db/test_assert_swipl.jl"]
TC = ["test/compile/test_ssu_compile_swipl.jl"]
TARGETS = TS + TB                                    # the baseline's targets (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
R = "src/pl-trace.jl"
S = "src/pl-supervisor.jl"
C = "src/pl-comp.jl"
MUTANTS = [
    # ── pl-vmi.c the trail tests ──
    dict(id="SSU2-T1 I_SSU_COMMIT's trail test `>` -> `>=`: no `=>` clause ever matches (KILL s01, s02, s10, d01, a01)", file=W, targets=TS + TB,
         old="    @label I_SSU_COMMIT\n    if length(ld.trail) > ld.choices[ld.BFR].mark.trailtop     # tTop > BFR->mark.trailtop\n",
         new="    @label I_SSU_COMMIT\n    if length(ld.trail) >= ld.choices[ld.BFR].mark.trailtop     # tTop > BFR->mark.trailtop\n"),
    dict(id="SSU2-T2 I_SSU_COMMIT without the trail test: the head may bind the goal (KILL s03, s07, s12, s22, s34, s36, H1 rows)", file=W, targets=TS,
         old="    @label I_SSU_COMMIT\n    if length(ld.trail) > ld.choices[ld.BFR].mark.trailtop     # tTop > BFR->mark.trailtop\n",
         new="    @label I_SSU_COMMIT\n    if false\n"),
    dict(id="SSU2-T3 I_SSU_CHOICE's trail test `>` -> `>=`: no `?=>` clause ever matches (KILL s16, s21, s47, s56, d04)", file=W, targets=TS,
         old="    @label I_SSU_CHOICE\n    if length(ld.trail) > ld.choices[ld.BFR].mark.trailtop     # tTop > BFR->mark.trailtop\n",
         new="    @label I_SSU_CHOICE\n    if length(ld.trail) >= ld.choices[ld.BFR].mark.trailtop     # tTop > BFR->mark.trailtop\n"),
    dict(id="SSU2-T4 I_SSU_CHOICE without the trail test: a moved unification binds the goal (KILL s14, s22, s25, s42, d03)", file=W, targets=TS,
         old="    @label I_SSU_CHOICE\n    if length(ld.trail) > ld.choices[ld.BFR].mark.trailtop     # tTop > BFR->mark.trailtop\n",
         new="    @label I_SSU_CHOICE\n    if false\n"),
    # ── pl-vmi.c I_CHP ──
    dict(id="SSU2-C1 I_CHP's condition inverted: a choice point only where the frame has one (KILL s01, d01, D2 wb)", file=W, targets=TS,
         old="    if ld.choices[ld.BFR].frame != FR               # if ( BFR->frame != FR )\n",
         new="    if ld.choices[ld.BFR].frame == FR               # if ( BFR->frame != FR )\n"),
    dict(id="SSU2-C2 I_CHP always pushes: I_SSU_COMMIT pops its own and leaves S_STATIC's CHP_CLAUSE (KILL d02, D2 wb dup; design H2)", file=W, targets=TS,
         old="    if ld.choices[ld.BFR].frame != FR               # if ( BFR->frame != FR )\n",
         new="    if true\n"),
    dict(id="SSU2-C3 I_CHP never pushes: a single clause tests the trail against the caller's mark and pops the caller's choice point (KILL s01, s26, d01, D2 wb)", file=W, targets=TS,
         old="    if ld.choices[ld.BFR].frame != FR               # if ( BFR->frame != FR )\n",
         new="    if false\n"),
    # ── pl-vmi.c I_SSU_COMMIT's commit ──
    dict(id="SSU2-P1 I_SSU_COMMIT does not pop the choice point (KILL d01, d02, D2 wb)", file=W, targets=TS,
         old="    ld.BFR = ld.choices[ssc_ch].parent              # BFR = BFR->parent\n    lowerLTop!(ld, ssc_base)                        # lTop = (LocalFrame)BFR\n",
         new="    nothing\n"),
    dict(id="SSU2-P2 I_SSU_COMMIT does not clear FR_SSU_DET: a failing body raises (KILL s15, s16)", file=W, targets=TS,
         old="    ld.frames[FR].flags &= ~FR_SSU_DET              # clearLocal(FR, FR_SSU_DET)\n",
         new="    nothing\n"),
    dict(id="SSU2-P3 I_SSU_CHOICE clears FR_SSU_DET: no redo error (KILL s48, s49, d03, D2 wb cmove)", file=W, targets=TS,
         old="    @goto I_ENTER                                   # VMI_GOTO(I_ENTER)\n\n    # PORT: pl-vmi.c I_SSU_COMMIT\n",
         new="    ld.frames[FR].flags &= ~FR_SSU_DET\n    @goto I_ENTER                                   # VMI_GOTO(I_ENTER)\n\n    # PORT: pl-vmi.c I_SSU_COMMIT\n"),
    # ── pl-vmi.c S_SSU_DET, pl-supervisor.c the chain ──
    dict(id="SSU2-S1 S_SSU_DET a no-op: no clause matching fails instead of raising (KILL s03, s04, s11, a04)", file=W, targets=TS,
         old="    ld.frames[FR].flags |= FR_SSU_DET               # setLocal(FR, FR_SSU_DET)\n",
         new="    nothing\n"),
    dict(id="SSU2-S2 the chain does not prepend S_SSU_DET (KILL s04, s11, a04; SSU1's v-rows)", file=S, targets=TS + TC,
         old="    if (def.flags & P_SSU_DET) != 0                 # ison(def, P_SSU_DET|P_DET) (P_DET: see above)\n",
         new="    if false\n"),
    # ── pl-vmi.c I_CUT ──
    dict(id="SSU2-K1 I_CUT does not clear FR_SSU_DET: a body failing after the guard's cut raises the matching-rule error (KILL s65, s66; V6a's equivalent, retired; s16/s50/d04 do not kill it: their bodies never fail after the cut, so the flag is never read — gate run 1 SURVIVED, rows added)", file=W, targets=TS,
         old="    ld.frames[FR].flags &= ~FR_SSU_DET              # clear(FR, FR_SSU_DET)\n",
         new="    nothing\n"),
    # ── pl-wam.c ssu_or_det_failed, pl-trace.c put_frame_goal ──
    dict(id="SSU2-E1 the SSU branch raises the determinism error (KILL s03, s04, s44, a04)", file=W, targets=TS,
         old="    if (ld.frames[fr].flags & FR_SSU_DET) == 0      # isoff(fr, FR_SSU_DET)\n",
         new="    if true\n"),
    dict(id="SSU2-E2 put_frame_goal never qualifies: the goal of a module's predicate is unqualified (KILL s58)", file=R, targets=TS,
         old="    if m.index != MODULE_user(gd).index && (m.flags & M_SYSTEM) == 0   # (|| SYSTEM_MODE: never)\n",
         new="    if false\n"),
    dict(id="SSU2-E3 put_frame_goal qualifies `user` too: `user:m(_, _)` (KILL s03, s04, s44)", file=R, targets=TS,
         old="    if m.index != MODULE_user(gd).index && (m.flags & M_SYSTEM) == 0   # (|| SYSTEM_MODE: never)\n",
         new="    if (m.flags & M_SYSTEM) == 0\n"),
    dict(id="SSU2-E4 put_frame_goal leaves the arguments fresh: the goal loses the caller's terms (KILL s04, s11, s36, s44)", file=R, targets=TS,
         old="            _cell_link!(ld, argp + i, argv + i)         # deRef2(argv+i, a); argp[i] = linked a\n",
         new="            nothing\n"),
    # ── re-run from SSU1 ──
    dict(id="SSU2-R1 (SSU1-C1 re-run) `I_CHP` not emitted: the trail test reads the caller's mark (KILL s01, d01, D2 wb)", file=C, targets=TS,
         old="        Output_0!(ci, I_CHP)\n",
         new="        nothing\n"),
]
