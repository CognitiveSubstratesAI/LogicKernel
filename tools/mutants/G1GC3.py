# ORIGINAL: G1-GC G1-3's mutant list; the collector's mark phase is a port of pl-gc.c at the pin, the list itself is the kernel's own.
# tools/mutants/G1GC3.py — the mutation battery of G1-GC step G1-3, the MARK phase of the stack collector: src/pl-gcmark.jl (the cell
# bits, mark_variable and its pointer reversal, the indirect value of ruling D1, the term-reference roots: foreign frames, nb_ variables,
# the argument stack, the attvar chain, gc_clear_marks!) and src/pl-gcwalk.jl (the walk of a clause head for the alternative clauses,
# early_reset_vars, mergeTrailedAssignments, mark_alt_clauses, mark_choicepoints, mark_environments, mark_stacks, mark_phase, unmark_*).
# The list pins what is there at the gate of G1-3 (NOTHING was run when it was drafted: the kills below are read off the rows of
# test/core_lang/test_gc_mark.jl, the CI battery is the verdict). Run ONCE, in CI (.github/workflows/mutation.yml). Format:
# tools/mutate_drive.py's (as TRIE4.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the testset of test/core_lang/test_gc_mark.jl (GM) that must fail, by the first words of its name:
#   TR = "term references: exactly the reachable cells are marked ..."   DC = "dead cells stay unmarked; a shared and a cyclic term ..."
#   IN = "an indirect value marks its box cell only (ruling D1)"         AV = "attributed variables: the attvar cell and its attributes ..."
#   GV = "global variables (nb_setval) are roots ..."                    ER = "early reset: an unreachable trailed variable is reset ..."
#   KA = "early reset: a kept assignment marks the old value it saved"   LQ = "the argument stack and the choicepoints and frames of a live query ..."
#   AS = "the argument stack's global entries are term references ..."  AC = "mark_alt_clauses marks only the arguments the alternative clauses read"
#   CO = "deliberate corruptions FAIL the comparison"
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect. The mark phase has no caller yet beyond the
#   test file of the step (G1-2 and G1-5 call it later): test_gc_mark.jl is the only file that reaches these functions, and `git grep` of
#   the names in test/ finds no other (a file that drives the collector later adds itself here).
# VERDICTS: the CI battery runs one fresh process per mutant and its verdicts are authoritative. A mutant that corrupts the pointer
#   reversal of mark_variable (G1GC3-V6, G1GC3-V7) may loop or fail with an error instead of a failed comparison: an error is a kill, a
#   timeout is NO verdict (never caught).
# DEFERRED KILLS (audit D-0374 item 2): a row declared `equivalent="DEFERRED KILL: ..."` has no killing assertion yet; it must SURVIVE the
#   battery and the next piece of G1-3 adds the row named in its text:
#   * G1GC3-D1, G1GC3-D2, G1GC3-D3: the live-query heap has one frame and an n/1 whose alternatives read the one argument, so
#     mark_environments' mark_arguments and mark_choicepoints' mark_alt_clauses cover each other; a row with an alternative that does not read an
#     argument (m(b, _)) driven through mark_phase on the live query kills the first two, a nested call (a frame with a parent, resumed at a
#     pc) kills the third;
#   * G1GC3-D5: mergeTrailedAssignments' duplicate arm needs a cell assigned twice within one trail range.
# EQUIVALENT mutants (declared with their reason, file:line in the `equivalent` text): G1GC3-E1, G1GC3-E2, G1GC3-E3.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GC3` from the repository root;
# `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GM = "test/core_lang/test_gc_mark.jl"
TARGETS = [GM]
M = "src/pl-gcmark.jl"
W = "src/pl-gcwalk.jl"

def m(id, old, new, file=M, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=[GM])
    if eq:
        d["equivalent"] = eq
    return d

