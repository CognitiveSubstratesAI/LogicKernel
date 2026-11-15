# TAB1 first-run report at 99e5975c (lane 2, wip/tab1-mono), three types per file, one file at a time

Method: `LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file test/core_lang/<file>` (reference, alt, alt_interned), one file
at a time on the warm daemon. Counts are per three types (a failure counted 3x is ONE row failing on every type, unless stated).
swipl = pin binary `~/.local/bin/swipl` (10.1.20, 18168e62); the answers of the rows are the pins of each file (swipl's own `~q`, two
identical runs; for the monotonic file re-measured here: two runs, same md5 6c2ec356f21fee67b71df7d7806b7592).
Classes: TEST/DRIVER = a row, harness or fixture of the test file; ENGINE = the kernel's answer differs from swipl's (named, not pinned, not fixed).
Upstream source only via `git -C ~/dev-zone/swipl-devel show 18168e62:<file>`.

## Files that PASS on three types (rc 0, no Test Failed / Error During)
abolish_delay_deps, abolish_depending_table, abstract_completion, answer_insert, answer_subsumption, delay_after_simplify, drop_intermediate,
incr_answer_subsumption, incr_retractall, incr_subsumptive, monotonic_lazy, reeval_exceptions, reeval, reeval_wfs, simplify_completed,
tabled_shortest_path, tabling_upstream_a, tabling_upstream_c, tbl_sdg, wfs (all `test_tabling_*_upstream_swipl.jl`), and
test_tabling_abolish_bulk_upstream_swipl.jl, test_tabling_min_swipl.jl (run before). Their logs carry load-time Warning lines of the TEST PROGRAMS
(discontiguous clauses, singleton variables, a `library(time)` goal of dialect xsb/timed_call.pl in wfs) and no SKIP.

## FAILING files (first failing row: swipl vs kernel; class)

### 1. test_tabling_monotonic_swipl.jl (baseline of EV1T T1/T9): 10 pass / 2 fail per type (testset "monotonic tabling as swipl's (mono)", :124) -> ENGINE
- mono04 `t_mono04(R)`: swipl `r([],[a-b,a-c,b-c])`; kernel `exc(error(representation_error(int),context(system:'$idg_mono_index_deps'/4,_)))`.
- mono05: swipl `r(6,[a-b,a-c,a-d,b-c,b-d,c-d])`; kernel `r(2,[a-b,c-d])` (follows mono04: the propagation raised, the closure never grew).
- CAUSE (read, one line, confirmed by the code both sides): src/pl-tabling.jl:9723 `leaf = PL_get_integer_ex(ld, PL__t0 + 1)`; upstream
  pl-tabling.c:8908-8925 uses `PL_get_pointer_ex(A2, &leaf)`. The kernel's leaf is `'$trie_gen_node'/3`'s handle, `(tr.serial << 32) | nid`
  (src/pl-trie.jl:2253), which does not fit `PL_get_integer`'s Int32 range (src/pl-fli.jl:504), so `PL_get_integer_ex` raises
  representation_error(int) (src/pl-error.jl:767). Caller: boot/tabling.pl:1690-1691 `monotonic_affects/6`.
- Same cause, other files: test_tabling_mono_subsumptive_upstream (t_ms04.. on, 8 rows/type, kernel `raised(representation_error(int))`, swipl `ok`),
  test_tabling_mono_reuse_upstream :380 (t_mr01, t_mr02, t_mr04, t_mr05: 4 rows/type, same answers), test_tabling_monotonic_upstream :588
  (t_m04, t_m05: 2 rows/type, same answers). Total 16 + 2 rows/type of the 34-file failure list come from this ONE line. NOT fixed (engine).

