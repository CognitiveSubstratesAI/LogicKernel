# LB3 re-stack onto landing A — state (re-stack agent, Sonnet, 2026-11-01)

Branch `wip/lb3-s` (local only, NOT pushed; wip/lb3-r and gate/lb3 + mutants/LB3 at 3033cb5 untouched).
Base: gate/dstack-a3 **8edf02b** (A, main still 1286e62 at the time). The remote ref gate/dstack-a3 has since moved to b9de14d
(two test/evidence commits above 8edf02b, no src change): one more rebase onto the new A tip is test-only and cheap.

## Rebase (13 commits of wip/lb3-r)
- src/pl-global.jl: A's LD tail (gvar_nb_vars, gvar_grefs, gvar_enums, recorded_states) first, then LB3's input_context_stack and
  qlf_write_state; the PL_local_data constructor argument list in step (recorded_state pool gets its comma).
- src/pl-ext.jl: `wic` table registered between `read` and `file` in _PRED_TABLES and _FOREIGN_VA; the header comment carries both.
- docs/port_inventory.md: base's, then regenerated (`warm.sh inventory`). docs/architecture.md, test/static_analysis_manifest.jl,
  src/LogicKernel.jl merged without conflict; no conflict markers anywhere.

## Fix folded in (CI of 3033cb5, static 3/8, test/static_analysis_body.jl:134, 3012 vs 3008 unique)
The LB3 block sits in `_index_entry_points(T)`, spliced in for _M1 and _M3, so the four type-independent entries
(cond_true, condc, qlfEndPart, addDirectiveWic) were listed twice. Moved after `_le_byte`'s comment in the main tuple.
Daemon probe: 3053 entries, 3053 unique. The static file itself was NOT run (CI only, D-0220).

## Gates on this tree (daemon restarted by the struct gate: PL_global_data/PL_local_data/tables)
- `warm.sh inventory`; `warm.sh check --summary` PASS twice (before and after the manifest fix; Blue-clean, nothing for fmt to change).
- test/files/test_qlf_swipl.jl 276/276 (3 types); test_type_discipline 33/33; test_manifest_entries 9/9.
- Alloc pins x3: test_zero_exports 239, test_local_stack 377, test_rules_swipl 439, foreign/test_query 347 (all pass, = gate.md numbers).
- `tools/pkgtest_way.sh test/files/test_qlf_swipl.jl`: passed, peak 1352 MiB (run by hand, check left it to the branch-gate by budget).
- `warm.sh branch-gate --summary`: PASS 718 s (run BEFORE the manifest fix commit; the fix touches only test/static_analysis_manifest.jl,
  re-checked by `check` + the probe + test_manifest_entries).
- tools/mutants/LB3.py: all 54 `old` strings occur exactly once in the rebased, formatted tree (dry run). Declared equivalents unchanged: D4, P3, F5.
- Term grep (D-0164) over diff base..HEAD and messages: one hit, an unchanged context line of docs/architecture.md that names
  a predicate; nothing else in added lines or messages.

## Left for the push (dispatcher)
1. After A lands (or on the new A tip b9de14d): rebase wip/lb3-s into a NEW branch name (e.g. wip/lb3-t), test-only delta,
   `warm.sh check`, dry run of LB3.py if anything moved.
2. Push gate/<new name> and mutants/LB3 (TARGETS = TT already in the list) at the SAME SHA.
3. Daemon logickernel-warm-13b94ed9 (third) is free from the moment of the hand-back.
