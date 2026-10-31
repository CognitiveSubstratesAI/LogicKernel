# MOD5a — export and import (modules.md section 7). Edit-only coding, coder 1. NOTHING COMPILED OR RUN.

Branch wip/mod5a off main 07a8e01 (LOCAL, never pushed). Reference: swipl-devel cbf4e1896275.

## Plan (upstream file:line -> Julia site)
Group 1 (data): `PROC_IMPORTED = 0x0004` (pl-incl.h:1807) after `PROC_MULTISOURCE` in src/pl-incl.jl;
  `definition.shared::Int` (pl-incl.h:1769), LAST field, so the three positional constructors gain a trailing
  count (STRUCT CHANGE: the warm daemon restarts): src/pl-proc.jl lookupProcedure (1: pl-proc.c:122
  `def->shared = 1`), src/pl-global.jl:117 (dc_def, 1) and :502 (idle index_context definition, 0);
  `shareDefinition`/`unshareDefinition` (pl-proc.c:569-579) in src/pl-proc.jl before `autoImport`;
  `autoImport` shares/unshares (pl-proc.c:2897-2907).
Group 2 (get_functor): `get_functor` (pl-proc.c:614-672) in src/pl-proc.jl after `get_functor_procedure` (which is
  its `GF_PROCEDURE` core, kept): strip module unless `GP_NOT_QUALIFIED` (new constant 0x2000, pl-incl.h:1020),
  `GF_NAMEARITY` (0x4) / `GF_PROCEDURE` (0x2) (pl-incl.h:1024-1025).
Group 3 (export/import): src/pl-modul.jl: `isPublicModule` (pl-modul.c:844), `exportProcedure` (1504),
  `export_pi1`, `export_pi` (1514-1554), `fixExportModule`, `fixExport` (1635-1660), `atomToImportStrength`
  (1663), `import_` (1676-1802); `exportProcedureSource` (pl-srcfile.c:1427) into src/pl-srcfile.jl (the kernel
  has no `reload`: it is `exportProcedure`). `ERR_IMPORT_PROC` (pl-error.c:447-470) as a PL_error method in
  src/pl-error.jl (enum member appended).
Group 4 (predicates): `pl_export1_va`, `pl_import1_va`, `pl_import2_va` (`'$import'/2`), `pl_undefined_export2_va`,
  `pl_def_modules2_va` + `find_modules_with_defs` (pl-modul.c:1218-1277) in src/pl-modul.jl; entries in
  `PL_predicates_from_module`; manifest entries in test/static_analysis_manifest.jl.
Group 5: rows (evidence/MOD5a gen_rows.py + driver + .out; test/modules/ file), tools/mutants/MOD5a.py,
  docs/architecture.md MOD5a section, this handoff.

## F5 check (weak-import refusal, src/pl-proc.jl:1028)
`abolishProcedure` does NOT exist in src (read: pl-proc.jl:1004-1005, 1050, 1073, 1119 still name it as owed). The
refusal in `overruleImportedProcedure` is KEPT. NEW: `import/1`'s weak strength (`'$import'(PI, weak)`) is the only
producer of a PROC_WEAK procedure, so the refusal becomes reachable (it was unreachable); the NotPortedError text
says "overruling a weak import (abolishProcedure)", "R2" - unchanged.
