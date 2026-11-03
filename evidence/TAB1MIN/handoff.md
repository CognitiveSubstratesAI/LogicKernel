# TAB1MIN handoff (writer 1, Sonnet, edit-only; audit D-0387 item 2; sizing: lk-channel evidence/R2/tab1min_sizing.md)

Branch wip/tab1min in /home/shivaji1012/code/lk-tab1, off origin/main f08167f. NOTHING is compiled or run: every line is UNVERIFIED.
NOT mine: T2 (pl-incl.jl `tabling` field, pl-proc.jl) and T3 (opcodes, pl-wam.jl, pl-vmi.jl numbers: Q3 is the audit's).

## Capability search (CLAUDE.md OPERATING RULES), main f08167f
`bash workflows/capability_search.sh <term>` covers Core/FabricPC/MORK/PathMap, not LogicKernel; the LogicKernel check is
`git grep -n -i <term> -- src` on the worktree (log: scratchpad t1w1-gitgrep.log). Results:
- tbl_trienode: found only in this plan. trienode: reserved symbol only (src/pl-atom.jl:964, :2023; src/pl-ressymbol.jl:18, :108).
- wrap_predicate: src/pl-ext.jl:1040 (meta-spec list entry `unwrap_predicate`), src/pl-supervisor.jl:21 (comment). closure_blob:
  a comment on closures at src/pl-wam.jl:3488. callwrapper: comments at src/pl-supervisor.jl:21, :53 (the DIVERGES T5 removes).
- S_WRAP, skipWrapperPrefix, resetWrappedSupervisor: found only in this plan. "tabling": only comments and flag notes (pl-prologflag.jl).

## Plan (commit order; each group committed, this file updated after each)
G0 plan (this file).
G1 T1: src/pl-tabling.jl (NEW) `'$tbl_trienode'/1`, `'$tbl_is_trienode'/1` (pl-tabling.c:6253-6277), PL_predicates_from_tabling;
   include in src/LogicKernel.jl before pl-ext.jl, registration in src/pl-ext.jl (the two tables, appended last).
G2 T1 rows: test/core_lang/test_tabling_min_swipl.jl + evidence/TAB1MIN generator/driver/pins from swipl 10.1.19 (two runs).
G3 T4: src/pl-wrap.jl (NEW) closure blob + `'$c_wrap_predicate'/5` + helpers. Needs T3's S_CALLWRAPPER/S_TABLED opcodes and T2's
   `tabling` flag bits: written against those NAMES; the file is not loadable before T3. Dependency recorded below.
G4 T5: freeCodesDefinition! wrapper branch, resetWrappedSupervisor, skipWrapperPrefix, unregisterWrappedSupervisor in
   src/pl-supervisor.jl (the DIVERGES at :64-72 goes). Needs only T4's closure type.
G5 T4/T5 rows (direct `$c_wrap_predicate` rows; the clause-add-after-wrap row that FAILS without T5).
G6 mutants tools/mutants/TAB1MIN.py (>= 8), manifest entries, docs/architecture.md block, final handoff.

## Status
(updated after each commit below)

## STATE at the hand-back (writer 1 hit the 150k context cap; all UNVERIFIED: nothing compiled or run)
Committed on wip/tab1min (worktree /home/shivaji1012/code/lk-tab1, base origin/main f08167f):
- 701e758 G0 plan.
- 0f8e0bd G1 T1: src/pl-tabling.jl (NEW) `'$tbl_trienode'/1`, `'$tbl_is_trienode'/1`, `PL_predicates_from_tabling`; included after
  pl-dict.jl in src/LogicKernel.jl; appended last in `_PRED_TABLES` and `_FOREIGN_VA` of src/pl-ext.jl.
- 99011e6 G2 T1 rows: test/core_lang/test_tabling_min_swipl.jl (rows tmt01-tmt22; copy of test_event_swipl.jl's driver/runner;
  pins from swipl 10.1.19, two byte-identical runs), evidence/TAB1MIN/gen_rows.py, tm_rows.pl, tm_driver.pl, tm_rows.out.
  New groups append cases to `_TM_CASES` (ids `tm[a-z]NN`: tmw = `$c_wrap_predicate`, tmc = clause added after the wrap) then
  `python3 -I gen_rows.py ../../test/core_lang/test_tabling_min_swipl.jl` in evidence/TAB1MIN, run `LC_ALL=C swipl -q tm_driver.pl`
  twice (cmp), `--fill`. The non-vacuity testset names tmt only: extend its prefix list.

Left (NOT written): G3 T4 src/pl-wrap.jl, G4 T5 (pl-supervisor.jl freeCodesDefinition! wrapper branch), G5 rows, G6 mutants
tools/mutants/TAB1MIN.py (>= 8), manifest entries (`_manifest_index` end: `LK.pl_tbl_trienode1_va`, `LK.pl_tbl_is_trienode1_va` as
`Tuple{LD, Int, Int, LK.control_t{T}}` rows like the BOOTPRED3 block, and `(LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_tabling)}, false)`
after test/static_analysis_manifest.jl:3352), docs/architecture.md block at the END (row for src/pl-tabling.jl), WHATS-HERE-UPSTREAM header.
Mutants for T1 so far (to write): TARGETS = test_tabling_min_swipl.jl (+ every test that calls the predicates: none found by git grep
of test/ for tbl_/trienode: only test_atom_table.jl:183 names the atom); candidate mutants: `w == ATOM_trienode` -> `w != ATOM_trienode`;
`k == DU_WORD && ` dropped; `mk_reserved_symbol(T, :trienode)` -> `mk_sym(T, :trienode)` (kills tmt01/tmt11).

### Findings that shape T4/T5 (read from the kernel, main f08167f)
1. Supervisors are `codes::Vector{code}` + side table `codes_crefs` (src/pl-supervisor.jl header): a wrapper supervisor is
   `code[S_CALLWRAPPER-or-S_TABLED, code(1), closure atom word, wrapper-name atom word]` with `codes_crefs = [wrapper clause ref]`
   (the operand `codes[1]` indexes the side table, like `S_TRUSTME` in singleClauseSupervisor). `chainPredicateSupervisor(def, (codes, crefs))`
   exists and returns a tuple; there is NO `setSupervisor`/`allocCodes`: install with `def.codes, def.codes_crefs = ...`
   (upstream `def->codes = SUPERVISOR(virgin); setSupervisor` = set the chained tuple; see setDefaultSupervisor for the idiom).
   `freeSupervisor` is a no-op; `freeCodesDefinition!` is at pl-supervisor.jl:64-72 (the DIVERGES T5 removes).
2. `definition{T}` (pl-incl.jl:872) has `const code_data::PL_code_data` and `const name`; a closure's copy of the definition
   needs a fresh `definition{T}(...)` (impl_clauses = an empty `clause_list`, because upstream's `impl` union overlays the clause list
   with `wrapped.predicate/.supervisor`), `codes = code_data.wrapper` (T3's new block of `PL_code_data`, pl-incl.jl:772).
3. BLOB STORAGE NEEDS A GLOBAL-DATA FIELD (T4 BLOCKER, not mine to edit): a unique blob holds bytes only. The clause and record blobs
   keep a serial in the payload and the object in `gd.clause_refs` / `gd.record_refs` (src/pl-dbref.jl:40-135, :180-230; src/pl-global.jl:93-98,
   :203-208). The closure needs the same: `gd.closure_refs::Vector{closure{T}}` in src/pl-global.jl (+ constructor entry), and
   `mutable struct closure{T}` (fields: `def::definition{T}` the copy, `predicate::definition{T}`, `supervisor::Vector{code}`,
   `supervisor_crefs`) in src/pl-incl.jl after `definition` (a struct field cannot be `::Any`: test_type_discipline). Blob type:
   `const closure_blob = PL_blob_t(PL_BLOB_UNIQUE, "closure")`; register it with `PL_register_blob_type(atoms, closure_blob, builtin_atom("closure"))`
   (is `closure` in `_BUILTIN_ATOM_IDS`? NOT CHECKED); payload `_clref_bytes`-style serial; read back like `recref_record`
   (`atomValue(gd.atoms, blob_handle(a)).type === closure_blob`); build the term with `lookupBlob` + `_blob_term!` (pl-dbref.jl:199-201).
   Printing `<closure>(m:p/1)` needs the writer's blob hook (the kernel's stream blob has none: `<stream>(0x..)` is the term layer's):
   a DIVERGES row, pin it in the rows as UNVERIFIED.
4. `unify_wrapped` builds `call(<blob>(Args...))` as a compound whose functor name is the blob atom: use `lookupFunctorDef(ld.functors,
   closure_atom_word, arity)` + the FLI (`PL_new_term_ref`, `PL_unify_functor` pl-fli.jl:171, `PL_unify_atom` :1084); `get_procedure` is at
   src/pl-proc.jl:1376 (GP_DEFINE), `assert_term!` at src/pl-comp.jl:4032, `retractClauseDefinition!` pl-proc.jl:599,
   `pushPredicateAccessObj!` pl-thread.jl:38: signatures NOT YET READ. Whether pl-comp compiles a blob-headed compound inside
   `call/1` (sizing Q1/R3): NOT READ.
5. T4 needs, beyond T1: T3's `S_CALLWRAPPER`, `S_TABLED`, `S_WRAP` opcodes and the `wrapper` block (`PL_code_data.wrapper`, built by
   `initSupervisors`), T2's `definition.tabling` + `TP_VARIANT` (for `wrapper_vmi`), item 3's struct/GD fields. ONE struct commit (T2: tabling
   field; T3: wrapper block; item 3: closure struct + `closure_refs`) means ONE daemon restart; the prepared text above is the spec for it.
   T5 needs only the closure type and the opcodes (`skipWrapperPrefix` reads S_MQUAL/S_LMQUAL/S_DET/S_SSU_DET: all declared; `isCallWrapper`
   reads the two new opcodes).
6. Registration of `$c_wrap_predicate/5` goes into `PL_predicates_from_wrap` (flags PL_FA_TRANSPARENT|PL_FA_VARARGS), appended to pl-ext.jl
   exactly as T1 did (include pl-wrap.jl after pl-tabling.jl; `# allow-new-artifact: <reason>` line in the new file, the hook demands it;
   the absence-claim hook fires on text that quotes a status phrase of a source comment: say "left out" or describe the comment).
7. The test rows for T4/T5 cannot run before the struct commit; write them against the pins measured in the sizing section 5
   ('$tabling':'$wrap$eval_subgoal_in_residual'/2: dynamic, volatile, transparent, notrace, number_of_clauses(1)) and add a row that adds a clause
   after the wrap and checks `number_of_clauses` of the WRAPPER predicate AND the wrapped predicate (the row must FAIL without T5).

### Rulings relayed after the hand-back (audit D-0388 item 5; recorded, not yet acted on)
- Q3: T3's opcode numbers follow the PIN's VMI order (pl-vmi.c), not "next free"; whichever of T3 and b2 lands second renumbers its own.
- OPEN, to do by the next agent BEFORE T3 is written: grep test/ and tools/ (named files, git grep) for pinned opcode numbers 159..165 and
  the codes' names in `_CODE_TABLE` rows, and list the hits here. NOT DONE by writer 1 (context cap).
- Q1 (a) closure record; Q2 (a) install-only with named refusals; Q4 the code goes in new src/pl-tabling.jl (T1 did; T4's closure/wrap
  code is the question of src/pl-wrap.jl vs pl-tabling.jl: the ruling names pl-tabling.jl for the reserved-symbol predicates, the sizing
  names pl-wrap.jl for pl-wrap.c: keep pl-wrap.c's code in pl-wrap.jl, one file per upstream file); Q5 no reader substitute.

## READY-FOR-GATE
Nothing yet: T1 (pl-tabling.jl + rows tmt) is complete as written but is gated together with the rest (inventory, fmt, check, rows x3, pkgtest_way on
test_tabling_min_swipl.jl, type discipline, mutants TAB1MIN not yet written).
Daemons: this writer started none and ran no Julia.
