# ORIGINAL: AV6's mutant list — no swipl-devel counterpart.
# tools/mutants/AV6.py — the mutation battery of AV6 (attributed variables in pl-copyterm.c COPY_ATTRS / alloc_attvar /
# unshare_attvar / must_copy_attvar and the non-ATTRS shared-attvar path, pl-rec.c PL_TYPE_ATTVAR / PL_REC_ALLOCVAR,
# pl-prims.c term_attvars/2 + $term_attvar_variables/2 (TV_ATTVAR, TV_ATTS) and free_variables' canBind), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as AV5.py).
# Killed by test/core_lang/test_attvar_wakeup.jl, the `_WK_AV6_ROWS` rows named in each id's `KILL`. NOTHING WAS RUN when this was
# written (no daemon slot): every KILL is the author's trace through the code, to be CONFIRMED by the hand run (D-0059 item 4).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string
# that does not occur exactly once). AV5's V1 `old` (term_variables_loop `canBind(w)`) is indented 8 spaces; AV6's body puts it in
# an inner `while true` (12 spaces): on the rebase onto AV5 re-pin AV5-V1's `old` to the 12-space line.
# NOT LISTED:
#   * EQUIVALENT (below, E1): alloc_attvar's `gp[2] = ATOM_nil` store.
#   * NO ROW, no mutant: `register_attvar` in alloc_attvar (src/pl-attvar.jl) and in copy_record's PL_TYPE_ATTVAR case
#     (src/pl-rec.jl): the chain is read only by backtracking's reclaim_attvars; a copy that is undone with the chain unlinked is
#     not observable from a goal. TODO-VERIFY (run agent): one `(copy_term(X,C), fail ; …)` row, or record it for the audit.
#   * The non-ATTRS branch of mark_for_duplicate_cells (`k == DU_ATTVAR` after the while): duplicate_term/2 and the ball copy
#     both pass COPY_ATTRS, so flags = 0 without COPY_SHARE is never used: dead in the kernel, as in upstream (duplicate_term
#     always has COPY_ATTRS). No mutant.
#   * `info.size += 3` / `b.gstore += 3` (pl-rec.jl): sizing mutants, no row separates them reliably. Left to the audit.
TA = ["test/core_lang/test_attvar_wakeup.jl"]
TARGETS = TA                                         # the baseline's targets (mutate_ci.py plan reads TARGETS)
C = "src/pl-copyterm.jl"
R = "src/pl-rec.jl"
P = "src/pl-prims.jl"
F = "src/pl-fli.jl"
A = "src/pl-attvar.jl"
MUTANTS = [
    # ── pl-copyterm.c: can_share / must_copy_attvar / unshare_attvar ──
    dict(id="AV6-C1 can_share shares an attributed variable's compound as ground (KILL ct05f)", file=C, targets=TA,
         old="    (isVar(c) || isAttVar(c)) && return false               # TAG_VAR, TAG_ATTVAR: no COPY_MARKED\n",
         new="    isVar(c) && return false                                # TAG_VAR, TAG_ATTVAR: no COPY_MARKED\n"),
    dict(id="AV6-C2 must_copy_attvar never walks the attributes (KILL ct05v: a variable in an attribute and outside it)", file=C, targets=TA,
         old="@inline must_copy_attvar(flags::Int)::Bool = (flags & COPY_ATTRS) != 0\n",
         new="@inline must_copy_attvar(flags::Int)::Bool = false\n"),
    dict(id="AV6-C3 mark_for_copy's pop does not unshare_attvar (the attribute cells are shared ground; KILL ct05u)", file=C, targets=TA,
         old="                unshare_attvar_cells(ld, valPtr(pw & ~BOTH_MASK))\n",
         new="                nothing\n"),
    dict(id="AV6-C4 unshare_attvar_cells leaves the att/3 cell unmarked (KILL ct05u)", file=C, targets=TA,
         old="            ld.gstack[q] = fd | MARK_MASK                   # t->definition = fd | MARK_MASK\n",
         new="            ld.gstack[q] = fd                               # t->definition = fd | MARK_MASK\n"),
    dict(id="AV6-C5 mark_for_copy (no COPY_ATTRS) never makes a second occurrence of an attvar shared (KILL ct06s)", file=C, targets=TA,
         old="                ld.gstack[p] = c | BOTH_MASK\n",
         new="                ld.gstack[p] = c\n"),
    # ── mark_for_duplicate / cp_unmark: the attribute walk (`goto again`) ──
    dict(id="AV6-D1 mark_for_duplicate does not walk an attvar's attributes (KILL dt02)", file=C, targets=TA,
         old="        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)\n        while k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:\n",
         new="        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)\n        while false && k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:\n"),
    dict(id="AV6-D2 cp_unmark does not walk an attvar's attributes (their marks stay; KILL ct05o / ct05u, EXPECTED, confirm by the run)", file=C, targets=TA,
         old="        k, w, p = _deref_loc(ld, q)\n        while k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:\n",
         new="        k, w, p = _deref_loc(ld, q)\n        while false && k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:\n"),
    dict(id="AV6-D3 cp_unmark leaves the copy marks in an attvar's word (no COPY_ATTRS; KILL ct06d)", file=C, targets=TA,
         old="            ld.gstack[p] = w & ~BOTH_MASK\n",
         new="            nothing\n"),
    # ── exitCyclicCopy: the two-entry form ──
    dict(id="AV6-X1 exitCyclicCopy does not tell the attvar entry apart (isRef; KILL ct05o)", file=C, targets=TA,
         old="        if !isRef(c)                                        # an attributed variable\n",
         new="        if false                                            # an attributed variable\n"),
    dict(id="AV6-X2 exitCyclicCopy does not put the original attvar word back (KILL ct05o, ct05u)", file=C, targets=TA,
         old="            ld.gstack[p] = consPtr(old, STG_GLOBAL | TAG_ATTVAR)\n",
         new="            nothing\n"),
    dict(id="AV6-X3 exitCyclicCopy leaves VAR_MARK on the non-ATTRS copy's variable (KILL ct06x)", file=C, targets=TA,
         old="                _cp_vm!(ld, p2, _cp_vm(ld, p2) & ~_CPV_VARMARK)                       # setVar(*p2)\n",
         new="                nothing                                                                # setVar(*p2)\n"),
    # ── copy_term_cells: the TAG_ATTVAR branch ──
    dict(id="AV6-T1 copy_term never finds an attvar already copied (a second occurrence gets its own copy; KILL ct05s)", file=C, targets=TA,
         old="                    if isAttVar(ld.gstack[p])               # already copied\n",
         new="                    if false                                # already copied\n"),
    dict(id="AV6-T2 copy_term does not forward the original attvar word (KILL ct05s)", file=C, targets=TA,
         old="                    ld.gstack[f] = consPtr(attr, STG_GLOBAL | TAG_ATTVAR)\n",
         new="                    nothing\n"),
    dict(id="AV6-T3 copy_term writes the attribute list into the wrong cell (t = attr; KILL ct05)", file=C, targets=TA,
         old="                    t = attr + 1\n",
         new="                    t = attr\n"),
    dict(id="AV6-T4 copy_term does not TrailCyclic(from) (the original word is not restored; KILL ct05o)", file=C, targets=TA,
         old="                    push!(ld.cp_lstack, f)                  # TrailCyclic(from)\n                    ld.gstack[f] = consPtr(attr, STG_GLOBAL | TAG_ATTVAR)\n",
         new="                    ld.gstack[f] = consPtr(attr, STG_GLOBAL | TAG_ATTVAR)\n"),
    dict(id="AV6-T5 copy_term_nat: the shared attvar branch never recognises the copy (VAR_MARK; KILL ct06s)", file=C, targets=TA,
         old="                    if isVar(ld.gstack[p]) && (_cp_vm(ld, p) & _CPV_VARMARK) != 0   # *p == VAR_MARK\n",
         new="                    if false                                # *p == VAR_MARK\n"),
    dict(id="AV6-T6 copy_term_nat: a shared attvar is not taken as shared (KILL ct06s)", file=C, targets=TA,
         old="                elseif (c & BOTH_MASK) == BOTH_MASK         # shared(*from)\n",
         new="                elseif false                                # shared(*from)\n"),
    dict(id="AV6-T7 do_copy_term takes a top-level attvar as an atomic (KILL ct05, ct06, bg06u)", file=C, targets=TA,
         old="    if !(k == DU_ATTVAR || (k == DU_WORD && _is_gcompound(w)))  # TAG_ATTVAR, TAG_COMPOUND: break\n",
         new="    if !(k == DU_WORD && _is_gcompound(w))                  # TAG_ATTVAR, TAG_COMPOUND: break\n"),
    # ── the flags of the built-ins ──
    dict(id="AV6-F1 copy_term/2 without COPY_ATTRS (KILL ct05)", file=C, targets=TA,
         old="copy_term_refs(ld, A1, copy, cp_options(COPY_SHARE | COPY_ATTRS)) || return FFALSE\n",
         new="copy_term_refs(ld, A1, copy, cp_options(COPY_SHARE)) || return FFALSE\n"),
    dict(id="AV6-F2 copy_term_nat/2 with COPY_ATTRS (KILL ct06)", file=C, targets=TA,
         old="copy_term_refs(ld, A1, copy, cp_options(COPY_SHARE)) || return FFALSE\n",
         new="copy_term_refs(ld, A1, copy, cp_options(COPY_SHARE | COPY_ATTRS)) || return FFALSE\n"),
    dict(id="AV6-F3 duplicate_term/2 without COPY_ATTRS (KILL dt02)", file=C, targets=TA,
         old="copy_term_refs(ld, A1, copy, cp_options(COPY_ATTRS)) || return FFALSE\n",
         new="copy_term_refs(ld, A1, copy, cp_options(0)) || return FFALSE\n"),
    dict(id="AV6-F4 the ball is copied without COPY_ATTRS (KILL ex02)", file=F, targets=TA,
         old="    rc = do_copy_term_cells(ld, -(ex + 1), dest, cp_options(COPY_ATTRS))\n",
         new="    rc = do_copy_term_cells(ld, -(ex + 1), dest, cp_options(0))\n"),
    # ── alloc_attvar (pl-attvar.c) ──
    dict(id="AV6-A1 alloc_attvar's attvar word points at its own cell, not at the attribute cell (KILL ct05)", file=A, targets=TA,
         old="    ld.gstack[gp + 1] = consPtr(gp + 2, TAG_ATTVAR | STG_GLOBAL)    # gp[1] = consPtr(&gp[2], …)\n",
         new="    ld.gstack[gp + 1] = consPtr(gp + 1, TAG_ATTVAR | STG_GLOBAL)    # gp[1] = consPtr(&gp[2], …)\n"),
    dict(id="AV6-E1 alloc_attvar does not set its attribute cell to []", file=A, targets=TA,
         old="    ld.gstack[gp + 2] = ld.atom_nil_w                       # gp[2] = ATOM_nil\n",
         new="",
         equivalent="src/pl-attvar.jl:319 — read, not run: the only caller (src/pl-copyterm.jl:361, copy_term_cells) continues with `t = attr + 1` = gp + 2 and every branch of the `again` loop assigns ld.gstack[t] before the agenda moves on, so the cell is overwritten before anything reads it; nothing GCs between (allocGlobalNoShift never shifts or collects). Upstream sets it for the collector. PENDING AUDIT (hand run to confirm it SURVIVES)."),
    # ── records (pl-rec.c) ──
    dict(id="AV6-R1 compile_term_to_heap does not enter the TAG_ATTVAR loop (KILL bg01, bg02a)", file=R, targets=TA,
         old="        while isAttVar(w)                                   # TAG_ATTVAR (a global cell: p > 0)\n",
         new="        while false && isAttVar(w)                          # TAG_ATTVAR (a global cell: p > 0)\n"),
    dict(id="AV6-R2 a root attvar gets no PL_REC_ALLOCVAR (KILL bg01c)", file=R, targets=TA,
         old="            if isempty(info.code)                           # isEmptyBuffer(&info->code)\n",
         new="            if false                                        # isEmptyBuffer(&info->code)\n"),
    dict(id="AV6-R3 the attvar's saved word is not kept for restoreVars (KILL bg01o)", file=R, targets=TA,
         old="            push!(info.vars, reinterpret(Int, w))           # addBuffer(&info->vars, *p, word): save value\n",
         new=""),
    dict(id="AV6-R4 restoreVars does not restore an attvar's word (KILL bg01o)", file=R, targets=TA,
         old="        if p < 0                                            # if ( isAttVarP(*p) )\n",
         new="        if false                                            # if ( isAttVarP(*p) )\n"),
    dict(id="AV6-R5 copy_record forgets the attvar in vars[n] (a second occurrence is not shared; KILL bg02a)", file=R, targets=TA,
         old="            b.vars[n] = p                                   # b->vars[n] = p\n",
         new=""),
    dict(id="AV6-R6 copy_record's attribute list starts at the attvar cell (KILL bg01)", file=R, targets=TA,
         old="            p = g + 2                                       # p = &b->gstore[2]\n",
         new="            p = g + 1                                       # p = &b->gstore[2]\n"),
    # ── term_attvars/2, $term_attvar_variables/2 (pl-prims.c) ──
    dict(id="AV6-V1 TV_ATTVAR lists the plain variables too (KILL ta01, ta04)", file=P, targets=TA,
         old="                ((flags & TV_ATTVAR) != 0 && k != DU_ATTVAR) && break   # attributed vars only\n",
         new=""),
    dict(id="AV6-V2 TV_ATTS does not go into the attributes (`goto again`; KILL ta03, tv01)", file=P, targets=TA,
         old="                if (flags & TV_ATTS) != 0 && k == DU_ATTVAR\n",
         new="                if false && (flags & TV_ATTS) != 0 && k == DU_ATTVAR\n"),
    dict(id="AV6-V3 term_attvars/2 without TV_ATTS (KILL ta03)", file=P, targets=TA,
         old="    return term_variables(ld, A1, A2, 0, TV_ATTVAR | TV_ATTS) ? FTRUE : FFALSE\n",
         new="    return term_variables(ld, A1, A2, 0, TV_ATTVAR) ? FTRUE : FFALSE\n"),
    dict(id="AV6-V4 $term_attvar_variables/2 without TV_ATTS (KILL tv01)", file=P, targets=TA,
         old="    return term_variables(ld, A1, A2, 0, TV_ATTS) ? FTRUE : FFALSE\n",
         new="    return term_variables(ld, A1, A2, 0, 0) ? FTRUE : FFALSE\n"),
    dict(id="AV6-V5 term_attvars/2 is not registered (KILL ta01)", file=P, targets=TA,
         old="    PL_extension(\"term_attvars\", 2, pl_term_attvars2_va, PL_FA_VARARGS),\n",
         new=""),
    dict(id="AV6-V6 $term_attvar_variables/2 is not registered (KILL tv01)", file=P, targets=TA,
         old="    PL_extension(\"\\$term_attvar_variables\", 2, pl_term_attvar_variables2_va, PL_FA_VARARGS),   # (AV6)\n",
         new=""),
    # ── free_variables (bagof/^): canBind ──
    dict(id="AV6-B1 free_variables_loop does not admit an attributed variable (canBind; KILL cb01)", file=P, targets=TA,
         old="        if k == DU_CELL || k == DU_ATTVAR                   # canBind(*t): a variable or an attvar (AV6)\n",
         new="        if k == DU_CELL                                     # canBind(*t): a variable or an attvar (AV6)\n"),
    # ── TV_ATTVAR / TV_ATTS rows named by the brief: the const bits ──
    dict(id="AV6-V7 TV_ATTVAR is 0 (no attvar-only filter; KILL ta01, ta04)", file=P, targets=TA,
         old="const TV_ATTVAR = 1                                        # 0x1\n",
         new="const TV_ATTVAR = 0                                        # 0x1\n"),
]
