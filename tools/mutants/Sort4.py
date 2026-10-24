# ORIGINAL: Sort4's mutant list — no swipl-devel counterpart.
# tools/mutants/Sort4.py — the mutation battery of sort/4 (audit D-0127 item 2, D-0130 item 3: pl_sort4_va,
# get_key_arg_ex, extract_key_cells and the order table in src/pl-list.jl; 2026-10-24), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. The rows are q1..q30 of
# test/core_lang/test_sortlist_swipl.jl (kernel == swipl, line for line).
TARGETS = ["test/core_lang/test_sortlist_swipl.jl"]
T = TARGETS
L = "src/pl-list.jl"
MUTANTS = [
    dict(id="SO1 @>= removes duplicates", file=L, targets=T,
         old='''(">=", SORT_DESC, false), ("@>=", SORT_DESC, false)''',
         new='''(">=", SORT_DESC, false), ("@>=", SORT_DESC, true)'''),
    dict(id="SO2 key 0 is followed as an argument path", file=L, targets=T,
         old='''        key === 0 || push!(argv, key) ''',
         new='''        push!(argv, key) '''),
    dict(id="SO3 the argument number is checked against the arity strictly", file=L, targets=T,
         old='''                if an <= arity''',
         new='''                if an < arity'''),
    dict(id="SO4 a missing argument raises nothing", file=L, targets=T,
         old='''                PL_existence_error3(ld, mk_sym(T, :argument), ant, err_t)
''',
         new=''''''),
    dict(id="SO5 a list key may hold 0", file=L, targets=T,
         old='''        tagged && n == 0 && zero_ok && return (1, 0)''',
         new='''        tagged && n == 0 && return (1, 0)'''),
    dict(id="SO6 an atom key on a compound is a compound type error", file=L, targets=T,
         old='''            expected = "dict"                           # no dict, atom key''',
         new='''            expected = "compound"                       # no dict, atom key'''),
    dict(id="SO7 sort/4 is not registered", file=L, targets=T,
         old='''    PL_extension("sort", 4, pl_sort4_va, PL_FA_VARARGS)
''',
         new='''
'''),
    dict(id="SO8 @< keeps duplicates", file=L, targets=T,
         old='''("<", SORT_ASC, true), ("@<", SORT_ASC, true)''',
         new='''("<", SORT_ASC, true), ("@<", SORT_ASC, false)'''),
]
