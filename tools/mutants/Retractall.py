# ORIGINAL: Retractall's mutant list — no swipl-devel counterpart.
# tools/mutants/Retractall.py — the mutation battery of retractall/1 (audit D-0127 item 2, D-0130 item 3:
# pl_retractall1_va, get_procedure_create and its registration in src/pl-proc.jl; 2026-10-24), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. The rows are the programs of
# test/db/test_retractall_swipl.jl (kernel == swipl, line for line).
#
# NOT MUTATED: the `P_FOREIGN` check of pl_retractall1_va — a built-in is also `isDefinedProcedure`, so without it the
# next branch raises the SAME permission_error(modify, static_procedure, …): an equivalent mutant.
TARGETS = ["test/db/test_retractall_swipl.jl"]
T = TARGETS
P = "src/pl-proc.jl"
MUTANTS = [
    dict(id="RA1 retractall/1 is not registered", file=P, targets=T,
         old='''    PL_extension("retractall", 1, pl_retractall1_va, PL_FA_ISO | PL_FA_VARARGS),''',
         new='''    PL_extension("retractall_unregistered", 1, pl_retractall1_va, PL_FA_ISO | PL_FA_VARARGS),'''),
    dict(id="RA2 a static predicate is made dynamic", file=P, targets=T,
         old='''        if isDefinedProcedure(gd, proc)
            PL_error(ld, ERR_MODIFY_STATIC_PROC, proc)''',
         new='''        if false
            PL_error(ld, ERR_MODIFY_STATIC_PROC, proc)'''),
    dict(id="RA3 a new predicate is not made dynamic", file=P, targets=T,
         old='''        return setDynamicDefinition!(def, true) ? FTRUE : FFALSE      # nothing to retract''',
         new='''        return FTRUE      # nothing to retract'''),
    dict(id="RA4 the plain head is not handed on", file=P, targets=T,
         old='''    PL_put_term(ld, h, head)                            # if ( h ) PL_put_term(h, head)''',
         new='''    nothing'''),
]
