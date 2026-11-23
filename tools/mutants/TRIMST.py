# ORIGINAL: TRIMST's mutant list — no swipl-devel counterpart.
# tools/mutants/TRIMST.py — the mutation battery of TRIMST (`trim_stacks/0`, pl-setup.c:1751: src/pl-setup.jl `pl_trim_stacks0_va`
# and its entry in `PL_predicates_from_setup`; src/pl-ext.jl's two lists), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as Q10.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Killed by test/core_lang/test_trim_stacks_swipl.jl (rows ts01-ts14 and the white-box testset, named in
# each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT any
# that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur exactly once in
# its file at the TRIMST commit (a text count, no Julia).
# NOT LISTED (with its reason):
#   * the body of `trimStacks!` (src/pl-setup.jl): ported and listed by the steps that read it (V5d, L1f f1b); a mutant of it needs every
#     stack-overflow test file in TARGETS (audit D-0238), which this step does not own. The white-box testset here pins the `resize` path's
#     effect (the stack given back), so TRIMST-A2 and A3 are killed at the predicate's call of it.
#   * the `PL_FA_VARARGS` flag of the table entry: the entry is called through the variadic convention only; a mutant that drops the flag
#     is a broken call path, not a verdict about the port.
# TARGETS (audit D-0238): the only test file that calls `trim_stacks/0`: no file of the kernel's tests reaches it otherwise (boot/toplevel.pl,
# which calls it after a query, is not loaded by the kernel).
TARGETS = ["test/core_lang/test_trim_stacks_swipl.jl"]
S = "src/pl-setup.jl"
X = "src/pl-ext.jl"
MUTANTS = [
    dict(id="TRIMST-A1 the predicate fails (KILL ts01-ts06, ts08-ts10, ts12-ts14, the white-box testset)",
         file=S, targets=TARGETS,
         old='''    trimStacks!(ld, true)                               # trimStacks(true)
    return FTRUE''',
         new='''    trimStacks!(ld, true)                               # trimStacks(true)
    return FFALSE'''),
    dict(id="TRIMST-A2 the spares are re-reserved but the stack is not shrunk: `trimStacks(false)` (KILL the white-box testset: size() < grown)",
         file=S, targets=TARGETS,
         old='''    trimStacks!(ld, true)                               # trimStacks(true)
    return FTRUE''',
         new='''    trimStacks!(ld, false)                               # trimStacks(true)
    return FTRUE'''),
    dict(id="TRIMST-A3 the call does nothing (KILL the white-box testset: size() < grown)",
         file=S, targets=TARGETS,
         old='''    trimStacks!(ld, true)                               # trimStacks(true)
    return FTRUE''',
         new='''    nothing
    return FTRUE'''),
    dict(id="TRIMST-A4 the entry's arity is 1: trim_stacks/0 is undefined (KILL ts01-ts06, ts08-ts14; ts07 answers instead of raising)",
         file=S, targets=TARGETS,
         old='PL_extension("trim_stacks", 0, pl_trim_stacks0_va, PL_FA_VARARGS)',
         new='PL_extension("trim_stacks", 1, pl_trim_stacks0_va, PL_FA_VARARGS)'),
    dict(id="TRIMST-A5 the entry's name is another: trim_stack/0 (KILL ts01-ts06, ts08-ts14)",
         file=S, targets=TARGETS,
         old='PL_extension("trim_stacks", 0, pl_trim_stacks0_va, PL_FA_VARARGS)',
         new='PL_extension("trim_stack", 0, pl_trim_stacks0_va, PL_FA_VARARGS)'),
]
