# ORIGINAL: FRAMEATTR's mutant list — no swipl-devel counterpart.
# tools/mutants/FRAMEATTR.py — the mutation battery of FRAMEATTR: pl-trace.c's prolog_frame_attribute/3 (the keys argument, goal,
# predicate_indicator, parent_goal, pc, alternative, level, top, skipped, hidden, context_module, parent, clause), its helpers
# (has_alternatives, isDebugFrame, parentFrame walks), the FR_NOTIFY / FR_CAUGHT invariant of pl-vmi.c's exit_watched with
# frameFinished/callCleanupHandler, and the TRACE_ME flag lookupProcedure hands a new definition (pl-proc.c). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Written UNTESTED
# (nothing compiled): every `old` text was counted with python3 -I against the tree of wip/late-preds-2 (each occurs once in its file).
# KILL rows are rows of test/core_lang/test_frameattr_swipl.pl (t24-t48, t58-t65, the predicates `tN(R)` the driver compares with the
# .out). Ids keep the numbering of the old line's DBG1 b-part (b1-b5, b9-b19, b24) and its groups c and d; the old b6-b8, b20-b23
# (choice_attribute) belong to wip/miss-preds, the old group e (I_DEPART/I_LCALL/I_TCALL/I_EXITQUERY, rows t66-t71) to the engine-core
# step that ports the FR_WATCHED branches of those instructions.
# TARGETS (audit D-0238): the step's own file first; every other file that reads a frame with prolog_frame_attribute/3 from Prolog
# (test_wrap_swipl.jl, test_autoload_trap.jl, test_tabling_answers_swipl.jl) runs the same code, because the call sets FR_NOTIFY on
# the frame it reads and that frame then exits through exit_watched; the cleanup, catch and event files run the exit_watched /
# callCleanupHandler / frameFinished mutants; test_meta_predicate_swipl.jl calls get_procedure with a head term.
TD = ["test/core_lang/test_frameattr_swipl.jl"]
TW = TD + [
    "test/core_lang/test_wrap_swipl.jl", "test/core_lang/test_autoload_trap.jl", "test/core_lang/test_tabling_answers_swipl.jl",
]
TARGETS = sorted(set(TW + [
    "test/core_lang/test_meta_predicate_swipl.jl", "test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_event_swipl.jl", "test/db/test_procedures.jl",
]))   # the baseline's (mutate_ci.py plan reads TARGETS)
TRC = "src/pl-trace.jl"
PRC = "src/pl-proc.jl"
WAM = "src/pl-wam.jl"


def m(id, old, new, targets=TW, equivalent=None, file=TRC):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if equivalent is not None:
        d["equivalent"] = equivalent
    return d


