# ORIGINAL: SYNC-Z12's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCZ12.py — the mutation battery of SYNC-Z12 (the pl-list.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. One decision: the guard of `'$length'/2` against a length whose
# `3 * len` overflows (pl-list.c:72-73 of the target). `pl_dlength2_va` is exercised by test_builtins_cells.jl (the guard and the
# unchanged small length) and by test_sortlist_swipl.jl (length/2 through boot/init.pl's `'$length'/2`).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does not
# occur exactly once).
TARGETS = ["test/core_lang/test_builtins_cells.jl", "test/core_lang/test_sortlist_swipl.jl"]
T = TARGETS
L = "src/pl-list.jl"
MUTANTS = [
    dict(id="SZ12-1 the overflow guard of '$length'/2 is dropped", file=L, targets=T,
         old='''            if UInt(len) > typemax(UInt) ÷ UInt(3 * sizeof(UInt))   # (size_t)len > SIZE_MAX/(3*sizeof(word)): len*3 overflows''',
         new='''            if false   # (size_t)len > SIZE_MAX/(3*sizeof(word)): len*3 overflows'''),
    dict(id="SZ12-2 the guard's bound is the Int range, not the size_t one", file=L, targets=T,
         old='''            if UInt(len) > typemax(UInt) ÷ UInt(3 * sizeof(UInt))''',
         new='''            if UInt(len) > typemax(UInt) ÷ UInt(3)'''),
]
