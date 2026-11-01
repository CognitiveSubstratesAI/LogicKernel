# LB4 chunk (b1) — handoff (writer: Sonnet, edit-only; D-0286 item 2, D-0290 item 1)

Worktree ~/code/lk-lb4b1, branch wip/lb4b1 (off origin/main e0dfb4a). Nothing pushed. No Julia was run.
Scope: b1-1 template database, b1-2 H3 rows, b1-3 kernel-side readers of the boot image (T1/T3); the mutants list, docs and
manifest last. NOT in scope: b2 (the boot enabled, stand-ins deleted, `load_file!`), Q2 `bare` constructor (waits for the
first boot measurement, D-0286 item 3).

## Plan (ordered groups, commit estimate 7-8)
1. plan (this file) — 1 commit.
2. b1-1 `src/gd_template.jl` (ORIGINAL; loader_boot.md LD4 / Q2(a), H3). Included after src/pl-ext.jl (LogicKernel.jl, one line).
   - `copy_global_data(gd)`: a `@generated` function that builds the constructor call field by field from `fieldnames`, so a
     field a sibling stack appends (G1, D2, F1b, O1B) is copied with no edit here. Policy per field in the table
     `GD_COPY_POLICY` (a NamedTuple of Symbols, the exceptions only): DEFAULT is `:deep` = `Base.deepcopy_internal(field,
     stay)` with ONE `stay` IdDict for the whole GD, so the identities inside the database survive (`modules_user ===
     modules[user.index]`, `procedures_*` are entries of the system module, the shared supervisor vectors of
     `code_data`, the Clause/Definition cycles). `:streams` = the stream tables: the copy gets empty tables of the same shape and
     the copy REFUSES (error) a template that holds a live `IOSTREAM` (an open file must not be shared by two databases).
   - the registry: `gd_template(T; build)` boots (builds) once per process and term type under a lock;
     `PL_global_data_from_template(T; build)` = a copy of it; `reset_gd_templates!()`, `gd_template_built(T)`.
     DORMANT: no existing constructor calls any of it; `build` defaults to the UNBOOTED `PL_global_data{T}()` constructor, which
     b2 replaces by the booted one. The process-level registry is module state: ONE allowlist entry in tools/lint_globals.jl
     (flag for the audit).
   - `gd_aliased_objects(a, b)`: the mutable objects reachable from both (the alias check the H3 rows and the mutants use).
3. b1-2 `test/db/test_gd_template.jl` (TERM-GENERIC, reference type): the H3 rows — the copy equals the template structurally;
   NO mutable object is shared; asserting a clause / interning an atom / setting a flag / making a module / defining an operator in the
   copy leaves the template AND a sibling copy unchanged (digest compare, both sides non-empty); the registry builds once
   per type, resets; the stream-clean refusal; a negative control for the alias check. + `evidence/LB4B1/bench_note.md`: the
   boot-time bench (30 interleaved runs, NOT RUN) — what to time, the method.
4. b1-3 `src/boot_image.jl` (ORIGINAL): `boot_image_predicates(gd)` (T1 columns: module, name, arity, defined, dynamic,
   foreign, number_of_clauses, locked, iso, transparent, meta, public, exported — read from the definition tables, no
   syspred.pl, loader_boot.md:380) and `boot_image_source_files(gd)` (T3: `$time_source_file/3` order, the
   `$source_file_property/3` columns, from `gd.files_array`), + `test/db/test_boot_image_readers.jl` (the readers against
   hand-built definitions and the kernel's own built-ins; a swipl 10.1.19 oracle block for the C predicates both sides define).
5. `tools/mutants/LB4B1.py` — the template shares clause table / flag table / atom table / module table, the stream refusal,
   the registry builds twice, a reader column dropped, etc.; TARGETS every file that exercises the new code.
6. docs/architecture.md block (APPENDED) — 1 commit. 7. test/static_analysis_manifest.jl entries (APPENDED) — 1 commit.

## Tier-1 contact
src/pl-global.jl is NOT edited (the new code sits in new files), so no struct changes here. The gate order still needs: the
alloc pins x3 only if a Tier-1 file changes in the final diff (none planned). BUT the GD struct that siblings change is the one
`copy_global_data` is generated from: when G1/D2/F1b/O1B land the generated copy changes with it (no edit), and the H3 alias
row is the guard that a new mutable field is not shared.

## State
(updated after each commit below)
