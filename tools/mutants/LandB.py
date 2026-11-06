# ORIGINAL: landing B's mutant list — no swipl-devel counterpart.
# tools/mutants/LandB.py — the mutation battery of landing B (f3b-3 + f3b-3b; D-0107 item 3: its NEW invariants and
# CHANGED behaviour only; D-0112 item 2: the pl-wam.jl wiring's removal must be caught by the G3 row): the goal clause
# read off the cells (localGoal, compileGoalClause on a location), and boot/init.jl on term references. Run once, in
# CI, alongside the gate's CI + Evidence (D-0105 item 2; .github/workflows/mutation.yml). Format: tools/mutate_drive.py's.
#
# Not a mutant, with the reason: disabling localGoal's CYCLE_CHECK_AT test loops on G3 with unbounded memory (the walk
# is iterative), so it can only end as a TIMEOUT, never a verdict; the wiring mutant (LB1) covers the cyclic goal.
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/core_lang/test_metacall_control.jl",
    "test/files/test_load_swipl.jl",
]
WAM, CMP, BOOT = "src/pl-wam.jl", "src/pl-comp.jl", "boot/init.jl"
MUTANTS = [
    # i_metacall_common (f3b-3): the goal clause compiled from the goal's LOCATION; without the wiring the term
    # method walks the cyclic export without end (G3: the base's stack overflow)
    # LB1 removed with the code it mutated (59a05eed); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # link_local_var (pl-comp.c 2947): a variable's pseudo cell references the variable's own cell
    dict(id="LB2 a goal-clause variable is not linked to its cell", file=CMP,
         targets=["test/core_lang/test_metacall_control.jl"],
         old="            ld.slots[i] = makeRefG(p)                          # *k = makeRefG(vd->address)\n            return nothing\n",
         new=""),
    # compileArgument's argvar (pl-comp.c 3181): an argvar's cell takes its argument's word
    dict(id="LB3 an argvar's cell takes its placeholder, not the argument's word", file=CMP,
         targets=["test/core_lang/test_metacall_control.jl"],
         old="                ld.slots[i] = lw[j].second                     # *k = *arg\n",
         new="                setSlotValue!(ld, i, t)                        # *k = *arg\n"),
    # boot's catch(…, error(_,_), …): an error ball is printed, any other ends the load
    # LB4 removed with the code it mutated (d6faa3f7); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # _pattr_error (f3b-3b): its message terms live in a frame of their own, gone before the query closes
    # LB5 removed with the code it mutated (d6faa3f7); ledger: evidence/MUTREFIT/deleted_mutants.tsv
]
