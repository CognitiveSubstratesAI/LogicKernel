# ORIGINAL: ENG1's mutant list — no swipl-devel counterpart.
# tools/mutants/ENG1.py — the mutation battery of STEP ENG1 (TAB1): `delete_dynamic_table` (src/pl-tabling.jl) runs the IDG branch of
# pl-tabling.c `reset_answer_table` (:2654-2662, `idg_destroy` of the node every orphan dynamic pseudo table has) before `trie_delete`,
# where upstream's release chain (`release_variant_table_node`, :2679-2689) runs it; before ENG1 the kernel's chain raised its named IDG
# refusal for every real orphan (evidence/TAB1/defkill_inventory.md ENGINE FINDING). Run ONCE, in CI (.github/workflows/mutation.yml).
# Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# NOT RUN YET (written edit-only on wip/eng1, nothing compiled or run): every KILL below is an EXPECTATION read off the rows named, none
# observed; the first hand-run replaces this header with the true verdicts.
# THE ROWS: T5R = test_tabling_tb5rows_swipl.jl, groups A7 (a704: `abolish_table_subgoals(ap(_))` leaves no table; a703 the control) and O5 (o504: the
#   sweep leaves 6 tables, `i6`), pinned from swipl, in `_T5_GROUPS_RUN` since ENG1. Both reach `delete_dynamic_table` with a real orphan, which has its
#   IDG node (`orphan_dynamic_table` needs `atrie.IDG !== nothing`).
# TARGETS (audit D-0238): every test file that mentions `reset_answer_table`, `delete_dynamic_table`, `reset_answer_table_idg`, `idg_destroy`,
#   `abolish_table`, `orphan_dynamic` or `sweep_orphan` (two greps over test/ at wip/eng1, the union, test/static_analysis_manifest.jl left out: a
#   static-analysis CI job, not a mutation target).
# Every `old` was counted EXACTLY once in src/pl-tabling.jl at wip/eng1 by a python3 -I script (no Julia ran).
# RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
T5R = "test/core_lang/test_tabling_tb5rows_swipl.jl"
AB = "test/core_lang/test_tabling_abolish_swipl.jl"
TARGETS = [
    AB,
    "test/core_lang/test_tabling_abolish_bulk_upstream_swipl.jl",
    "test/core_lang/test_tabling_abolish_delay_deps_upstream_swipl.jl",
    "test/core_lang/test_tabling_abolish_depending_table_upstream_swipl.jl",
    "test/core_lang/test_tabling_engine_finding_cleanup_throw_swipl.jl",
    "test/core_lang/test_tabling_idg_sets_upstream_swipl.jl",
    "test/core_lang/test_tabling_idg_swipl.jl",
    "test/core_lang/test_tabling_incr_dyn_nodes_upstream_swipl.jl",
    "test/core_lang/test_tabling_supervisor_upstream_swipl.jl",
    "test/core_lang/test_tabling_tb4_tb5_swipl.jl",
    T5R,
    "test/core_lang/test_tabling_tb6rows_swipl.jl",
    "test/core_lang/test_tabling_tb9rows_swipl.jl",
    "test/core_lang/test_tabling_transaction_nested_swipl.jl",
    "test/core_lang/test_tabling_transaction_wb_swipl.jl",
    "test/core_lang/test_tabling_trie_children_upstream_swipl.jl",
    "test/core_lang/test_tabling_variant_swipl.jl",
    "test/core_lang/test_tabling_w2_swipl.jl",
]
TAB = "src/pl-tabling.jl"
IDG_LINE = "        reset_answer_table_idg(ld, atrie, vtrie.magic == TRIE_CMAGIC ? RAT_CLEANUP : 0)\n"
MUTANTS = [
    dict(id="ENG1-D1 delete_dynamic_table does not destroy the orphan's IDG node before the trie_delete (KILL a704, o504 of T5R: the release chain reaches "
            "reset_answer_table's named IDG refusal, so abolish_table_subgoals(ap(_)) and the sweep raise where swipl deletes; the case is a raised(...) line, "
            "the pin is the empty list / i6)",
         file=TAB, targets=TARGETS,
         old=IDG_LINE + "        trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n    end\n\n    return nothing\nend\n\n"
             "# PORT: pl-tabling.c delete_orphan_dynamic_tables\n",
         new="        trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n    end\n\n    return nothing\nend\n\n"
             "# PORT: pl-tabling.c delete_orphan_dynamic_tables\n"),
    dict(id="ENG1-D2 the IDG branch runs after the trie_delete instead of before (KILL a704, o504 of T5R: trie_delete's release chain sees `atrie.IDG` "
            "still set and raises the refusal; the same observation as ENG1-D1)",
         file=TAB, targets=TARGETS,
         old=IDG_LINE + "        trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n    end\n\n    return nothing\nend\n\n"
             "# PORT: pl-tabling.c delete_orphan_dynamic_tables\n",
         new="        trie_delete(_query_gd(ld), vtrie, atrie.variant, true)\n" + IDG_LINE +
             "    end\n\n    return nothing\nend\n\n# PORT: pl-tabling.c delete_orphan_dynamic_tables\n"),
    dict(id="ENG1-D3 the orphan's node is destroyed as a bulk reset's: `RAT_BULK` for the flags, `idg_destroy_private` (the registry entry is left, the "
            "neighbours' sets are cleared without their back edges) where `idg_destroy` removes both (EXPECTED to be killed by the IDG registry reads of "
            "AB (testset \"clear_variant_table releases the IDG registry\") or test_tabling_idg_swipl.jl ONLY if a row counts the registry after an orphan's "
            "deletion: NOT VERIFIED, the first hand-run decides; a survivor needs a white-box row (registry size before and after `abolish_table_subgoals` of "
            "an incremental table over a dynamic one))",
         file=TAB, targets=TARGETS,
         old=IDG_LINE,
         new="        reset_answer_table_idg(ld, atrie, vtrie.magic == TRIE_CMAGIC ? RAT_CLEANUP : RAT_BULK)\n"),
    dict(id="ENG1-D4 the flags are 0 for the cleanup variant table too (EQUIVALENT)",
         file=TAB, targets=TARGETS,
         equivalent="src/pl-tabling.jl `reset_answer_table_idg` reads only `flags & RAT_BULK` (its body, `if (flags & RAT_BULK) != 0`); RAT_CLEANUP is read by "
                    "`reset_answer_table_worklist` and `reset_answer_table` (the worklist branch, `destroy_depending_worklists`), neither of which runs in "
                    "delete_dynamic_table: the table's worklist is the sentinel `WL_DYNAMIC`, an `Int`. Upstream's `release_variant_table_node` passes the same flag "
                    "(pl-tabling.c:2688-2689), so the line keeps it for fidelity",
         old=IDG_LINE,
         new="        reset_answer_table_idg(ld, atrie, 0)\n"),
]

