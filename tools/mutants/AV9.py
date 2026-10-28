# ORIGINAL: AV9's mutant list — no swipl-devel counterpart.
# tools/mutants/AV9.py — the mutation battery of AV9 (deterministic/1: pl-prims.c `deterministic`; call_residue_vars/2's
# C half: pl-attvar.c `trail_new_attvar`, `has_attributes_after`, `scan_trail`, `$attvars_after_choicepoint`,
# `$call_residue_vars_start`, `$call_residue_vars_end`; pl-wam.c `existingChoice`; the boot-level call_residue_vars/2
# and run_crv/4 stand-ins `_boot_call_residue_vars!` in src/pl-ext.jl), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as AV8.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_attvar_wakeup.jl, the `_WK_AV9` rows (or the white-box test of trail_new_attvar) named in each id's `KILL`.
# Hand-run before the commit (D-0104, `tools/mutate.sh run-in-tree`): verdicts in lk-channel evidence/AV9/mutants_verdicts.tsv.
# NOT LISTED:
#   * deterministic/1's `ch.base > fr_base` as `>=`: a choice point and a frame never share a local-stack position.
#   * has_attributes_after's `f > gtop` as `>=`: `gtop` is the last cell in use at the mark, and a functor cell is never
#     a compound's last cell (its arguments follow), so no compound starts AT it.
#   * `$attvars_after_choicepoint`'s `ld.attvar_attvars == 0` early return: without it the loop finds no attributed
#     variable and answers [] as well (one global cell stays allocated until backtracking).
#   * existingChoice's `0 <= off < ld.lTop` test: every record on the chain has `0 <= base < lTop`, so `base == off`
#     already fails for an `off` outside; and its `frames[fr].base` test: a live choice point's frame is live.
TA = ["test/core_lang/test_attvar_wakeup.jl"]
TARGETS = TA                                         # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/pl-prims.jl"
A = "src/pl-attvar.jl"
W = "src/pl-wam.jl"
E = "src/pl-ext.jl"
MUTANTS = [
    # ── pl-prims.c deterministic ──
    dict(id="AV9-D1 deterministic/1 ignores its own clause's CHP_CLAUSE (KILL dt08, dt11)", file=P, targets=TA,
         old="            if ch.type == CHP_CLAUSE && ch.frame == FR      #   if ( BFR->frame == FR )\n",
         new="            if false && ch.type == CHP_CLAUSE && ch.frame == FR      #   if ( BFR->frame == FR )\n"),
    dict(id="AV9-D2 deterministic/1 answers true for a choice point above the frame (KILL dt02, dt04, dt05, dt06)", file=P, targets=TA,
         old="            if ch.base > fr_base                            #   if ( (void *)BFR > (void *)FR )\n",
         new="            if false                            #   if ( (void *)BFR > (void *)FR )\n"),
    dict(id="AV9-D3 deterministic/1 stops at a choice point of any type (catch/3's CHP_CATCH; KILL dt15, dt16)", file=P, targets=TA,
         old="        if ch.type == CHP_CLAUSE || ch.type == CHP_JUMP     # case CHP_CLAUSE: … case CHP_JUMP:\n",
         new="        if true     # case CHP_CLAUSE: … case CHP_JUMP:\n"),
    dict(id="AV9-D4 deterministic/1 takes its own foreign frame for the clause's (no ->parent; KILL dt02)", file=P, targets=TA,
         old="    FR = ld.frames[ld.environment_frame].parent             # LocalFrame FR = environment_frame->parent\n",
         new="    FR = ld.environment_frame             # LocalFrame FR = environment_frame->parent\n"),
    dict(id="AV9-D5 deterministic/1 is not registered (KILL dt01)", file=P, targets=TA,
         old="    PL_extension(\"deterministic\", 1, pl_deterministic1_va, PL_FA_VARARGS),   # (AV9)\n",
         new=""),
    # ── pl-attvar.c trail_new_attvar ──
    dict(id="AV9-T1 trail_new_attvar never trails (the count guard false; KILL cr35: a frozen stack keeps the first answer's attvar)", file=A, targets=TA,
         old="    if ld.attvar_call_residue_vars_count != 0              # if ( LD->attvar.call_residue_vars_count )\n",
         new="    if false              # if ( LD->attvar.call_residue_vars_count )\n"),
    dict(id="AV9-T2 trail_new_attvar always trails (no count guard; KILL the white-box test of the bare entry: no Prolog row sees it)", file=A, targets=TA,
         old="    if ld.attvar_call_residue_vars_count != 0              # if ( LD->attvar.call_residue_vars_count )\n",
         new="    if true              # if ( LD->attvar.call_residue_vars_count )\n"),
    # ── pl-attvar.c has_attributes_after ──
    dict(id="AV9-H1 has_attributes_after misses an att/3 made after the choice point (KILL cr01, cr22, cr23)", file=A, targets=TA,
         old="            f > gtop && return true                         #     created after choice\n",
         new=""),
    dict(id="AV9-H2 has_attributes_after misses a value assigned after the choice point (is_marked; KILL cr05, cr24, cr16)", file=A, targets=TA,
         old="                (ld.gstack[pv] & MARK_MASK) != 0 && return true     # is_marked(pv): modified after choice point\n",
         new=""),
    dict(id="AV9-H3 has_attributes_after misses a value compound made after the choice point (KILL cr29)", file=A, targets=TA,
         old="                isTermW(w) && valPtr(w) > gtop && return true   # argument term after choice point\n",
         new=""),
    dict(id="AV9-H4 has_attributes_after reads only the first att/3 (KILL cr23)", file=A, targets=TA,
         old="                l = pv + 1                                  #       l = pv+1\n",
         new="                return false                                  #       l = pv+1\n"),
    # ── pl-attvar.c scan_trail ──
    dict(id="AV9-S1 the marks are never cleared (KILL cr16; TrailAssignment! asserts MARK clear)", file=A, targets=TA,
         old="    scan_trail(ld, ch, false)                               # scan_trail(ch, false)\n",
         new=""),
    dict(id="AV9-S2 the marks are never set (KILL cr05, cr24)", file=A, targets=TA,
         old="    scan_trail(ld, ch, true)                                # scan_trail(ch, true)\n",
         new=""),
    dict(id="AV9-S3 scan_trail marks the value entry's word, not the assigned cell (KILL cr05)", file=A, targets=TA,
         old="        if isTrailVal(ld.trail[te])                         # if ( isTrailVal(te->address) )\n            te -= 1                                         #   te--\n",
         new="        if isTrailVal(ld.trail[te])                         # if ( isTrailVal(te->address) )\n"),
    # ── pl-attvar.c $attvars_after_choicepoint ──
    dict(id="AV9-C1 a position that is no live choice point is not an existence error (KILL cr17, cr18)", file=A, targets=TA,
         old="    if ch == 0                                              # if ( !existingChoice(ch) )\n",
         new="    if false                                              # if ( !existingChoice(ch) )\n"),
    dict(id="AV9-C2 `$attvars_after_choicepoint` always answers [] (KILL cr01, cr05)", file=A, targets=TA,
         old="    if list == tailp\n",
         new="    if true\n"),
    dict(id="AV9-C3 a bound attributed variable on the chain is not skipped (KILL cr32, cr33, cr34)", file=A, targets=TA,
         old="        if isAttVar(ld.gstack[pav]) && has_attributes_after(ld, pav, ch)\n",
         new="        if has_attributes_after(ld, pav, ch)\n"),
    dict(id="AV9-C4 the list's tail does not advance: only the last variable is kept (KILL cr21)", file=A, targets=TA,
         old="            tailp = q + 2                                   #   tailp = &p[2]\n",
         new=""),
    dict(id="AV9-C5 a non-integer Chp fails instead of raising the type error (KILL cr12)", file=A, targets=TA,
         old="    off = PL_get_intptr_ex(ld, A1)                          # if ( !PL_get_intptr_ex(A1, &off) )\n",
         new="    off = PL_get_intptr(ld, A1)                          # if ( !PL_get_intptr_ex(A1, &off) )\n"),
    dict(id="AV9-C6 `$attvars_after_choicepoint` is not registered (KILL cr01)", file=A, targets=TA,
         old="    PL_extension(\n        \"\\$attvars_after_choicepoint\", 2, pl_dattvars_after_choicepoint2_va, PL_FA_VARARGS\n    ),\n",
         new=""),
    # ── pl-attvar.c $call_residue_vars_start / _end ──
    dict(id="AV9-R1 `$call_residue_vars_start` does not count (KILL cr35, as AV9-T1)", file=A, targets=TA,
         old="    ld.attvar_call_residue_vars_count += 1                  # LD->attvar.call_residue_vars_count++\n",
         new=""),
    dict(id="AV9-R2 `$call_residue_vars_end` does not count down (KILL the white-box test: the count after start/end; no Prolog row sees it)", file=A, targets=TA,
         old="    ld.attvar_call_residue_vars_count -= 1                  # LD->attvar.call_residue_vars_count--\n",
         new=""),
    # ── pl-wam.c existingChoice ──
    dict(id="AV9-X1 existingChoice takes the next older choice point for a position that is none (KILL cr17)", file=W, targets=TA,
         old="    ch2 != 0 && ld.choices[ch2].base == off || return 0     # if ( ch2 == ch )\n",
         new="    ch2 != 0 || return 0     # if ( ch2 == ch )\n"),
    # ── boot-level call_residue_vars/2 and run_crv/4 (_boot_call_residue_vars!) ──
    dict(id="AV9-B1 call_residue_vars/2 never cuts its second clause (KILL dt13)", file=E, targets=TA,
         old="                                mk_sym(T, :!)\n",
         new="                                mk_sym(T, Symbol(\"true\"))\n"),
    dict(id="AV9-B2 call_residue_vars/2 cuts after a nondeterministic goal (KILL cr06, cr07, dt14)", file=E, targets=TA,
         old="                                _boot_term(Symbol(\"==\"), T[Det, mk_sym(T, Symbol(\"true\"))]),\n",
         new="                                _boot_term(Symbol(\"==\"), T[Det, mk_sym(T, Symbol(\"false\"))]),\n"),
    dict(id="AV9-B3 run_crv/4 does not call deterministic/1 (Det unbound: no cut; KILL dt13)", file=E, targets=TA,
         old="                _boot_term(:deterministic, T[Det]),\n",
         new=""),
    dict(id="AV9-B4 call_residue_vars/2 is not defined (KILL cr01)", file=E, targets=TA,
         old="    _boot_call_residue_vars!(gd, ld)\n    return nothing\nend\n",
         new="    return nothing\nend\n"),
]
