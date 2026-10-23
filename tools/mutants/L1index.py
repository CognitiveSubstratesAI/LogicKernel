# ORIGINAL: L1index's mutant list — no swipl-devel counterpart.
# tools/mutants/L1index.py — the mutation battery of the L1 index step (audit D-0121 item 1; the term index
# path deleted, every search on the cells; a86f678, 2026-10-23), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`,
# `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` (a mutant that must SURVIVE, with the
# code reason) and `targets`.
#
# Subject: the cell argv that the moved test drivers now search through at the TOP level (`ix_with_argv`,
# test/db/index_testlib.jl) — its argument locations, the deep descent from it, and its variable test.
TARGETS = [
    "test/db/test_index_argv.jl",
    "test/db/test_index_context.jl",
    "test/core_lang/test_index_words.jl",
    "test/db/test_index_swipl.jl",
]
I = "src/pl-index.jl"
T = TARGETS
MUTANTS = [
    dict(id="LI1 the deep descent searches one argument too few", file=I, targets=T,
         old='''        argv_cells(ld, q), arityFunctor(ld.functors, ld.gstack[q]), cl, ctx''',
         new='''        argv_cells(ld, q), arityFunctor(ld.functors, ld.gstack[q]) - 1, cl, ctx'''),
    dict(id="LI2 the deep descent starts one cell past the functor", file=I, targets=T,
         old='''    q = valPtr(w)                                           # argv = argTermP(*argv, 0)''',
         new='''    q = valPtr(w) + 1                                           # argv = argTermP(*argv, 0)'''),
    dict(id="LI3 no argument is ever an unbound variable", file=I, targets=T,
         old='''    k, _, _ = _deref_loc(v.ld, _argv_loc(v, i))
    return k == DU_CELL''',
         new='''    k, _, _ = _deref_loc(v.ld, _argv_loc(v, i))
    return false'''),
]
