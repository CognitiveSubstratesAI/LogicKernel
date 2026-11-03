# EV1 gate agent 1 — state (forced hand-back at the 150k cap; daemon stopped by the dispatcher)

Lane ~/code/lk-ev1, branch wip/ev1b. Re-stacked onto origin/main dd93b68 (plain `git rebase`, 22 commits, ONE conflict: src/pl-modul.jl,
the old `_abolishProcedure_pristine` was removed by PR1b; resolved by dropping it and calling `destroy_event_list!(def)` in
`resetProcedure!` (src/pl-proc.jl), which is pl-proc.c:409's place). Nothing else conflicted.

## Commits after the re-stack (on top of the rebased handoff5 commit)
- 2e11449 MODIFIED: EV1 first-compile fixes (see its message). Compile traps found and fixed:
  * three short-form methods `f(...)::R where {T} = ...` (pl-proc.jl: the 4-arg _assertDefinition!, announceErasedClause, 3-arg
    cleanDefinition!) evaluate T at top level (the precompile died "UndefVarError T"): long form, same behaviour;
  * flag 13: event_list_at/event_list_set! now an if/elseif chain over the 7 hook field names (no getfield/setfield! on a runtime Symbol);
  * test_event_swipl.jl: a stray `"""function` (raw-string suffix error); `forall/member` do not exist in the kernel -> ev1_unl/ev1_rounds by
    recursion and ev1_retall (behaviour identical, swipl pins unchanged); the rows ev1p18 and the program's `ev1_m:` declaration/clause left
    out (boot/init.jl set_pattr! refuses a declaration for another module, R2 modules; a loader limit, not the port); ev1g01 now runs through
    `garbage_collect_clauses/0` (PR1 registered it; the white-box Julia call did not collect: generation of the closed query still held) and the
    white-box testset and _EV_WHITEBOX are gone; the non-vacuity "raised" count looks for the functor's codes `c[114,97,105,115,101,100]/1`
    (the pins are code-encoded; the old count was always 0).
- UNCOMMITTED when the cap hit (commit them first): docs/architecture.md (EV1 block: destroy_event_list! in resetProcedure!, abolishProcedure! calls it; the
  deferred list loses the "full abolish" item) and tools/mutants/EV1.py header lines (pl-modul.jl:1330 -> resetProcedure! in src/pl-proc.jl). Anchor check
  after both: EV1.py 48 mutants, BOOTPREDSUB.py 35, 0 bad (checker: .warm/ev1chk.py in the lane clone, untracked; NOT the shared scratchpad, another agent overwrote my file there).

## Gate steps done
- Step 2 (parse + run) on the REFERENCE type: test_event_swipl.jl 96/96 pass (80 rows + ev1g01 + non-vacuity + live swipl pins), after the fixes above.
  All 80 swipl-pinned rows agreed with the kernel at the first run: no port bug found, no engine change beyond typo level.
- The three-type run of test_event_swipl.jl: the daemon DIED during seq=7 (the dispatcher stopped it for the RD1c slot); NOT completed.
- test_bootpred3_swipl.jl: NOT run yet on the new stack. Nothing else of steps 3-8 done (no fmt, inventory, check, pins, pkgtest_way, push).

## READY TO RUN (when the dispatcher gives a slot back): in ~/code/lk-ev1
0. git status; commit the two uncommitted files (explicit paths, one commit).
1. `LOGICKERNEL_WARM_SECOND=1 tools/warm.sh start` (warm cache for the struct change exists in compiled/, so it should be quick).
2. `tools/warm.sh file test/core_lang/test_event_swipl.jl` (all three types, one call) then `... test_bootpred3_swipl.jl`; read SKIP/Warning lines.
   Expect bootpred3 rows: bp3l33 now swipl's; the others as handoff BOOTPRED3 (known differences pinned).
3. Optional rows for the NOT LISTED sites (swipl is a plain process, no daemon needed; generator evidence/EV1/gen_rows.py, see its header):
   ev1g02 a listener that throws during garbage_collect_clauses (kills `rcp[] = false`), a partial-unification unlisten (listeners ev1_pair(a,b),
   ev1_pair(z,c); unlisten ev1_pair(X,c): kills the PL_rewind_foreign_frame), an abolish of a predicate with listeners (kills destroy_event_list! in
   resetProcedure!); add the closures to the ev1_unl list; cases go at the END of _EV_CASES; rerun gen_rows.py twice (byte-identical) and --fill.
   The self-removing-listener snapshot stays NOT LISTED (private to the audit, D-0164). Declared equivalents C8, C9, C10 need file:line at the FINAL sha.
4. `warm.sh fmt` only diffs against HEAD: format the committed files through `warm.sh send` (JuliaFormatter on src/pl-event.jl, pl-proc.jl, pl-rec.jl,
   pl-wam.jl, pl-trace.jl, pl-copyterm.jl, pl-global.jl, pl-incl.jl, pl-modul.jl, the two test files, the manifest); rerun .warm/ev1chk.py on both mutant lists.
5. `warm.sh inventory` (commit the generated docs/port_inventory.md), `warm.sh check`, test/test_type_discipline.jl, test/static_analysis_fast.jl then
   test_static_analysis.jl, test_manifest_entries.jl (each `warm.sh file <f>`), then tools/pkgtest_way.sh for test_event_swipl.jl, then test_bootpred3_swipl.jl.
6. Alloc pins x3 types: test_zero_exports 239, test_local_stack 377, test/foreign/test_query 347, test_rules_swipl 433.
7. Crash-term grep over added diff lines + messages (hits are the event name `abort`/`:onabort`); copy tools/mutants/EV1.py to the file name of the
   mutants branch (mutants/EV1c -> tools/mutants/EV1c.py); author check; bare pushes at the SAME SHA: gate/ev1c, mutants/EV1c; one ci_status call.

## Daemon state
No daemon of mine is running (stopped by the dispatcher). The other slot (lk-lb4b2-run) untouched. Hook refusals: none except the cap and absence/empty-search warnings.
