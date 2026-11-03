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

## WRITER 2 (Sonnet, edit-only; nothing compiled or run: every line UNVERIFIED). Origin/main still f08167f at start: ENG3 NOT landed.
Scratch logs are in the shared scratchpad with prefix t1w2-.
### Opcode-number grep (D-0388 item 5; `git grep` over test/ and tools/, 37 lines, log t1w2-opnum.log)
No test or tool pins the numbers 159..165 as opcodes (hits are unrelated: signal numbers in test_halt_swipl.jl, array indexes, bench tsv).
ONE test reads the whole table: test/foreign/test_query.jl:305-330 builds `notrun` = every opcode of `LK._CODE_TABLE` whose name is not in `LK.VMI_RUN`,
takes `first(notrun)` and expects a NotPortedError naming it (and `isempty(notrun)` is an error). T3 must keep at least one declared opcode
outside VMI_RUN, and the named-refusal bodies of S_CALLWRAPPER/S_TABLED/S_WRAP change which opcode is first (only if they are declared before it).
### T2 (struct commit): written, committed (see git log: "T2")
- src/pl-incl.jl: `TP_TABLED..TP_VARIANT` (pl-tabling.h), `mutable struct table_props` (flags, abstract, subgoal_abstract, answer_abstract,
  max_answers as Int with -1 for (size_t)-1, start_id; `lazy_queue` left to TAB1: DIVERGES), field `tabling::Union{Nothing, table_props}` AFTER `events`
  in `definition{T}` (the 11-argument outer constructor passes `nothing, nothing`), `mutable struct closure{T}` (def, predicate, supervisor,
  supervisor_crefs) after `const Definition`.
- src/pl-global.jl: `const closure_refs::Vector{closure{T}}` appended at the END of `PL_global_data` and of its constructor call, header note.
- src/pl-tabling.jl: clear_table_props!, tbl_reset_tabling_attributes!, get_predicate_table_props!, tbl_get_predicate_attribute, get_size_or_inf,
  tbl_set_incremental_predicate (calls freeCodesDefinition!), set_bool_attr, tbl_set_predicate_attribute.
- src/pl-proc.jl: `$set_predicate_attribute` tabling branch BEFORE `get_bool_or_int_ex` (upstream order: pl-proc.c:3864-3868; value may be `infinite`),
  `$get_predicate_attribute` calls tbl_get_predicate_attribute (was `FFALSE`), resetProcedure! clears the properties.
  unallocDefinition (pl-proc.c:264): Julia's GC frees the properties; no hook is written.
- NOT done in T2: `_tbl_is_predicate_attribute` stays in pl-proc.jl (already there, unchanged); the blob type and `initWrap!` come with T4.
- The struct changes (definition.tabling, PL_global_data.closure_refs) restart the daemon: cold compile at the gate.
- T2 commit: 921d1eb. (A reworded comment in pl-proc.jl: the absence-claim hook fires on a re-flowed old comment that holds the phrase for
  a not-ported item; the new text says "left to a transactions step".)
- T2 rows (swipl-compared `$set_predicate_attribute` / `$get_predicate_attribute` of tabled, tabled_variant, incremental, abstract
  infinite/integer, the type error of a non-bool, and the resetProcedure clear) are NOT WRITTEN: a `tmt`-style group `tma` in gen_rows.py.

### STATE at the forced hand-back of writer 2 (context cap): T2 committed; T4, T5, T3, rows, mutants, manifest, docs NOT WRITTEN
ENG3 has NOT landed (origin/main still f08167f at writer 2's start): T3 (opcodes S_CALLWRAPPER/S_TABLED/S_WRAP, `wrapper` field of
PL_code_data, pl-wam.jl bodies) was not touched. T4 and T5 need T3's names (`S_CALLWRAPPER`, `S_TABLED`, `code_data.wrapper`).

#### What writer 2 READ for T4 (signatures; all UNVERIFIED against a run)
- Upstream pl-wrap.c at the pin: write_closure prints `<closure>(%s)` with predicateName; unify_closure :132-142; skipWrapperPrefix :170-187;
  unregisterWrappedSupervisor :190-203; resetWrappedSupervisor :205-226; find_wrapper :228-243; assert_wrapper :246-278; unify_wrapped :280-319;
  wrapper_vmi :322-332; c_wrap_predicate :337-403; initWrap :558 (`PL_register_blob_type(&_PL_closure_blob)`, called at pl-setup.c:152, after initDBRef).
