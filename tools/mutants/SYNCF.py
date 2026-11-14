# ORIGINAL: SYNC-F's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCF.py — the mutation battery of SYNC-F (the pl-index.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. One mutant per changed behaviour: `hashIndex`'s shift, the
# `assess_remove_duplicates!` space test (guard dropped, boundary, operator), each opcode of `indexableCompound`'s new arm, the order
# of `sort_indexes!` (direction, stability, range, the call itself) and `get_existing_index`. The refactors of the slice (the bucket
# key read once in `first_clause_guarded!`) have none. The `old` strings were written BEFORE `tools/warm.sh fmt` and each checked
# to occur exactly once with a Python count: re-check them after it (mutate_drive.py refuses a string that does not occur once).
# SF-17 (the sort call) may SURVIVE: nothing here builds a predicate whose candidate indexes come out unsorted; a predicate-level row
# is to be found by running (evidence/SYNC/sync_f_handoff.md).
# TARGETS (audit D-0238) name every file that exercises the mutated code: the slice's own file, then every file that runs a clause
# search (the index walk, nth_clause, retract, clause/2, the procedures) and the index's key and argv readers.
TS = ["test/db/test_index_sync_f.jl"]
TV = [
    "test/db/test_index_swipl.jl", "test/db/test_index_argv.jl", "test/db/test_index_context.jl", "test/core_lang/test_index_words.jl",
    "test/db/test_clause_swipl.jl", "test/db/test_nth_clause_swipl.jl", "test/db/test_retract_swipl.jl",
    "test/db/test_retractall_swipl.jl", "test/db/test_procedures.jl",
]
TARGETS = TS + TV
T = TARGETS
X = "src/pl-index.jl"
MUTANTS = [
    dict(id="SF-1 hashIndex does not shift the tag bits out", file=X, targets=T,
         old='key >>= LMASK_BITS',
         new='key >>= 0'),
    dict(id="SF-2 hashIndex shifts one bit too many", file=X, targets=T,
         old='key >>= LMASK_BITS',
         new='key >>= LMASK_BITS + 1'),
    dict(id="SF-3 assess: a variable-heavy small table is never indexable (the space test is dropped)", file=X, targets=T,
         old='a.var_count * a.size > clause_count',
         new='true'),
    dict(id="SF-4 assess: the space boundary is exclusive (>=)", file=X, targets=T,
         old='a.var_count * a.size > clause_count',
         new='a.var_count * a.size >= clause_count'),
    dict(id="SF-5 assess: the space is var_count + size", file=X, targets=T,
         old='a.var_count * a.size > clause_count',
         new='a.var_count + a.size > clause_count'),
    dict(id="SF-6 indexableCompound: I_EXITCATCH no longer ends the argument list", file=X, targets=T,
         old='c2 == I_EXITCATCH',
         new='false'),
    dict(id="SF-7 indexableCompound: I_EXITRESET no longer ends the argument list", file=X, targets=T,
         old='c2 == I_EXITRESET',
         new='false'),
    dict(id="SF-8 indexableCompound: I_EXITFACT no longer ends the argument list", file=X, targets=T,
         old='c2 == I_EXITFACT',
         new='false'),
    dict(id="SF-9 indexableCompound: I_EXIT no longer ends the argument list", file=X, targets=T,
         old='c2 == I_EXIT ||',
         new='false ||'),
    dict(id="SF-10 indexableCompound: I_ENTER no longer ends the argument list", file=X, targets=T,
         old='c2 == I_ENTER',
         new='false'),
    dict(id="SF-11 indexableCompound: I_SSU_COMMIT no longer ends the argument list", file=X, targets=T,
         old='c2 == I_SSU_COMMIT',
         new='false'),
    dict(id="SF-12 indexableCompound: I_SSU_CHOICE no longer ends the argument list", file=X, targets=T,
         old='c2 == I_SSU_CHOICE',
         new='false'),
    dict(id="SF-13 sort_indexes!: ascending speedup", file=X, targets=T,
         old='.speedup < ci.speedup',
         new='.speedup > ci.speedup'),
    dict(id="SF-14 sort_indexes!: not stable (equal speedups swap)", file=X, targets=T,
         old='.speedup < ci.speedup',
         new='.speedup <= ci.speedup'),
    dict(id="SF-15 sort_indexes!: the second slot is never moved", file=X, targets=T,
         old='j > 1 &&',
         new='j > 2 &&'),
    dict(id="SF-16 sort_indexes!: the last slot is left where it is", file=X, targets=T,
         old='for i in 2:count',
         new='for i in 2:count - 1'),
    dict(id="SF-17 set_candidate_indexes! does not sort", file=X, targets=T,
         old='        sort_indexes!(cip, max)\n',
         new=''),
    dict(id="SF-18 get_existing_index answers the first index that differs", file=X, targets=T,
         old='if ci.args == hints.args',
         new='if ci.args != hints.args'),
]
