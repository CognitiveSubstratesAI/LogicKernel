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

## SECOND AGENT (lane 2, wip/tab1-mono at 74934bf1; EDITS UNCOMMITTED, forced hand-back at the 150k cap)
State of the worktree: two test files edited, NOT yet run on three types, NOT fmt/check'd, NOT committed; two untracked probe files must be deleted
(`test/core_lang/zz_probe.jl`, `test/core_lang/zz_probe_t1.jl`, `zz_probe_t2.jl`, `zz_probe_t3.jl`; never commit them). Probes and logs live in the
session scratchpad `.../scratchpad/tb2/` (pr/t1-t3.pl = the Prolog probes, run on the kernel via `zz_probe_<n>.jl` and on the pin swipl).
All results below are on the REFERENCE type only (`warm.sh file <f> reference`); three-type runs are still to do.

### test_tabling_idg_swipl.jl: TEST/DRIVER, FIXED in the working tree (reference: 291/291 pass, was 265 pass/20 fail/4 error)
No row's expectation was touched. Fixes (all harness errors of rows written "unverified"):
- `_ti_tvt`: Status is term reference `t+3` and IsMono `t+5` (the harness read `t+4` and `t+6`: off by one against `PL_new_term_refs` numbering); fixes idg17, idg18, idg19 (all rows: `ok && st == "complete"` etc.). Kernel answers equal the rows once read correctly: no ENGINE row among idg17-19.
- `_ti_answer_trie_type`: the answer is term reference `a+1`, not `a+2` (read a stray cell, the file path text); fixes idg20 (8 rows; `monotonic(eager)` now answers as the row says).
- idg21 :715: the must-fail `!=` row ran after `tp.flags = saved` (the plain table then gets its node, both sides `("clref",1,"node")`); the restore moved after the row.
- idg29: a fresh kernel has no table pool (upstream creates it with the first variant table, pl-tabling.c:2604-2606; kernel src/pl-tabling.jl:3170); the row now calls `LK.variant_table(ld, false)` first, `pool isa alloc_pool` stays.
- idg31: `LK.PL_CREATE_INCREMENTAL` is a `UInt16`; `assert_term!` takes `Int` flags: `Int(...)` at the two call sites.

### test_tabling_idg_sets_upstream_swipl.jl: TEST/DRIVER, FIXED in the working tree (reference: 76 pass, 7 broken, 0 fail)
The unit never loaded because of the DRIVER, not the load: the module files were named `plunit_sets` / `plunit_reader` / `plunit_space` but every row calls
`plunit_idg_sets:test/2` etc. The load itself is clean (probe: each file loads status ok, no message). swipl (pin, my own run of the same files) answers
`raised(existence_error(procedure,plunit_idg_sets:test/2))` for t_id01 too, i.e. the LIVE row (:660) failed on swipl as well. Fix: `_tt_unit_module` names the module
`plunit_<unit>` from the `begin_tests(<unit>)` directive. Also added the sibling pattern of test_tabling_abolish_bulk_upstream_swipl.jl: `_tt_ask` returns
`<pred> refused(<owner>)` on a `NotPortedError` (idg_reader_registry TH1, row t_id16), one kernel per row, a refused row is @test_broken with its owner.
After the fix all 11 non-thread rows equal swipl; the 7 thread-bound rows are @test_broken (kernel: `existence_error(procedure,'$syspreds':thread_create/3)` for
t_id09 t_id10 t_id11 t_id14 t_id17 t_id18, refused(TH1) for t_id16), as the file's header design says.

### test_tabling_incr_dyn_nodes_upstream_swipl.jl t_id01, t_id02 (reference 7 pass 2 fail): ENGINE ANSWER DIFFERS, NOT fixed, NOT pinned
Kernel: after `fill, abolish_table_subgoals(q(_))` the dynamic pseudo-table count is 13, swipl 10 (q(1..7), p(1..7) destroyed, q(8..10), p(8..10) kept).
Reduced to a plain trie, same on the pin: `trie_new(T), forall(between(1,N,I), trie_insert(T,k(I),v)), ( trie_gen(T,K,V), trie_delete(T,K,V), fail ; true ), aggregate_all(count, trie_gen(T,_,_), R)`:
kernel N=1..4 R=0, N=5 R=1, N=6 R=1, N=7 R=2, N=8 R=2, N=9 R=3, N=10 R=3, N=16 R=6, N=40 R=18; swipl R=0 for every N. The enumeration visits only k(1)..k(4) (N=5), k(1)..k(6) (N=8), k(1)..k(7) (N=10):
a trie_delete of the node just enumerated ends the enumeration early once the children are a hash (more than 4 children). The same shape is `abolish_table_subgoals/1` (boot/tabling.pl:1158-1168 `trie_gen(VariantTrie, M:SubGoal, Trie), '$tbl_destroy_table'(Trie), fail`); `abolish_all_tables/0` (:1120-1130) and `abolish_module_tables/1` (:1174-1181) too.
Upstream: pl-trie.c next_choice0 :3948-3990, next_choice :3995-4005 (qcursor `prune`, `check_epoch`, `restore_cursor`, `advance_node`), trie_delete :2673, prune_node :1460, trie_gen :4186. Kernel: src/pl-trie.jl next_choice! :2973, trie_gen_raw :3031, trie_delete :1924, prune_node :1010.
The effect is wide: every row that abolishes tables by enumeration with more than 4 tables. Next agent: ask the dispatcher for an engine fix of ONE class (trie_gen enumeration robust against deletion of the visited node), then re-run incr_dyn_nodes t_id01/t_id02, tabling_b t_tt22 (suspected same class), and test_tabling_answer_discard / trie_* files.