- `closure` is NOT in ATOMS: `PL_register_blob_type(atoms, closure_blob)` (third argument defaulted) makes the atom by `lookupAtom` as upstream's
  `PL_new_atom(type->name)`. Plan: `const closure_blob = PL_blob_t(PL_BLOB_UNIQUE, "closure")` in src/pl-wrap.jl, `initWrap!(atoms)` called in the
  PL_global_data constructor (src/pl-global.jl) right after `initDBRef!(atoms)` (line ~160). Stale-pin risk: a test that counts atoms of a fresh database
  (test_atom_table.jl) or pins atom indexes: grep before the gate.
- Blob idiom (src/pl-dbref.jl:140-150, 112-125): `bytes = _clref_bytes(serial)`; `w, new = lookupBlob(gd.atoms, bytes, length(bytes), clause_blob)`;
  `a = _blob_term!(gd.atoms, gd.atom_symbols, T, w)`; read back `atomValue(gd.atoms, blob_handle(a)).type === closure_blob`, `serial = reinterpret(Int64, at.name[1:8])[1]`,
  `gd.closure_refs[Int(serial)]`. An atom word is `UInt64` and `code = UInt64` (pl-incl.jl:51), so a wrapper supervisor can hold the words directly:
  `code[S_CALLWRAPPER_or_S_TABLED, code(1), w_closure, _atom_word!(ld, wname)]` with crefs `[cref]` (operand 1 = index into the side table, as S_LIST's
  `code(1), code(2)` in src/pl-supervisor.jl:160). `_atom_word!(ld::PL_local_data{T}, v::T)` is src/pl-inline.jl:257; `_atom_value(ld, w)` :272.
- Supervisor install idiom: `codes, crefs = chainPredicateSupervisor(def, (codes, crefs))`; then `def.codes = def.code_data.virgin; def.codes, def.codes_crefs = codes, crefs`
  (setDefaultSupervisor, pl-supervisor.jl:~270, sets `def.codes`/`def.codes_crefs` directly; setSupervisor/allocCodes are replaced by that assignment).
- `get_procedure(gd, ld, descr, GP_DEFINE, head_term_ref)` returns the Procedure or `nothing` (pl-proc.jl:1376; the 5th argument receives the stripped head).
- `assert_term!(gd, ld, term, module_, where_, owner, loc, flags)` (pl-comp.jl:4032): call `assert_term!(gd, ld, A5, 0, CL_END, nothing, nothing, 0)`; returns the
  Clause{T} or `nothing`. The clause's predicate: check the `clause{T,D}` field name (`predicate`) at pl-incl.jl (~line 1010-1030, NOT READ).
  The ClauseRef of the clause: walk `def.impl_clauses.first_clause` until `cref.clause === cl` (as assert_wrapper does).
- `retractClauseDefinition!(gd, def, clause, notify)` (pl-proc.jl:588, no ld) or `(gd, ld, def, clause, notify)` (:596): upstream passes `false` for notify.
- `pushPredicateAccessObj!(ld, gd, def)` (pl-thread.jl:38, NOTE the argument order ld, gd) and `popPredicateAccess!(ld, def)`; `acquire_def/release_def` are threads-only
  (left out), the loop scanning for the cref sits between push and pop.
- unify_wrapped plan: `PL_get_name_arity(ld, ...)` (pl-fli.jl:532, signature NOT READ) or `_cp_get_functor(ld, head)` (pl-proc.jl:2276) for (name, arity); for arity > 0
  `t = PL_new_term_ref(ld)`; `PL_unify_functor(ld, t, closure_term::T, arity)` (pl-fli.jl:171: name is the T blob term, `_atom_word!` takes the blob branch),
  then per argument `_PL_get_arg(ld, i, head, tmp)` + `PL_unify_arg(ld, i, t, tmp)`, then `PL_unify(ld, wrapped, t)`; for arity 0 `PL_unify_atom(ld, wrapped, closure_term)`.
- unify_closure plan: copy = `definition{T}(def.functor_name, def.arity, ClauseList{T}() [set its `args` field to def.impl_clauses.args], def.flags, def.name,
  def.code_data.wrapper [T3], ClauseRef{T}[], def.code_data, def.impl_foreign_function, def.module_, def.shared)`; set `copy.tabling = def.tabling`, `copy.events = def.events`;
  `closure{T}(copy, def, supervisor, supervisor_crefs)`; push to `gd.closure_refs`, payload `_clref_bytes`-style (own `_closure_bytes`).