### 2. test_tabling_trie_attvars_upstream_swipl.jl :495 (30 rows/type) -> ENGINE (undefined library/foreign procedures)
- first row t_tt01n01: swipl `ok`; kernel `raised(existence_error(procedure, plunit_trie_attvars:test/2))`.
- cause in the log, loading the unit's file (test_trie_attvars.pl:7, `use_module(library(terms))`): `Exported procedure terms:term_hash/2`, `term_hash/4`,
  `term_factorized/3`, `term_factorized/4` are reported undefined, then `'$foreign_source_location'/3: Unknown procedure '$foreign_predicate_source'/2`
  and `use_module(plunit_trie_attvars)` fails, so the unit's test/2 is undefined for every row. The foreign predicates belong to the termhash
  compile branch (D-0807 (4) item 4), not to the tabling line. Not a row/driver fix.

### 3. test_tabling_answer_discard_upstream_swipl.jl :458 (13 rows/type) -> ENGINE (undefined builtin)
- first row t_ad01: swipl `false`; kernel `raised(existence_error(procedure, '$syspreds':current_blob/2))`; rows t_ad02,03,04,07,08,10,11.. alike
  (swipl `1`, `false`, `equal`). `current_blob/2` is undefined in src/ (a NAME grep over src/*.jl finds nothing, on origin/main too; a capability search was NOT made, so the class is `undefined procedure at this SHA`).

### 4. test_tabling_idg_swipl.jl (20 fails + 4 errors/type; testsets idg17 3, idg18 3, idg19 4, idg20 8, idg21 1, idg29 2 + error, idg31 3 + 2 errors) -> TEST/DRIVER (not fixed yet)
White-box rows against stale internals; first failing rows: idg17 :527 `ok && st == "complete"` (the harness call `LK.tbl_variant_table(ld, t, ..., 9 args)`),
idg19 :581 `mo == "true"`, idg20 :650 `typ(tabs[1]) == "normal"` evaluates to the file path `/tmp/jl_*/tabling_idg_wb.pl` (the extractor reads a different
slot than the table's type), idg21 :715 (both sides `("clref", 1, "node")`, the `!=` row cannot hold), idg29 :995 `nothing isa LogicKernel.alloc_pool`
(+ FieldError `Nothing` lacks the field `size`, :993), idg31 :1065/:1068 MethodError `assert_term!(gd, ld, <Term>, 0, CL_END, nothing, nothing, PL_CREATE_INCREMENTAL)`
(the kernel's method takes `Int64` term_t arguments, src/pl-comp.jl:4044). Not yet diagnosed row by row: the idg17-idg20 rows may also hide ENGINE answers
(the dispatcher's note: '$is_answer_trie' pl-tabling.c:7372-7392, IsMono pl-tabling.c:5977-6020); the next agent compares each with swipl via `tbl_variant_table` on the pin.

### 5. test_tabling_trie_children_upstream_swipl.jl :745 (2 rows/type; 15 broken) -> ENGINE (undefined builtins)
- t_tt01n11: swipl `ok`; kernel `raised(existence_error(procedure, '$syspreds':current_blob/2))`.
- t_tt02n02: swipl `ok`; kernel `raised(existence_error(procedure, test_trie_children:garbage_collect_atoms/0))`.
  (thread rows t_tt03*: thread_create/3, message_queue_create/2 undefined: they are the file's own @test_broken rows.)

### 6. test_tabling_idg_sets_upstream_swipl.jl :618 (11 rows/type) and :660 (1 row/type) -> not classified (plunit unit never loads)
- first row t_id01: swipl `ok`; kernel `raised(existence_error(procedure, plunit_idg_sets:test/2))` for every row of the unit: the unit file does
  not load. The load error itself is not in the run log (the log shows only the Test Failed lines): the next agent reads the unit's load status
  (`catch(use_module(..), _, true)` in the driver hides it, see the header comment of the file).

### 7. test_tabling_trie_index_upstream_swipl.jl :587 (3 rows/type) -> ENGINE (undefined builtins)
- t_tt01n01, t_tt01n17: swipl `ok`; kernel `raised(existence_error(procedure, plunit_trie_index:set_random/1))`; t_tt01n11: `raised(existence_error(procedure, prolog_stack:prolog_frame_attribute/3))`.

### 8. test_tabling_incr_dyn_nodes_upstream_swipl.jl :297 (2 rows/type: t_id01, t_id02) -> not classified
- swipl `ok`; kernel `failed`. The rows use the private `'$tbl_local_variant_table'/1` and `'$tbl_table_status'/2` (header comment: "may leave them undefined").
  Next agent: run the row's goal on the kernel to see which call fails.

### 9. test_tabling_tb7rows_swipl.jl :503-547 (8 assertions/type, 24 in total) -> TEST/DRIVER, FIXED (commit below)
- `_T7_names(_T7_ans(key, id))` returned the answer's own wrapper functor (`t_d01`, `t_c05`, ...) as first name, the expected lists start at the answer `R`
  (e.g. d01 got `["t_d01","raised","dependency_error",...]`, want `["raised","dependency_error",...]`). swipl's pin lines are unchanged (`t_d01 t_d01(raised(...))`).
  Fix: `_T7_names` drops the wrapper (asserts it starts with `t_`); no expectation touched. After: 633 pass / 633 on three types, no Test Failed/Warning/SKIP.

### 10. test_tabling_supervisor_upstream_swipl.jl (3 fails + 6 errors/type counts: 3 Test Failed :684, 3 Error During :682, 3 Error During :662) -> TEST/DRIVER (to confirm)
- :662 "the kernel answers every non-thread row": `NotPortedError(get_answer_table, "a shared tabled predicate (O_PLMT)", owner TH1)` raised from
  `tbl_variant_table` (src/pl-tabling.jl:3024 via :3473, :3924) outside a `@test`; :682/:684 "thread-bound: expected refusal": BoundsError on a
  0-element `Vector{String}` at index 4 and a failed row. The rows meant to expect the refusal do not catch it (the kernel refuses shared tables by name,
  owner TH1); the next agent decides per row whether the driver must catch `NotPortedError` (test fix, `@test_broken` with the owner, per A-0570) or the kernel's refusal is wrong.

### 11. test_tabling_table_statistics_upstream_swipl.jl :230 (1 row/type, t_ts02) -> ENGINE (undefined builtin)
- swipl `r(4-4,no_dependency_nodes)`; kernel `raised(existence_error(procedure, aggregate:succ/2))` (the run's answer; the name search over src/ finds nothing, a search by capability was NOT made).

### 12. test_tabling_tabling_upstream_b_swipl.jl :705 (1 row/type, t_tt22) -> not classified
- swipl `ok`; kernel `failed`. Next agent: run the unit's test (units 13..25) goal directly.

### 13. test_tabling_trie_upstream_swipl.jl :616 (1 error on each of the three types) -> ENGINE
- `Error During Test ... Got exception outside of a @test`: "global cell 13197 holds 0x0000000000000100: no variable, reference, atom, compound, small integer, attributed variable or value-table word"
  raised in src/pl-prims.jl:721 `_deref_loc` from `ph_acyclic_mark_cells` (:1002) <- `is_acyclic_cells` (:1076) <- `trie_lookup_abstract` (src/pl-trie.jl:1353) <- `trie_insert` (:2214).
  A term on the global stack with a stale word, found by `trie_insert` on the kernel; no swipl row (the file errors before comparing). Named, not diagnosed.

## Order for the next agent (by failure count, of the list in D-0809 (1))
Done (named above): attvars (2), answer_discard (3), mono_subsumptive (1, same line as 1), idg_swipl (4, needs row-by-row work), trie_children (5),
idg_sets (6), mono_reuse (1), trie_index (7), incr_dyn_nodes (8), tb7rows (9, fixed), plus monotonic, monotonic_upstream, supervisor, table_statistics,
tabling_b, trie_upstream. Next: 4 (idg_swipl) row by row; 6, 8, 12 (the first kernel failure inside each row); 10 (supervisor driver).
Then the remaining NEW `test_tabling_*` files of the branch that are not `*upstream*` (tb*rows, trie_*, w*): `ls test/core_lang | grep tabling`, compare with `git ls-tree origin/main test/core_lang`.