MUTANTS = [
    # ---- the term-reference roots (pl-gcmark.jl)
    m("G1GC3-R1 mark_term_refs: only the innermost foreign frame is walked (KILL GV: the frame of `keep` is not marked; TR/CO: every frame but one is a root class dropped)",
      "        fr = f.parent\n    end\n    return nothing\nend\n\n# PORT: pl-gc.c mark_foreign_frame",
      "        fr = 0\n    end\n    return nothing\nend\n\n# PORT: pl-gc.c mark_foreign_frame"),
    m("G1GC3-R2 mark_term_refs: the last reference of every frame is skipped (KILL TR: the cells it roots stay unmarked, `marked == model`)",
      "        for k in 0:(f.size - 1)\n            a = -_gc_fli_slot(f, k)",
      "        for k in 0:(f.size - 2)\n            a = -_gc_fli_slot(f, k)"),
    m("G1GC3-R3 mark_foreign_frame: early reset of the frame's trail range is not run (KILL ER: c2 is not reset, its entry is not deleted; KA: the pair's old value is not marked)",
      "        te = early_reset_vars(ld, st, f.mark, te)       # G1-3b",
      "        te = te       # G1-3b"),
    m("G1GC3-R4 gvars_to_term_refs: no global value of an nb_ variable becomes a term reference (KILL GV: the copy is not a root; term_refs_to_gvars sees 0 of the found values)",
      "            _gc_is_global_ref(w) && gc_new_term_ref!(ld, w)\n        end\n    end\n    sb = 0",
      "            false && gc_new_term_ref!(ld, w)\n        end\n    end\n    sb = 0"),
    m("G1GC3-R5 term_refs_to_gvars: the saved frozen bar is not restored (KILL GV: `ld.frozen_bar == bar0`; the mark of the first foreign frame keeps bar0 != 0)",
      "        ld.frozen_bar = valPtr(ld.slots[sb + 1])",
      "        ld.frozen_bar = 0"),

    m("G1GC3-R7 argument_stack_to_term_refs: refuses when the safe point saves the argument stack (KILL AS: `fid2 != 0`)",
      "    vm.save_argp || return 0\n    ensureLocalSpace(ld, SIZEOF_FLIFRAME + ld.aTop + 4)",
      "    vm.save_argp && return 0\n    ensureLocalSpace(ld, SIZEOF_FLIFRAME + ld.aTop + 4)"),
    m("G1GC3-R8 argument_stack_to_term_refs: the reference names the cell above the entry (KILL AS: `c in marked`, `marked == model`)",
      "                gc_new_term_ref!(ld, makeRefG(e.argp.pos))",
      "                gc_new_term_ref!(ld, makeRefG(e.argp.pos + 1))"),
    m("G1GC3-R9 term_refs_to_argument_stack: the pushed registers entry is not popped (KILL AS: `ld.aTop == a0 + 1`)",
      "    ld.aTop -= 1\n    PL_close_foreign_frame(ld, fid)\n    return nothing\nend\n\n# PORT: pl-gc.c count_need_protection_attvars",
      "    PL_close_foreign_frame(ld, fid)\n    return nothing\nend\n\n# PORT: pl-gc.c count_need_protection_attvars"),
    m("G1GC3-R10 link_attvars: the term reference names the chain's link cell, not the attvar cell (KILL AV: `A in marked2`, `marked2 == model`)",
      "        isAttVar(ld.gstack[avp]) && gc_new_term_ref!(ld, makeRefG(avp))",
      "        isAttVar(ld.gstack[avp]) && gc_new_term_ref!(ld, makeRefG(p))"),
    m("G1GC3-R11 link_attvars: also outside call_residue_vars (KILL AV: `link_attvars(ld) == 0`, and the first `_gm_agree`, the link roots the attvar)",
      "    (ld.attvar_call_residue_vars_count != 0 && ld.attvar_attvars != 0) || return 0",
      "    ld.attvar_attvars != 0 || return 0"),
    # ---- mark_variable: the pointer reversal and the indirect (D1)
    m("G1GC3-V1 mark_variable, indirect: the box cell is not marked, only counted (KILL IN: `marked == model`, the boxes in `boxes`; TR: every vbox of this heap)",
      "                    ld.gstack[bp] = set_marked(ld.gstack[bp])\n                    st.total_marked += 1",
      "                    st.total_marked += 1"),

    m("G1GC3-V3 mark_variable, indirect: the cell after the box is marked as well, the whole indirect as upstream does (KILL IN: `marked == model`; ruling D1 marks the box cell only)",
      "                    ld.gstack[bp] = set_marked(ld.gstack[bp])\n                    st.total_marked += 1",
      "                    ld.gstack[bp] = set_marked(ld.gstack[bp])\n                    ld.gstack[bp + 1] = set_marked(ld.gstack[bp + 1])\n                    st.total_marked += 1"),
    m("G1GC3-V4 mark_variable, compound: the mark bit does not stop a second visit (KILL DC: the shared and the cyclic term are entered twice, domark of a marked cell is an error)",
      "                if is_marked(ld.gstack[nxt])        # term has already been marked\n                    mode = 2\n                else\n                    args = arityFunctor",
      "                if false        # term has already been marked\n                    mode = 2\n                else\n                    args = arityFunctor"),
    m("G1GC3-V5 mark_variable, compound: the FIRST bit of the last argument is left unset too (KILL TR, DC: the reversal does not find the end of the term; an error or a failed `marked == model`)",
      "                        while args > 1\n",
      "                        while args > 2\n"),
    m("G1GC3-V6 mark_variable, backward: the compound pointer is restored one cell high (KILL TR: `(ld.gstack .& VALUE_MASK) == (sn.g .& VALUE_MASK)`)",
      "                    val = consPtr(current - 1, TAG_COMPOUND | STG_GLOBAL)",
      "                    val = consPtr(current, TAG_COMPOUND | STG_GLOBAL)"),
    m("G1GC3-V7 mark_variable, backward: the reference is restored to the next cell (KILL TR: the same value comparison)",
      "                    val = makeRefG(current)\n",
      "                    val = makeRefG(current + 1)\n"),
    m("G1GC3-V8 mark_variable, backward: the FIRST bit of the cell the walk returns to stays set (KILL TR: `!any(LK.is_first, ...)`)",
      "            _gc_set!(ld, current, clear_first(_gc_get(ld, current)))",
      "            _gc_set!(ld, current, _gc_get(ld, current))"),
    m("G1GC3-V11 gc_clear_marks!: the global cells keep their bits (KILL TR: `ld.gstack == sn.g`; LQ: the GC_MASK of every cell)",
      "        ld.gstack[i] = ld.gstack[i] & VALUE_MASK",
      "        ld.gstack[i] = ld.gstack[i]"),

    # ---- the walk of the alternative clauses (pl-gcwalk.jl)
    m("G1GC3-A1 mark_alt_clauses: a frame with unmarked arguments returns at once (KILL AC: argument 1 is not marked)",
      "    unmarked == 0 && return nothing\n    ws = gc_walk_state(",
      "    unmarked == 0 || return nothing\n    ws = gc_walk_state(", file=W),
    m("G1GC3-A2 mark_alt_clauses: `envtop` is the first argument, nothing is below it (KILL AC: `is_marked(ld.slots[sp + 1])`)",
      "    ws.envtop = sp + argc\n",
      "    ws.envtop = sp\n", file=W),
    m("G1GC3-A3 mark_alt_clauses: only clauses NOT visible at the frame's generation are walked (KILL AC: the alternative `m(b, _)` is not walked)",
      "        if cl !== nothing && visibleClause(ld, cl, generationFrame(f))",
      "        if cl !== nothing && !visibleClause(ld, cl, generationFrame(f))", file=W),
    m("G1GC3-A4 walk_and_mark_gc: a head atom marks no argument (KILL AC: argument 1 of `m(b, _)` is read by H_ATOM)",
      "        elseif op == H_ATOM || op == H_SMALLINT || op == H_NIL || op == H_FLOAT\n            mark_argp_gc(ld, st, ws)",
      "        elseif op == H_ATOM || op == H_SMALLINT || op == H_NIL || op == H_FLOAT\n            nothing", file=W),
    m("G1GC3-A5 walk_and_mark_gc: a void head argument marks its argument (D4, wrong alternative marking; KILL AC: `!is_marked(ld.slots[sp + 2])`)",
      "        elseif op == H_VOID\n            ws.adepth == 0 && (ws.ARGP += 1)",
      "        elseif op == H_VOID\n            mark_argp_gc(ld, st, ws)", file=W),

    # ---- early reset of the trail (pl-gcwalk.jl)
    m("G1GC3-T1 early_reset_vars: a marked trailed variable is reset like an unmarked one (KILL ER: `ld.gstack[c1]` and its entry; KA: the pair is deleted)",
      "            elseif !is_marked(ld.gstack[tard])\n                ld.gstack[tard] = word(0)               # setVar(*tard)",
      "            elseif is_marked(ld.gstack[tard])\n                ld.gstack[tard] = word(0)               # setVar(*tard)", file=W),
    m("G1GC3-T2 early_reset_vars: the unreachable variable keeps its value (KILL ER: `ld.gstack[c2] == 0`)",
      "                ld.gstack[tard] = word(0)               # setVar(*tard)\n",
      "                nothing               # setVar(*tard)\n", file=W),
    m("G1GC3-T3 early_reset_vars: every trailed cell counts as newer than the frame (KILL ER: c1's entry is deleted, `ld.trail[tr0 + 1] != 0`)",
      "            if tard > gk + 1                            # tard > gKeep && tard < gMax",
      "            if tard > 0                            # tard > gKeep && tard < gMax", file=W),
    m("G1GC3-T4 early_reset_vars: the cell of a kept assignment is not recognised as marked (KILL KA: the pair is reset and deleted, `ld.trail[tr0 + 1] != 0`)",
      "            elseif is_marked(ld.gstack[tard])\n                keep = true",
      "            elseif false\n                keep = true", file=W),
    m("G1GC3-T5 early_reset_vars: the saved old value of a kept assignment is not marked (KILL KA: `gp in marked`, `marked == with`)",
      "                if !is_marked(ld.gstack[gp])\n                    mark_variable(ld, st, gp)",
      "                if is_marked(ld.gstack[gp])\n                    mark_variable(ld, st, gp)", file=W),
    m("G1GC3-T6 mergeTrailedAssignments: the pair is not counted off (KILL KA: `assignments == 0` fails, an error)",
      "            assignments -= 1\n            if is_first(ld.gstack[p])",
      "            assignments -= 0\n            if is_first(ld.gstack[p])", file=W),
    m("G1GC3-T7 mergeTrailedAssignments: the FIRST bits it set are not cleared (KILL KA: the row asserts no FIRST bit is left after mark_phase)",
      "        ld.gstack[p] = clear_first(ld.gstack[p])\n    end\n    assignments == 0",
      "        ld.gstack[p] = ld.gstack[p]\n    end\n    assignments == 0", file=W),
    # ---- the drivers and unmark (pl-gcwalk.jl)

    m("G1GC3-S2 mark_stacks: no foreign frame is left to early reset (KILL ER: c2 stays unreset, its entry stays; KA)",
      "    ms.flictx = ld.fli_context\n    st.trailcells_deleted = 0",
      "    ms.flictx = 0\n    st.trailcells_deleted = 0", file=W),
    m("G1GC3-S3 mark_phase: the stacks are walked before the term references (KILL ER: c1 is not yet marked when early reset looks at it, it is reset to 0, `ld.gstack[c1]`)",
      "    mark_term_refs(ld, st)\n    mark_stacks(ld, st, vm; vmi_state_of=vmi_state_of)",
      "    mark_stacks(ld, st, vm; vmi_state_of=vmi_state_of)\n    mark_term_refs(ld, st)", file=W),
    m("G1GC3-S4 mark_phase: the term references are not marked (KILL TR, GV, AV, AS: `marked == model`; CO: the stacks alone mark nothing)",
      "    mark_term_refs(ld, st)\n    mark_stacks(ld, st, vm; vmi_state_of=vmi_state_of)",
      "    mark_stacks(ld, st, vm; vmi_state_of=vmi_state_of)", file=W),
    m("G1GC3-U1 unmark_environments: the flag is kept, the other flags are cleared (KILL LQ: `FR_MARKED == 0` of every frame)",
      "        f.flags &= ~mask\n",
      "        f.flags &= mask\n", file=W),
    m("G1GC3-U2 unmark_environments: stops at a frame whose flag IS set (KILL LQ: nothing is unmarked)",
      "        (f.flags & mask) == 0 && return 0\n",
      "        (f.flags & mask) != 0 && return 0\n", file=W),
    # ---- DEFERRED KILLS (the row to add is named in the header)
    m("G1GC3-D1 mark_environments: the frame's arguments are not marked (DEFERRED KILL: the live-query row's alternatives read the one argument)",
      "        if (pred.flags & P_FOREIGN) != 0 || pc == 0 || f.clause === nothing\n            mark_arguments(ld, st, fr)",
      "        if (pred.flags & P_FOREIGN) != 0 || pc == 0 || f.clause === nothing\n            nothing",
      file=W,
      eq="DEFERRED KILL: src/pl-gcwalk.jl mark_environments' first arm and mark_choicepoints' CHP_CLAUSE arm (mark_alt_clauses) mark the same argument of n/1 in the live-query row; the next piece adds a live-query row over m(b, _)"),
    m("G1GC3-D2 mark_choicepoints: the alternative clauses of a CHP_CLAUSE are not walked (DEFERRED KILL: see G1GC3-D1)",
      "            mark_alt_clauses(ld, st, fr, c.value_clause.cref)\n            f = ld.frames[fr]",
      "            nothing\n            f = ld.frames[fr]",
      file=W,
      eq="DEFERRED KILL: mark_environments (pc == 0) has marked every argument of the frame before mark_alt_clauses runs in the live-query row"),
    m("G1GC3-D3 mark_environments: the walk does not go on to the parent frame (DEFERRED KILL: the live-query row's frame has no parent)",
      "        if f.parent != 0\n            pc = f.programPointer.pc\n            fr = f.parent",
      "        if false\n            pc = f.programPointer.pc\n            fr = f.parent",
      file=W,
      eq="DEFERRED KILL: the frame of the live-query row is the query's top frame (`parent == 0`); a nested call resumed at a pc kills it"),

    m("G1GC3-D5 mergeTrailedAssignments: a later pair for the same cell is kept (DEFERRED KILL: no row assigns one cell twice within one range)",
      "            if is_first(ld.gstack[p])\n                trail[te] = word(0)                     # te->as_word = 0",
      "            if false\n                trail[te] = word(0)                     # te->as_word = 0",
      file=W,
      eq="DEFERRED KILL: row KA trails one assignment, the duplicate arm needs two TrailAssignment! of one cell within one choicepoint's range"),
    # ---- EQUIVALENT
    m("G1GC3-E1 mark_environments: a frame is not flagged FR_MARKED (EQUIVALENT: mark_choicepoints flags it before it reads the flag)",
      "            f.flags |= FR_MARKED\n            ws.flags = GCM_CLEAR",
      "            ws.flags = GCM_CLEAR",
      file=W,
      eq="src/pl-gcwalk.jl mark_choicepoints, the CHP_CLAUSE arm, sets FR_MARKED itself before the (parent) walk; the live-query row's frame is flagged there"),
    m("G1GC3-E2 mark_local_variable: the local-reference refusal is skipped (EQUIVALENT: the kernel stores no local-stack reference)",
      "    if isRef(w) && storage(w) == STG_LOCAL\n        throw(\n            NotPortedError(\n                ld.placeholder,\n                \"a local-stack reference in mark_local_variable",
      "    if false && isRef(w) && storage(w) == STG_LOCAL\n        throw(\n            NotPortedError(\n                ld.placeholder,\n                \"a local-stack reference in mark_local_variable",
      eq="src/pl-gcmark.jl mark_local_variable: no word the kernel builds is a local-stack reference (the DIVERGES note), so the branch never fires"),
    m("G1GC3-E3 mark_stacks: the trail-cell counter is not reset (EQUIVALENT: every row passes a fresh gc_mark_counts)",
      "    ms.flictx = ld.fli_context\n    st.trailcells_deleted = 0\n",
      "    ms.flictx = ld.fli_context\n",
      file=W,
      eq="src/pl-gcwalk.jl mark_stacks: st is a fresh gc_mark_counts() in every row of test_gc_mark.jl, its trailcells_deleted is 0 already"),
]