- OPEN, the gate decides: whether `compileClause`/`export_cells` accept a compound whose head is a BLOB (the wrapper clause body holds `<blob>(Args...)` as an argument of
  `start_tabling/3`, syspred.pl:1717-1732; it is data, not a goal). The term interface allows it; NOT READ in pl-comp.jl/export_cells.
- Printing `<closure>(m:p/1)`: the writer has no blob hook: DIVERGES row, UNVERIFIED.

#### Left, in order
1. T4 src/pl-wrap.jl (NEW, `# allow-new-artifact:` line): closure_blob, initWrap!, unify_closure, get_closure_predicate, find_wrapper, assert_wrapper, unify_wrapped, wrapper_vmi,
   pl_c_wrap_predicate5_va (PL_FA_TRANSPARENT|PL_FA_VARARGS) and `PL_predicates_from_wrap`; include after pl-tabling.jl in src/LogicKernel.jl; append the table to `_PRED_TABLES`/`_FOREIGN_VA` in
   src/pl-ext.jl as T1 did (grep the T1 diff `git show 0f8e0bd -- src/pl-ext.jl src/LogicKernel.jl`); call `initWrap!(atoms)` in pl-global.jl after initDBRef!.
2. T5 src/pl-supervisor.jl: `isCallWrapper`, `skipWrapperPrefix`, `unregisterWrappedSupervisor` (no-op: no atom refcounts), `resetWrappedSupervisor`, and the wrapper branch of
   `freeCodesDefinition!` (pl-supervisor.c:108-129 at the pin, NOT READ by writer 2; the current function is lines 52-64 of src/pl-supervisor.jl), dropping the DIVERGES text above it
   and the header lines 21-24; a white-box row: install a wrapper, add a clause (tabling.pl:2358 shape), the wrapper survives (must FAIL without T5).
3. T3 after ENG3 lands (`git -C /home/shivaji1012/code/lk-tab1 fetch origin`, `git rebase origin/main`): opcodes in src/pl-vmi.jl at the PIN's VMI order, `_CODE_TABLE` rows,
   `wrapper` field of PL_code_data (pl-incl.jl:~770) + `initSupervisors` (pl-supervisor.jl:36, `code[S_WRAP, I_EXIT]`) + the PL_code_data(...) literal at src/pl-global.jl:~611 (a 6-block literal in the
   idle index_context: needs the 7th), run-loop bodies in pl-wam.jl as named refusals. Keep one declared opcode outside VMI_RUN (test/foreign/test_query.jl:305-330).
4. rows tmt23+ (generator in evidence/TAB1MIN/gen_rows.py, `_TM_CASES`; groups tmw, tmc, tma), the non-vacuity prefix list; tools/mutants/TAB1MIN.py (>= 8 mutants over T1/T2/T4/T5, TARGETS =
   test_tabling_min_swipl.jl + test_pr1_swipl.jl (the getter row pr93) + every file the changed code reaches, `grep -L '@testset\|@test'` check); manifest entries at the END of `_manifest_index`
   (T1: `LK.pl_tbl_trienode1_va`, `LK.pl_tbl_is_trienode1_va`; T2: `clear_table_props!`, `tbl_reset_tabling_attributes!`, `get_predicate_table_props!`, `tbl_get_predicate_attribute`, `get_size_or_inf`,
   `tbl_set_incremental_predicate`, `set_bool_attr`, `tbl_set_predicate_attribute`); docs/architecture.md block at the END (rows for src/pl-tabling.jl, src/pl-wrap.jl).
5. READY-FOR-GATE list (D-order): inventory, fmt via warm.sh send, check (cold compile: struct change), rows x3 + type discipline + every file calling definition/closure code (grep -l), manifest, pkgtest_way
   one file at a time, alloc pins x3 (239/377/433; test_query 347 old main / 365 after ENG3), static_analysis (JET + AllocCheck), term grep, gate/tab1min + mutants/TAB1MIN at the same SHA.
   Expected effect on the T3 pin: `$init_goal/3` 2 -> 7 and load.pl's list reaching user:topvars; tabling.pl cannot be read before RDDICT (`#{}` :1280, `Dict0.put` :1373).
Daemon state: writer 2 started none, ran no Julia.

