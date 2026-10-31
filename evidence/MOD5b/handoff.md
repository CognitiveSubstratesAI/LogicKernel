# MOD5b — declaring and destroying modules (modules.md section 7). Edit-only coding, coder 1. NOTHING COMPILED OR RUN.

Branch wip/mod5b stacked on wip/mod5a (c9054e1). LOCAL, never pushed. Reference: swipl-devel cbf4e1896275.

## Plan (upstream file:line -> Julia site)
Group 1 (module lifetime; src/pl-modul.jl, new block after `pl_def_modules2_va`, before `module_code_size`):
  `acquireModule` (pl-modul.c:195), `acquireModulePtr` (208), `releaseModule_unlocked` (217), `releaseModule` (233),
  `unallocModule` (351; resets the source and typein modules to `user`, the memory is Julia's), `unlinkSourceFilesModule`
  (pl-modul.c:402; `markSourceFilesProcedure` 389), `destroyModule` (429). src/pl-srcfile.jl: `unlinkSourceFileModule`
  (pl-srcfile.c:544, after `addModuleSourceFile`).
Group 2 (declareModule; same file): `_text_summary`/`atom_summary` (pl-util.c:67-116) in pl-modul.jl,
  `declareModule` (1287-1366), `pl_declare_module6_va` (1376-1400).
Group 3 (destroy predicate; same file): `pl_destroy_module1_va` (1826-1848).
Group 4: registration in `PL_predicates_from_module` (`$declare_module`/6 and `$destroy_module`/1, upstream's PRED_IMPL flags 0),
  header comment of pl-modul.jl, manifest entries (test/static_analysis_manifest.jl, MOD5b block after MOD5a's).
Group 5: rows (evidence/MOD5b/gen_rows.py + drivers + .out; test/core_lang/test_declare_destroy_swipl.jl), tools/mutants/MOD5b.py,
  docs/architecture.md MOD5b section, this handoff.

## Q7 (declareModule on a module that has clauses)
modules.md section 8 Q7 recommends: refuse by name (`NotPortedError`, "abolish") until F5 (`abolishProcedure`, pl-proc.c:1510;
resetProcedure 388, removeClausesPredicate 1573 are not in the kernel). Taken as the decision of the design. Narrowed to what
abolish would actually do: a procedure the loop would abolish is refused unless its definition is pristine (own, no clauses,
flags 0), where abolishProcedure changes nothing observable. FLAG for the audit: the narrowing is mine.
