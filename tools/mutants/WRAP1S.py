# ORIGINAL: the mutant list of R2 WRAP1's run-time callers of `freeCodesDefinition!` — no swipl-devel counterpart.
# tools/mutants/WRAP1S.py — `setDynamicDefinition!(gd, ...)` and `resetProcedure!(gd, ...)` (src/pl-proc.jl) hand the database to
# `freeCodesDefinition!`, so a wrapped predicate made dynamic or abolished at run time keeps its wrapper (pl-supervisor.c:108-129).
# Format: tools/mutate_drive.py's (as MOD3b.py). Verdicts: written by the battery, not yet run. Anchors checked to occur exactly once
# (a text count); RE-FIT any that `warm.sh fmt` rewraps. TARGETS (audit D-0238): test_tabling_min_swipl.jl (rows tmd01, tmd02) and
# every file whose program abolishes or makes predicates dynamic through these functions (as tools/mutants/TAB1MIN.py's SUP).
TM = ["test/core_lang/test_tabling_min_swipl.jl"]
TARGETS = TM + ["test/core_lang/test_pr1_swipl.jl", "test/core_lang/test_event_swipl.jl",
                "test/db/test_procedures.jl", "test/db/test_assert_swipl.jl"]
PR = "src/pl-proc.jl"
MUTANTS = [
    dict(id="WRAP1S-1 setDynamicDefinition!(gd, ...) static to dynamic calls the 2-argument freeCodesDefinition!: a wrapped predicate raises (KILL tmd01, tmd02)",
         file=PR, targets=TARGETS,
         old="P_DYNAMIC | P_TRANSACT\n        freeCodesDefinition!(gd, def, true)",
         new="P_DYNAMIC | P_TRANSACT\n        freeCodesDefinition!(def, true)"),
    dict(id="WRAP1S-2 resetProcedure!(gd, ...) calls the 2-argument freeCodesDefinition!: abolishing a wrapped predicate raises (KILL tmd02)",
         file=PR, targets=TARGETS,
         old="    freeCodesDefinition!(gd, def, !isnew)\n",
         new="    freeCodesDefinition!(def, !isnew)\n"),
]
