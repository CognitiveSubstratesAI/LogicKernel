# DSTACK — the linear stack wip/dstack = G1, D2, O1, F1b (integrator, edit-only; NOTHING compiled or run)

Branch wip/dstack off main faee65f, linear (git cherry-pick, no merge commit). Source branches untouched: wip/g1 (bf41225..), wip/d2 (bf41225..),
wip/o1 (faee65f..), wip/f1b (faee65f..). Each step's own handoff stays in the tree: evidence/G1/handoff.md, evidence/D2/handoff.md, evidence/O1/handoff.md,
evidence/F1B/handoff.md (detail, UNVERIFIED lists and audit flags are THERE and are not decided here).

## STATE (partial commit after G1 + D2)
- G1: 15 picks, NO conflict. Boundary SHA (last G1 commit, the G1 handoff): 5aa749e846f43ed305fedf3d2fa5b3a8307fd00a
- D2: 13 picks, 3 conflicting picks. Boundary SHA (last D2 commit, the D2 handoff): 0e82d755447de8eaab347319dc8a5b0458b49f9d
- NEXT: git cherry-pick faee65f..wip/o1 (32 commits), then faee65f..wip/f1b.

## CONFLICTS AND HOW THEY WERE RESOLVED
- D2 687fb43 src/pl-ext.jl: the comment above `_PRED_TABLES` (G1 appended "gvar — G1", D2 appended "D2: the recorded database"). One line with both.
- D2 6cdcd1d src/pl-global.jl (3 hunks) and src/pl-fli.jl (1 hunk): both steps appended at the end of the LD struct, the LD constructor call, the
  struct's doc comment and `live_states`. Kept both, G1's first, D2 after: LD fields `gvar_nb_vars, gvar_grefs, gvar_enums, recorded_states`; constructor
  args in the same order (the G1 last arg got its trailing comma); `live_states` = `... + ld.prolog_flag_enums.live + ld.gvar_enums.live + ld.recorded_states.live`.
  The GD fields `record_lists, record_lists_order, record_refs` of D2 merged without conflict (G1 adds no GD field).
- D2 eb05797 docs/architecture.md: both appended before "## Still to come": `## G1` then `## D2`.
- Auto-merged without conflict: src/LogicKernel.jl, test/static_analysis_manifest.jl (G1's block; D2 has none), src/pl-incl.jl.

## pl-global.jl FIELD COUNT (struct fields / constructor arguments, counted by a throwaway script)
| point | GD struct/ctor | LD struct/ctor |
|---|---|---|
| main faee65f | 36/36 | 118/118 |
| after G1 | 36/36 | 121/121 |
| after D2 | 39/39 | 122/122 |

## MUTANT LISTS (throwaway python3 -I + runpy checker: every `old` once, new != old, ids unique, targets on disk)
G1 20 mutants, D2 45, D1c 100: 0 problems after D2 (D2's own D1c re-fit of 10 stale anchors came with its picks).
