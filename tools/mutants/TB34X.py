# ORIGINAL: the equivalence-scan device list of TAB1 (audit D-0705 item 3): a repository list of ours (upstream has no such file).
# tools/mutants/TB34X.py: the SAME mutants as tools/mutants/TB4.py (TB4-S1, S3, S4, A2, A3: declared open survivors at batch 3; TB4-I3, whose
# `equivalent` text claimed no row prints the wrapper) and tools/mutants/TB3.py (TB3-A3, F3, F4, U2, T2, D3, C2, C8: declared EQUIVALENT), each
# with the same id, file, `old` and `new` byte for byte in value, but with (1) `targets` = the entry's own targets PLUS every test file that
# mentions the mutated function or a Prolog predicate that reaches it (the scan of evidence/TAB1/equiv_scan.md) and (2) `equivalent` REMOVED, so the
# three-type battery's verdict is honest: SURVIVED or caught, per term type. The mutated tree is the batch-3 tree (src and test). Run ONCE, in CI.
# An id that stays SURVIVED on all three term types with these targets is tested by no file of test/ that touches the code.
S5G = "test/core_lang/test_tabling_s5_guard.jl"
A1G = "test/core_lang/test_tabling_a1_guard.jl"
TATT = "test/core_lang/test_trie_attvar_swipl.jl"
TG = "test/core_lang/test_trie_gen_swipl.jl"
TBR = "test/core_lang/test_tabling_tb4rows_swipl.jl"
TBR2 = "test/core_lang/test_tabling_tb4rows2_swipl.jl"
TCMP = "test/core_lang/test_trie_compiled_swipl.jl"
TT = "test/core_lang/test_tabling_state_swipl.jl"
TW = "test/core_lang/test_tabling_wfs_swipl.jl"
TP = "test/core_lang/test_trie_preds_swipl.jl"
TV = "test/core_lang/test_tabling_variant_swipl.jl"
TWL = "test/core_lang/test_tabling_worklist_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
TA = "test/core_lang/test_tabling_answers_swipl.jl"
TRIE = "test/core_lang/test_trie_swipl.jl"
TARGETS = [S5G, A1G, TATT, TG, TBR, TBR2, TCMP, TT, TW, TP, TV, TWL, TM, TA, TRIE]            # every file a mutant lists (mutate_ci.py plan reads TARGETS)
TAB = "src/pl-tabling.jl"
MUTANTS = [
    dict(id='TB4-S1 add_to_delay_set does not count an active delay (OPEN SURVIVOR AT BATCH 3, declared (audit D-0659), closes in tab-int with the TB5 builtin, owner TAB1/TB5: the rows need the builtin $tbl_destroy_table/1 (answer completion ends with abolish_table_subgoals), a TB5 builtin absent from batch 3, so the rows are in test_tabling_tb4_tb5_swipl.jl on the integration branch wip/tab-int, not in TR/TR2; the row: TR rows r09a-r09d, r10a-r10c: `ds.active` reaches 0 at the first removed member, the answer turns unconditional too early; the model of the stale-delay program and `sb :- tnot(sa). sb.` with sa false)',
         file=TAB, targets=[TBR, TBR2, TW, TA],
         old='    variant != 0 && (ds.active += UInt32(1))\n',
         new='    variant != 0 && (ds.active += UInt32(0))\n'),
    dict(id='TB4-S3 propagate_to_answer: a true result removes the conjunction (OPEN SURVIVOR AT BATCH 3, declared (audit D-0659), closes in tab-int with the TB5 builtin, owner TAB1/TB5: the rows need the builtin $tbl_destroy_table/1 (answer completion ends with abolish_table_subgoals), a TB5 builtin absent from batch 3, so the rows are in test_tabling_tb4_tb5_swipl.jl on the integration branch wip/tab-int, not in TR/TR2; the row: TR rows r10a, r10b: `k10 :- tnot(n10).` with n10 ending without an answer, call_delays(k10, true) pinned yes)',
         file=TAB, targets=[TBR, TBR2, TW, TA],
         old='                        if res                                  # remove member from conjunction',
         new='                        if !res                                 # remove member from conjunction'),
    dict(id='TB4-S4 simplify_component stops after one pass (OPEN SURVIVOR AT BATCH 3, declared (audit D-0659), closes in tab-int with the TB5 builtin, owner TAB1/TB5: the rows need the builtin $tbl_destroy_table/1 (answer completion ends with abolish_table_subgoals), a TB5 builtin absent from batch 3, so the rows are in test_tabling_tb4_tb5_swipl.jl on the integration branch wip/tab-int, not in TR/TR2; the row: TR row r09a: the stale-delay program a..f called from f needs several passes of simplify_component, pinned model a,f true and b..e false)',
         file=TAB, targets=[S5G, TBR, TBR2, TW, TWL, TM, TA],
         old='        (count == 0 || undefined == 0) && break\n',
         new='        break\n'),
    dict(id='TB4-A2 is_ac_candidate_wl asks only `wl.undefined != 0` (OPEN SURVIVOR AT BATCH 3, declared (audit D-0659), closes in tab-int with the TB5 builtin, owner TAB1/TB5: the rows need the builtin $tbl_destroy_table/1 (answer completion ends with abolish_table_subgoals), a TB5 builtin absent from batch 3, so the rows are in test_tabling_tb4_tb5_swipl.jl on the integration branch wip/tab-int, not in TR/TR2; the row: TR2 group g13a, rows r1301 + r1302: a prolog_wrap counter on the answer completion pins ONE call for the program, the mutant also calls it on the worklists already marked answer completed)',
         file=TAB, targets=[A1G, TBR, TBR2, TW],
         old='    if wl.undefined != 0 && !wl.answer_completed && !isempty(wl.delays)\n',
         new='    if wl.undefined != 0\n'),
    dict(id='TB4-A3 has_positive_dl counts a negative delay (OPEN SURVIVOR AT BATCH 3, declared (audit D-0659), closes in tab-int with the TB5 builtin, owner TAB1/TB5: the rows need the builtin $tbl_destroy_table/1 (answer completion ends with abolish_table_subgoals), a TB5 builtin absent from batch 3, so the rows are in test_tabling_tb4_tb5_swipl.jl on the integration branch wip/tab-int, not in TR/TR2; the row: TR2 group g13b, rows r1303 + r1304: the same counter pins ZERO calls for a program whose delays are all negative, the mutant calls the answer completion)',
         file=TAB, targets=[A1G, TBR, TBR2, TW],
         old='                    d.answer != 0 && return true\n',
         new='                    return true\n'),
    dict(id="TB4-I3 init_delay_list's wrapper functor is +/1, not -/1 (EQUIVALENT)",
         file=TAB, targets=[TT, TW, TA],
         old='mk_sym(T, :-)), 1), a\n',
         new='mk_sym(T, :+)), 1), a\n'),
    dict(id='TB3-A3 a moded answer that changed nothing is reported new, `: TBL_ANSWER_NEW` (EQUIVALENT: only the truthiness of the result is read, `$tbl_wkl_add_answer`/4 pl-tabling.jl:555-567, and delim/4, boot/tabling.pl:695-696, fails after both; the effects on the trie are the same)',
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='wkl_mode_add_answer(ld, wl, atrie, answer, delays) != 0 ? TBL_ANSWER_NEW : 0',
         new='wkl_mode_add_answer(ld, wl, atrie, answer, delays) != 0 ? TBL_ANSWER_NEW : TBL_ANSWER_NEW'),
    dict(id='TB3-F3 tbl_add_answer_found: a variant answer reports TBL_ANSWER_NEW, `return 0  # already in trie` -> NEW (EQUIVALENT: as TB3-A3, only truthiness, pl-tabling.jl:555-567 and boot/tabling.pl:695-696; the trie and the worklist are untouched by this return)',
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='                return 0                            # already in trie\n',
         new='                return TBL_ANSWER_NEW                # already in trie\n'),
    dict(id='TB3-F4 tbl_add_answer_found: the IDG_DELETED flag of a found node is not cleared (EQUIVALENT: nothing sets TN_IDG_DELETED at wip/tb3, grep src/: the constant pl-incl.jl:1261 and its mask :1285 only; TB6 sets it, owner TB6 re-judges)',
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='                if (nd.flags & TN_IDG_DELETED) != 0\n                    nd.flags &= ~TN_IDG_DELETED\n                    @goto update_dl\n',
         new='                if (nd.flags & TN_IDG_DELETED) != 0\n                    @goto update_dl\n'),
    dict(id="TB3-U2 update_delay_list: no early completion of a ground call, `return UDL_TRUE` (EQUIVALENT in every answer: an early completion only prunes the worker's choice points (pl-tabling.jl:419-426); a ground variant has at most one answer; the side-effect witness is TB3-F7's row, DEFERRED TB5)",
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='        return wl.ground ? UDL_COMPLETE : UDL_TRUE\n',
         new='        return UDL_TRUE\n'),
    dict(id="TB3-T2 tbl_single_answer: the answer count is not 1, `!= 1` (EQUIVALENT until TB6: the conjunct `atrie.IDG !== nothing` after it is false for every table, pl-tabling.jl:874-880, so the result is 0 whatever the count is; TB6 re-judges with TB3-T1's row)",
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='    if atrie.value_count == 1 &&\n',
         new='    if atrie.value_count != 1 &&\n'),
    dict(id="TB3-D3 trie_gen's data kind of `$tbl_answer` is the node handle, 0 for 2 (EQUIVALENT, audit D-0635 re-judged: the constant is only a tag shared by its three callers and the one comparison, see `equivalent`; no row can differ)",
         file=TAB, targets=[TATT, TG, TBR2, TCMP, TP, TV, TM, TA, TRIE],
         old='const TRIE_GEN_DELAY_INFO = 2\n',
         new='const TRIE_GEN_DELAY_INFO = 0\n'),
    dict(id='TB3-C2 complete_answer_clause: a single-answer table gets no symbol, `tbl_single_answer(atrie) != 0 && return trie_symbol(gd, atrie)` dropped (EQUIVALENT until TB6: `tbl_single_answer` answers 0 for every table, pl-tabling.jl:874-880, so the line never returns)',
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='        tbl_single_answer(atrie) != 0 && return trie_symbol(gd, atrie)\n',
         new='        nothing\n'),
    dict(id='TB3-C8 tbl_complete_answer_clause: the cached start node is not stored, `set_start_node` dropped (EQUIVALENT in every answer: the start node only shortens the next trie_lookup_flat (`cached = start != 0`, pl-tabling.jl:1090-1094), the lookup from the root finds the same node; a performance cache)',
         file=TAB, targets=[TBR, TBR2, TW, TWL, TM, TA],
         old='    if !cached && start != 0\n        set_start_node(ld, variants, id, start)\n    end\n',
         new='    if !cached && start != 0\n        nothing\n    end\n'),
]
