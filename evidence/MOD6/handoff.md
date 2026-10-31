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
