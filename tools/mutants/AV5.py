# ORIGINAL: AV5's mutant list — no swipl-devel counterpart.
# tools/mutants/AV5.py — the mutation battery of AV5 (attributed variables in pl-prims.c do_number_vars' `on_attvar`
# (numbervars/4's `attvar` option), pl-write.c writeAttVar / writeAttributes / varName / writeNumberVar, and pl-list.c
# put_sort_list's reference to an attvar item), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's.
# Killed by test/core_lang/test_attvar_wakeup.jl (the `_WK_AV5` rows: nv01-nv03, nv05, hk20, so01-so04, av19) for N*, V* and S1,
# and by test/core_lang/test_write_cells.jl (the "attributed variable written" testset: at01-at12) for W*.
# W4 is declared `equivalent` (reason in its dict; pending audit).
# NOT LISTED (equivalent, with the code reason):
#   * pl-variant.c's `isomorphic` attvar branch (D-0162 item 2; src/pl-variant.jl `isomorphic_cells`, the TAG_ATTVAR
#     case): EQUIVALENT in practice. `variant`'s `var_id` (pl-variant.c:143-158) overwrites EVERY visited var/attvar cell
#     with `consVar(n)` (TAG_VAR), and the agenda is depth-first, so by the time `isomorphic` compares two right-hand
#     compounds an attvar of the first side has already been visited (TAG_VAR) while the other side's is still TAG_ATTVAR:
#     `tag(wl) != tag(wr)` answers false BEFORE the TAG_ATTVAR branch is reached. AV5's session 2 probed every shape it
#     could think of (equal / different / no attributes, a cyclic shape: evidence/av/av5_report.md §2b) — all
#     `not_variant` in swipl 10.1.19 and in the kernel, none reaches the branch. The audit's call (D-0162): record it.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string
# that does not occur exactly once).
TN = ["test/core_lang/test_attvar_wakeup.jl"]
TW = ["test/core_lang/test_write_cells.jl"]
TARGETS = TN
P = "src/pl-prims.jl"
W = "src/pl-write.jl"
L = "src/pl-list.jl"
MUTANTS = [
    # ── numbervars/4's `attvar` option (pl-prims.c do_number_vars) ──
    dict(id="AV5-N1 do_number_vars does not admit an attributed variable (it is walked as a nonvariable)", file=P, targets=TN,
         old="        if k == DU_CELL || k == DU_ATTVAR                   # canBind(*p)\n",
         new="        if k == DU_CELL                                     # canBind(*p)\n"),
    dict(id="AV5-N2 attvar(skip) numbers the attributed variable too (no `continue`)", file=P, targets=TN,
         old="                if options.on_attvar == AV_SKIP             #   case AV_SKIP: continue\n                    continue\n",
         new="                if options.on_attvar == AV_SKIP             #   case AV_SKIP: continue\n                    nothing\n"),
    dict(id="AV5-N3 attvar(error) does not stop (no `break` with CONTAINS_ATTVAR)", file=P, targets=TN,
         old="                    n = CONTAINS_ATTVAR                     #     n = CONTAINS_ATTVAR; goto out\n                    break\n",
         new="                    n = CONTAINS_ATTVAR                     #     n = CONTAINS_ATTVAR; goto out\n"),
    dict(id="AV5-N4 numbervars binds an attributed variable with _bind_const! (no wakeup; hk20)", file=P, targets=TN,
         old="            bindConst(ld, p, consPtr(c, TAG_COMPOUND | STG_GLOBAL))   # bindConst(p, v): an attvar wakes (AV5)\n",
         new="            _bind_const!(ld, p, consPtr(c, TAG_COMPOUND | STG_GLOBAL))   # bindConst(p, v): an attvar wakes (AV5)\n"),
    # ── the writer (pl-write.c) ──
    dict(id="AV5-W1 writePrimitive does not look for an attributed variable (written as a plain variable)", file=W, targets=TW,
         old="    PL_is_attvar(ld, t) && return writeAttVar(t, options)  # if ( PL_is_attvar(t) ) (AV5)\n",
         new=""),
    dict(id="AV5-W2 varName does not name an attributed variable (the error)", file=W, targets=TW,
         old="    k == DU_ATTVAR && return \"_\" * string((p - 1) * 2)      # an attvar cell: deRef stops on it (AV5)\n",
         new=""),
    dict(id="AV5-W3 writeAttributes writes no comma between attributes (a:1b:2)", file=W, targets=TW,
         old="        (!first && !PutComma(options)) && return false\n",
         new=""),
    dict(id="AV5-W4 writeNumberVar treats '$VAR'(Attvar) as a number (no refusal; at09)", file=W, targets=TW,
         old="    k == DU_ATTVAR && return 0                      # '$VAR'(Attvar): not an integer or atom (AV5)\n",
         new="",
         equivalent="src/pl-write.jl:1128-1130 — hand-run 2026-10-27: SURVIVES test_write_cells.jl at01-at12 (at09 included). Without the line the attvar word is read by _atom_value as an atom index; the index (a global-stack offset) names no variable-name atom, so isTextAtom/atomIsVarName fall through to `return 0`, the same answer. The guard is memory-safety (upstream: PL_get_atom/PL_get_integer fail on an attvar), not observable by a swipl differential. PENDING AUDIT."),
    # ── put_sort_list (pl-list.c; carried by name since D-0141/D-0150 item 5) ──
    dict(id="AV5-S1 put_sort_list copies an attributed variable's word into the list (no reference; so04)", file=L, targets=TN,
         old="        ld.gstack[b + 1] = needsRef(c) ? makeRefG(ip) : c   # needsRef(*item) ? makeRefG(item) : *item (AV1)\n",
         new="        ld.gstack[b + 1] = c                                # needsRef(*item) ? makeRefG(item) : *item (AV1)\n"),
    # ── term_variables/2,3 (pl-prims.c term_variables_loop `canBind`; row av19) ──
    dict(id="AV5-V1 term_variables_loop does not admit an attributed variable (f(X,X) with X an attvar gives 0 variables; av19)", file=P, targets=TN,
         old="            if k == DU_CELL || k == DU_ATTVAR               # canBind(w): a variable or an attvar (AV5)\n",
         new="            if k == DU_CELL                                 # canBind(w): a variable or an attvar (AV5)\n"),
    dict(id="AV5-V2 visitedWord_cells does not mark an attributed variable (it is counted once per occurrence; av19)", file=P, targets=TN,
         old="    if isVar(w) || isAttVar(w)                              # an attvar cell too (AV5): canBind\n",
         new="    if isVar(w)                                             # an attvar cell too (AV5): canBind\n"),
    dict(id="AV5-V3 unvisit_cells does not clear an attributed variable's visit mark (a second term_variables sees it visited; av19)", file=P, targets=TN,
         old="        if isVar(w) || isAttVar(w)\n",
         new="        if isVar(w)\n"),
]
