# ORIGINAL: TB5's mutant list — no swipl-devel counterpart.
# tools/mutants/TB5.py — the mutation battery of TAB1 TB5 (tabling abolish/reclaim: the TB5 part 1 block of src/pl-tabling.jl before
# `PL_predicates_from_tabling` = pl-tabling.c abolish_table, tbl_destroy_table, tbl_abolish_local_tables, destroy_answer_trie,
# delayed_destroy_table, the orphan-dynamic functions, empty_variant_table, clear_variant_table, clearThreadTablingData, untable_from_clause;
# pl-trie.c get_trie_from_node, release_trie_value; and the database threaded through src/pl-proc.jl `setDynamicDefinition!`/`resetProcedure!`
# and the callers in src/pl-comp.jl). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's
# (as TB0.py, PIN1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written edit-only on
# wip/tb5, 2026-11-10, nothing compiled): every KILL below is read off the rows of test/core_lang/test_tabling_abolish_swipl.jl at wip/tb5 10ca4cf7
# (the file is unchanged by 3f7161af..38cf05b8); the first hand-run replaces this header with the true verdicts.
# THE ROWS (AB = test_tabling_abolish_swipl.jl). The swipl-differential rows are named by their `rowid` (`aba01` ... `abw01`, `abu01` ...; a failing
# case is the bare `t_<id>` line, `_ab_row` AB:403); the white-box testset "abolish, direct on the tries" is AB:452-489 (cited AB:<line>):
#   aba = abolish_all_tables (AB:177-185), abp = abolish_private_tables, abs = abolish_shared_tables, abg = abolish_table_subgoals, abm = abolish_module_tables,
#   abd = `$tbl_destroy_table` (abd01 destroys ab_p(1) then counts the variant table: 2; abd02 destroys twice; abd03 `is_trie(T)` after; abd04 the list after;
#   abd05/abd06 type_error / instantiation_error; abd10 two tables), abl = `$tbl_abolish_local_tables` (abl01 true, abl02 count 0, abl05 `is_trie(T)` yes after),
#   abw01 = the call from inside an evaluation FAILS and touches nothing (AB:422-426), abu = untable (needs `$wrap_predicate/5`: the stack).
#   white-box: AB:458 DYN_ORPHAN_SWEEP_MIN == 1024, AB:459 get_trie_from_node, AB:462-465 the four predicates on a complete table, AB:468-471 the sweep below
#   the threshold, AB:473-478 destroy_answer_trie/abolish_table leave the variant table (value_count 2, 1, 0), AB:481-484 clear_variant_table.
# CLASSES (counts in evidence/TB5/handoff3.md):
#   KILL                 the id names the assertion that must fail.
#   EQUIVALENT           `equivalent:` carries the reason with file:line.
#   ADD-ROW              no row asserts it yet; it is an assertion on a function THIS step ports and the gate (the agent that hand-runs this list) ADDS it to
#                        the white-box testset: the id says which (R-A ... R-E below). Until then it survives; it is not equivalent.
#   DEFERRED KILL        the mutated code cannot be reached before the owner step: TB6 (IDG nodes, the dynamic pseudo table `WL_DYNAMIC` is only written by
#                        TB6: `orphan_dynamic_table` is false before it), TH1 (shared tables), TB2 (worklists, an incomplete table), TB4 (delay info),
#                        LB6b (`untable_from_clause`'s call sites pl-srcfile.c:1476 `unloadFile` and :1544 `endReconsult` do not exist in the kernel until LB6b),
#                        TAB1-WRAP (a wrapped predicate: the `abu` rows run on a kernel with `$wrap_predicate/5`, at the stack). The owner adds the row named.
# ROWS TO ADD (white-box, in AB's testset "abolish, direct on the tries"; each is an assertion on the already built atries/variants of AB:455-457):
#   R-A after `clear_variant_table(ld)` (AB:481): `variants.value_count == 0`, `all(a -> a.variant == 0, atries)`, `all(a -> a.magic == LK.TRIE_CMAGIC, atries)`,
#       `variants.magic == LK.TRIE_CMAGIC`; and `ld.tabling.start_nodes = Int[1]` set before the call, `=== nothing` after (the existing AB:483 holds under the
#       mutant if table creation never fills `start_nodes`).  [pl-tabling.jl: reset_table_bulk resets `variant`, release_trie_value destroys a trie without a symbol]
#   R-B `LK.abolish_table(ld, a)` on a trie WITHOUT a symbol (AB:475, :477): `a.magic == LK.TRIE_CMAGIC` afterwards (trie_destroy, src/pl-trie.jl:242-248).
#   R-C `LK.sweep_orphan_dynamic_tables(ld) === nothing` after `clear_variant_table` (AB:481: `variant_table == 0`).
#   R-D `ld.tabling.dyn_orphan_events = 2000` then `sweep_orphan_dynamic_tables(ld)`: the events are 0 afterwards and value_count is unchanged (the sweep ran: 2000
#       >= 1024 and >= 3); and `dyn_orphan_events = 5` before `clear_variant_table` is 0 after (empty_variant_table's reset).
#   R-E a freed object `tbl_free(ld, kind, obj)` (TT's `_ts_*` helpers, TT:216-228) before `'$tbl_abolish_local_tables'`: all four lists are empty afterwards
#       and `fo.closed` is still false (`clearThreadTablingData(ld, false)`).
#   R-G `vtrie.references = 1` white-box before `clear_variant_table(ld)` (a reader holds the table): the call leaves `variants.value_count == 3` (the last reader empties it).
#   R-F `a.worklist = LK.WL_DYNAMIC` on a table (white-box; WL_DYNAMIC is TB6's to WRITE, the abolish code reads it): `abolish_table(ld, a) == true` and the
#       variant table is untouched. (Also kills the `_wl_is` and `return true` mutants below; filed under TB6 only because a real dynamic pseudo table is TB6's.)
# ROWS WRITTEN (STEP DEFKILL, audit D-0668 item 2(d)): R-A ... R-F are now the testsets between "clear_variant_table: the IDG nodes of the tables go with them"
# and "the abolish rows are not vacuous" in AB (white-box; R-A also carries R-C and the Y3/O4 reads, R-B the abolish_table / destroy_answer_trie
# destruction, R-D the sweep, R-E clearThreadTablingData, R-F the non-orphan dynamic table, R-G the reader case). The 17 ADD-ROW mutants of the first
# version are KILL, except TB5-C7 (EQUIVALENT: empty_trie is a no-op for a trie with a reader, `equivalent` has the lines) and TB5-A7/O5 stay DEFERRED:
# an orphan dynamic table has an IDG node (orphan_dynamic_table), and delete_dynamic_table reaches reset_answer_table's IDG refusal (engine finding,
# evidence/TAB1/defkill_inventory.md). Rows NOT RUN (nothing compiled): the first hand-run decides.
# TARGETS (audit D-0238): AB (the step's file); TV = test_tabling_variant_swipl.jl (TB1, on wip/tb1, in the stack: it builds the variant tables and `$tbl_existing_variant_table`
# the abolish code deletes from); TT = test_tabling_state_swipl.jl (the freed-object lists `clearThreadTablingData` calls, the `ld.tabling` fields); TM =
# test_tabling_min_swipl.jl (the `$tbl_*` predicates of the registration tuple); BI = test/db/test_boot_image_swipl.jl (the kernel-foreign count, 372 since TB5);
# DYN = the test files that call `setDynamicDefinition!`/`resetProcedure!` (grepped one pattern at a time over wip/tb5 test/, 2026-11-10; not
# test/static_analysis_manifest.jl: a static-analysis CI job, not a mutation target). A test file that calls `resetProcedure!` directly: none (only the manifest).
# Every `old` was counted EXACTLY once in the file it targets at wip/tb5 38cf05b8 by a python3 -I script (the count is in handoff3.md; no Julia ran).
# RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
AB = "test/core_lang/test_tabling_abolish_swipl.jl"
TV = "test/core_lang/test_tabling_variant_swipl.jl"
TT = "test/core_lang/test_tabling_state_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
BI = "test/db/test_boot_image_swipl.jl"
DYN = [
    "test/compile/test_body_code_swipl.jl",
    "test/compile/test_call_operands.jl",
    "test/core_lang/test_attvar_wakeup.jl",
    "test/core_lang/test_autoload_trap.jl",
    "test/core_lang/test_module_path.jl",
    "test/core_lang/test_rules_swipl.jl",
    "test/core_lang/test_top1_pro.jl",
    "test/core_lang/test_top1b_swipl.jl",
    "test/db/test_assert_swipl.jl",
    "test/db/test_procedures.jl",
    "test/db/test_reload_blocks_swipl.jl",
]
TABL = [AB, TV]                           # the abolish code and the tables it deletes from
TW = "test/core_lang/test_trie_swipl.jl"                     # TR1: trie_delete / release_value (G3, G4 moved to src/pl-trie.jl)
TP = "test/core_lang/test_trie_preds_swipl.jl"                # TR1: the trie_* predicates that delete nodes
TRIE = TABL + [TW, TP]
TABLS = [AB, TV, TT]                      # the same, where it reads or writes `ld.tabling` or the freed objects
TARGETS = [AB, TV, TT, TM, BI, TW, TP] + DYN      # every file a mutant lists (mutate_ci.py plan reads TARGETS)
TAB = "src/pl-tabling.jl"
PROC = "src/pl-proc.jl"
COMP = "src/pl-comp.jl"
WRAP = ("DEFERRED KILL, owner TAB1-WRAP: the two methods differ ONLY for a wrapped (tabled) predicate, where the 2-argument freeCodesDefinition! raises "
        "NotPortedError (src/pl-supervisor.jl:85-98) and the one with `gd` resets the wrapped supervisor (:62-82): the abu row to add on the stack "
        "(`$wrap_predicate/5` defined): `dynamic ab_u1/1` on the wrapped predicate answers without an error; a boot or non-wrapped caller does not differ")
