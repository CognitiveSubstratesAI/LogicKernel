# DSTACK restack3 — A and B re-stacked onto origin/main d334065 (MOD6 landed). EDIT-ONLY: git only, nothing compiled or run

Base: origin/main d334065 (fetched 2026-11-01; unmoved during the restack). New branches, no force, old ones untouched.

## New SHAs
| landing | branch | tip / code SHA | old |
|---|---|---|---|
| A = G1 + D2 | wip/dstack-a2 | 568fa9b899341a9adadffbb345bdc4d7d698d0d3 (30 commits on d334065) | wip/dstack-a 3b8f8aa |
| B = O1B + O1A + F1b | wip/dstack-b2 | code SHA cc78b9af53a7481513d05b4f0b9d650caf40ee56 (62 commits on the A2 tip); tip = split.md commit + this file (`git log -1 wip/dstack-b2`) | wip/dstack-b code 7f0b41e |

Order of the pick: `git cherry-pick e863f77..3b8f8aa` (A), `3b8f8aa..7f0b41e` (B), then 80c9d10 (split.md, updated for the new SHAs and the MOD6 base).
Commit hook: no refusal; no commit was made with a bypass.

## Conflicts and how they were resolved
A (2 stops, both in the LD-struct places that MOD6 touched):
1. a93743b (G1 fields): src/pl-global.jl (doc comment, struct, constructor) and src/pl-fli.jl live_states. Kept MOD6's `module_enums` where main has it (the last field), G1's `gvar_nb_vars, gvar_grefs, gvar_enums` right after; the constructor's `foreign_state_pool{module_enum}()` got its trailing comma; the doc comment keeps MOD6's line then G1's (the duplicated "the pool of current_prolog_flag/2's states." line dropped).
2. 5292ca1 (D2 fields): src/pl-fli.jl live_states only (pl-global.jl merged by git: `recorded_states` after `gvar_enums`; GD `record_lists, record_lists_order, record_refs` no conflict). Final: `ld.prolog_flag_enums.live + ld.module_enums.live + ld.gvar_enums.live + ld.recorded_states.live`.

B (1 stop): the first pick (docs/port_inventory.md, content conflict): took main's (`--ours`); the gate regenerates it (`warm.sh inventory`). pl-global.jl / pl-ext.jl / docs/architecture.md / manifest merged WITHOUT conflict in B; F1b's deletions and O1B's `IO_output_stack` land after the A fields.

Textually clean but read: src/pl-ext.jl (MOD6 adds nothing there; `PL_predicates_from_module` was already in both tables, so nothing was kept or lost; gvar between attvar and dict in both `_PRED_TABLES` and `_FOREIGN_VA`, redirect/format at O1's place), src/LogicKernel.jl include order, docs/architecture.md (MOD6, G1, D2, O1B, O1A sections all present: `## MOD6` before `## D1`, `## G1`..`## O1A` before "Still to come").

## Final PL_local_data order (struct = constructor, same position; a throwaway python counter zips field names with constructor arguments)
... prolog_flag_access_level, module_enums (MOD6), gvar_nb_vars, gvar_grefs, gvar_enums (G1), recorded_states (D2), IO_output_stack (O1B).

| tree | GD struct/ctor | LD struct/ctor |
|---|---|---|
| main d334065 | 36/36 | 119/119 |
| A2 | 39/39 | 123/123 |
| B2 | 39/39 | 118/118 (119 + 4 + 1 - 6 deleted by F1b) |

Cross-check: B2's field list and argument list equal wip/dstack-b's with `module_enums` inserted after `prolog_flag_access_level` (python, both true). Other `PL_local_data{T}(...)` sites in src, test and tools take only `gd`: unaffected. The positional call in pl-global.jl is the only one.

## Tree equivalence
- `git diff wip/dstack-b wip/dstack-b2 -- src test tools` = exactly the MOD6 delta (pl-fli, pl-global, pl-incl, pl-modul, test_module_enum_swipl.jl, manifest +10, tools/mutants/MOD6d.py); the +/- line multiset equals `git diff e863f77 d334065 -- src test tools` except the merge lines of pl-global.jl and pl-fli.jl (the comma after the `module_enum` constructor argument, the position of the `ACCESS_LEVEL_USER` comma, `live_states` with G1/D2, the doc comment). The same check holds for A2 against wip/dstack-a.
- docs/architecture.md: only additions against old B (MOD6's section); docs/port_inventory.md = main's (stale for the stack; the gate's `warm.sh inventory` regenerates it); evidence differs by MOD6's files and split.md.
- No conflict marker in src, test, tools, docs, evidence, boot at the B2 tip (git grep); test/static_analysis_manifest.jl brackets balanced (python scan, strings and comments skipped).

## Mutant list validators (python: every `old` once in its file, new != old, ids unique, targets on disk; /tmp/claude-1000/g3_val.py)
- A2 tree: G1 20, D2 45, D1c 100: 0 bad.
- B2 tree: O1B 23, O1A 130, F1B 22, G1 20, D2 45, D1c 100, MOD6d 34: 0 bad.
- MOD3a 18 / SSU1 28 / V9f 44: 9 stale anchors (MOD3a-S1, MOD3a-S2, SSU1-R4, SSU1-S1, V9f MK4, MK16, MK22, MD7, MD21), the same nine on wip/dstack-b AND on origin/main d334065 itself: not the restack's, not touched (MOD3a-S1's anchor `if tm === ci.module_` reads `elseif tm === ci.module_` in the formatted pl-comp.jl of MOD3b). They need a re-fit before anyone runs those three lists; flag for the dispatcher.
- F1B is 22 mutants on both the old and the new tree (earlier notes said 23).

## Gates still to run (per evidence/DSTACK/split.md; nothing was compiled)
Per landing, A first: `warm.sh fmt`, `warm.sh inventory`, `warm.sh check` (with the Pkg.test-way run), changed test files x 3 term types (A: test_gvar_swipl.jl, test_record_swipl.jl; B: the 12 files of split.md), test_type_discipline.jl, pins x3 (test_zero_exports, test_ball_cells: the LD order above is new against r3 and the first compile checks the constructor positions), FULL static, `tools/pkgtest_way.sh <file>` one at a time, push `mutants/<STEP>` at the WIP SHA, branch-gate, crash-term grep, `gate/*` + `mutants/*` at the same SHA. B after A is green (B2 sits on the A2 tip; an A-gate fixup commit re-stacks B under a new name). MOD6's own test file (test/core_lang/test_module_enum_swipl.jl) is main's and unchanged, but it reads the same LD struct and `live_states`: run it x3 on A2.
Daemon: none started, none used by this step.
