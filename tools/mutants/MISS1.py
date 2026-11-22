# ORIGINAL: MISS1's mutant list: the pieces of wip/miss-preds (prolog_choice_attribute/3, '$leash'/2, '$visible'/2, trace/0, tracing/0, '$unload_file'/1);
# NOTHING was run when this list was drafted: the kills below are read off the rows, the CI battery is the verdict.
# tools/mutants/MISS1.py -- Format: tools/mutate_drive.py's: `id`, `file`, `old` (EXACTLY once), `new`, `targets`, optional `equivalent`.
# Each id names its KILL by the row of test/core_lang/test_miss_preds_swipl.jl (MG): ca01-ca13 prolog_choice_attribute/3, ld01-ld06 and vs01-vs04 the masks,
# the direct testset trace/tracing, ul01-ul07 '$unload_file'/1.
# TARGETS (audit D-0238): the test files that exercise the mutated code: the choice/frame code is read by test_local_stack.jl, test_rules_swipl.jl,
# test_builtins_swipl.jl, test_cont_boot_swipl.jl and test_attvar_wakeup.jl (prolog_current_choice/1); the notrace/trace functions by test_notrace_swipl.jl.
# NOT COVERED (a row would need the measured pc): `PL_unify_int64(ld, A3, offset)` of the `pc` key (offset + 1 survives: ca09 checks `integer(P)` only).
# Every `old` was counted EXACTLY once in its file (python3, src.count(old) == 1) at the tip of wip/miss-preds when this file was written (no Julia ran);
# `new` != `old`. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
MG = "test/core_lang/test_miss_preds_swipl.jl"
TARGETS_CA = [MG, "test/core_lang/test_local_stack.jl", "test/core_lang/test_rules_swipl.jl"]
TARGETS_TR = [MG, "test/core_lang/test_notrace_swipl.jl"]
TARGETS = TARGETS_CA + [t for t in TARGETS_TR if t not in TARGETS_CA]
T = "src/pl-trace.jl"
S = "src/pl-srcfile.jl"


def m(id, old, new, targets, file=T, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # PL_get_choice: a failed lookup does not stop the predicate (kill: MG ca05/ca06 index ld.choices[0])
    m("MISS1-CA1", "    ch == 0 && return FFALSE                            # !PL_get_choice(A1, &ch)",
      "    false && return FFALSE", TARGETS_CA),
    # PL_get_choice: the existence error names the wrong type (kill: MG ca06)
    m("MISS1-CA2", "            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :choice), r)",
      "            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :frame), r)", TARGETS_CA),
    # PL_get_choice: the type error names the wrong type (kill: MG ca05)
    m("MISS1-CA3", "    PL_error(ld, ERR_TYPE, mk_sym(T, :choice), r)",
      "    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), r)", TARGETS_CA),
    # the unknown key's domain error names the wrong domain (kill: MG ca04)
    m("MISS1-CA4", "    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :key), A2) ? FTRUE : FFALSE",
      "    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :frame), A2) ? FTRUE : FFALSE", TARGETS_CA),
    # parent: never unified (kill: MG ca03 reads noparent)
    m("MISS1-CA5", "        p != 0 && return PL_unify_choice(ld, A3, p) ? FTRUE : FFALSE",
      "        false && return PL_unify_choice(ld, A3, p) ? FTRUE : FFALSE", TARGETS_CA),
    # parent: the CHP_DEBUG skip dropped
    m("MISS1-CA6", "        while p != 0 && ld.choices[p].type == CHP_DEBUG",
      "        while false && ld.choices[p].type == CHP_DEBUG", TARGETS_CA,
      eq="a CHP_DEBUG choice point exists only under the debugger's redo support (NOT PORTED: CHP_DEBUG), none in the tests"),
    # frame: the frame term is always `none` (kill: MG ca02 integer(F), ca11)
    m("MISS1-CA7", "        return PL_unify_frame(ld, A3, ld.choices[ch].frame) ? FTRUE : FFALSE",
      "        return PL_unify_frame(ld, A3, 0) ? FTRUE : FFALSE", TARGETS_CA),
    # pc: never answered (kill: MG ca09 reads `jump-nopc`)
    m("MISS1-CA8", "        offset != -1 && return PL_unify_int64(ld, A3, offset) ? FTRUE : FFALSE",
      "        false && return PL_unify_int64(ld, A3, offset) ? FTRUE : FFALSE", TARGETS_CA),
    # choice_type_atom: a foreign redo named `clause` (kill: MG ca12)
    m("MISS1-CA9", "                    return mk_sym(T, :foreign)",
      "                    return mk_sym(T, :clause)", TARGETS_CA),
    # choice_type_atom: a catch choice named `debug` (kill: MG ca13)
    m("MISS1-CA10", "c.type == CHP_TOP ? :top : c.type == CHP_CATCH ? :catch : :debug",
      "c.type == CHP_TOP ? :top : c.type == CHP_CATCH ? :debug : :debug", TARGETS_CA),
    # '$leash'/2 stores into the visible mask (kill: MG ld02, vs03)
    m("MISS1-LV1", "    ld.debugstatus_leashing = v\n", "    ld.debugstatus_visible = v\n", [MG]),
    # '$visible'/2 stores into the leash mask (kill: MG vs02)
    m("MISS1-LV2", "    ld.debugstatus_visible = v\n", "    ld.debugstatus_leashing = v\n", [MG]),
    # setInteger: Old is not unified (kill: MG ld04: the mask is set although Old differs)
    m("MISS1-LV3", "    PL_unify_integer(ld, old, cur) || return nothing\n",
      "    true || return nothing\n", [MG]),
    # tracing/0 always false (kill: MG direct testset: tracing after trace)
    m("MISS1-TR1", "    return ld.debugstatus_tracing ? FTRUE : FFALSE\n", "    return FFALSE\n", TARGETS_TR),
    # trace/0 switches the trace mode off (kill: MG direct testset)
    m("MISS1-TR2", "    return tracemode(ld, true, nothing) ? FTRUE : FFALSE\n",
      "    return tracemode(ld, false, nothing) ? FTRUE : FFALSE\n", TARGETS_TR),
    # '$unload_file'/1: no check of the argument (kill: MG ul04/ul05)
    m("MISS1-UL1", "    name === nothing && return FFALSE\n\n    sf = lookupSourceFile(gd, name, false)\n",
      "    sf = lookupSourceFile(gd, name::T, false)\n", [MG], file=S),
    # '$unload_file'/1: the public table is kept (kill: MG ul06 exports)
    m("MISS1-UL2", "                    empty!(m.public_)               # clearHTableWP(m->public)\n",
      "", [MG], file=S),
]