## WRITER 3 (Sonnet, edit-only; nothing compiled or run: every line UNVERIFIED). Forced hand-back at the 150k cap.
origin/main fetched at start: STILL f08167f (ENG3 NOT landed): T3 NOT TOUCHED. Scratch prefix t1w3-.
### Committed / staged
- 3ed9158 T4: src/pl-wrap.jl (NEW): closure_blob, _closure_bytes, closure_of_word(gd, w), initWrap!(atoms) (called in the
  PL_global_data constructor right after initDBRef!, pl-global.jl), unify_closure, get_closure_predicate, isCallWrapper,
  skipWrapperPrefix(codes, pc=1)::Int (1-based index; S_DET left out: not declared), find_wrapper(gd, def, namew) ->
  (codes, crefs, i) | nothing, assert_wrapper, unify_wrapped, wrapper_vmi, pl_c_wrap_predicate5_va, PL_predicates_from_wrap
  (PL_FA_TRANSPARENT|PL_FA_VARARGS); included after pl-tabling.jl in LogicKernel.jl, appended to _PRED_TABLES/_FOREIGN_VA.
  Wrapper supervisor layout: codes = code[op, 1, closure atom word, wrapper name atom word] (op at i, side-table index i+1,
  closure i+2, name i+3), crefs = [wrapper clause ref]; chained by chainPredicateSupervisor; installed by assigning
  def.codes / def.codes_crefs.
- T5 STAGED in the index (src/pl-supervisor.jl, src/pl-wrap.jl, src/pl-proc.jl, src/pl-tabling.jl), committed together with this
  handoff by the writer's last command (message: evidence/TAB1MIN/t1w3-msg-t5.txt in lk-channel, removed after): if `git log` does
  not show it, run `git status`, and commit the staged files with the message "UPSTREAM: pl-supervisor.c freeCodesDefinition wrapper
  branch; pl-wrap.c resetWrappedSupervisor, unregisterWrappedSupervisor (swipl-devel cbf4e1896275)".
  Content: freeCodesDefinition!(gd, def, do_linger) = the whole upstream function (pl-supervisor.c:108-129); the 2-argument method
  keeps the old behaviour for an unwrapped def and THROWS NotPortedError naming "freeCodesDefinition! of a wrapped predicate needs the
  database" for a wrapped one; resetWrappedSupervisor(gd, def0, do_linger) and a no-op unregisterWrappedSupervisor in pl-wrap.jl;
  _assertDefinition! (pl-proc.jl) passes gd; tbl_set_incremental_predicate now takes gd (set_bool_attr passes _query_gd(ld)).
### DESIGN QUESTION for the audit (T5)
Q-A: freeCodesDefinition! has no database at setDynamicDefinition! (pl-proc.jl:363), resetProcedure! (:926), setThreadLocalDefinition!
(:1537); the closure is found through gd.closure_refs. Options: (a) as written: the 2-arg method refuses a wrapped predicate by name
(`dynamic`/abolish of a wrapped predicate then raises; deferred to TAB1); (b) thread gd through those three functions and their ~25
callers (test files call setDynamicDefinition!(def, bool)); (c) a closure back-pointer in `definition` (impossible: mutually recursive
structs). RECOMMEND (a) for the minimal slice.
### NOT DONE (all UNVERIFIED / NOT STARTED), in order
1. T5 white-box row (an installed wrapper survives the first added clause; must FAIL without T5) and rows tmt23+: groups tma (T2 attribute
   rows), tmw (`$c_wrap_predicate`), tmc (clause after wrap), pins from swipl 10.1.19 via evidence/TAB1MIN/gen_rows.py (see the T1 notes
   above: `_TM_CASES`, two byte-identical runs, `--fill`, extend the non-vacuity prefix list).
2. tools/mutants/TAB1MIN.py (>= 10 mutants over T1/T2/T4/T5; TARGETS: test_tabling_min_swipl.jl, test_pr1_swipl.jl (getter row pr93),
   test_type_discipline.jl, test_atom_table.jl [the `closure` atom adds one atom to a fresh database: grep for a pinned count]; module
   TARGETS only real test files: `grep -L '@testset\|@test'`); candidate mutants: T1 `w == ATOM_trienode` -> `!=`; `mk_reserved_symbol` ->
   `mk_sym`; T4 `codes[i + 3] == name` -> `!=`; wrapper_vmi S_TABLED<->S_CALLWRAPPER; skipWrapperPrefix `pc += 2` -> `+= 1`; T5 drop the
   `isCallWrapper` branch of freeCodesDefinition!; resetWrappedSupervisor `c.supervisor = virgin` removed; T2 `p.flags |= flag`.
   Every `old` once (throwaway python3 -I checker), ids unique, old != new.
