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

## State (forced hand-back at the 150k cap, 2026-11-01)
COMMITTED on wip/lb4b1: 89822c9 (this plan), ea0ab88 (b1-1: src/gd_template.jl, the include line in src/LogicKernel.jl, the
`LogicKernel._GD_TEMPLATES` allowlist entry in tools/lint_globals.jl).

UNCOMMITTED in the worktree (a fresh agent: finish these two edits, then `git add` + commit as b1-2):
- `test/db/test_gd_template.jl` is WRITTEN (untracked): the H3 rows (copy == template by digest, alias check with two negative
  controls, identities in the copy, six mutations each leaving template and sibling unchanged, stream tables, registry).
  PENDING EDIT 1 in it: the line `cf[findfirst(==(:atoms), fieldnames(typeof(TMPL)))] = TMPL.atoms` must become
  `cf[Base.fieldindex(typeof(TMPL), :atoms)] = TMPL.atoms` (findfirst on a tuple of names is not defined).
- PENDING EDIT 2 in `src/gd_template.jl` `_reachable_mutables`: after the `_alias_skip(x) && continue` line add
  `x isa Memory && isempty(x) && continue` (the empty Memory of a type is one shared instance: a false alias between any
  two empty vectors). Fold this edit into the b1-2 commit (the unlanded b1-1 is on a wip branch; message line).

NOT STARTED (in plan order): the bench note `evidence/LB4B1/bench_note.md` (30 interleaved runs of the template build vs a
copy: what to time = `gd_template` first request, `copy_global_data`, an unbooted `PL_global_data{T}()`, per term type; method
= memory "bench method", quiet machine, allocations decide; NOT RUN); b1-3 `src/boot_image.jl` + `test/db/test_boot_image_readers.jl`;
`tools/mutants/LB4B1.py`; docs/architecture.md block; manifest entries. Design notes for b1-3 (read already, so not re-read):
- T1 row per procedure of every module in `gd.modules` (`m.procedures`, key `(sym_key(name), arity)`; `proc.definition`):
  module/name (`sym_text`)/arity, defined = `isDefinedProcedure(gd, proc)`, dynamic = `P_DYNAMIC`, foreign = `P_FOREIGN`,
  locked = `P_LOCKED`, iso = `P_ISO`, transparent = `P_TRANSPARENT`, meta = `P_META`, public = `P_PUBLIC`, exported =
  `haskey(m.public_, key)`; number_of_clauses as pl-proc.c:3648-3658: absent (nothing) for a foreign predicate, absent when 0 and
  not dynamic, else the VISIBLE clause count (`visibleClauseCNT(cl, global_generation(gd))` over `def.impl_clauses.first_clause`
  chain for a dynamic one, `number_of_clauses` for a static one). Sorted by (module, name, arity).
- T3 row per source file: `for index in 0:highSourceFileIndex(gd)-1`, `f = indexToSourceFile(gd, index)`, skip nothing / `count == 0`
  (pl-srcfile.jl:296-330): index, name text, type (`f.system` -> system/user), load_count = `f.count`, number_of_clauses,
  resource, from_state, loaded = `f.ltime != 0.0`, reloading = false, module names `f.modules`.
- The swipl oracle block for the readers: C predicates both sides define (atom_length/2, functor/3, =/2, ...) with
  `predicate_property` (defined, foreign, iso, number_of_clauses absent for foreign); generator + driver + .out via swipl 10.1.19
  (see evidence/MOD5b/ and evidence/MOD6/ of the channel).
- Mutants (LB4B1.py, anchors to verify with `grep -c -F`): gd_template.jl — the `:streams` policy removed (stream refusal),
  `stay` made per field (identities broken), `GD_COPY_POLICY` field copied shallow (a table shared: replace one `deepcopy_internal`
  by a plain `getfield`), the `t === nothing` registry test removed (builds twice), the registry key made constant (not per
  type), `reset_gd_templates!` not clearing, `unlock` dropped (lock held after a raising build), the empty-Memory skip removed
  (equivalent? no: the alias rows would flag a false alias — a kill), `_copy_stream_free` accepting a live stream. TARGETS:
  test/db/test_gd_template.jl (the new file) + test/db/test_procedures.jl + test/test_lint_globals.jl + test/test_static_analysis.jl
  (only what exercises gd_template.jl; D-0238).