MUTANTS = [
    # ── group b: prolog_frame_attribute/3 and its helpers ──
    m("FRAMEATTR-b1 argument(N): the bound on the clause's variables is lifted (KILL t34: argument(1000) answers yes)",
      "argn > cl.prolog_vars && return false", "argn >= cl.prolog_vars + 1000000 && return false"),
    m("FRAMEATTR-b2 parent_goal: no rewind between the frames tried (KILL t58: bindings of a failed frame stay)",
      "                    PL_rewind_foreign_frame(ld, fid)\n                    cur = parentFrame(ld, cur)\n",
      "                    cur = parentFrame(ld, cur)\n"),
    m("FRAMEATTR-b3 key top is swapped (KILL t27, t47)",
      "PL_put_atom(ld, result, mk_sym(T, f.parent != 0 ? :false : :true))",
      "PL_put_atom(ld, result, mk_sym(T, f.parent != 0 ? :true : :false))"),
    m("FRAMEATTR-b4 has_alternatives ignores a jump choice point (KILL t59)",
      "                if c.type == CHP_CLAUSE || c.type == CHP_JUMP\n                    return true",
      "                if c.type == CHP_CLAUSE\n                    return true"),
    m("FRAMEATTR-b5 alternative: a choice point of the frame itself is the alternative (KILL t40, t38)",
      "if c2.frame != frame && (c2.type == CHP_CLAUSE || c2.type == CHP_JUMP)",
      "if c2.frame == frame && (c2.type == CHP_CLAUSE || c2.type == CHP_JUMP)"),
    m("FRAMEATTR-b9 predicate_indicator is the head, not Name/Arity (KILL t24, t31)",
      "unify_definition(gd, ld, gd.modules[m], result, def, 0, GP_NAMEARITY)",
      "unify_definition(gd, ld, gd.modules[m], result, def, 0, 0)"),
    m("FRAMEATTR-b10 prolog_frame_attribute(none, _, _) succeeds (KILL t45)",
      "fr == 0 && return false                             # frame == 'none'",
      "fr == 0 && return true                              # frame == 'none'"),
    m("FRAMEATTR-b11 argument(0) is not refused (KILL t46)",
      "argn < 1 && return PL_error(ld, ERR_DOMAIN, mk_sym(T, :natural), arg)",
      "argn < 0 && return PL_error(ld, ERR_DOMAIN, mk_sym(T, :natural), arg)"),
    m("FRAMEATTR-b12 level is always 0 (KILL t26)",
      "PL_put_integer(ld, result, Int(levelFrame(f)))", "PL_put_integer(ld, result, 0)"),
    m("FRAMEATTR-b13 skipped is swapped (KILL t27)",
      "(f.flags & FR_SKIPPED) != 0 ? :true : :false", "(f.flags & FR_SKIPPED) != 0 ? :false : :true"),
    m("FRAMEATTR-b14 pc is refused for a clause frame (KILL t37)",
      "if pp.pc != 0 && parent != 0\n            pf = ld.frames[parent]",
      "if pp.pc != 0 && parent == 0\n            pf = ld.frames[parent]"),
    m("FRAMEATTR-b15 parent_goal(Next) hands back the atom none for a frame (KILL t42)",
      "PL_unify_frame(ld, arg, parent) && return true",
      "PL_unify_atom(ld, arg, mk_sym(T, :none)) && return true"),
    m("FRAMEATTR-b16 an unknown parent_goal predicate is a match (KILL t44)",
      "        proc === nothing && return false\n\n        fid = PL_open_foreign_frame(ld)",
      "        proc === nothing && return true\n\n        fid = PL_open_foreign_frame(ld)"),
    m("FRAMEATTR-b17 the context module of a frame is the value's module (KILL t60)",
      "gd.modules[contextModule(gd, ld, fr)].atom", "gd.modules[m].atom"),
    m("FRAMEATTR-b18 a hidden predicate (no TRACE_ME) is visible (KILL t61)",
      "(def.flags & TRACE_ME) == 0 && return false         # hidden predicate",
      "(def.flags & TRACE_ME) == 0 && return true          # hidden predicate"),
    m("FRAMEATTR-b19 a user predicate's frame is hidden (KILL t27)",
      "(def.flags & HIDE_CHILDS) == 0 && return true       # user pred",
      "(def.flags & HIDE_CHILDS) == 0 && return false      # user pred"),
    m("FRAMEATTR-b24 get_procedure puts the head only where none is wanted (KILL t41-t44, t58 through parent_goal, which passes a head; the callers meta_declaration and the wrap predicate pass one too, those of clause/2 and retract/1 pass 0)",
      "        h != 0 && PL_put_term(ld, h, head)                          # if ( h ) PL_put_term(h, head)\n",
      "        h == 0 && PL_put_term(ld, h, head)                          # if ( h ) PL_put_term(h, head)\n",
      targets=TW + ["test/core_lang/test_meta_predicate_swipl.jl"], file=PRC),
    # ── group c: exit_watched's check: a frame watched through FR_NOTIFY alone exits there without FR_CAUGHT; a CLEANUP frame has run
    #    its handler (FR_CAUGHT) before it exits. Rows t62, t63: a frame that is both. ──
    m("FRAMEATTR-c1 exit_watched asserts FR_CAUGHT for every watched frame (the original assertion) (KILL t24-t61: a frame read by prolog_frame_attribute/3 exits through exit_watched with FR_NOTIFY and no FR_CAUGHT; t62, t63 do NOT kill it: their frame has FR_CAUGHT)",
      "    @assert (ew_f.flags & FR_CLEANUP) == 0 ||\n        (ew_f.flags & FR_CAUGHT) != 0 \"exit_watched: a cleanup frame exits before its handler ran\"\n",
      "    @assert (ew_f.flags & FR_CAUGHT) != 0 \"exit_watched: a cleanup frame exits before its handler ran\"\n",
      targets=TW + ["test/core_lang/test_event_swipl.jl"], file=WAM),
    m("FRAMEATTR-c2 callCleanupHandler (reached from I_EXITCLEANUP) does not set FR_CAUGHT: a cleanup frame exits deterministically with its handler run and the flag clear (KILL t62, t63 and every cleanup row of test_cleanup_swipl.jl: the assertion of exit_watched trips)",
      "        f.flags |= FR_CAUGHT\n\n        # Unify the catcher",
      "        # Unify the catcher",
      targets=TD + ["test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_catch_swipl.jl", "test/core_lang/test_event_swipl.jl"], file=WAM),
    m("FRAMEATTR-c3 frameFinished runs no cleanup handler for a frame that is also FR_NOTIFY (KILL t62, t63: the handler's effect is gone and the assertion of exit_watched trips; no row of t24-t61 has a cleanup frame)",
      "    if (ld.frames[fr].flags & FR_CLEANUP) != 0\n        callCleanupHandler(ld, fr, reason)",
      "    if (ld.frames[fr].flags & (FR_CLEANUP | FR_NOTIFY)) == FR_CLEANUP\n        callCleanupHandler(ld, fr, reason)",
      targets=TD + ["test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_event_swipl.jl"], file=WAM),
    # ── group d: the TRACE_ME flag of a new definition (lookupProcedure; pl-proc.c resetProcedure: `stringAtom(name)[0] != '$'`) ──
    m("FRAMEATTR-d1 lookupProcedure gives a user-module predicate no TRACE_ME: a user predicate's frame is hidden (KILL t27, t64, test_procedures.jl: a new predicate's flags)",
      "key, arity, clauses, userpred ? TRACE_ME : UInt64(0), name,", "key, arity, clauses, UInt64(0), name,",
      targets=TD + ["test/db/test_procedures.jl"], file=PRC),
    m("FRAMEATTR-d2 lookupProcedure gives a system-module predicate TRACE_ME too: a system predicate's frame is visible: the frame of `$bags:findall_loop/4`, the parent of findall/3's goal, reads hidden=false (KILL t65; not t61: catch/3's flags are set by its own registration, not by lookupProcedure)",
      "(m.flags & M_SYSTEM) == 0 && sym_first_byte(name) != 0x24", "sym_first_byte(name) != 0x24",
      targets=TD + ["test/db/test_procedures.jl"], file=PRC),
]
