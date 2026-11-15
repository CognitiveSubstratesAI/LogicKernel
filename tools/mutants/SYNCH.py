# ORIGINAL: SYNC-H's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCH.py — the mutation battery of SYNC-H2 (the pl-comp.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. Only the behaviour change of the slice has mutants: `arithCompilable`
# and its guard in `compileSubClause!` (a goal with a "char" list whose element or tail is unbound is compiled as a call under
# `optimise`); the other changed functions are notes (atom registration, pointer integers, unwritten A_CMP_* instructions, HEAD-RIGHT:
# see evidence/SYNC/sync_h_handoff.md, section SYNC-H2). TARGETS are every test file that compiles a clause under `optimise` (D-0238):
# the flag is set through PLFLAG_OPTIMISE or `set_prolog_flag(optimise, ...)` in these.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does not
# occur exactly once).
TARGETS = [
    "test/compile/test_body_code_swipl.jl",
    "test/core_lang/test_firstvar_swipl.jl",
    "test/core_lang/test_head_unify_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/core_lang/test_push_flag_swipl.jl",
    "test/core_lang/test_set_flag_swipl.jl",
]
T = TARGETS
P = "src/pl-comp.jl"
MUTANTS = [
    dict(id="SH-1 the optimise guard no longer asks arithCompilable", file=P, targets=T,
         old='''            truePrologFlag(ld, PLFLAG_OPTIMISE) && arithCompilable(T, arg) &&''',
         new='''            truePrologFlag(ld, PLFLAG_OPTIMISE) &&'''),
    dict(id="SH-2 arithCompilable: a list cell is refused only when head AND tail are unbound", file=P, targets=T,
         old='''                if kind(child(arg, 2)) === VAR || kind(child(arg, 3)) === VAR''',
         new='''                if kind(child(arg, 2)) === VAR && kind(child(arg, 3)) === VAR'''),
    dict(id="SH-3 arithCompilable: only the list's head is checked", file=P, targets=T,
         old='''                if kind(child(arg, 2)) === VAR || kind(child(arg, 3)) === VAR''',
         new='''                if kind(child(arg, 2)) === VAR'''),
    dict(id="SH-4 arithCompilable: only the list's tail is checked", file=P, targets=T,
         old='''                if kind(child(arg, 2)) === VAR || kind(child(arg, 3)) === VAR''',
         new='''                if kind(child(arg, 3)) === VAR'''),
    dict(id="SH-5 arithCompilable: the arguments of a compound are not descended", file=P, targets=T,
         old='''                    push!(stack, _comp_arg(arg, off, i))''',
         new='''                    nothing'''),
]