3. Manifest entries at the END of `_manifest_index` (test/static_analysis_manifest.jl): T1 pl_tbl_trienode1_va / pl_tbl_is_trienode1_va
   (Tuple{LD, Int, Int, LK.control_t{T}} rows like the BOOTPRED3 block), PL_predicates_from_tabling, T2 functions (clear_table_props!,
   tbl_reset_tabling_attributes!, get_predicate_table_props!, tbl_get_predicate_attribute, get_size_or_inf,
   tbl_set_incremental_predicate(gd, def, Bool), set_bool_attr, tbl_set_predicate_attribute), T4 (closure_of_word, initWrap!, unify_closure,
   get_closure_predicate, isCallWrapper, skipWrapperPrefix, unregisterWrappedSupervisor, resetWrappedSupervisor, find_wrapper, assert_wrapper,
   unify_wrapped, wrapper_vmi, pl_c_wrap_predicate5_va, _closure_bytes), T5 (the 3-arg freeCodesDefinition!; the 2-arg row at
   test/static_analysis_manifest.jl:1416 stays); docs/architecture.md block at the END (rows for src/pl-tabling.jl and src/pl-wrap.jl;
   DIVERGES: table_props sizes as Int with -1 for (size_t)-1 and the representation_error above typemax(Int); lazy_queue left to TAB1;
   `<closure>(m:p/1)` needs a writer blob hook: a DIVERGES row; closure = a record, owner WRAP1). Never regenerate docs/port_inventory.md.
4. T3 (after ENG3 lands: `git fetch origin`, `git rebase origin/main`): see "Left, in order" item 3 of writer 2 above; T4/T5 need
   S_CALLWRAPPER, S_TABLED, S_WRAP, `code_data.wrapper` (a 7th block in PL_code_data, initSupervisors, the PL_code_data literal in
   pl-global.jl ~611), S_MQUAL/S_LMQUAL/S_SSU_DET exist (pl-vmi.jl:567-582, S_DET is NOT declared). Opcodes at the PIN's VMI order, named
   refusals in pl-wam.jl, keep one declared opcode outside VMI_RUN (test/foreign/test_query.jl:305-330).
5. READY-FOR-GATE (D-order): inventory, fmt via warm.sh send, check (cold compile: struct change), rows x3, type discipline, test_atom_table,
   manifest entries, pkgtest_way (one file at a time), alloc pins x3 (239/377/433; test_query 347 on f08167f / 365 after ENG3), static analysis
   (JET + AllocCheck), term grep (crash-term pattern over diff + messages), gate/tab1min + mutants/TAB1MIN at the same SHA.
   Things the gate must check that the writers could not: `ClauseList{T}()` + `cl.args =` assignment (clause_list is mutable), `PL_unify_functor`
   with a blob T-term as the name, `atomValue(gd.atoms, w)` on a blob word, `_atom_value(ld, w)` for the closure word (symbol recorded by
   `_blob_term!`), `assert_term!` accepting a blob-headed compound inside the wrapper clause body (open since writer 1), whether the
   `closure` atom shifts a pinned atom count (test_atom_table.jl) or blob rank.
Daemon state: writer 3 started none, ran no Julia.

## WRITER 4 (Sonnet, edit-only; nothing compiled or run: every line UNVERIFIED). Scratch prefix t1w4-.
origin/main fetched at start: STILL f08167f (ENG3 NOT landed): T3 NOT TOUCHED (it needs ENG3's stubs; opcodes in the PIN's VMI order
[S_CALLWRAPPER, S_TABLED, S_WRAP], the 7th block `wrapper` in PL_code_data + initSupervisors + the idle index_context literal at
pl-global.jl ~611, named-refusal bodies in pl-wam.jl, ONE declared opcode outside VMI_RUN for test/foreign/test_query.jl:305-330; b2
holds 159..165, whoever lands second renumbers).
### DISPATCHER RULING (provisional, pending audit) on writer 3's Q-A
Option (a): the 2-argument freeCodesDefinition! raises a named refusal naming the problem for a wrapped predicate, so `dynamic` or
abolish of a wrapped predicate is refused until TAB1; (b) (thread gd through ~25 callers) and (c) (a back-pointer; impossible in
Julia) are NOT taken. Stated in the architecture DIVERGES with owner TAB1.
### Committed by writer 4 (in order; each commit also updates this file)
1. rows tma01-tma23 (T2), tmw01-tmw13 (T4), tmc01-tmc06 (T5) in test/core_lang/test_tabling_min_swipl.jl + a white-box testset
   (LK-only: wrapper supervisors read from `def.codes`/`closure_of_word`); pins from swipl 10.1.19 (two byte-identical runs, 64 cases,
   LC_ALL=C), evidence/TAB1MIN/tm_rows.{pl,out}, tm_driver.pl; non-vacuity prefix list tmt/tma/tmw/tmc + distinctness asserts.
   Rows that FAIL without T5: tmc02, tmc03 (the rewrap of a name after a clause add finds the SAME closure), white-box `_tm_wrapped(d01c)`.
   `tmc` rows wrap in a DIRECTIVE of the consulted program (assertProcedure calls freeCodesDefinition only for STATIC predicates, so
   a clause added by `assertz` to a dynamic one never reaches it: the clause must come from the file).
   Not written: rows that CALL a wrapped predicate (S_CALLWRAPPER/S_WRAP run-loop bodies are named refusals; WRAP1).
