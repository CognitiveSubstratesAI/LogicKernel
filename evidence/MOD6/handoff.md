# MOD6 — the module enumerations (modules.md section 7). Edit-only coding, coder 1. NOTHING COMPILED OR RUN.

Branch wip/mod6 stacked on wip/mod5b (5b221de). LOCAL, never pushed. Reference: swipl-devel cbf4e1896275 (pl-modul.c, pl-incl.h:2209).
Daemon: this coder started none; lanes.conf untouched. swipl 10.1.19 is the oracle for the rows.

## Plan (upstream file:line -> Julia site)
Group 1 (state and pool): `module_enum` (pl-incl.h:2209-2213) + `MENUM_TEMP` (pl-incl.h:2207) in src/pl-incl.jl beside `module_table`;
  the pool `ld.module_enums::foreign_state_pool{module_enum}` (src/pl-global.jl, appended last: a STRUCT CHANGE of PL_local_data);
  `live_states` (src/pl-fli.jl:1241) adds `ld.module_enums.live`.
Group 2 (src/pl-modul.jl, after `destroyModule`): `newModuleEnum` (pl-modul.c:242), `advanceModuleEnum` (260), `freeModuleEnum` (289);
  `pl_import_module2_va` (876-918, `PL_retry(i+1)` as src/pl-srcfile.jl `$time_source_file`); `get_existing_source_file` (952);
  `pl_current_module2_va` (983-1075, `PL_retry_address(k)` as src/pl-op.jl current_op_ndet; FRG_CUTTED frees the state).
Group 3: registration in `PL_predicates_from_module` (upstream order: `import_module` first, `$current_module` after `set_module`,
  both PL_FA_NONDETERMINISTIC), header comments, manifest block (test/static_analysis_manifest.jl).
Group 4: rows (evidence/MOD6/gen_rows.py, mm_*.pl/.out, test/core_lang/test_module_enum_swipl.jl).
Group 5: tools/mutants/MOD6.py. Group 6: docs/architecture.md `## MOD6`. Group 7: this handoff (state, flags, gate order).

## Upstream facts used
- `$current_module` enumerates with `newModuleEnum(0)`: temporary modules are NEVER listed (MENUM_TEMP is unused at the pin; ported anyway).
- Every answer of `$current_module` returns `ForeignRedoPtr(e)` (no "last answer is det" test, unlike import_module).
- A failed unify of the module/file pair ends the enumeration (`break; /* must be an error */`).
- In the kernel a module is never removed from the `Vector`; a destroyed module's name is taken out of `names`: the walk skips a record
  whose name does not map back to its own index (= upstream's table enumeration not seeing a deleted entry).

## STATE (coder 1, forced hand-back at the cap): groups 1-4 WRITTEN, 5-6 NOT written; NOTHING COMPILED OR RUN (no Julia, no daemon)
Commits on wip/mod6 after 5b221de: 3a20d7e plan; ffa4003 group 1 (module_enum, MENUM_TEMP, `ld.module_enums` appended LAST to PL_local_data =
STRUCT CHANGE, `live_states`); 3f201ac group 2+3 source (newModuleEnum/advanceModuleEnum/freeModuleEnum, get_existing_source_file,
pl_import_module2_va, pl_current_module2_va, registration with PL_FA_NONDETERMINISTIC in upstream's order, header comments);
3a8fab4 manifest block; then ONE commit with the rows (this handoff, evidence/MOD6/gen_rows.py + mm_rows.pl/.out/.err/mm_driver.pl,
test/core_lang/test_module_enum_swipl.jl: 46 cases s01, i01-i21, c01-c20, d01, d03-d05; pins FILLED from swipl 10.1.19, byte-stable on a re-run).
NOT DONE: (5) tools/mutants/MOD6.py (20-30 mutants + validator); (6) docs/architecture.md `## MOD6` after the MOD5b section;
docs/port_inventory.md (`warm.sh inventory`); a test-file registry entry if the runner lists files (glob assumed).

## Mutant ideas for the next agent (TARGETS = test_module_enum_swipl.jl + test_declare_destroy_swipl.jl + test_module_swipl.jl;
test_between_swipl.jl/test_current_op_swipl.jl only if live_states is mutated)
import_module: `n == i` -> `true`/`n <= i`; ndet `n + 1 < length` -> `<=`/dropped; `&& PL_is_variable` dropped; `PL_retry(i + 1)` -> `PL_retry(i)`;
create flag true -> false (i03); FRG_CUTTED branch returns FFALSE. current_module: m.file == 0 -> nil swap; list branch `length > 1` -> `>= 1`;
`rc = false` on a failed list unify dropped; the system-class hide condition (`m.name != system` dropped, `!SYSTEM_MODE` dropped,
`PL_is_variable(module_)` dropped); `break` after a failed unify -> `continue`; `ok || return FFALSE` dropped; FRG_CUTTED `freeModuleEnum` dropped (live_states);
`PL_retry_address(k)` -> FTRUE (c15/c16 determinism); advanceModuleEnum: `get(table.names, c.name, 0) == c.index` dropped (d04), `(en.flags & MENUM_TEMP) == 0`
-> `!= 0`, `m.references += 1` dropped, the release of `current` dropped; freeModuleEnum: the release dropped / `en.current = 0` dropped;
newModuleEnum: `en.next = 1` dropped (second enumeration starts mid-table); live_states: `+ ld.module_enums.live` dropped.

## FLAGS
(1) STRUCT CHANGE: `module_enums` appended last in PL_local_data (src/pl-global.jl) - the warm daemon restarts; MOD3b/others may conflict at the end of the
    field list and of the constructor call: rebase by hand. (2) DIVERGES logged in comments: creation order vs hash order (rows sorted), `tenum` = vector
    index, state record in a pool, no PL_no_memory path. (3) The file -> module mode on a file whose module was DESTROYED: the swipl 10.1.19 oracle
    process ends abnormally (3-line repro: '$declare_module' of a temporary module with a file, '$destroy_module', then '$current_module'(M, File));
    rows for it (d02, d06, d07) were taken out; the dispatcher files it in the PRIVATE register (batch day), not here. The kernel keeps the module in
    the source file's list after a destroy (as upstream's unlink does), so a kernel row would read a destroyed record; nothing pins it.
