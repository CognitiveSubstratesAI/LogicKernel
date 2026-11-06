# ORIGINAL: AV7's mutant list — no swipl-devel counterpart.
# tools/mutants/AV7.py — the mutation battery of AV7 (freeze/2: pl-attvar.c `$freeze` as pl_dfreeze2_va, boot/attvar.pl's
# uhook(freeze, …), unfreeze/1 and freeze/2 as `_boot_freeze_uhook!` / `_boot_freeze!` in src/pl-ext.jl), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as AV6.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Killed by test/core_lang/test_attvar_wakeup.jl, the `_WK_AV7` rows named in each id's `KILL`. Hand-run before the commit
# (D-0104, `tools/mutate.sh run-in-tree`): every mutant caught (verdicts: lk-channel evidence/AV7/mutants_verdicts.tsv);
# AV7-U2 survived fz04/fz15 (the fixture's user:attr_unify_hook/2 is visible from module `freeze`, so the general clause
# fails too — swipl 10.1.19 with the cut removed answers the same) and is killed by fz18.
# NOT LISTED:
#   * The two TrailAssignment! calls of pl_dfreeze2_va: no row backtracks over a second freeze of one variable.
#   * freeze/2's cut (first clause): no row backtracks into freeze/2 after `$freeze` succeeded.
TA = ["test/core_lang/test_attvar_wakeup.jl"]
TARGETS = TA                                         # the baseline's targets (mutate_ci.py plan reads TARGETS)
A = "src/pl-attvar.jl"
E = "src/pl-ext.jl"
MUTANTS = [
    # ── pl-attvar.c `$freeze` (pl_dfreeze2_va) ──
    dict(id="AV7-F1 $freeze takes only a plain variable (isAttVar dropped; KILL fz05, fz05g, hk22)", file=A, targets=TA,
         old="    if k == DU_CELL || k == DU_ATTVAR                       # if ( isVar(*v) || isAttVar(*v) )\n",
         new="    if k == DU_CELL                                         # if ( isVar(*v) || isAttVar(*v) )\n"),
    dict(id="AV7-F2 $freeze never finds the freeze attribute (the `$and` branch skipped; KILL fz05, fz05g)", file=A, targets=TA,
         old="            if found                                        #     if ( find_attr(v, ATOM_freeze, &vp) )\n",
         new="            if false                                        #     if ( find_attr(v, ATOM_freeze, &vp) )\n"),
    dict(id="AV7-F3 $freeze's `$and` puts the new goal first (KILL fz05, fz05g)", file=A, targets=TA,
         old="                ld.gstack[gc + 2] = gw                      #       gc[2] = *goal\n",
         new="                ld.gstack[gc + 2] = ld.gstack[gc + 1]\n                ld.gstack[gc + 1] = gw                      #       gc[2] = *goal\n"),
    dict(id="AV7-F4 $freeze does not append to another module's attributes (vp branch skipped; KILL hk22)", file=A, targets=TA,
         old="            elseif vp != 0                                  #     else if ( vp ): vp points to []\n",
         new="            elseif false                                    #     else if ( vp ): vp points to []\n"),
    dict(id="AV7-F5 $freeze appends `[]` as the goal (vp branch; KILL hk22)", file=A, targets=TA,
         old="                ld.gstack[at + 2] = gw                      #       at[2] = *goal\n",
         new="                ld.gstack[at + 2] = ld.atom_nil_w           #       at[2] = *goal\n"),
    dict(id="AV7-F6 $freeze links an unbound goal instead of storing a fresh variable (word 0; KILL fz16, fz17)", file=A, targets=TA,
         old="        gw = goal[1] == DU_CELL ? word(0) : _link_val_loc!(ld, goal)   # *goal\n",
         new="        gw = _link_val_loc!(ld, goal)                                 # *goal\n"),
    dict(id="AV7-F7 $freeze is not registered (KILL fz01)", file=A, targets=TA,
         old="    PL_extension(\"\\$freeze\", 2, pl_dfreeze2_va, PL_FA_VARARGS),\n",
         new=""),
    # ── boot/attvar.pl uhook(freeze, …), unfreeze/1 (_boot_freeze_uhook!) ──
    # AV7-U1 removed with the code it mutated (08660b2a); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # AV7-U2 removed with the code it mutated (08660b2a); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # AV7-U3 removed with the code it mutated (08660b2a); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # AV7-U4 removed with the code it mutated (08660b2a); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # AV7-U5 removed with the code it mutated (08660b2a); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # ── boot/attvar.pl freeze/2 (_boot_freeze!): the Q4 (a) qualification ──
    # AV7-Q1 removed with the code it mutated (08660b2a); ledger: evidence/MUTREFIT/deleted_mutants.tsv
]