### test_tabling_tabling_upstream_b_swipl.jl t_tt22 (reference 38 pass 1 fail, :705): `failed`, swipl `ok`; class NOT yet read
Not diagnosed (cap). Next: read the t_tt22 row in the file (the `tt22` case near :566, the program near it) and run its goal on the kernel as I did for incr_dyn_nodes (zz_probe pattern: the file's own `_tt_materialize`, append `:- catch((( Goal ) -> ... ; ...), E, ...)` directives, run with `warm.sh file`, compare with the pin swipl on the same files). Check first whether it abolishes tables by enumeration (same engine class).

### Not started: test_tabling_supervisor_upstream_swipl.jl (:662/:682/:684) and step 5 (non-upstream test_tabling_* files)
Supervisor: the NotPortedError of :662 is the same shape as idg_sets: copy the abolish_bulk pattern (a `refused(<owner>)` line from `_tt_ask`, per-row kernel, @test_broken). Run first.

### TO DO before the commit (next agent, FIRST)
1. Delete the untracked `zz_probe*.jl` files in test/core_lang.
2. `warm.sh file` on three types for test_tabling_idg_swipl.jl and test_tabling_idg_sets_upstream_swipl.jl; grep the logs for `SKIP|Warning|Test Failed|Error During`.
3. `tools/warm.sh fmt`, then after the remaining fixes `tools/warm.sh check` ONCE; commit on wip/tab1-mono (two commits: idg_swipl; idg_sets), message `FIXED: test_tabling_idg_swipl.jl: ...`.

## THIRD AGENT (lane 2, wip/tab1-mono; commits 85597ed1 afb6eb4d a4df0c40 67ba9867 + the commits listed at the end)
All runs: `tools/warm.sh file <f>` on the three term types (reference, alt, alt_interned), one file at a time, lane-2 daemon, julia 1.13.3.
Log counts are `grep -cE 'SKIP|Warning|Test Failed|Error During'`.

### Committed, green on three types
- test_tabling_idg_swipl.jl (85597ed1): 291 pass on each type, 0 fail, 0 error, count 0. Diff read: five harness fixes, no expectation changed
  (idg21 moves the flag restore after the must-fail comparison: same comparison, same operands).
- test_tabling_idg_sets_upstream_swipl.jl (afb6eb4d): 76 pass, 7 broken on each type, count 0. The 7 broken are the thread-bound rows (6 x
  thread_create/3 existence_error, t_id16 refused(TH1)); the 11 other rows equal swipl. No pin changed.
- test_tabling_transaction_nested_swipl.jl (67ba9867): `_tn_abolish_obs` appended the `_TN_MONO` named tuple instead of `_TN_MONO.program`
  (MethodError outside a @test, :448, one per type); 131 pass on each type, count 0.

### test_tabling_supervisor_upstream_swipl.jl (a4df0c40): DRIVER fixed, 8 rows ENGINE (undefined procedures), not pinned
The abolish_bulk pattern is in (one kernel per row, `_tt_ask` returns `<pred> refused(<owner>)`, a refused row @test_broken): the file now runs to
its end (no NotPortedError outside a @test, no BoundsError at :682/:684). Per type: 110 pass, 24/3 = 8 fail, 4 broken (the totals of the run:
330 pass, 24 fail, 12 broken). Refused (TH1, get_answer_table: a shared tabled predicate O_PLMT): t_s03 t_s14 t_s29. The 8 failing rows, kernel
vs swipl `ok`, the same on all three types:
- t_s09 attvar_arg, t_s15 slow_path_debug, t_s16 answers: `raised(existence_error(procedure, edinburgh:notrace/0))`.
- t_s10 abolish_pinned, t_s11 abolish_reuse, t_s12 abolish_all_cache, t_s24 no_reeval, t_s26: `raised(existence_error(procedure,
  '$syspreds':get_flag/2))` (boot/syspred.pl:213/218 `flag/3` calls get_flag/2; the C predicate of pl-flag.c).
Class: UNDEFINED PROCEDURES (D-0810 E2 shape), two names: edinburgh:notrace/0 and get_flag/2. Rows need the line that owns them; not pinned, not weakened.

### test_tabling_tabling_upstream_b_swipl.jl t_tt22 (:705): NOT the trie_gen-with-delete class; ENGINE: tabling with attributed variables (clpfd)
The row is `( has_trie_attvar_support -> once((fib(N,13), N == 6)) ; ... )` with library(clpfd) (`N #> 2, N #< 10, N1 #= N-1, fib(N1,X1) ...`):
no table is abolished by enumeration. Probe (own program, the unit's text, kernel and the pin swipl, same file; scratchpad tb3/t23.pl):
- `has_trie_attvar_support` true on both (trie_insert of f(AttVar) succeeds).
- `findall(fib(N,X), fib(N,X), L)` ... kernel: `fib(_,3)` -> [fib(3,3)] (swipl [fib(3,3)]); `fib(_,5)` kernel [] swipl [fib(4,5)];
  `fib(_,8)` kernel [] swipl [fib(5,8)]; `fib(_,13)` kernel [] swipl [fib(6,13)]; `fib(_,_)` kernel [fib(1,1),fib(2,2),fib(3,3)], swipl
  fib(1,1) .. fib(9,55) (nine answers). Calls `fib(2,X)` and `fib(3,X)` with N bound answer 2 and 3 on both.
First failing answer: the answers for N >= 4: the recursive tabled call `fib(N1,X1)` with N1 an attributed variable (clpfd domain) yields no
answers or its answers are lost. Same family as test_tabling_trie_attvars_upstream_swipl.jl (90 failures, D-0809 (1)). Not diagnosed further.

### test_tabling_incr_dyn_nodes_upstream_swipl.jl t_id01, t_id02: unchanged from SECOND AGENT (engine: trie_gen with trie_delete of the visited node)
Not re-run here.

### Non-upstream test_tabling_* files the branch adds over origin/main (18), three types, one at a time
Green, count 0: tb4_tb5_guard, tb4_tb5, tb5rows, tb6rows, tb7rows, tb9rows, w2, abolish, engine_finding_cleanup_throw, events, restraint_wb, sdg,
transaction_wb, transaction_nested (after 67ba9867; was 3 errors).
tb8rows: 378 pass (126 per type), exit 0; the log has 12 lines `Warning: [Thread main] Trapped tripwire max_table_subgoal_size for
user:s0..sv`: the rows provoke the `warning` action of the tripwire (4 per type), they are the engine's Prolog message, not a Julia warning.
RED:
- test_tabling_monotonic_swipl.jl: 6 fails (2 rows x 3 types), :124. t_mono04: kernel `exc(error(representation_error(int),
  context(system:'$idg_mono_index_deps'/4,_)))`, swipl `r([],[a-b,a-c,b-c])`: the E1 site of A-0575 (leaf read with the 32-bit getter,
  pl-tabling.jl:9723, upstream pl-tabling.c:8908-8925; D-0810 (3), Sonnet one-site fix). t_mono05: kernel `r(2,[a-b,c-d])`, swipl
  `r(6,[a-b,a-c,a-d,b-c,b-d,c-d])`: runs after t_mono04 on the same kernel, probably the consequence, not verified.
- test_transaction_swipl.jl (ADDED by the branch; fixed in the commit after this report's first one): green on every other row; `trie`, `trie_property_idg`,
  `trie_compiled`, `trie_preds` (test_trie_*_swipl.jl, added or changed over main) green on three types, count 0.
  TEST/DRIVER fixed: txx16's last row compared `tx_pushed ...` against the answer without the functor (`_tx_ask` encodes the whole answer
  `tx_pushed([a])`, as every other row); the expectation is the same Prolog answer `[a]`, written in the file's encoding.
  ENGINE, named, not pinned, not fixed (2 rows per type, 6 failures): (1) t_txx11 (:757): kernel `raised(existence_error(procedure,
  '$bags':'$suspend_findall_bag'/0))`, swipl `[once/1, transaction/1, transaction/1]`: UNDEFINED PROCEDURE (pl-bag.c's suspend_findall_bag, D-0810 E2
  shape). (2) txx16 :827 `!UNDO_SCHEDULED(ld)`: at the end of the query `( undo(tx_push(a)), fail ; R = x )` the undo schedule is still non-empty on the
  kernel; the row's header says upstream runs the goals at the backtrack (pl-vmi.c b_failed, `LD->alerted`), the kernel runs them at the next call
  (the following `tx_pushed` call then answers `[a]`). Kernel side not read further.

### Ordered next list (third agent)
1. E1 one-site fix (D-0810 (3)): test_tabling_monotonic_swipl.jl t_mono04/t_mono05, mono_subsumptive/mono_reuse/monotonic_upstream.
2. Engine, one class at a time (audit asks): (a) trie_gen enumeration robust against trie_delete of the visited node (incr_dyn_nodes t_id01/02,
   abolish_table_subgoals; answer_discard, trie_* files to be re-run after); (b) tabling with attributed variables (t_tt22 clpfd; trie_attvars_upstream,
   90); (c) undefined procedures: edinburgh:notrace/0, get_flag/2 (supervisor 8 rows), '$bags':'$suspend_findall_bag'/0 (txx11), plus D-0810 E2's four;
   (d) undo goals at the backtrack (txx16 :827).
3. Not yet run on a lane by this agent: the remaining `*upstream*` files not named in D-0809 (1), and test_tabling_trie_* upstream files after (2a).