2. row tmc07 (a predicate that RAN before the wrap: the clause add resets the wrapped supervisor) + white-box rows (c06.supervisor virgin,
   rewrap installs the newest wrapper clause in the side table) + a unit testset for skipWrapperPrefix/isCallWrapper (hand-built codes
   with S_MQUAL, S_LMQUAL, S_SSU_DET prefixes): these kill the pc increments and the side-table update, which no swipl row reaches.

### STATE at writer 4's hand-back (150k cap hit before the mutants file). Committed: 6033b70 (rows), b95f2e1 (tmc07 + white-box/unit rows). All UNVERIFIED.
origin/main still f08167f at start (ENG3 NOT landed): T3 NOT possible/NOT TOUCHED (needs: opcodes at the PIN's VMI order [S_CALLWRAPPER, S_TABLED, S_WRAP],
7th block `wrapper` in PL_code_data + initSupervisors + the idle index_context literal at pl-global.jl ~611, named-refusal bodies in pl-wam.jl, one declared
opcode outside VMI_RUN for test/foreign/test_query.jl:305-330; b2 holds 159..165). The tmw/tmc rows and the white-box rows cannot load before T3.
Rows now: 65 cases (tmt01-22, tma01-23, tmw01-13, tmc01-07), pins from two identical swipl 10.1.19 runs; kernel-FAIL-without-T5: tmc02, tmc03, tmc07 (white-box), `_tm_wrapped`.
#### LEFT (next agent), in order
A. tools/mutants/TAB1MIN.py (format of tools/mutants/MOD3b.py: dict(id, file, old, new, targets); module TARGETS = real test files only, `grep -L '@testset\|@test'`).
   TM = test/core_lang/test_tabling_min_swipl.jl; getter mutants add test/core_lang/test_pr1_swipl.jl (pr93); supervisor/reset mutants add test_pr1_swipl.jl + test_event_swipl.jl.
   Candidates (anchor line then mutation; check each `old` occurs exactly once with a throwaway python3 -I script): pl-tabling.jl `w == ATOM_trienode` -> `!=`;
   `mk_reserved_symbol(T, :trienode)` -> `mk_sym(T, :trienode)`; set_bool_attr `props.flags |= flag` -> `|= TP_TABLED`; `props.flags &= ~flag` -> no-op;
   tbl_get `(p.flags & TP_VARIANT) != 0 ? 1 : 0` -> TP_TABLED; `v0 != -1 &&` -> `v0 != -2 &&`; tbl_reset `p === nothing || clear_table_props!(p)` -> `|| nothing`;
   tbl_set `set_bool_attr(ld, def, TP_INCREMENTAL, value)` (the :incremental branch) -> TP_MONOTONIC; `if val != now` -> `if val == now`;
   pl-proc.jl resetProcedure! `def.tabling === nothing || tbl_reset_tabling_attributes!(def)` -> drop the call;
   pl-wrap.jl `codes[i + 3] == name && return` -> `!=`; wrapper_vmi `return S_TABLED` -> `return S_CALLWRAPPER`; unify_wrapped arity-0 `return PL_unify_atom(ld, wrapped, clo)` -> `return false`;
   `retractClauseDefinition!(gd, old.predicate, old, false)` removed (kills tmw05); `crefs[Int(codes[i + 1])] = cref` removed (white-box side-table row);
   skipWrapperPrefix `pc += 2` -> `pc += 1`; isCallWrapper `|| c == S_TABLED` dropped; resetWrappedSupervisor `while isCallWrapper(codes[cw])` -> `if` (kills tmc03);
   `c.supervisor = def0.code_data.virgin` removed (kills only via tmc07/white-box c06, because a never-called predicate already has the virgin supervisor);
   pl-supervisor.jl 3-arg freeCodesDefinition! `if isCallWrapper(codes[skipWrapperPrefix(codes)])` -> `if false`, and `if !do_linger` -> `if do_linger` (kill tmc02);
   2-arg method's `throw(` refusal -> `nothing` (white-box @test_throws).