(4) SYSTEM_MODE hiding: no row (the access level cannot be set to `system` yet). (5) The kernel's `sf.modules` order is declaration order; row c07 pins swipl's
    (declaration order too). (6) call_cleanup/2 determinism probe (mme_det) is UNVERIFIED on the kernel; if it fails there, the fix is in the helper, not the pin.

## GATE ORDER (a new agent)
Rebase onto the landed MOD5b under a NEW branch name (never force); `warm.sh fmt` (long registration lines; re-check mutant anchors); `warm.sh inventory`;
`warm.sh check`; the rows x3 term types (`warm.sh file test/core_lang/test_module_enum_swipl.jl`), `test/test_type_discipline.jl`,
`tools/pkgtest_way.sh test/core_lang/test_module_enum_swipl.jl`; push `mutants/MOD6` at the WIP SHA once MOD6.py exists; branch-gate; the term grep over diff and
message; the NDET instructions are untouched, but the `PL_local_data` struct changed: run test_zero_exports and test_ball_cells x3 (alloc pins); then
`gate/mod6` and `mutants/MOD6` at the SAME SHA. If a row fails on the kernel, swipl's pin is truth: fix the source (D-0084).

## Coder 2 (edit-only, nothing compiled or run): groups 5 and 6 WRITTEN
- b81873f tools/mutants/MOD6.py: 34 mutants (I1-I9 import_module, C1-C15 current_module, G1, N1, A1-A4, F1-F3, L1, R1, R2). Validated by a throwaway
  python3 -I + runpy script: every `old` occurs exactly once in its file, new != old, ids unique, every target exists (34 mutants, 0 problems).
  Equivalents (4, reasons in the entries): I9 (FRG_CUTTED value discarded), C4 (dropped `ok ||`), C9 (`break` -> `continue`), F3 (`en.current = 0`).
  EXPECTED SURVIVORS (2, named in the header; the gate agent adds the rows): I5 (determinism with a BOUND second argument:
  `mme_det(import_module(mmx_c2, mmx_u), D)`) and C6 (a `[]` module argument with a multi-module file: `'$current_module'([], '/mmx/g.pl')`).
  TARGETS: the rows file; test_module_swipl.jl for import_module/2; every live_states reader for L1 (test_declare_destroy_swipl.jl does not call
  the code, so it is left out by D-0238's rule, contrary to the idea list above).
  Anchors need a re-fit at the first battery run if fmt re-flows a line (comment alignment, the registration lines).
- 452925b docs/architecture.md `## MOD6` (before `## D1`, after the MOD5b section).
- No daemon started by this coder; lanes.conf untouched.

## GATE ORDER (restated for the next agent)
1. Rebase onto the landed MOD5b under a NEW branch name (never force); the STRUCT CHANGE needs a hand-merge at the end of `PL_local_data`'s
   field list and constructor call if MOD3b/MOD5 landed fields there.
2. `warm.sh fmt` (format committed files through `warm.sh send`); then `warm.sh inventory` (docs/port_inventory.md) and hand `declared` edits as
   earlier steps needed.
3. `warm.sh check`; the rows on all three term types (`warm.sh file test/core_lang/test_module_enum_swipl.jl`); `test/test_type_discipline.jl`;
   `tools/pkgtest_way.sh test/core_lang/test_module_enum_swipl.jl` (one at a time).
4. Re-check the MOD6.py anchors (each `old` once in its file); add rows for I5 and C6 or record them; push `mutants/MOD6` at the WIP SHA.
5. branch-gate; the term grep over diff and message; test_zero_exports and test_ball_cells x3 (struct change); then `gate/mod6` (local branch at the
   SHA; wip refs are refused) and `mutants/MOD6` at the SAME SHA. A row failing on the kernel: swipl's pin is truth, fix the source (D-0084).
