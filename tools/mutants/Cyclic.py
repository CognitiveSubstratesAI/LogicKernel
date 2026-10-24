# ORIGINAL: Cyclic's mutant list — no swipl-devel counterpart.
# tools/mutants/Cyclic.py — the mutation battery of acyclic_term/1 and cyclic_term/1 (audit D-0127 item 2, D-0130 item 3:
# pl_acyclic_term1_va / pl_cyclic_term1_va in src/pl-prims.jl and their registration; 2026-10-24), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
TARGETS = ["test/core_lang/test_cyclic_term_swipl.jl"]
T = TARGETS
P = "src/pl-prims.jl"
MUTANTS = [
    dict(id="CY1 acyclic_term/1 answers the opposite", file=P, targets=T,
         old='''    return is_acyclic_cells(ld, -(A1 + 1)) ? FTRUE : FFALSE
end

# PORT: pl-prims.c cyclic_term''',
         new='''    return is_acyclic_cells(ld, -(A1 + 1)) ? FFALSE : FTRUE
end

# PORT: pl-prims.c cyclic_term'''),
    dict(id="CY2 cyclic_term/1 answers the opposite", file=P, targets=T,
         old='''    return is_acyclic_cells(ld, -(A1 + 1)) ? FFALSE : FTRUE''',
         new='''    return is_acyclic_cells(ld, -(A1 + 1)) ? FTRUE : FFALSE'''),
    dict(id="CY3 cyclic_term/1 is not registered", file=P, targets=T,
         old='''    PL_extension("cyclic_term", 1, pl_cyclic_term1_va, PL_FA_VARARGS),
''',
         new=''''''),
    dict(id="CY4 acyclic_term/1 is true of every term", file=P, targets=T,
         old='''    return is_acyclic_cells(ld, -(A1 + 1)) ? FTRUE : FFALSE
end

# PORT: pl-prims.c cyclic_term''',
         new='''    return FTRUE
end

# PORT: pl-prims.c cyclic_term'''),
]
