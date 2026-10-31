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

## STATE at the 150k cap (coder 1) — UNRUN: nothing compiled, no Julia started
Commits on wip/mod5a: 4e0af26 plan; 720594f group 1; ddc3076 group 2 (get_functor). Group 3 is in the working tree and
committed as the commit after this handoff (see git log).
WRITTEN (group 3, uncompiled): src/pl-error.jl: ERR_IMPORT_PROC (enum member appended) + `PL_error(ld, pred, arity, msg,
ERR_IMPORT_PROC, proc, dest, old)`; `_PL_error_close!` gained a 10-arg method taking a ready `msgterm0` (the 9-arg one forwards).
src/pl-srcfile.jl: exportProcedureSource (no reload in the kernel -> exportProcedure). src/pl-modul.jl (before the MQ3
`module_code_size` block): isPublicModule, exportProcedure, export_pi1, export_pi, pl_export1_va, pl_undefined_export2_va,
fixExportModule, fixExport, atomToImportStrength, import_, pl_import1_va, pl_import2_va.
NOT YET WRITTEN (next agent, in this order):
 (a) `'$def_modules'/2` + find_modules_with_defs (pl-modul.c:1157-1277): source module = `gd.modules[ld.modules_source]`;
     `stripModuleName_cells(ld, -(A1+1))` -> `(ok, loc, mnameword)`, `_slot_link_loc!(ld, ttail+1, loc)`; qualifier module:
     isCurrentModule(gd.modules, _atom_value(ld, mnameword)) else system if the text starts with `$` else user;
     targets via `get_functor(gd, ld, thead, 0, 0, GF_PROCEDURE | GP_NOT_QUALIFIED)` (max 10: `PL_error(ld, ERR_RESOURCE,
     mk_sym(T,:target_predicates))`); `PL_get_list_ex` loop then `PL_get_nil_ex`; defined test `_impl_any_defined(proc.definition)`;
     `mhead/plist/phead = PL_new_term_refs(ld, 3)`; the pair `M-List` built with `_message_term(ld, :-, _err_atom(ld, m.atom),
     plist)` then PL_unify(mhead, ...); recursion over `m.supers` with l-1, l < 0 -> `error("loop in default modules")`.
     (b) register in `PL_predicates_from_module` (src/pl-modul.jl, end): export/1 (PL_FA_TRANSPARENT|PL_FA_VARARGS),
     import/1 and `$import`/2 (transparent), `$undefined_export`/2 (VARARGS), `$def_modules`/2 (transparent);
     update the two NOT PORTED comments in src/pl-modul.jl (lines 18 and ~668: remove MOD5a names; header comment).
     (c) manifest entries in test/static_analysis_manifest.jl (near line 685/704): `(LK.exportProcedure, Tuple{MOD, PR}, false)`,
     isPublicModule, export_pi1/export_pi (Tuple{GD, LD, Int, Int[, Int]}), fixExport, fixExportModule, atomToImportStrength,
     import_ (Tuple{GD, LD, Int, Int}), exportProcedureSource, the five `_va` predicates in the `Tuple{LD, Int, Int,
     control_t{T}}` list near line 1486, `PL_error` with `Tuple{LD, String, Int, String, PL_error_code, PR, T, Union{Nothing,T}}`.
     (d) group 5: rows via the oracle swipl (MOD3a pattern), tools/mutants/MOD5a.py, docs/architecture.md MOD5a, rows file in
     test/ with ONE extractor; `docs/port_inventory.md` via `warm.sh inventory`; the `_enum_hash` of PL_error_code: I did not
     find a manifest entry for the enum (SSU1 appended ERR_PERMISSION_SSU_DEF with none) - the gate agent checks `check`.
