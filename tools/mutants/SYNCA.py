# ORIGINAL: SYNC-A's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCA.py — the mutation battery of SYNC-A, the first slice of the sync to swipl-devel cf6960c2 (audit D-0731 B (5), D-0720 (5b)),
# run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE4.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Only the BEHAVIOUR change of the slice is mutated: `is_trie_clause` (pl-trie.h:244-248, written inline in S_TRIE_GEN) and its use (pl-vmi.c:6118-6120): a clause
# reference that is not a compiled trie clause is a `trie_or_clause` type error. The other edits of the slice (B_UNIFY_VV calling do_unify directly, the
# fast cut of I_CUT, S_TABLED's clause_dbref, deep_backtrack's profiler call) change no observable result of the kernel (reasons: the commit messages
# and the notes at the labels in src/pl-wam.jl): no mutant, a mutant of the fast cut would need the whole suite as TARGETS (D-0238).
# KILLS: SA-1 the new kernel-only testset of test/core_lang/test_trie_compiled_swipl.jl (rows k5, k6: SYNC-A TARGET-ONLY, hand-written from the target's C);
#        SA-2 and SA-3: that file's rows t22/t24 (a clause reference of a set trie, of a map trie, run as the first argument);
#        SA-4: k5 and k6 (the test inverted).
# TARGETS (D-0238): S_TRIE_GEN and `is_trie_clause` run in every file that calls trie_gen_compiled/2,3 or runs a completed table's answer trie.
# Every `old` was counted EXACTLY once in its file by a python3 -I script when this file was written (no Julia ran).
TC = "test/core_lang/test_trie_compiled_swipl.jl"
TG = "test/core_lang/test_trie_gen_swipl.jl"
TS = "test/core_lang/test_trie_swipl.jl"
TA = "test/core_lang/test_tabling_answers_swipl.jl"
TV = "test/core_lang/test_trie_attvar_swipl.jl"
TB = "test/db/test_boot_image_swipl.jl"
TT = [TC, TG, TS, TA, TV, TB]
TARGETS = TT
W = "src/pl-wam.jl"


def m(id, old, new, targets=TT, file=W, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    m("SA-1", "        stg_is_trie_clause || @goto trie_gen_type_error",
      "        true || @goto trie_gen_type_error"),
    m("SA-2", "stg_cl.predicate === stg_gc3 || stg_cl.predicate === stg_gc2",
      "stg_cl.predicate === stg_gc2"),
    m("SA-3", "stg_cl.predicate === stg_gc3 || stg_cl.predicate === stg_gc2",
      "stg_cl.predicate === stg_gc3"),
    m("SA-4", "        stg_is_trie_clause || @goto trie_gen_type_error",
      "        stg_is_trie_clause && @goto trie_gen_type_error"),
]
