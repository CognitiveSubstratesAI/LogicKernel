# ORIGINAL: FuzzCi's mutant list — no swipl-devel counterpart.
# tools/mutants/FuzzCi.py — the mutation battery of the nightly fuzzer's guards (audit D-0127 item 3: tools/fuzz.jl, its
# exit codes and its comparison; 2026-10-24), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# (a mutant that must SURVIVE, with the code reason) and `targets`. The target is a shell command (`sh:`): tools/test_fuzz.sh,
# judged by its exit code, runs the fuzzer itself in fresh Julia processes.
#
# A guard is useless three ways (CLAUDE.md): it cannot pass, it cannot fail, or it compares the wrong thing. FZ1 makes the
# run unable to fail, FZ2 makes the comparison blind to a changed line, FZ3 makes the seed range run another count, FZ4 lets
# a run with nothing compared pass.
TARGETS = ["sh:tools/test_fuzz.sh"]       # also the baseline's: tools/mutate_ci.py takes the unmutated run's targets from here
T = TARGETS
F = "tools/fuzz.jl"
MUTANTS = [
    dict(id="FZ1 a run with mismatching seeds exits 0", file=F, targets=T,
         old='''    return isempty(bad_seeds) ? 0 : 1''',
         new='''    return 0'''),
    dict(id="FZ2 the comparison looks at the number of lines only", file=F, targets=T,
         old='''        i in 1:max(length(sw), length(kl)) if get(sw, i, nothing) != get(kl, i, nothing)''',
         new='''        i in 1:max(length(sw), length(kl)) if i > min(length(sw), length(kl))'''),
    dict(id="FZ3 one seed more than asked for is run", file=F, targets=T,
         old='''    for seed in FIRST_SEED:(FIRST_SEED + NSEEDS - 1)''',
         new='''    for seed in FIRST_SEED:(FIRST_SEED + NSEEDS)'''),
    dict(id="FZ4 swipl's answer is not checked for completeness", file=F, targets=T,
         old='''        length(sw) == length(names) + 1 || begin''',
         new='''        true || begin'''),
]