B. manifest entries at the END of `_manifest_index` (test/static_analysis_manifest.jl): `LK.pl_tbl_trienode1_va`, `LK.pl_tbl_is_trienode1_va` (Tuple{LD, Int, Int, LK.control_t{T}} rows
   like the BOOTPRED3 block), `(LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_tabling)}, false)` after :3352, T2 (clear_table_props!, tbl_reset_tabling_attributes!,
   get_predicate_table_props!, tbl_get_predicate_attribute, get_size_or_inf, tbl_set_incremental_predicate(gd, def, Bool), set_bool_attr, tbl_set_predicate_attribute), T4
   (closure_of_word, initWrap!, unify_closure, get_closure_predicate, isCallWrapper, skipWrapperPrefix, unregisterWrappedSupervisor, resetWrappedSupervisor, find_wrapper,
   assert_wrapper, unify_wrapped, wrapper_vmi, pl_c_wrap_predicate5_va, _closure_bytes), T5 (3-arg freeCodesDefinition!; the 2-arg row at :1416 stays);
   check with `git diff f08167f HEAD -- src` that no new function is missing. docs/architecture.md block at the END: UPSTREAM header names pl-tabling.c, pl-wrap.c, pl-supervisor.c,
   pl-proc.c rows; DIVERGES: table_props sizes as Int with -1 for (size_t)-1 and the representation_error above typemax(Int); lazy_queue left to TAB1; Q-A (the 2-argument
   freeCodesDefinition! refuses a wrapped predicate by name: `dynamic`/abolish of a wrapped predicate refused until TAB1; owner TAB1; ruling above); printing `<closure>(m:p/1)` needs a
   writer blob hook; closure = a record (owner WRAP1); ORIGINAL rows; never regenerate docs/port_inventory.md.
C. READY-FOR-GATE list (D-order), once T3 exists: inventory (`warm.sh inventory`), fmt via warm.sh send, check (struct change restarts the daemon: cold compile), rows on three term types,
   test/test_type_discipline.jl, test_atom_table.jl (the `closure` atom adds one atom), manifest entries, `tools/pkgtest_way.sh test/core_lang/test_tabling_min_swipl.jl` one at a time,
   alloc pins x3 (239/377/433; test_query 347 on f08167f / 365 after ENG3), static analysis (JET + AllocCheck), crash-term grep over diff + messages, push mutants/TAB1MIN and gate/tab1min at the SAME SHA.
   Things only the gate can check: `ClauseList{T}()` + `cl.args =`, `PL_unify_functor` with a blob T-term as name, `atomValue` on a blob word, `assert_term!` accepting a blob-headed compound
   (row tmw12 reads it back through clause/2), whether `closure` shifts a pinned atom count, `blob/2` of the closure blob (tmw02-04), `abolish` of a dynamic tm_x22 clearing the properties (tma22).
Daemon state: writer 4 started none, ran no Julia. Scratch prefix t1w4-.

