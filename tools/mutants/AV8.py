# ORIGINAL: AV8's mutant list — no swipl-devel counterpart.
# tools/mutants/AV8.py — the mutation battery of AV8 (when/2's C half: pl-attvar.c `$eval_when_condition` — is_or, add_or,
# make_disj_list, when_condition, pl_deval_when_condition2_va — and `$suspend`, plus the boot-level when/2 and trigger_first/2
# stand-ins `_boot_when!` in src/pl-ext.jl), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as AV7.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_attvar_wakeup.jl, the `_WK_AV8` rows named in each id's `KILL`.
# Hand-run before the commit (D-0104, `tools/mutate.sh run-in-tree`): verdicts in lk-channel evidence/AV8/mutants_verdicts.tsv.
# NOT LISTED:
#   * `c1 == true_w` in the `,` case: no row has a true first conjunct beside a pending second one.
#   * add_or's `is_or(c2)` branch: no row joins two `or/1` conditions.
#   * The TrailAssignment! of `$suspend` is listed (su07); the `ensureGlobalSpace` guard cannot fail (the stack grows).
#   * E_NOSPACE: never returned (see the DIVERGES at the constants).
TA = ["test/core_lang/test_attvar_wakeup.jl"]
TARGETS = TA                                         # the baseline's targets (mutate_ci.py plan reads TARGETS)
A = "src/pl-attvar.jl"
E = "src/pl-ext.jl"
MUTANTS = [
    # ── pl-attvar.c when_condition ──
    dict(id="AV8-W1 when_condition never checks a deep condition for cycles (KILL we14)", file=A, targets=TA,
         old="        is_acyclic_cells(ld, cond) || return (E_CYCLIC, word(0))\n",
         new="        nothing\n"),
    dict(id="AV8-W2 nonvar(X) is kept when X is bound and dropped when it is not (KILL we01, we02)", file=A, targets=TA,
         old="(k1 == DU_CELL || k1 == DU_ATTVAR) ? w : true_w)   # canBind(*a1)\n",
         new="(k1 == DU_CELL || k1 == DU_ATTVAR) ? true_w : w)   # canBind(*a1)\n"),
    dict(id="AV8-W3 ground(T) is kept when T is ground and dropped when it is not (KILL we03, we17)", file=A, targets=TA,
         old="ground_cells(ld, a) == 0 ? true_w : w)\n",
         new="ground_cells(ld, a) == 0 ? w : true_w)\n"),
    dict(id="AV8-W4 `,` keeps a true second conjunct (KILL we09)", file=A, targets=TA,
         old="            c2 == true_w && return (E_OK, c1)\n",
         new=""),
    dict(id="AV8-W5 `;` does not short-circuit on a true first disjunct (KILL we07)", file=A, targets=TA,
         old="            c1 == true_w && return (E_OK, c1)\n",
         new=""),
    dict(id="AV8-W6 `;` does not short-circuit on a true second disjunct (KILL we08)", file=A, targets=TA,
         old="            c2 == true_w && return (E_OK, c2)\n",
         new=""),
    dict(id="AV8-W7 a condition that is a variable is a domain error (the isVar test removed; KILL we16)", file=A, targets=TA,
         old="    k == DU_CELL && return (E_INSTANTIATION_ERROR, word(0)) # if ( isVar(*cond) )\n",
         new=""),
    dict(id="AV8-W8 an attributed variable counts as isVar: a nested one raises instantiation_error (KILL we21; as the condition itself, PL_error's canBind conversion hides it: we13)", file=A, targets=TA,
         old="    k == DU_CELL && return (E_INSTANTIATION_ERROR, word(0)) # if ( isVar(*cond) )\n",
         new="    (k == DU_CELL || k == DU_ATTVAR) && return (E_INSTANTIATION_ERROR, word(0)) # if ( isVar(*cond) )\n"),
    # ── pl-attvar.c make_disj_list ──
    dict(id="AV8-D1 make_disj_list does not extend c1's or/1 ((x;y);z) nests (KILL we05, we18)", file=A, targets=TA,
         old="    if is_or(ld, c1)\n        return (add_or(ld, c1, c2), c1)",
         new="    if false\n        return (add_or(ld, c1, c2), c1)"),
    dict(id="AV8-D2 make_disj_list does not extend c2's or/1 (x;(y;z)) nests (KILL we06)", file=A, targets=TA,
         old="    elseif is_or(ld, c2)\n        return (add_or(ld, c2, c1), c2)",
         new="    elseif false\n        return (add_or(ld, c2, c1), c2)"),
    # ── pl-attvar.c pl_deval_when_condition2_va ──
    dict(id="AV8-E1 the domain error names the unbound second argument, not the condition (KILL we11, we12, we15)", file=A, targets=TA,
         old="PL_error(ld, ERR_DOMAIN, mk_sym(T, :when_condition), A1)",
         new="PL_error(ld, ERR_DOMAIN, mk_sym(T, :when_condition), A2)"),
    dict(id="AV8-E2 a cyclic condition raises no error (the type_error branch answers false; KILL we14)", file=A, targets=TA,
         old="            return PL_error(ld, ERR_TYPE, mk_sym(T, :acyclic_term), A1) ? FTRUE : FFALSE\n",
         new="            return FFALSE\n"),
    dict(id="AV8-E3 `$eval_when_condition` is not registered (KILL we01)", file=A, targets=TA,
         old="    PL_extension(\"\\$eval_when_condition\", 2, pl_deval_when_condition2_va, PL_FA_VARARGS),\n",
         new=""),
    # ── pl-attvar.c pl_dsuspend3_va ──
    dict(id="AV8-S1 `$suspend` never qualifies the goal (KILL su01, su02)", file=A, targets=TA,
         old="    if !(\n        g[1] == DU_WORD && _is_gcompound(g[2]) &&\n",
         new="    if false && !(\n        g[1] == DU_WORD && _is_gcompound(g[2]) &&\n"),
    dict(id="AV8-S2 `$suspend` qualifies an already qualified goal again (KILL su03)", file=A, targets=TA,
         old="    if !(\n        g[1] == DU_WORD && _is_gcompound(g[2]) &&\n",
         new="    if true || !(\n        g[1] == DU_WORD && _is_gcompound(g[2]) &&\n"),
    dict(id="AV8-S3 `$suspend` finds an existing call/1 value but does not conjoin (answers false; KILL su02)", file=A, targets=TA,
         old="            if k0 == DU_WORD && _is_gcompound(w0) &&\n",
         new="            if false && k0 == DU_WORD && _is_gcompound(w0) &&\n"),
    dict(id="AV8-S4 `$suspend` on a non-call/1 value succeeds (KILL su04)", file=A, targets=TA,
         old="            end\n            return FFALSE\n        elseif vp != 0",
         new="            end\n            return FTRUE\n        elseif vp != 0"),
    dict(id="AV8-S5 `$suspend` does not add its attribute to a variable that has others (KILL su03, su08)", file=A, targets=TA,
         old="        elseif vp != 0\n            put_att_value(ld, vp, name, (DU_WORD, _suspend_call_word!(ld, g), 0))\n",
         new="        elseif false\n            put_att_value(ld, vp, name, (DU_WORD, _suspend_call_word!(ld, g), 0))\n"),
    dict(id="AV8-S6 `$suspend`'s conjunction assignment is not trailed (KILL su07)", file=A, targets=TA,
         old="                TrailAssignment!(ld, ap)                    # TrailAssignment(ap): $suspend\n",
         new=""),
    dict(id="AV8-S7 `$suspend` on a nonvariable fails instead of raising the uninstantiation error (KILL su05)", file=A, targets=TA,
         old="    return PL_error(ld, \"\\$suspend\", 3, \"\", ERR_UNINSTANTIATION, 1, A1) ? FTRUE : FFALSE\n",
         new="    return FFALSE\n"),
    dict(id="AV8-S8 `$suspend` is not registered (KILL su01)", file=A, targets=TA,
         old="    PL_extension(\"\\$suspend\", 3, pl_dsuspend3_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),\n",
         new=""),
    # ── boot-level when/2 and trigger_first/2 (_boot_when!) ──
    dict(id="AV8-B1 trigger_first(true, Goal) does not call the goal (KILL wh07)", file=E, targets=TA,
         old="_boot_conj(T[mk_sym(T, :!), _boot_term(:call, T[Goal])]), UInt64(0)",
         new="_boot_conj(T[mk_sym(T, :!), mk_sym(T, Symbol(\"true\"))]), UInt64(0)"),
    dict(id="AV8-B2 when/2 is not defined (KILL wh07)", file=E, targets=TA,
         old="    _boot_when!(gd, ld)\n    return nothing\nend\n",
         new="    return nothing\nend\n"),
]
