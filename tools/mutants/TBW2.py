# ORIGINAL: TBW2's mutant list — no swipl-devel counterpart.
# tools/mutants/TBW2.py — the mutation battery of TAB1 W2: `$tbl_node_answer/2` (pl-tabling.c:8957-8969 at 18168e62) and the node handle
# `mdep_unify_answers` hands to it, `take_table_value` (:2804-2822), `save_tabling_status` / `restore_tabling_status` (:2539-2566). Run ONCE, in CI
# (.github/workflows/mutation.yml; locally one mutant at a time). Format: tools/mutate_drive.py's (as TB7.py): `id`, `file`, `old` (must occur EXACTLY
# once), `new`, optional `equivalent` and `targets`.
# NOT RUN YET (written edit-only on wip/tb-w2, 2026-11-13, nothing compiled): every KILL below is an EXPECTATION read off the rows of
# test/core_lang/test_tabling_w2_swipl.jl (W2), none observed; the first hand-run replaces this header with the true verdicts.
# KILL ROWS LEGEND (W2 = test/core_lang/test_tabling_w2_swipl.jl; `t_<case>` in the order of `_TI_CASES`, pins from swipl 10.1.20):
#   lz03 lz04 lz05a lz05b lz06 lz10  the lazy monotonic units of test_monotonic_lazy.pl: each answer list after a new clause is read through
#                                    `$tbl_node_answer/2` (reeval_monotonic_node); a wrong decode or a wrong result changes the answers
#   lc15   the deterministic lazy/eager/plain closure comparison (36 calls of `$tbl_node_answer/2`)
#   lz99   the per-case call counts of `$tbl_node_answer/2` (wrap_predicate): a handle that never decodes loses the calls
#   ab01-ab04  abolish_all_tables of non-empty tables and the rebuild (`empty_variant_table`, `take_table_value`)
#   wbtake  the white-box testset "take_table_value! appends in order"; wbsave  "save_tabling_status / restore_tabling_status (wb)", nested pair
# THE STACK: the lz/lc rows need TB1-TB3, TB6, TB7 and V9's `get_procedure(.., GP_FIND)` (a named refusal until then, see the file header): on this
# branch alone they cannot pass; wbtake and wbsave need none of it.
# TARGETS (audit D-0238): W2 (the step's own rows); TM (test_tabling_monotonic_swipl.jl: the monotonic propagation reaches `mdep_unify_answers`
# through `$idg_mono_affects_lazy`); AB (test_tabling_abolish_swipl.jl: abolish reaches `empty_variant_table` -> `take_table_value!`); TI
# (test_tabling_idg_swipl.jl: the IDG paths reach `empty_variant_table`). For save/restore_tabling_status also TOP1B (test_top1b_swipl.jl: break/0
# runs `pl_break1`). Every `old` was counted EXACTLY once by `python3 -I ~/code/lk-t27-scratch/oldscan.py TBW2` (no Julia ran).
W2 = "test/core_lang/test_tabling_w2_swipl.jl"
TM = "test/core_lang/test_tabling_monotonic_swipl.jl"
AB = "test/core_lang/test_tabling_abolish_swipl.jl"
TI = "test/core_lang/test_tabling_idg_swipl.jl"
TOP1B = "test/core_lang/test_top1b_swipl.jl"
TARGETS_NODE = [W2, TM, AB, TI]
TARGETS_TAKE = [W2, AB, TI, TM]
TARGETS_STATUS = [W2, TOP1B, AB]
TAB = "src/pl-tabling.jl"
MUTANTS = [
    dict(id='TBW2-node-decode-swapped (KILL lz03-lz10, lc15, lz99: the trie of the handle is read from its node field, the lookup fails or names the wrong trie)',
         file=TAB, targets=TARGETS_NODE,
         old='    ti = answer_ref_trie(ptr)\n',
         new='    ti = answer_ref_node(ptr)\n'),
    dict(id='TBW2-node-result-negated (KILL lz03-lz10, lc15, lz99: the answer is unified but the predicate reports the opposite, so the reevaluation sees a failure)',
         file=TAB, targets=TARGETS_NODE,
         old='    return tbl_unify_answer(ld, atrie, nid, A2) ? FTRUE : FFALSE\n',
         new='    return tbl_unify_answer(ld, atrie, nid, A2) ? FFALSE : FTRUE\n'),
    dict(id='TBW2-mdep-bare-node-id (KILL lz03-lz10, lc15, lz99: the Answers list holds the bare node id again, which decodes as trie 0)',
         file=TAB, targets=TARGETS_NODE,
         old='PL_unify_integer(ld, head, answer_ref(atrie.serial, a))',
         new='PL_unify_integer(ld, head, a)'),
    dict(id='TBW2-take-pushfirst (KILL wbtake: the values arrive in reverse order; sort_table_values! hides it in the abolish rows)',
         file=TAB, targets=TARGETS_TAKE,
         old='    push!(values, value)                                # br->values[br->count++] = value\n',
         new='    pushfirst!(values, value)                           # br->values[br->count++] = value\n'),
    dict(id='TBW2-take-skips-the-value (KILL wbtake, ab01-ab04: the value is never stored, its table is never reset and never released, so the table count after abolish_all_tables stays)',
         file=TAB, targets=TARGETS_TAKE,
         old='    push!(values, value)                                # br->values[br->count++] = value\n',
         new='    nothing                                             # br->values[br->count++] = value\n'),
    dict(id='TBW2-save-forgets-prev (KILL wbsave: the nested pair loses the chain, `s2.prev` is not `s1`)',
         file=TAB, targets=TARGETS_STATUS,
         old='    state.prev = tb.saved_status\n',
         new='    state.prev = nothing\n'),
    dict(id='TBW2-save-keeps-component (KILL wbsave: the fresh status still has the old component)',
         file=TAB, targets=TARGETS_STATUS,
         old='    tb.component = nothing\n    tb.has_scheduling_component = false\n',
         new='    tb.has_scheduling_component = false\n'),
    dict(id='TBW2-restore-forgets-iap (KILL wbsave: in_assert_propagation stays false after the restore)',
         file=TAB, targets=TARGETS_STATUS,
         old='    tb.in_assert_propagation = state.iap\n',
         new='    tb.in_assert_propagation = false\n'),
    dict(id='TBW2-restore-keeps-chain (KILL wbsave: saved_status is the restored state itself, not its prev)',
         file=TAB, targets=TARGETS_STATUS,
         old='    tb.saved_status = state.prev\n',
         new='    tb.saved_status = state\n'),
]
