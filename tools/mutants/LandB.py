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
    dict(id="LB1 i_metacall_common compiles the goal clause from the goal's term export", file=WAM,
         targets=["test/core_lang/test_metacall_control.jl"],
         old="            compileGoalClause(gd, ld, mc_gloc, gd.modules[mc_mi], mc_nb)\n",
         new="            compileGoalClause(\n                gd, ld, _compound_term(ld, valPtr(mc_w)), gd.modules[mc_mi], mc_nb\n            )\n"),
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
    dict(id="LB4 boot ends the load on every directive error", file=BOOT,
         targets=["test/files/test_load_swipl.jl"],
         old="    _is_error_term(ld, ex) || return _init_export(ld, ex)\n",
         new="    return _init_export(ld, ex)\n"),
    # _pattr_error (f3b-3b): its message terms live in a frame of their own, gone before the query closes
    dict(id="LB5 _pattr_error's message terms outlive the open query", file=BOOT,
         targets=["test/files/test_load_swipl.jl"],
         old="    PL_discard_foreign_frame(ld, fid)\n    return nothing\nend\n\n# PORT: init.pl $pi_head as _pi_head\n",
         new="    return nothing\nend\n\n# PORT: init.pl $pi_head as _pi_head\n"),
]
