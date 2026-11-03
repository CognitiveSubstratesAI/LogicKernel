# TAB1MIN handoff (writer 1, Sonnet, edit-only; audit D-0387 item 2; sizing: lk-channel evidence/R2/tab1min_sizing.md)

Branch wip/tab1min in /home/shivaji1012/code/lk-tab1, off origin/main f08167f. NOTHING is compiled or run: every line is UNVERIFIED.
NOT mine: T2 (pl-incl.jl `tabling` field, pl-proc.jl) and T3 (opcodes, pl-wam.jl, pl-vmi.jl numbers: Q3 is the audit's).

## Capability search (CLAUDE.md OPERATING RULES), main f08167f
`bash workflows/capability_search.sh <term>` covers Core/FabricPC/MORK/PathMap, not LogicKernel; the LogicKernel check is
`git grep -n -i <term> -- src` on the worktree (log: scratchpad t1w1-gitgrep.log). Results:
- tbl_trienode: found only in this plan. trienode: reserved symbol only (src/pl-atom.jl:964, :2023; src/pl-ressymbol.jl:18, :108).
- wrap_predicate: src/pl-ext.jl:1040 (meta-spec list entry `unwrap_predicate`), src/pl-supervisor.jl:21 (comment). closure_blob:
  a comment on closures at src/pl-wam.jl:3488. callwrapper: comments at src/pl-supervisor.jl:21, :53 (the DIVERGES T5 removes).
- S_WRAP, skipWrapperPrefix, resetWrappedSupervisor: found only in this plan. "tabling": only comments and flag notes (pl-prologflag.jl).

## Plan (commit order; each group committed, this file updated after each)
G0 plan (this file).
G1 T1: src/pl-tabling.jl (NEW) `'$tbl_trienode'/1`, `'$tbl_is_trienode'/1` (pl-tabling.c:6253-6277), PL_predicates_from_tabling;
   include in src/LogicKernel.jl before pl-ext.jl, registration in src/pl-ext.jl (the two tables, appended last).
G2 T1 rows: test/core_lang/test_tabling_min_swipl.jl + evidence/TAB1MIN generator/driver/pins from swipl 10.1.19 (two runs).
G3 T4: src/pl-wrap.jl (NEW) closure blob + `'$c_wrap_predicate'/5` + helpers. Needs T3's S_CALLWRAPPER/S_TABLED opcodes and T2's
   `tabling` flag bits: written against those NAMES; the file is not loadable before T3. Dependency recorded below.
G4 T5: freeCodesDefinition! wrapper branch, resetWrappedSupervisor, skipWrapperPrefix, unregisterWrappedSupervisor in
   src/pl-supervisor.jl (the DIVERGES at :64-72 goes). Needs only T4's closure type.
G5 T4/T5 rows (direct `$c_wrap_predicate` rows; the clause-add-after-wrap row that FAILS without T5).
G6 mutants tools/mutants/TAB1MIN.py (>= 8), manifest entries, docs/architecture.md block, final handoff.

## Status
(updated after each commit below)