## WRITER 5 (Sonnet, edit-only; nothing compiled or run: every line UNVERIFIED). Scratch prefix t1w5-.
origin/main fetched at start: STILL f08167f (ENG3 NOT landed): T3 NOT possible (needs ENG3's stubs); NOT TOUCHED.
1. (A) tools/mutants/TAB1MIN.py: 33 mutants (ids TAB1MIN-A1..D10) over T1/T2/T4/T5; validated by a throwaway python3 -I script
   (each `old` once, old != new, ids unique, targets exist, module TARGETS = five real test files [`grep -L '@testset\|@test'` empty]).
   NOT LISTED with reasons: `k == DU_WORD &&` of `$tbl_is_trienode`, `freeCodesDefinition!` in `tbl_set_incremental_predicate`,
   the two asserts, `unregisterWrappedSupervisor` (header of the file). D6 (side table reset) kills only if the called single-clause
   supervisor had a side-table entry: new white-box row `@test isempty(c06.supervisor_crefs)` added to the test file (UNVERIFIED).
   Commit 5a6a6de.
2. (B) manifest entries (test/static_analysis_manifest.jl): at the END of `_manifest_index(T)` (the 3 pl_*_va rows, T2 functions,
   T4/T5 functions incl. the 3-argument freeCodesDefinition!, noalloc false) and at the end of `_DISPATCH_MANIFEST_TUPLE` (the two
   `_extension_sigs` rows, `table_props()`, clear_table_props!, _closure_bytes, initWrap!, isCallWrapper, skipWrapperPrefix [1 and 2
   args], unregisterWrappedSupervisor). Checked against `git diff f08167f HEAD -U0 -- src`: every new function/method has a row
   (the auto constructors of table_props [6 args] and closure/definition are structs' own). RISK for the gate: the 2-argument
   freeCodesDefinition! row (:1416) is `noalloc=true` and the method now contains a `throw(NotPortedError...)` branch: if AllocCheck
   counts the throw path, flip that row to false (alloc pin). Commit c9edf71.
3. (docs) docs/architecture.md: rows for src/pl-tabling.jl (`src/pl-tabling.c`) and src/pl-wrap.jl (`src/pl-wrap.c`, `src/pl-wrap.h`)
   after the pl-event.jl row of "What's here", the pl-incl.jl row gains `src/pl-tabling.h`, `src/pl-wrap.h`, and the block
   "TAB1-min" at the END (ported, T3 NOT STARTED, DIVERGES 1-5 with owners [sizes as Int -1; lazy_queue; Q-A; writer blob hook; closure
   = record], left out, ORIGINAL, tests/mutants). FOUND and FIXED: src/pl-incl.jl had `# PORT: pl-tabling.h` and `# PORT: pl-wrap.h`
   markers but no matching UPSTREAM header lines (port_check MARKER-FILE-UNKNOWN): the two UPSTREAM lines are added to the file header.
   docs/port_inventory.md NOT regenerated (the gate does; the inventory's counts and the new files' rows come with it).
   Commit ae550dc. Writer 5 hit the 150k cap here (forced hand-back); this section 4 (ready list) is in the handoff commit after it.
4. READY-FOR-GATE LIST (final state). CAN THE GATE START? NO: T3 is NOT on the branch (ENG3 not landed; origin/main = f08167f at the
   start of writer 5). Without S_CALLWRAPPER/S_TABLED/S_WRAP and `code_data.wrapper`, src/pl-wrap.jl, the isCallWrapper branch of
   pl-supervisor.jl and `unify_closure` do not load. Order: (a) ENG3 lands, `git fetch origin`, `git rebase origin/main`, T3 by a new
   writer (opcodes at the PIN's VMI order S_CALLWRAPPER, S_TABLED, S_WRAP; 7th block `wrapper` in PL_code_data + initSupervisors + the idle
   index_context literal at pl-global.jl ~611; named-refusal bodies in pl-wam.jl; ONE declared opcode outside VMI_RUN: test/foreign/test_query.jl:305-330;
   no test or tool pins 159..165 [writer 2's grep]; b2 holds 159..165, the second to land renumbers). (b) then the gate, D-order:
   `warm.sh inventory` (commit the generated docs/port_inventory.md; WHATS-HERE-UPSTREAM and MARKER-FILE-UNKNOWN were checked by reading only),
   fmt via warm.sh send (RE-FIT the mutants' anchors fmt rewraps), `warm.sh check` (struct change: cold compile), test/core_lang/test_tabling_min_swipl.jl
   on all three term types, test/test_type_discipline.jl, test_atom_table.jl (the `closure` atom), test_pr1_swipl.jl (pr93) and test_event_swipl.jl,
   test_procedures.jl, test_assert_swipl.jl (freeCodesDefinition! callers), `tools/pkgtest_way.sh test/core_lang/test_tabling_min_swipl.jl` (one at a time),
   alloc pins x3 (239/377/433; test_query 347 on f08167f / 365 after ENG3; the 2-arg freeCodesDefinition! row :1416 is noalloc=true and now has a throw branch),
   static analysis (JET + AllocCheck), crash-term grep over diff + messages, push mutants/TAB1MIN and gate/tab1min at the SAME SHA.
   Only the gate can check (writers could not): `ClauseList{T}()` + `cl.args =`, `PL_unify_functor` with a blob T-term as name, `atomValue` on a blob word,
   `assert_term!` accepting a blob-headed compound (tmw12), whether `closure` shifts a pinned atom count, `blob/2` of the closure (tmw02-04), `abolish` of a
   dynamic tm_x22 clearing the properties (tma22), D6's white-box `isempty(c06.supervisor_crefs)`.
   Commits on wip/tab1min (writer 5): 5a6a6de mutants (33), c9edf71 manifest rows, ae550dc docs block.
   Daemons: writer 5 started none, ran no Julia.