FLAGS: (1) STRUCT CHANGE: definition.shared (daemon restart, ~30 min cold). (2) F5: abolishProcedure does not exist in src;
the weak-import NotPortedError at pl-proc.jl:1028 is KEPT and now becomes reachable through `'$import'(PI, weak)`.
(3) DIVERGES logged in comments: public table walked in insertion order; no reload in exportProcedureSource; GC for lingerDefinition.
(4) UNSURE: `PL_cons_functor` with an unbound `plist` (def_modules) globalises the variable as upstream's PL_unify_term - verify in rows;
`old.flags |= pflags | PROC_IMPORTED` (UInt32); `import_` calls `contextModule(gd, ld, ld.environment_frame)` without the 0 guard.
(5) The 9-arg `_PL_error_close!` now forwards: PL_error allocation behaviour unchanged for other callers.
GATE ORDER for the gate agent: fmt, check, rows x3 term types, test_type_discipline, branch-gate, alloc pins only if the run loop
changed (it did not), mutants/MOD5a to CI, crash-term grep (no hits expected in my text).
Daemon: coder 1 started none. Hooks: edit-and-commit-in-one-call blocks twice (split), the cap hook at 151k.

## coder 2 (EDIT-ONLY, nothing compiled, no Julia started) — SOURCE COMPLETE
Commits on wip/mod5a after coder 1's ddc3076: fd63662 group 3 (export/import, ERR_IMPORT_PROC, exportProcedureSource);
ce500b1 `'$def_modules'/2` (MAX_TARGETS, find_modules_with_defs, pl_def_modules2_va; src/pl-modul.jl, before the
module_code_size block); 9de843f registration in PL_predicates_from_module (upstream's order and flags: `$def_modules`
first; `import`, `$import`, `export` (transparent) and `$undefined_export` after strip_module/3) + the two header
comments reworded (now say what MOD5a ports; the remaining items under "LATER STEPS"); 6f0b418 manifest entries
(test/static_analysis_manifest.jl, MOD5a block after `pl_context_module`: isPublicModule, exportProcedure,
exportProcedureSource, export_pi1, export_pi, fixExportModule, fixExport, atomToImportStrength, import_,
find_modules_with_defs, PL_error ERR_IMPORT_PROC method, 10-arg _PL_error_close!, the five `_va` predicates; all `false`).
OPEN POINT CLOSED (plist): `PL_put_variable` makes a global cell (a slot holds no unbound word), so `PL_cons_functor`
with plist as an argument lays in a reference to that cell via `_cell_link!` = upstream's PL_unify_term PL_TERM (linkValG).
No extra globalisation written. Verify in the rows: the pair `M-[PI|_]` is shared with the list tail that `PL_unify_list`
binds, and `[]` closes it (`PL_unify_nil(plist)`).
`PL_error_code` / `_enum_hash`: the manifest keys `_enum_hash` by enum TYPE (lines ~2461-2470, the R1c list); PL_error_code
has no entry and SSU1 appended a member without one; a new member adds no type, so NO manifest entry is needed - the
gate agent's `check` confirms. Nothing invented.
NOT WRITTEN (a later coder): rows (test/modules/ file + evidence/MOD5a gen_rows.py + driver + .out, oracle swipl; ONE
extractor; both sides non-empty), tools/mutants/MOD5a.py (TARGETS: every test file exercising export/import/def_modules,
D-0238: the module rows, MOD1..MOD4 rows, the load/consult files that call export/import via the module/2 path),
docs/architecture.md MOD5a section, `warm.sh inventory` for docs/port_inventory.md.
FLAGS (new): (6) the formatter may reflow a few long lines in the new code and the manifest block: `warm.sh fmt` first.
(7) find_modules_with_defs raises `error("OOPS loop in default modules???")` for upstream's sysError (a kernel error).
(8) pl_def_modules2_va: `PL_resource_error` then FFALSE for >10 targets, as upstream. (9) The manifest signatures are
from the definitions' annotations (`find_modules_with_defs`: `Vector{Tuple{UInt64,Int,Int}}`, term_t = Int): `check` verifies.
Daemon: coder 2 started none and did not touch lanes.conf.