## Flags for the audit
1. Tier-1 contact: NONE so far. src/pl-global.jl is not edited; no struct changed. Alloc pins x3 not triggered by this chunk.
2. NEW MODULE-LEVEL STATE: `LogicKernel._GD_TEMPLATES` (a lock and a dict of templates) with an allowlist entry in
   tools/lint_globals.jl whose text says "Audit decision pending". The process-level registry is what D-0286's sizing named; the
   kernel lint forbids mutable module state otherwise. Alternative if refused: a caller-held registry value (b2's constructor
   then needs one passed or held in a database). Recommend: accept.
3. The template build function is a POSITIONAL argument (`gd_template(T, build)`), the one-argument form builds with the unbooted
   constructor; b2 swaps the default. `PL_global_data{T}()` and every existing constructor are unchanged.
4. Hook note: creating src/gd_template.jl was blocked by `require-reference-for-new-artifact.sh` until a corpus index was read
   (I read workflows/DEVZONE_INDEX.md). `discourage-vector-any.sh` wants `# allow-any:` on the `Any[]`/`IdSet{Any}` of the alias walk
   (done, reason given: a heterogeneous object-graph walk used by tests only).
5. FIELD TABLE of `copy_global_data` (policy at 89822c9..ea0ab88; the 37 fields of `PL_global_data` on e0dfb4a): `:streams` (empty
   same-shape copy, a live IOSTREAM refused) = `stream_filenames`, `stream_aliases`, `stream_table`; every other field is `:deep`
   (one shared IdDict, identities kept): `_generation procedures_dirty clauses_cgc_active functors_control modules modules_user
   modules_system subclause_names code_data procedures_dc_call_prolog0 procedures_equals2 procedures_dcall1 procedures_catch3
   procedures_dwakeup1 clauses_top_clause clauses_top_cref atom_nil atom_dot no_literals files_table files_array files_no_hole_before
   stream_alias_names atoms atom_symbols functors atom_dexpr functor_dot2 atom_nil_w prolog_flag clause_refs clause_serials bootsession`.
   Sibling fields (`record_lists record_lists_order record_refs gvar_nb_vars gvar_grefs gvar_enums recorded_states` from the D stack,
   `IO_output_stack` from O1B: an `Vector{IOSTREAM}` that is EMPTY after a boot, but would be deep-copied with IOSTREAMs if not: add
   it to `GD_COPY_POLICY` as `:streams` when O1B lands — a one-line edit, and the H3 alias row would otherwise not see it because
   the template's vector is empty) are `:deep` by default.
6. Risks for the first run (nothing was run): (a) `deepcopy_internal` of a closure that captured the template would keep a
   reference to it (the alias row would show a shared object only if the closure is mutable-reachable); (b) JET on the `@generated`
   body and the `Dict{DataType, PL_global_data}` registry; manifest entries needed (see the manifest group); (c) deepcopy time of a
   BOOTED database (millions of objects) is unmeasured: that is H3's bench; (d) `Term{Int64}` is used as the second term type in the
   registry row: if `PL_global_data{Term{Int64}}()` does not construct, use another `Term{G}`.
7. Gate order for this chunk (from WRITER_RULES): fmt (format committed files through `warm.sh send`), inventory, check, rows on
   all three term types (test/db/test_gd_template.jl, test/db/test_boot_image_readers.jl), type discipline, `tools/pkgtest_way.sh`
   per changed test file, the mutants branch, branch-gate, term grep, gate push on a FRESH name. Tier-1 alloc pins: not needed.
Hook blocks seen: the two above (both cleared); and the 150k context cap that ended this agent.
