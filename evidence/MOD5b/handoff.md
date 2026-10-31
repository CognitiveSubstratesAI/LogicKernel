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

### OPEN POINT 1 (b05 RESOLVED by coder 2; the source item is still to do, see below)
b05 is well posed: the link made by b04's call is to a DYNAMIC predicate (b04 asserts zz4/1), and declareModule's loop skips a definition
with `P_DYNAMIC|P_MULTIFILE|P_FOREIGN` (tested on the IMPORTED definition), so the link survives the re-declaration: swipl's answer
(E unbound = `mns4:zz4(_)` succeeded) is right, and the kernel's loop already skips it (flags != 0). Checked in swipl: `imported(mnsup4)`
before and after the second `'$declare_module'`. New row b06 covers the other half: a STATIC predicate (`sup_s(8).` in the program,
reached through super `user`) imported by a call, then the module re-declared with super `system`: the link IS removed
(abolishProcedure's imported branch), the call raises `existence_error(procedure, mns5:sup_s/1)`. Only that branch needed the port.
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

## STATE after coder 2 (everything is WRITTEN, NOTHING IS RUN: no Julia, no daemon; swipl 10.1.19 used as the oracle)
Commits on wip/mod5b after ab5e112: bd12393 (b05 explained, row b06 added, pins regenerated twice byte-identical), 8866374 (pins FILLED:
`_MB_PINNED` 51 lines, `_MB_Q7_SWIPL` 2; gen_rows.py's --fill pattern fixed), 1ee36ef (abolishProcedure's imported-link branch in
`_abolishProcedure_pristine`, pl-modul.jl), df4e7cb (tools/mutants/MOD5b.py: 36 mutants, 3 equivalent, validated by a text count;
plus a white-box on b06's definitions in the H3 testset), 54626b0 (docs/architecture.md `## MOD5b`), this handoff.
b05 turned out to be WELL POSED: the link of b04 is to a dynamic predicate, declareModule's loop skips it (the imported definition's
flags are tested), `imported(mnsup4)` before and after in swipl. Row b06 (static `sup_s/1` of `user`, in the program) covers the link
that IS removed. OPEN POINT 1 is DONE (the branch is ported; the manifest signature of `_abolishProcedure_pristine` is unchanged).
UNVERIFIED on the kernel (listed in the test file header): b04, c01-c02, d03, b02, b05, b06, e01, e02, f01-f05, the b06 white-box
(`ss.definition.shared == 1`, `p5.definition.shared == 0`: derived by hand from upstream's memset and lookupProcedure's 1).
Daemon: coder 2 started none; lanes.conf untouched.

## NEXT (the gate; a new agent)
1. REBASE onto the landed MOD5a under a NEW branch name (never force); the struct change (`definition.shared`, MOD5a) makes the first
   daemon compile cold (~30 min).
2. `warm.sh fmt` (the new long lines; Blue may reflow the long `Definition{T}(...)` call and the registration entries), then
   `warm.sh inventory` (docs/port_inventory.md) + hand `declared` edits as MOD3b/MOD5a needed, then `warm.sh check`.
3. The rows on all three term types (`warm.sh file test/core_lang/test_declare_destroy_swipl.jl`, no impl), test/test_type_discipline.jl,
   `tools/pkgtest_way.sh test/core_lang/test_declare_destroy_swipl.jl` (one at a time, ~3 GB).
4. Re-check the mutant anchors after fmt (`python3 -I` runpy validator: old exactly once; the long ones: C2, M4, P1), push `mutants/MOD5b`
   at the WIP SHA, branch-gate, crash-term grep over diff and message, then `gate/mod5b` and `mutants/MOD5b` at the SAME SHA. No alloc
   pins (the run loop is untouched).
5. Expected survivors NOT listed (no row loads a procedure from the source file of a temporary module): markSourceFilesProcedure's
   MULTISOURCE test, unlinkSourceFilesModule's file loop, unlinkSourceFileModule's filter. LATER: a white-box with a consulted file
   that defines a predicate in the module.
6. If a row fails on the kernel, the swipl pin is truth: fix the source, not the pin (D-0084); the Q7 testset expects NotPortedError.

## Flags
(1) Q7 narrowing (above). (2) OPEN POINT 1 (import-link abolish; b05): DONE, see STATE. (3) DIVERGES logged in comments: GC for freeing (`unallocModule`
keeps the record), procedure walk order is Julia's Dict order (not upstream's hash order), `class`/`super` typed as atoms, no reload,
`$init_goal/3` half of the unlink test left to the loader, the destroyModule invariant print and the generation bump not kept.
(4) References: `'$declare_module'` acquires the source file (lookupSourceFile) and the module's `file` holds that reference until the
destroy (upstream's leak on the equal-file path and on the refusal path is mirrored). (5) `_text_summary` for a message only.
(6) The formatter may reflow the new long lines: `warm.sh fmt` first, then re-check mutant anchors.