MUTANTS = [
    # ── the registration tuple (pl-tabling.c BeginPredDefs: $tbl_destroy_table/1, $tbl_abolish_local_tables/0) ──
    dict(id="TB5-T1 `$tbl_destroy_table`/1 is not registered (KILL abd01: the call is an existence error, the row answers raised(...); BI's kernel-foreign count 372 fails, too)",
         file=TAB, targets=[AB, TM, BI],
         old=r'    PL_extension("\$tbl_destroy_table", 1, pl_tbl_destroy_table1_va, PL_FA_VARARGS),' + "\n",
         new=""),
    dict(id="TB5-T2 `$tbl_abolish_local_tables`/0 is not registered (KILL abl01: the call is an existence error; BI's count fails, too)",
         file=TAB, targets=[AB, TM, BI],
         old=r'    PL_extension("\$tbl_abolish_local_tables", 0, pl_tbl_abolish_local_tables0_va, PL_FA_VARARGS)' + "\n",
         new=""),
    # ── pl_tbl_destroy_table1_va ──
    dict(id="TB5-D1 `$tbl_destroy_table` always fails (KILL abd01: the case fails, the row is the bare `t_abd01`, the pin has an answer; abd02 too)",
         file=TAB, targets=[AB],
         old="    return abolish_table(ld, atrie) ? FTRUE : FFALSE\n",
         new="    abolish_table(ld, atrie)\n\n    return FFALSE\n"),
    dict(id="TB5-D2 `$tbl_destroy_table` answers the abolish result through `?:` as `true` always (EQUIVALENT: abolish_table answers true on every path)",
         file=TAB, targets=[AB],
         equivalent="src/pl-tabling.jl:9483-9508 abolish_table (the function above, `return true` at the WL_DYNAMIC branch and at its end): every path of abolish_table returns true (a refusal raises by `tbl_refuse`, not by returning false), so `abolish_table(ld, atrie) ? FTRUE : FFALSE` and `FTRUE` are the same value",
         old="    return abolish_table(ld, atrie) ? FTRUE : FFALSE\n",
         new="    abolish_table(ld, atrie)\n\n    return FTRUE\n"),
    # ── abolish_table (pl-tabling.c abolish_table) ──
    dict(id="TB5-A1 abolish_table schedules a COMPLETE table for destruction instead of deleting it, `if delayed_destroy_table` (KILL abd01: the variant table still holds 3 tables, the pin is 2; abg01, abd04, abd10, AB:474-478 value_count)",
         file=TAB, targets=TABL,
         old="            if !delayed_destroy_table(atrie)\n",
         new="            if delayed_destroy_table(atrie)\n"),
    dict(id="TB5-A2 abolish_table does not delete from the variant table: the test `is_variant_trie(vtrie)` is negated (KILL abd01, AB:474-478)",
         file=TAB, targets=TABL,
         old="        if vtrie !== nothing && is_variant_trie(vtrie)\n            (atrie.flags & TRIE_ISSHARED) != 0 &&\n                tbl_refuse(T, :abolish_table,",
         new="        if vtrie !== nothing && !is_variant_trie(vtrie)\n            (atrie.flags & TRIE_ISSHARED) != 0 &&\n                tbl_refuse(T, :abolish_table,"),
    dict(id="TB5-A3 abolish_table skips a table that has a node, `atrie.variant == 0` (KILL abd01, AB:474-478: a table with a node is not deleted)",
         file=TAB, targets=TABL,
         old="    if atrie.variant != 0\n        vtrie = get_trie_from_node(ld, atrie)\n        if vtrie !== nothing && is_variant_trie(vtrie)\n            (atrie.flags & TRIE_ISSHARED) != 0 &&\n                tbl_refuse(T, :abolish_table,",
         new="    if atrie.variant == 0\n        vtrie = get_trie_from_node(ld, atrie)\n        if vtrie !== nothing && is_variant_trie(vtrie)\n            (atrie.flags & TRIE_ISSHARED) != 0 &&\n                tbl_refuse(T, :abolish_table,"),
    dict(id="TB5-A4 abolish_table answers false after a deletion (KILL abd01: `$tbl_destroy_table` fails, the case fails; AB:475 `@test LK.abolish_table(ld, atries[2])`)",
         file=TAB, targets=TABL,
         old="    end\n\n    return true\nend\n\n# PORT: pl-tabling.c tbl_destroy_table as pl_tbl_destroy_table1_va\n",
         new="    end\n\n    return false\nend\n\n# PORT: pl-tabling.c tbl_destroy_table as pl_tbl_destroy_table1_va\n"),
    dict(id="TB5-A5 abolish_table of a dynamic pseudo table answers false (KILL AB R-F: white-box, `a.worklist = LK.WL_DYNAMIC` on a table without an IDG node, so `orphan_dynamic_table(a)` is false and nothing is deleted; `abolish_table(ld, a) === true` and the variant table keeps its 3 tables. The orphan case, a dynamic table WITH its IDG node, is not a row: see the engine finding in evidence/TAB1/defkill_inventory.md)",
         file=TAB, targets=TABL,
         old="        orphan_dynamic_table(atrie) && delete_dynamic_table(ld, atrie)\n\n        return true\n",
         new="        orphan_dynamic_table(atrie) && delete_dynamic_table(ld, atrie)\n\n        return false\n"),
    dict(id="TB5-A7 abolish_table does not delete the orphan children of the table (DEFERRED KILL, owner TB6: `collect_dynamic_children` is the empty vector before TB6, src/pl-tabling.jl collect_dynamic_children; TB6 adds the row: abolishing a table whose only dependent dynamic pseudo table has no other dependents deletes both)",
         file=TAB, targets=TABL,
         old="                trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n                delete_orphan_dynamic_tables(ld, b)\n",
         new="                trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n"),
    dict(id="TB5-A8 abolish_table treats every sentinel as the dynamic one, `_wl_is` ignores which (KILL abd01: the ground table ab_p(1) has `WL_GROUND`, is taken for a dynamic pseudo table and is not deleted; row R-F too)",
         file=TAB, targets=TABL,
         old="    return w isa Int && w == s\n",
         new="    return w isa Int\n"),
    dict(id="TB5-A9 abolish_table refuses nothing for a shared table (DEFERRED KILL, owner TH1: a shared table (`TRIE_ISSHARED`) is only made by TH1; TH1 adds the row: abolish_shared_tables on a shared table does not raise the TH1 refusal)",
         file=TAB, targets=TABL,
         old="            (atrie.flags & TRIE_ISSHARED) != 0 &&\n                tbl_refuse(T, :abolish_table, \"abolish_table: a shared table (take_trie, drop_trie)\", \"TH1\")\n",
         new=""),
    # ── delayed_destroy_table (pl-tabling.c delayed_destroy_table) ──
    dict(id="TB5-L1 delayed_destroy_table schedules a COMPLETE table, `!table_is_incomplete` (KILL AB:462 `delayed_destroy_table(a) == false` and :463, the flag stays 0)",
         file=TAB, targets=[AB],
         old="    if table_is_incomplete(atrie)\n        atrie.flags |= TRIE_ABOLISH_ON_COMPLETE\n",
         new="    if !table_is_incomplete(atrie)\n        atrie.flags |= TRIE_ABOLISH_ON_COMPLETE\n"),
    dict(id="TB5-L2 delayed_destroy_table does not set the flag (DEFERRED KILL, owner TB2: an INCOMPLETE table needs the worklist and the create path, TB2/TB3; the row: abolish_table of an incomplete table sets TRIE_ABOLISH_ON_COMPLETE and keeps the node)",
         file=TAB, targets=[AB],
         old="        atrie.flags |= TRIE_ABOLISH_ON_COMPLETE\n",
         new="        atrie.flags |= 0\n"),
    # ── destroy_answer_trie (pl-tabling.c destroy_answer_trie) ──
    dict(id="TB5-Y1 destroy_answer_trie ignores a table with a node, `atrie.variant == 0` (KILL AB:473 `@test LK.destroy_answer_trie(ld, atries[1])` and :474 value_count 2)",
         file=TAB, targets=TABL,
         old="function destroy_answer_trie(ld::PL_local_data{T}, atrie::trie{T})::Bool where {T}\n    if atrie.variant != 0\n",
         new="function destroy_answer_trie(ld::PL_local_data{T}, atrie::trie{T})::Bool where {T}\n    if atrie.variant == 0\n"),
    dict(id="TB5-Y2 destroy_answer_trie deletes but answers false (KILL AB:473 `@test LK.destroy_answer_trie(ld, atries[1])`)",
         file=TAB, targets=TABL,
         old="            trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n\n            return true\n        end\n    end\n\n    return false\nend\n",
         new="            trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n\n            return false\n        end\n    end\n\n    return false\nend\n"),
    dict(id="TB5-Y3 destroy_answer_trie answers true for a table that has no variant table (KILL AB R-A: after `clear_variant_table` `get_trie_from_node` is nothing, so `@test !LK.destroy_answer_trie(ld, atries[1])` is to be added at AB:484)",
         file=TAB, targets=TABL,
         old="            return true\n        end\n    end\n\n    return false\nend\n\n# PORT: pl-tabling.c delayed_destroy_table\n",
         new="            return true\n        end\n    end\n\n    return true\nend\n\n# PORT: pl-tabling.c delayed_destroy_table\n"),
    # ── get_trie_from_node, release_trie_value (pl-trie.c) ──
    dict(id="TB5-G1 get_trie_from_node finds a variant table after the thread's was cleared: no `vi == 0` guard (KILL AB:484 `get_trie_from_node(ld, atries[1]) === nothing`: `gd.tries[0]` is a BoundsError)",
         file=TAB, targets=TABL,
         old="    vi == 0 && return nothing\n\n    return _query_gd(ld).tries[vi]\n",
         new="    return _query_gd(ld).tries[vi]\n"),
    dict(id="TB5-G3 release_trie_value destroys the trie that has a symbol, `symbol != 0` (KILL aba06 and abl05: `ab_tab(user:ab_p(1), T)` hands T to Prolog (it has a symbol), so after abolish `is_trie(T)` stays yes in swipl, here it is destroyed; abd03 too. Needs TR1's `release_value` to call release_trie_value: merge hazard b in docs/architecture.md TAB1 TB5)",
         file="src/pl-trie.jl", targets=TRIE,
         old="        t.symbol == 0 && trie_destroy(gd, t)\n",
         new="        t.symbol != 0 && trie_destroy(gd, t)\n"),
    dict(id="TB5-G4 release_trie_value never destroys a trie without a symbol (KILL AB R-A for the bulk path, `all(a -> a.magic == LK.TRIE_CMAGIC, atries)` after clear_variant_table; R-B for abolish_table's `trie_delete` path)",
         file="src/pl-trie.jl", targets=TRIE,
         old="        t.symbol == 0 && trie_destroy(gd, t)\n",
         new="        nothing\n"),
    # ── reset_answer_table's IDG branch, run by the callers before trie_delete (option c; KILL AB "abolish: the IDG node goes with the table") ──
    dict(id="TB5-I1 destroy_answer_trie does not run the IDG branch before trie_delete (KILL AB: the chain's reset_answer_table refuses a table that still has an IDG node)",
         file="src/pl-tabling.jl", targets=[AB],
         old="reset_answer_table_idg(ld, atrie, rat_flags)\n            reset_answer_table_tracked(ld, atrie)\n            trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n\n            return true",
         new="reset_answer_table_tracked(ld, atrie)\n            trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n\n            return true"),
    dict(id="TB5-I2 abolish_table does not run the IDG branch before trie_delete (KILL AB: the same refusal for atries[3])",
         file="src/pl-tabling.jl", targets=[AB],
         old="reset_answer_table_idg(ld, atrie, rat_flags)\n                reset_answer_table_tracked(ld, atrie)\n                trie_delete(",
         new="reset_answer_table_tracked(ld, atrie)\n                trie_delete("),
    dict(id="TB5-I3 reset_answer_table_idg forgets to destroy the node (the link is dropped, the edges stay: KILL AB `live(nodes[1].dependent)` rows)",
         file="src/pl-tabling.jl", targets=[AB],
         old="            if (flags & RAT_BULK) != 0\n                idg_destroy_private(ld, n)\n            else\n                idg_destroy(ld, n)\n            end\n",
         new="            nothing\n"),
    dict(id="TB5-I4 reset_answer_table_idg keeps the node on the trie (KILL AB `atries[2].IDG === nothing`)",
         file="src/pl-tabling.jl", targets=[AB],
         old="            atrie.IDG = nothing\n            if (flags & RAT_BULK) != 0",
         new="            if (flags & RAT_BULK) != 0"),
    # ── the orphan-dynamic functions (pl-tabling.c orphan_dynamic_table ... sweep): all before TB6 ──
    dict(id="TB5-O1 DYN_ORPHAN_SWEEP_MIN is 1, not 1024 (KILL AB:458 `LK.DYN_ORPHAN_SWEEP_MIN == 1024`; AB:470 too: with 5 events >= 1 and >= value_count 3 the sweep runs and resets the events to 0)",
         file=TAB, targets=[AB],
         old="const DYN_ORPHAN_SWEEP_MIN = 1024\n",
         new="const DYN_ORPHAN_SWEEP_MIN = 1\n"),
    dict(id="TB5-O2 the sweep runs below the threshold, `>=` on the second condition becomes `<=` (KILL AB R-D: `dyn_orphan_events = 2000`, sweep, the events are 0: with `2000 <= 3` false the sweep does not run)",
         file=TAB, targets=[AB],
         old="       ld.tabling.dyn_orphan_events >= vtrie.value_count\n",
         new="       ld.tabling.dyn_orphan_events <= vtrie.value_count\n"),
    dict(id="TB5-O3 the sweep does not reset the event count (KILL AB R-D: the events are 0 after a sweep that ran)",
         file=TAB, targets=[AB],
         old="        ld.tabling.dyn_orphan_events = 0\n    end\n\n    return nothing\nend\n\n# PORT: pl-tabling.c unify_skeleton\n",
         new="    end\n\n    return nothing\nend\n\n# PORT: pl-tabling.c unify_skeleton\n"),
    dict(id="TB5-O4 the sweep has no `vi == 0` guard (KILL AB R-C: `sweep_orphan_dynamic_tables(ld) === nothing` with no variant table: `gd.tries[0]` is a BoundsError)",
         file=TAB, targets=[AB],
         old="    vi == 0 && return nothing\n    vtrie = gd.tries[vi]\n",
         new="    vtrie = gd.tries[vi]\n"),
    dict(id="TB5-O5 the sweep collects no orphan: `push!(b, atrie)` is skipped (DEFERRED KILL, owner TB6: orphan_dynamic_table is false before TB6; the row: 1024 lost dependents delete the dependent-less dynamic pseudo tables of the variant table)",
         file=TAB, targets=[AB],
         old="                orphan_dynamic_table(atrie) && push!(b, atrie)\n",
         new="                orphan_dynamic_table(atrie) && nothing\n"),
    # ── reset_table_bulk, sort_table_values!, empty_variant_table (pl-tabling.c) ──
    dict(id="TB5-E1 reset_table_bulk keeps the table's node: `atrie.variant = 0` is dropped (KILL AB R-A: `all(a -> a.variant == 0, atries)` after clear_variant_table)",
         file=TAB, targets=TABLS,
         old="    atrie.variant = 0\n\n    return nothing\nend\n\n# PORT: pl-tabling.c sort_table_values\n",
         new="    nothing\n\n    return nothing\nend\n\n# PORT: pl-tabling.c sort_table_values\n"),
    dict(id="TB5-E2 reset_table_bulk keeps the answers: the reset is skipped (KILL AB R-A: `value_count`/`magic` of the answer tries after clear_variant_table; the reset flags `RAT_CLEANUP | RAT_BULK` are TB1's `reset_answer_table`)",
         file=TAB, targets=TABLS,
         old="    reset_answer_table(gd, atrie, Int(RAT_CLEANUP | RAT_BULK))\n",
         new="    nothing\n"),
    dict(id="TB5-E4 sort_table_values! does not sort (EQUIVALENT: the order of the resets and releases is not observable)",
         file=TAB, targets=TABLS,
         equivalent="src/pl-tabling.jl:9566-9586 reset_table_bulk (`reset_answer_table` of its own atrie, `atrie.variant = 0`) and release_trie_value (`trie_destroy` of its own atrie) each touch only the trie named by the value, and `empty_variant_table`'s two loops run to completion over the same vector: no result depends on the order of the values (upstream sorts by address for the memory cache only, pl-tabling.c sort_table_values)",
         old="    sort!(values)\n\n    return nothing\nend\n",
         new="    return nothing\nend\n"),
    dict(id="TB5-E5 empty_variant_table releases no value: the second loop is skipped (KILL AB R-A: tries without a symbol are destroyed, `a.magic == LK.TRIE_CMAGIC`)",
         file=TAB, targets=TABLS,
         old="            isTriePtrValue(v) && release_value(gd, vtrie, v)\n",
         new="            isTriePtrValue(v) && nothing\n"),
    dict(id="TB5-E6 empty_variant_table releases a value that is no trie pointer without the test (EQUIVALENT: every value of a variant table is a trie pointer)",
         file=TAB, targets=TABLS,
         equivalent="src/pl-tabling.jl:9566-9569 reset_table_bulk, first line `atrie = value_trie(gd, value)`: the loop above (`reset_table_bulk(ld, v, registry, idg_nodes)` for each taken value) already calls `value_trie` on every value unconditionally, which only works for a trie pointer value; so `isTriePtrValue(v)` is true for every `v` that reaches the release loop and the test is redundant",
         old="            isTriePtrValue(v) && release_value(gd, vtrie, v)\n",
         new="            release_value(gd, vtrie, v)\n"),
    dict(id="TB5-E7 empty_variant_table does not reset the dynamic orphan event count (KILL AB R-D: `dyn_orphan_events = 5` before clear_variant_table, 0 after)",
         file=TAB, targets=TABLS,
         old="        ld.tabling.dyn_orphan_events = 0\n    else\n",
         new="    else\n"),
    dict(id="TB5-E8 empty_variant_table does not unlink the concurrent IDG nodes (the battery decides: the white-box row of test_tabling_abolish_swipl.jl 'clear_variant_table: the IDG nodes of the tables go with them' sets `concurrent` on one node; if it survives, the reason to record is that `idg_destroy_private` clears both sets of every node afterwards)",
         file=TAB, targets=TABLS,
         old="        if ld.tabling.concurrent_idg_nodes != 0\n            map_trie_node(vtrie, 1, idg_unlink_concurrent_table(ld))\n        end\n",
         new=""),
    dict(id="TB5-E10 empty_variant_table does not release the registry (KILL the same row: the nodes' and the thread's references are dropped, `registry` is the detached one)",
         file=TAB, targets=TABLS,
         old="        if registry !== nothing                         # the nodes' and the thread's\n            idg_registry_release_n(registry, idg_nodes[] + 1)\n        end\n",
         new=""),
    dict(id="TB5-E11 reset_table_bulk counts no node of the detached registry (the references are then released short: the row's `reg.refs` check is not written; the battery decides)",
         file=TAB, targets=TABLS,
         old="            idg_nodes[] += 1\n",
         new="            nothing\n"),
    dict(id="TB5-E9 the delay info pass of an unvisited variant table is skipped (DEFERRED KILL, owner TB4: destroy_delay_info_worklist needs a worklist with undefined answers; the row: clear_variant_table of a table with `undefined != 0` destroys the delay info)",
         file=TAB, targets=TABLS,
         old="        delays_done || map_trie_node(vtrie, 1, destroy_delay_info_table(gd))   # (*)\n",
         new="        nothing\n"),
    # ── clear_variant_table (pl-tabling.c clear_variant_table) ──
    dict(id="TB5-C1 clear_variant_table does nothing for a thread that has a variant table, `vi == 0` (KILL AB:482 `variant_table == 0`, AB:484; abl02: the three tables are still counted)",
         file=TAB, targets=TABLS,
         old="    vi = ld.tabling.variant_table\n    if vi != 0\n        vtrie = gd.tries[vi]\n        (vtrie.flags & TRIE_ISSHARED) != 0 &&\n            tbl_refuse(T, :clear_variant_table,",
         new="    vi = ld.tabling.variant_table\n    if vi == 0\n        vtrie = gd.tries[vi]\n        (vtrie.flags & TRIE_ISSHARED) != 0 &&\n            tbl_refuse(T, :clear_variant_table,"),
    dict(id="TB5-C2 clear_variant_table leaves the thread's variant table in place (KILL AB:482 `ld.tabling.variant_table == 0` and :484; abl02, abl03: ab_n is still 3)",
         file=TAB, targets=TABLS,
         old="        ld.tabling.variant_table = 0\n    end\n    ld.tabling.start_nodes = nothing",
         new="    end\n    ld.tabling.start_nodes = nothing"),
    dict(id="TB5-C3 clear_variant_table keeps the start node cache (KILL AB R-A: `ld.tabling.start_nodes = Int[1]` before, `=== nothing` after; AB:483 holds under this mutant if table creation never fills start_nodes)",
         file=TAB, targets=TABLS,
         old="    ld.tabling.start_nodes = nothing                    # free_node_array: the nodes are in vtrie\n",
         new="    nothing                    # free_node_array: the nodes are in vtrie\n"),
    dict(id="TB5-C4 clear_variant_table counts the reference down instead of up: `-= 1` (KILL AB R-A: the references go -1, readers is false, then -2: the table is never emptied, `variants.value_count == 0` fails)",
         file=TAB, targets=TABLS,
         old="        vtrie.references += 1                           # acquire_trie (**)\n",
         new="        vtrie.references -= 1                           # acquire_trie (**)\n"),
    dict(id="TB5-C5 clear_variant_table never releases its reference (KILL AB R-A: references stay 1, `== 0` is false, the table is never emptied, `variants.value_count == 0` fails)",
         file=TAB, targets=TABLS,
         old="        vtrie.references -= 1\n        vtrie.references == 0 && empty_variant_table(ld, vtrie, readers)\n",
         new="        vtrie.references == 0 && empty_variant_table(ld, vtrie, readers)\n"),
    dict(id="TB5-C6 clear_variant_table takes the readers branch always, `> 0` (KILL AB R-A: `readers` true makes `empty_variant_table(.., true)` take the plain `trie_empty` branch, which skips the bulk teardown's last lines: `ld.tabling.concurrent_idg_nodes = 1` stays 1 and `dyn_orphan_events = 5` stays 5 where the row reads 0 and 0; the IDG testset above it also raises, a node without the bulk path reaching reset_answer_table's refusal)",
         file=TAB, targets=TABLS,
         old="        readers = vtrie.references > 1\n",
         new="        readers = vtrie.references > 0\n"),
    dict(id="TB5-C7 clear_variant_table empties the table although a reader holds it, `true &&` for `references == 0 &&` (EQUIVALENT: with a reader the call is `empty_trie`'s no-op; the AB testset R-G pins the unchanged state)",
         file=TAB, targets=TABLS,
         equivalent="src/pl-tabling.jl clear_variant_table :9696-9699: `readers = references > 1` is taken after the acquire, so `readers` is true exactly when a reader still holds the table after the release (`references >= 1`); then `empty_variant_table(ld, vtrie, true)` takes its else branch (:9672-9676: the delay pass is skipped, `trie_empty`) and src/pl-trie.jl empty_trie (:321-327) returns false without touching a node while `tr.references != 0` (`trie_discard_clause` before it is a no-op for a variant table: no clause). With no reader (`references == 0`) the guard `references == 0 &&` is true and the original calls the same function with the same arguments. So both versions leave a table with a reader as it was and empty one without; the last reader empties it by trie_clean (pl-trie.c), which the R-G testset runs",
         old="        vtrie.references == 0 && empty_variant_table(ld, vtrie, readers)\n",
         new="        empty_variant_table(ld, vtrie, readers)\n"),
    dict(id="TB5-C8 clear_variant_table does not mark the table destroyed (KILL AB R-A: `variants.magic == LK.TRIE_CMAGIC`)",
         file=TAB, targets=TABLS,
         old="        vtrie.magic = TRIE_CMAGIC\n        readers =",
         new="        readers ="),
    # ── clearThreadTablingData, $tbl_abolish_local_tables (pl-tabling.c) ──
    dict(id="TB5-H1 clearThreadTablingData does not clear the variant table (KILL abl02, abl03 and abl04: three tables remain; abl05)",
         file=TAB, targets=TABLS,
         old="    clear_variant_table(ld)\n    free_tbl_free_objects(ld, exit)\n",
         new="    free_tbl_free_objects(ld, exit)\n"),
    dict(id="TB5-H2 clearThreadTablingData does not free the freed-object lists (KILL AB R-E: a freed object is dropped by the call, all four lists empty)",
         file=TAB, targets=TABLS,
         old="    free_tbl_free_objects(ld, exit)\n\n    return nothing\nend\n\n# PORT: pl-tabling.c tbl_abolish_local_tables",
         new="    nothing\n\n    return nothing\nend\n\n# PORT: pl-tabling.c tbl_abolish_local_tables"),
    dict(id="TB5-H3 clearThreadTablingData closes the freed objects always, `exit` becomes `true` (KILL AB R-E: `fo.closed` is false after `'$tbl_abolish_local_tables'`)",
         file=TAB, targets=TABLS,
         old="    free_tbl_free_objects(ld, exit)\n",
         new="    free_tbl_free_objects(ld, true)\n"),
    dict(id="TB5-H4 clearThreadTablingData keeps the global worklist (DEFERRED KILL, owner TB2: `ld.tabling.component` is nothing before the evaluation core; the row: a clear inside no evaluation with a completed component list resets it)",
         file=TAB, targets=TABLS,
         old="    c = ld.tabling.component\n    reset_global_worklist(ld, c)\n    reset_newly_created_worklists(",
         new="    c = ld.tabling.component\n    nothing\n    reset_newly_created_worklists("),
    dict(id="TB5-H6 `$tbl_abolish_local_tables` runs inside an evaluation, the scheduling test is dropped (KILL abw01: the call answers yes where the pin is no; AB:425 `variants.value_count == 3`; abl01 holds)",
         file=TAB, targets=TABLS,
         old="    if !ld.tabling.has_scheduling_component\n        clearThreadTablingData(ld, false)\n",
         new="    if true\n        clearThreadTablingData(ld, false)\n"),
    dict(id="TB5-H7 `$tbl_abolish_local_tables` fails when no scheduling component exists, `has_scheduling_component` without `!` (KILL abl01: the pin is yes; abl02, abl03, abl04 fail the same way)",
         file=TAB, targets=TABLS,
         old="    if !ld.tabling.has_scheduling_component\n",
         new="    if ld.tabling.has_scheduling_component\n"),
    dict(id="TB5-H8 `$tbl_abolish_local_tables` clears nothing but answers true (KILL abl02: three tables remain, the pin is 0)",
         file=TAB, targets=TABLS,
         old="        clearThreadTablingData(ld, false)\n\n        return FTRUE\n",
         new="        nothing\n\n        return FTRUE\n"),
    dict(id="TB5-H9 `$tbl_abolish_local_tables` answers true inside an evaluation (KILL abw01: the pin is no)",
         file=TAB, targets=TABLS,
         old="        return FTRUE\n    end\n\n    return FFALSE\nend\n\n# PORT: pl-tabling.c untable_from_clause\n",
         new="        return FTRUE\n    end\n\n    return FTRUE\nend\n\n# PORT: pl-tabling.c untable_from_clause\n"),
    # ── untable_from_clause, untable_definition_clauses (pl-tabling.c; call sites LB6b) ──
    dict(id="TB5-U1 untable_from_clause raises no error when the event hook fails (DEFERRED KILL, owner LB6b: the call sites pl-srcfile.c:1476 and :1544 do not exist before LB6b; LB6b's row: a reconsult of a file that had `:- table p/1` whose PLEV_UNTABLE hook fails raises the error)",
         file=TAB, targets=[AB],
         old='            error("Failed to register untable event")\n',
         new="            nothing\n"),
    dict(id="TB5-U5 untable_definition_clauses walks every definition, `def.arity == 2` is `def.arity == 1` (DEFERRED KILL, owner LB6b: LB6b's `unloadFile` row, a reconsult of a file with `:- table p/1`, fires the event once per `'\\$tabled'/2` clause)",
         file=TAB, targets=[AB],
         old="    if def.arity == 2 && def.functor_name == builtin_atom(\"\\$tabled\")\n",
         new="    if def.arity == 1 && def.functor_name == builtin_atom(\"\\$tabled\")\n"),
    # ── the database threaded through pl-proc.jl / pl-comp.jl (TB5 part 1b): `freeCodesDefinition!(gd, ...)` ──
    dict(id="TB5-P1 `_setDynamicDefinition!` takes the 2-argument freeCodesDefinition! with a database (" + WRAP + ")",
         file=PROC, targets=DYN,
         old="        freeCodesDefinition!(gd, def, true)             # reset to S_VIRGIN\n",
         new="        freeCodesDefinition!(def, true)             # reset to S_VIRGIN\n"),
    dict(id="TB5-P2 `_setDynamicDefinition!` takes the gd branch when there is none, `gd !== nothing` (KILL every caller of the 2-argument method: `freeCodesDefinition!(nothing, def, true)` is a MethodError; src/pl-ext.jl:228 is the boot path, so the boot fails; test_procedures.jl, test_assert_swipl.jl and the other DYN files)",
         file=PROC, targets=DYN,
         old="    if gd === nothing\n        freeCodesDefinition!(def, true)                 # reset to S_VIRGIN\n",
         new="    if gd !== nothing\n        freeCodesDefinition!(def, true)                 # reset to S_VIRGIN\n"),
    dict(id="TB5-P3 `_resetProcedure!` takes the 2-argument freeCodesDefinition! with a database (" + WRAP + ")",
         file=PROC, targets=DYN,
         old="        freeCodesDefinition!(gd, def, !isnew)\n",
         new="        freeCodesDefinition!(def, !isnew)\n"),
    dict(id="TB5-P7 the abolish path of src/pl-proc.jl takes the method without a database for the dynamic reset (" + WRAP + ")",
         file=PROC, targets=DYN,
         old="        setDynamicDefinition!(gd, def, false)\n        resetProcedure!(gd, proc, false)\n",
         new="        setDynamicDefinition!(def, false)\n        resetProcedure!(proc, false)\n"),
]
