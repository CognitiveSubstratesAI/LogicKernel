# ORIGINAL: F3b2a's mutant list — no swipl-devel counterpart.
# tools/mutants/F3b2a.py — the mutation battery of F3B step f3b-2's first landing (D-0095 item 1, 2026-10-22):
# two unbound cells ordered by position, and the writer's variable name from the position. Run ONCE, at the
# step's close, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's.
#
# FC1 is the guard of D-0095 item 2's rows (test_compare_cells.jl, variables made out of LIFO order: functor/3,
# after backtracking, copy_term/2, a nested body compound, =..): each is judged by swipl, so a flipped order
# must move them. FC2 is the guard of the changed test_var_identity.jl pin (D-0083).
# What this list does NOT cover: varName's boundary branch (a keyed variable's name, unchanged by this step).
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/core_lang/test_compare_cells.jl",
    "test/core_lang/test_var_identity.jl",
]
PRM = "src/pl-prims.jl"
WRT = "src/pl-write.jl"
MUTANTS = [
    dict(id="FC1 two unbound cells ordered against their positions", file=PRM,
         targets=["test/core_lang/test_compare_cells.jl"],
         old='''        return p1 < p2 ? CMP_LESS : CMP_GREATER              # SCALAR_TO_CMP(p1, p2)''',
         new='''        return p1 > p2 ? CMP_LESS : CMP_GREATER'''),
    dict(id="FC2 a variable's name counted from position 0, not from the stack base", file=WRT,
         targets=["test/core_lang/test_var_identity.jl"],
         old='''    k == DU_CELL && return "_" * string((p - 1) * 2)        # iref = ((Word)p - (Word)gBase)*2''',
         new='''    k == DU_CELL && return "_" * string(p * 2)'''),
]
