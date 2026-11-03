# AUTOLOAD1 writer handoff (A1, A4, Q3; edit-only, nothing run, no daemon)
Branch wip/autoload1 off origin/main 9cc76fa, worktree ~/code/lk-autoload. Plan: evidence/R2/autoload1_sizing.md (channel). Rulings: D-0387 item 3.

## Plan (ordered)
1. A1: `trapUndefined(gd, ld, def)`, `getProcDefinedDefinition(gd, ld, def)`, 5 call sites (pl-wam.jl PL_open_query, mcall_cont, I_DEPART-family resolve, S_VIRGIN; pl-comp.jl clause/2), mcall_cont frame set-up (pl-vmi.c:5707-5722), manifest + test_module_path.jl + MOD3a/MOD3a2 mutant anchors. No behaviour change.
2. A4: `autoload` flag setter (setAutoload pl-prologflag.c:928-945, propagateAutoload :987-1000), boot pair pl-qlf.c:4798/4808 in boot_from_source!, rows from swipl 10.1.19.
3. Q3: loud error for an undefined predicate during bootsession (pl-proc.c:3027), own commit, DIVERGES.
4. Mutants tools/mutants/AUTOLOAD1.py, manifest entries, architecture.md block (last commits).

## State
(updated after every commit)
- A1 WRITTEN (commit below). Unrun: everything. Unverified spots: (a) the mcall_cont frame set-up compiles/behaves (never run); the frame is an index so upstream's `NFR = valTermRef(nref)` is not needed; (b) AllocCheck: the new mcall_cont block must add no allocation outside `getProcDefinedDefinition` frames (test/static_analysis_body.jl:256-270 attributes sites by span); (c) `ld` is carried by trapUndefined and read from A3 on; (d) MOD3a.py/MOD3a2.py mutant M2 anchor re-fitted to the new call text (still exactly once in src/pl-wam.jl).
- Overlap with in-flight gates: src/pl-proc.jl (trapUndefined only; EV1d edits resetProcedure!), src/pl-wam.jl (PL_open_query, mcall_cont, I_DEPART resolve, S_VIRGIN: ENG3 edits query_answers), src/pl-comp.jl clause/2 site. Expect one rebase.
