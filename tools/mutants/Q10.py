# ORIGINAL: Q10's mutant list — no swipl-devel counterpart.
# tools/mutants/Q10.py — the mutation battery of Q10 (`'$style_check'/2`, pl-prims.c:6523-6537: src/pl-prims.jl
# `pl_style_check2_va` and its entry in `PL_predicates_from_prims`), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_style_check_swipl.jl (rows sc01-sc20 named in
# each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in src/pl-prims.jl at wip/q10 5a5d6ef (a text count, no Julia).
# NOT LISTED (with its reason):
#   * the range test of PL_get_integer (src/pl-fli.jl, `val > typemax(Int32) || val < typemin(Int32)`): the code is shared
#     with every caller of PL_get_integer, whose own files are not this step's; rows sc10 and sc13 pin the bounds here, a
#     mutant of the shared line would need every one of those files in TARGETS (audit D-0238) and belongs to the battery of
#     the step that ported PL_get_integer.
#   * the `PL_FA_VARARGS` flag of the table entry: the entry is called through the variadic convention only; a mutant that
#     drops the flag is a broken call path (the row driver reports "exception" or dies), not a verdict about the port.
# TARGETS (audit D-0238): the only test file that calls `'$style_check'/2`. The readers of the set (pl-comp.jl, pl-proc.jl,
# pl-read.jl) are not mutated here.
TARGETS = ["test/core_lang/test_style_check_swipl.jl"]
P = "src/pl-prims.jl"
MUTANTS = [
    dict(id="Q10-A1 the new style set is never stored: the set stays as it was (KILL sc03, sc04, sc11, sc13, sc16, sc20)",
         file=P, targets=TARGETS,
         old="            ld.debugstatus_styleCheck = n\n",
         new="            nothing\n"),
    dict(id="Q10-A2 Old is not unified with the set: the call answers without binding it (KILL sc01, sc03, sc05, sc09)",
         file=P, targets=TARGETS,
         old="    if PL_unify_integer(ld, old, ld.debugstatus_styleCheck)\n",
         new="    if true\n"),
    dict(id="Q10-A3 a New that is no int is taken as 0 and the call succeeds (KILL sc06, sc07, sc08, sc10, sc16, sc18)",
         file=P, targets=TARGETS,
         old="        n = PL_get_integer(ld, new)\n",
         new="        n = something(PL_get_integer(ld, new), 0)\n"),
    dict(id="Q10-A4 New is argument 1, the old value just unified: the set is stored unchanged (KILL sc03, sc04, sc11, sc12, sc20)",
         file=P, targets=TARGETS,
         old="    new = PL__t0 + 1\n",
         new="    new = PL__t0\n"),
    dict(id="Q10-A5 Old is unified with the set minus one: every old value is off (KILL sc01, sc02, sc03, sc05, sc09)",
         file=P, targets=TARGETS,
         old="    if PL_unify_integer(ld, old, ld.debugstatus_styleCheck)\n",
         new="    if PL_unify_integer(ld, old, ld.debugstatus_styleCheck - 1)\n"),
    dict(id="Q10-A6 only the low byte of New is stored: the C int's bounds are lost (KILL sc11, sc12, sc13)",
         file=P, targets=TARGETS,
         old="            ld.debugstatus_styleCheck = n\n",
         new="            ld.debugstatus_styleCheck = n & 0xff\n"),
    dict(id="Q10-A7 a negative New is stored by magnitude (KILL sc12, sc13)", file=P, targets=TARGETS,
         old="            ld.debugstatus_styleCheck = n\n",
         new="            ld.debugstatus_styleCheck = abs(n)\n"),
    dict(id="Q10-A8 the predicate is registered under another name: every row is undefined (KILL sc01-sc20)", file=P,
         targets=TARGETS,
         old="PL_extension(\"\\$style_check\", 2, pl_style_check2_va, PL_FA_VARARGS)",
         new="PL_extension(\"\\$style_check_\", 2, pl_style_check2_va, PL_FA_VARARGS)"),
]
