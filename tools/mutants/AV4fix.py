# ORIGINAL: the FIXED step's mutant list (found by AV4's run) — no swipl-devel counterpart.
# tools/mutants/AV4fix.py — the mutation battery of the FIXED step "attributed variables as sub-goal arguments of
# control constructs" (pl-comp.c localGoal: an attvar argument is an argvar, :1116-1119, whose cell is a reference
# to it, :3178-3179; in goal position it is not callable, :901, :3557-3558), run ONCE, in CI. The format is
# tools/mutate_drive.py's. Killed by test/core_lang/test_attvar_wakeup.jl (rows lg01-lg07).
TARGETS = ["test/core_lang/test_attvar_wakeup.jl"]
T = TARGETS
C = "src/pl-comp.jl"
MUTANTS = [
    dict(id="AV4fix-M1 _local_subgoal has no attributed-variable branch (a compound argvar read from it)", file=C, targets=T,
         old="        elseif k == DU_ATTVAR                       # an attributed variable: an argvar (c:1116)\n",
         new="        elseif false\n"),
    dict(id="AV4fix-M2 the attvar argument's cell takes the copied word, not a reference to it", file=C, targets=T,
         old="            push!(lw, a => makeRefG(p))             # *k = makeRefG(arg) (c:3178-3179)\n",
         new="            push!(lw, a => w)\n"),
    dict(id="AV4fix-M3 localGoal has no attributed-variable branch at goal position", file=C, targets=T,
         old="        elseif k == DU_ATTVAR               # an attributed variable: not a variable under islocal\n",
         new="        elseif false\n"),
]
