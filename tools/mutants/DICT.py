# ORIGINAL: DICT's mutant list — no swipl-devel counterpart.
# tools/mutants/DICT.py — the mutation battery of BOOTPRED-dict (D-0291 item 5; R2b): the pl-dict.c predicates written on wip/dict
# in src/pl-dict.jl — get_dict/5, put_dict/4, dict_pairs/3 (pl_for_dict, pl_dict_sort_indexes, put_pair), del_dict/4, `:<`/2 and `>:<`/2
# (unify_left_dict, partial_unify_dict), dict_same_keys/2 (copy_keys_dict, same_keys_dict) and `$get_dict_kv`/4,6,8 — run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old`
# (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_dict_preds_swipl.jl (rows dp01-dp164
# named in each id's KILL) and test/core_lang/test_bootpred_swipl.jl (put_dict/3 and get_dict/3 share put_dict and get_dict_ex).
# Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT
# any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur exactly
# once in src/pl-dict.jl at the wip/dict tip (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * the `ensureGlobalSpace(…) || return nothing` lines of del_dict and copy_keys_dict: the overflow they report is raised by
#     ensureGlobalSpace itself and no row grows the stacks, so no row can tell the line from its removal (the global-overflow rows are
#     the stack tests', not the dict rows').
#   * same_keys_dict's functor comparison (`ld.gstack[f1] != ld.gstack[f2]` removed): with different arities the loop would read
#     past the shorter dict, a crash or a hang, not a verdict.
#   * get_dict_kv's `dict_count` arithmetic: a wrong count reads the term-reference block out of range, the same.
# TARGETS (audit D-0238): every mutant lists every test file that exercises its mutated code: the step's own file first, then
# test_bootpred_swipl.jl (the pl-dict.c rows of BOOTPRED: put_dict and the lookup share the mutated functions) and
# test_type_discipline.jl (the three term types).
TD = "test/core_lang/test_dict_preds_swipl.jl"
TB = "test/core_lang/test_bootpred_swipl.jl"
TT = "test/test_type_discipline.jl"
TARGETS = [TD, TB, TT]
D = "src/pl-dict.jl"
MUTANTS = [
    # ── get_dict/5 ──
    dict(id="DICT-G1 get_dict/5 does not unify the old value with Val: a wrong Val is accepted (KILL dp16, dp24)", file=D, targets=TARGETS,
         old="    r === nothing && return FFALSE\n    unify_ptrs_cells(ld, r[1], -(A3 + 1)) || return FFALSE\n",
         new="    r === nothing && return FFALSE\n    nothing\n"),
    dict(id="DICT-G2 get_dict/5 puts the OLD value into the new dict: NewVal is ignored (KILL dp13, dp14, dp25)", file=D, targets=TARGETS,
         old="    _dict_link!(ld, av, -(A5 + 1))                  # PL_put_term(av+0, A5)\n",
         new="    _dict_link!(ld, av, -(A3 + 1))\n"),
    # ── put_dict/4 ──
    dict(id="DICT-P1 put_dict/4 puts the KEY as the value (KILL dp31, dp32, dp40)", file=D, targets=TARGETS,
         old="        _dict_link!(ld, av, -(value + 1))           # PL_put_term(av, value)\n",
         new="        _dict_link!(ld, av, -(key + 1))\n"),
    dict(id="DICT-P2 put_dict/4 puts no pair: the dict comes back unchanged (KILL dp31, dp33, dp34)", file=D, targets=TARGETS,
         old="        new = put_dict(ld, d0, 1, av)\n",
         new="        new = put_dict(ld, d0, 0, av)\n"),
    # ── dict_pairs/3 ──
    dict(id="DICT-D1 dict_pairs/3 does not sort the pairs: the kernel's own key-word order shows (KILL dp51, dp80, dp81)", file=D, targets=TARGETS,
         old="    sort!(indexes; lt = (a, b) -> compareStandard_cells(ld, f + 3 + 2 * a, f + 3 + 2 * b, false) < 0)\n",
         new="    sort!(indexes; lt = (a, b) -> a < b)\n"),
    dict(id="DICT-D2 dict_pairs/3 sorts the keys in reverse standard order (KILL dp50, dp51, dp80)", file=D, targets=TARGETS,
         old="    sort!(indexes; lt = (a, b) -> compareStandard_cells(ld, f + 3 + 2 * a, f + 3 + 2 * b, false) < 0)\n",
         new="    sort!(indexes; lt = (a, b) -> compareStandard_cells(ld, f + 3 + 2 * a, f + 3 + 2 * b, false) > 0)\n"),
    dict(id="DICT-D3 put_pair builds `=`/2 pairs, not `-`/2 (KILL dp50, dp51, dp54)", file=D, targets=TARGETS,
         old="    if PL_cons_functor(ld, tmp, _err_functor(ld, :-, 2), key, value) &&\n",
         new="    if PL_cons_functor(ld, tmp, _err_functor(ld, :(=), 2), key, value) &&\n"),
    dict(id="DICT-D4 dict_pairs/3 does not unify the tag with Tag (KILL dp50, dp67)", file=D, targets=TARGETS,
         old="               PL_unify(ld, tmp, A2) &&\n",
         new="               true &&\n"),
    dict(id="DICT-D5 dict_pairs/3 with an unbound dict takes a pair of any form: `a=1` is accepted (KILL dp58, dp59, dp60)", file=D, targets=TARGETS,
         old="        if PL_get_dict_ex(ld, A3, A2, m, DICT_GET_PAIRS)\n",
         new="        if PL_get_dict_ex(ld, A3, A2, m, DICT_GET_ALL)\n"),
    # ── del_dict/4 ──
    dict(id="DICT-E1 del_dict/4 keeps the deleted key and drops the others (KILL dp82, dp83, dp92)", file=D, targets=TARGETS,
         old="        if i_name != key\n",
         new="        if i_name == key\n"),
    dict(id="DICT-E2 del_dict/4 loses the tag: the new dict's tag is unbound (KILL dp89, dp97)", file=D, targets=TARGETS,
         old="    _dict_link!(ld, new + 1, f + 1)                 # new[1] = linkValI(&data->arguments[0])  tag\n",
         new="    ld.gstack[new + 1] = word(0)\n"),
    dict(id="DICT-E3 del_dict/4 does not unify Value with the deleted value (KILL dp85, dp91)", file=D, targets=TARGETS,
         old="        if r !== nothing && unify_ptrs_cells(ld, r[1], -(A3 + 1))\n",
         new="        if r !== nothing\n"),
    # ── :</2 and >:</2 ──
    dict(id="DICT-U1 `>:<` does not unify the tags (KILL dp117, dp118)", file=D, targets=TARGETS,
         old="    unify_tags(ld, in1, in2) || return false        # unify the tags\n",
         new="    nothing\n"),
    dict(id="DICT-U2 `:<` does not unify the tags (KILL dp99, dp102)", file=D, targets=TARGETS,
         old="    unify_tags(ld, din, fin) || return false        # unify the tags\n",
         new="    nothing\n"),
    dict(id="DICT-U3 `:<` succeeds when keys of Select are left over (KILL dp100, dp104, dp112)", file=D, targets=TARGETS,
         old="    return din == dend\n",
         new="    return true\n"),
    dict(id="DICT-U4 `:<` is called with its arguments swapped (KILL dp104, dp105)", file=D, targets=TARGETS,
         old="        return unify_left_dict(ld, d0, d1) ? FTRUE : FFALSE\n",
         new="        return unify_left_dict(ld, d1, d0) ? FTRUE : FFALSE\n"),
    dict(id="DICT-U5 `>:<` always succeeds after the type checks (KILL dp115, dp117)", file=D, targets=TARGETS,
         old="        return partial_unify_dict(ld, d0, d1) ? FTRUE : FFALSE\n",
         new="        return FTRUE\n"),
    dict(id="DICT-U6 `>:<` advances the second dict on a smaller key `<=`: the equal case is taken before, so the order of the two tests is not observable",
         file=D, targets=TARGETS, equivalent="src/pl-dict.jl:1093 partial_unify_dict: the `elseif n1 < n2` arm is reached only when n1 != n2 (the `n1 == n2` arm precedes it), so `<=` takes the same arms",
         old="        elseif n1 < n2\n",
         new="        elseif n1 <= n2\n"),
    dict(id="DICT-U7 `:<` returns false on a smaller key of Select `<=`: reached only when d != f, so the same arms",
         file=D, targets=TARGETS, equivalent="src/pl-dict.jl:1127 unify_left_dict: the `elseif d < f` arm is reached only when d != f (the `d == f` arm precedes it), so `<=` takes the same arms",
         old="        elseif d < f\n            return false\n",
         new="        elseif d <= f\n            return false\n"),
    # ── dict_same_keys/2 ──
    dict(id="DICT-S1 dict_same_keys/2 with two dicts always succeeds (KILL dp129, dp130)", file=D, targets=TARGETS,
         old="            return same_keys_dict(ld, d1, d2) ? FTRUE : FFALSE\n",
         new="            return FTRUE\n"),
    dict(id="DICT-S2 same_keys_dict compares no key: two dicts of the same size are the same (KILL dp129)", file=D, targets=TARGETS,
         old="        if k1 != k2\n",
         new="        if false\n"),
    dict(id="DICT-S3 copy_keys_dict copies the tag of the source instead of an unbound tag (KILL dp131, dp132, dp137)", file=D, targets=TARGETS,
         old="    ld.gstack[out] = word(0)                        # set tag to var\n",
         new="    ld.gstack[out] = ld.gstack[f + 1]\n"),
    # ── $get_dict_kv/4,6,8 ──
    dict(id="DICT-K1 $get_dict_kv rejects the first pair too (index 1) (KILL dp144, dp152)", file=D, targets=TARGETS,
         old="    (i === nothing || i == 0) && return false\n",
         new="    (i === nothing || i == 0 || i == 1) && return false\n"),
    dict(id="DICT-K2 $get_dict_kv fails at the last pair: `i >= darity / 2` (KILL dp144, dp152)", file=D, targets=TARGETS,
         old="        if i > darity ÷ 2\n",
         new="        if i >= darity ÷ 2\n"),
    dict(id="DICT-K3 $get_dict_kv raises compatible_dict when the first dict's key does not unify, instead of failing (KILL dp153, dp154)", file=D, targets=TARGETS,
         old="                if di == 0\n",
         new="                if false\n"),
]
