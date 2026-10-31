# MOD5b — declaring and destroying modules (modules.md section 7). Edit-only coding, coder 1. NOTHING COMPILED OR RUN.

Branch wip/mod5b stacked on wip/mod5a (c9054e1). LOCAL, never pushed. Reference: swipl-devel cbf4e1896275.
Daemon: coder 1 started none; lanes.conf untouched. swipl 10.1.19 run freely (oracle). Hook blocks: edit+commit in one call (split);
the cap hook at ~152k (forced this hand-back).

## Plan (upstream file:line -> Julia site) — groups 1-4 WRITTEN
Group 1 (src/pl-modul.jl, new block before the `module_code_size` comment): `acquireModule` (pl-modul.c:195), `acquireModulePtr` (208),
  `releaseModule_unlocked` (217), `releaseModule` (233), `unallocModule` (351; resets the source and typein modules to `user`, memory is
  Julia's), `markSourceFilesProcedure` (389), `unlinkSourceFilesModule` (402), `destroyModule` (429). src/pl-srcfile.jl:
  `unlinkSourceFileModule` (pl-srcfile.c:544).
Group 2: `_text_summary` (pl-util.c:67-116 text_summary/atom_summary), `declareModule` (1287-1366), `pl_declare_module6_va` (1376-1400).
Group 3: `pl_destroy_module1_va` (1826-1848). Group 4: registration in `PL_predicates_from_module` (upstream's order: `$declare_module`
  after `$def_modules`, `$destroy_module` after `$undefined_export`), header comments, manifest block (test/static_analysis_manifest.jl,
  after MOD5a's `]...,`).

## Commits on wip/mod5b (after c9054e1)
fee416c plan; 5ec0625 source (pl-modul.jl, pl-srcfile.jl); 629caf9 manifest entries; then ONE commit with the rows (this handoff,
evidence/MOD5b/gen_rows.py, mb_*.pl/.out/.err, test/core_lang/test_declare_destroy_swipl.jl) — see `git log`.

## Q7 (declareModule on a module that has clauses) — FLAG FOR THE AUDIT
modules.md section 8 Q7 recommends: refuse by name (`NotPortedError`) until F5 (`abolishProcedure`, pl-proc.c:1510). Done in
`_abolishProcedure_pristine` (src/pl-modul.jl): a procedure the loop would abolish is left alone only when PRISTINE (own definition, no
clauses, `def.flags == 0`: abolish changes nothing observable); any other (clauses, an IMPORTED link, flags set) throws
`NotPortedError{T}(def.name, "redeclaring a module that has predicates (abolishProcedure)", "R2")`. The narrowing to "pristine" is mine.
The loop runs AFTER class/file/source-module are set (as upstream), so a refused re-declaration has changed those.
The warning `declare_module(M, abolish(PIs))` branch (rdef, unify_definition, printMessage) is written but cannot be reached until F5.
swipl's answer for the Q7 program is pinned (evidence/MOD5b/mb_q7.out; stderr "Loading module mq abolished: mq:qs/1 [undefined]").

### OPEN POINT 1 (found writing row b05, NOT fixed): an auto-imported link blocks a re-declaration
Row b04 calls `mns4:zz4(X)`, which auto-imports mnsup4's zz4/1 into mns4's procedure table (an import link: `def.module_ != mns4.index`).
Row b05 then re-declares mns4: swipl's abolishProcedure REMOVES that link (pl-proc.c:1517-1530: a fresh Definition for the module,
`proc->definition = ndef`, `unshareDefinition(odef)`), the kernel's `_abolishProcedure_pristine` THROWS NotPortedError there. The next
agent should port that branch (cheap; the Definition constructor is lookupProcedure's positional form, last field `shared`; upstream's
memset leaves `shared` 0 for the new definition; `unshareDefinition(odef)` exists in src/pl-proc.jl:290; `lingerDefinition` is GC):
```
if def.module_ != m.index   # imported: remove the link
    ndef = Definition{T}(key, arity, <ClauseList with args as lookupProcedure>, UInt64(0), name, cd.virgin, ClauseRef{T}[], cd, 0, m.index, 0)
    proc.definition = ndef; unshareDefinition(def)
```
Then b05 passes in the kernel. ALSO FIX THE ROW b05: swipl's pinned answer is `t_b05 t_b05/1(V0)` — E stayed unbound, i.e. `mns4:zz4(_)`
STILL SUCCEEDED after the super was changed to `system`, because the link made by b04's call survived?? NO: swipl's abolish removes the
link, so the likely reason is different (the call found zz4 through the new super chain or the module's procedure was not abolished
because the loop condition tests the IMPORTED def's flags). Do not trust b05 as written: investigate in swipl (`'$declare_module'(mns4,
user, system, ...)` then `mns4:zz4(X)`), then replace b05 by a row on a predicate not called before (assert zz5 in mnsup4, re-declare
mns4 with super `system`, expect existence_error(procedure, mns4:zz5/1)), and re-run the generator with --fill. Until then b05 pins what
swipl does (the row is swipl's truth, only its comment "replaces the super" is unproven).

## Rows (group 5 part 1) — WRITTEN, swipl-pinned, NOT run on the kernel
test/core_lang/test_declare_destroy_swipl.jl (prefix `_MB`/`_mb`, ONE extractor `_mb_enc`, `lk_term_type`): 49 cases a01-a21, b01-b05,
c01-c02, d01-d12, e01-e04, f01-f05 + `mb_done` wrapper (source and typein back to `user`) + testsets: rows vs pins; non-vacuity;
white-box H3 (destroyed module keeps record: mtd7 has two records, old `M_DESTROYED`, `references == 0`, `file == 0`, old definitions
name the old index; mtd8 temporary again); Q7 testset (kernel must raise NotPortedError; swipl's two lines pinned); live swipl compare.
The pins `_MB_PINNED` / `_MB_Q7_SWIPL` in the file are EMPTY `[ ]`: FILL THEM: `cd evidence/MOD5b && python3 gen_rows.py
../../test/core_lang/test_declare_destroy_swipl.jl --fill` (the .out files already exist: mb_rows.out 50 lines, mb_q7.out 3 lines).
swipl facts: Redefine accepts 1 (PL_get_stdbool_ex); class is set BEFORE the redefine refusal (a06 -> class `system`); the class atom is
not checked (`weird`); a failed/absent `'$module_property'(M, class(_))` of a destroyed module: `gone` (d01) — the kernel must FAIL, not
create the module; a destroyed module's source module goes back to `user` (d02), typein too (d03); a temporary module in a clause body:
`permission_error(reference, module, mtd8)` (f01), `call(mtd8:true)` is fine (f02); after the destroy the name is a plain user module
(f04 ok); `'$destroy_module'(system)` and `(user)` -> permission_error(destroy, module, ...).
UNVERIFIED on the kernel (listed in the test file): b04, c01-c03, d03, e05-e08(sic: the header names rows by their draft ids; the real
ones are b02, b05, e01, e02, f01-f05), `set_module/1`, `'$module_property'(file/line_count)` after `'$declare_module'`.

## What the compiler's temporary-module refusal now needs (src/pl-comp.jl:392, `getTargetModule!`)
It was reachable already through `set_module(M:class(temporary))`; MOD5b adds the other producers (`'$declare_module'(M, temporary, ...)`) and
the way out (`'$destroy_module'/1`). The refusal itself needs NO change. After a destroy the name leaves `gd.modules.names`, so a later
`lookupModule` in `getTargetModule!` makes a FRESH user-class module (row f04) and clauses compiled earlier keep the OLD index (H3). Rows
f01-f05 pin both sides; the gate decides the kernel's answer.

## NOT WRITTEN (next agent, in this order)
1. Fill the pins (`gen_rows.py --fill`); read b05 (OPEN POINT 1); port the imported-link branch of abolish and rename/rewrite
   `_abolishProcedure_pristine` accordingly (update manifest signature if it changes).
2. tools/mutants/MOD5b.py in tools/mutants/MOD5a.py's format (20-30 mutants, every `old` exactly once: `grep -c -F`; TARGETS =
   test/core_lang/test_declare_destroy_swipl.jl, test/core_lang/test_export_import_swipl.jl, the MOD1-MOD4 module rows that call
   `lookupModule`/`$set_source_module`/`set_module`, D-0238). Candidate mutants: destroyModule (names not deleted; M_DESTROYED not set;
   releaseModule not called); releaseModule_unlocked (`== 0` -> `== 1`; `!= 0` flag test dropped); unallocModule (source/typein not reset;
   one of them); releaseModule/acquireModule (class test inverted); declareModule (class set after the refusal; `module_.file != 0`
   dropped; `sf.index` vs `module_.file` compare inverted; `allow_newfile` negation; line_no not set; modules_source not set; public_ not
   cleared; public_order not cleared; super not set; flags mask P_DYNAMIC dropped); _text_summary (`maxlen - 6`); the pl_*_va wrappers
   (argument order/redefine bool); unlinkSourceFilesModule (file not released; MULTISOURCE test); unlinkSourceFileModule (current_procedure).
3. docs/architecture.md MOD5b section after the MOD5a section (what ports what with file:line; the temporary class; Q7/F5; GC for freeing; the
   `$init_goal/3` half of unlinkSourceFileModule left to L6; `Sdprintf` invariant line and `GD->modules.generation` not kept).
4. `warm.sh inventory` (docs/port_inventory.md) after fmt.
5. Gate order: fmt, inventory, check, rows x3 term types, type discipline, tools/pkgtest_way.sh on the new file (one at a time), re-check
   mutant anchors after fmt, push mutants/MOD5b, branch-gate, crash-term grep, gate push. Alloc pins not needed (run loop untouched).
   MOD5a's `definition.shared` STRUCT CHANGE means a cold daemon compile (~30 min).

## Flags
(1) Q7 narrowing (above). (2) OPEN POINT 1 (import-link abolish; b05). (3) DIVERGES logged in comments: GC for freeing (`unallocModule`
keeps the record), procedure walk order is Julia's Dict order (not upstream's hash order), `class`/`super` typed as atoms, no reload,
`$init_goal/3` half of the unlink test left to the loader, the destroyModule invariant print and the generation bump not kept.
(4) References: `'$declare_module'` acquires the source file (lookupSourceFile) and the module's `file` holds that reference until the
destroy (upstream's leak on the equal-file path and on the refusal path is mirrored). (5) `_text_summary` for a message only.
(6) The formatter may reflow the new long lines: `warm.sh fmt` first, then re-check mutant anchors.