# TAB1 GATE: the files of evidence/TAB1/tab1_late.md are not in the gate tree (they stay on wip/tab1-late, each with the line it waits for): a target that is not in the tree makes the
# Baseline job fail (`exit notest`), so they are dropped from TARGETS and from every mutant's `targets`. A mutant whose kill row
# lived only in such a file keeps the remaining targets and shows in the verdict table as it is (survivor or caught).
# Remove this block when the late files return to the gate.
_TAB1_LATE = [
    "test/core_lang/test_tabling_answer_discard_upstream_swipl.jl",
    "test/core_lang/test_tabling_supervisor_upstream_swipl.jl",
    "test/core_lang/test_tabling_trie_children_upstream_swipl.jl",
    "test/core_lang/test_tabling_trie_index_upstream_swipl.jl",
    "test/core_lang/test_tabling_trie_upstream_swipl.jl",
    "test/core_lang/test_tabling_table_statistics_upstream_swipl.jl",
    "test/core_lang/test_tabling_tabling_upstream_b_swipl.jl",
    "test/core_lang/test_tabling_trie_attvars_upstream_swipl.jl",
    "test/core_lang/test_tabling_incr_dyn_nodes_upstream_swipl.jl",
    "test/core_lang/test_transaction_swipl.jl",
]
TARGETS = [_t for _t in TARGETS if _t not in _TAB1_LATE]
for _m in MUTANTS:
    _m["targets"] = [_t for _t in _m.get("targets", TARGETS) if _t not in _TAB1_LATE] or list(TARGETS)


# ENG1D4: ENG1-D4 ALONE (audit D-0911 (2): a single-mutant re-run at 1104ff8d; the same targets and baseline as ENG1)
MUTANTS = [m for m in MUTANTS if m["id"].startswith("ENG1-D4")]
