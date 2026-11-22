# ORIGINAL: MISS1's mutant list: the pieces of wip/miss-preds (prolog_choice_attribute/3, '$leash'/2, '$visible'/2, trace/0, tracing/0, '$unload_file'/1);
# NOTHING was run when this list was drafted: the kills below are read off the rows, the CI battery is the verdict.
# tools/mutants/MISS1.py -- Format: tools/mutate_drive.py's: `id`, `file`, `old` (EXACTLY once), `new`, `targets`, optional `equivalent`.
# Each id names its KILL by the row of test/core_lang/test_miss_preds_swipl.jl (MG): ca01-ca13 prolog_choice_attribute/3, ld01-ld06 and vs01-vs04 the masks,
# the direct testset trace/tracing, ul01-ul07 '$unload_file'/1.
# TARGETS (audit D-0238): the test files that exercise the mutated code: the choice/frame code is read by test_local_stack.jl, test_rules_swipl.jl,
# test_builtins_swipl.jl, test_cont_boot_swipl.jl and test_attvar_wakeup.jl (prolog_current_choice/1); the notrace/trace functions by test_notrace_swipl.jl.
# C22 (QUEUE-1): PC1-PC2 (the pc offset, kill: MG ca14, pinned 15 as MEASURED against the pinned swipl), PG1-PG6 (put/1,2 and get/1,2, kill: MG pu/ge rows),
# CN1-CN5 ('$call_no_catch'/1, kill: MG cn rows). TARGETS for the pl-file.jl and pl-pro.jl mutants add the files that exercise put_code and the
# character input (test_lb5_swipl.jl, test_s2a_swipl.jl; audit D-0238). NOT COVERED: `return streamStatus(ld, s)` of get_nonblank (a stream error at EOF
# needs an erroring stream: no row), `'$sig_unblock'` always true (not killable: nothing to observe).
# C23: TR3-TR8 (trace/0's refusal while a port is visible, audit D-0768 (2); kill: MG tr01-tr02 and the direct testset, written blind: nothing ran).
# Every `old` was counted EXACTLY once in its file (python3, src.count(old) == 1) at the tip of wip/miss-preds when this file was written (no Julia ran);
# `new` != `old`. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
MG = "test/core_lang/test_miss_preds_swipl.jl"
TARGETS_CA = [MG, "test/core_lang/test_local_stack.jl", "test/core_lang/test_rules_swipl.jl"]
TARGETS_TR = [MG, "test/core_lang/test_notrace_swipl.jl"]
F = "src/os/pl-file.jl"
P = "src/pl-pro.jl"
TARGETS_PG = [MG, "test/core_lang/test_lb5_swipl.jl", "test/core_lang/test_s2a_swipl.jl"]
TARGETS_CN = [MG]
TARGETS = TARGETS_CA + [t for t in TARGETS_TR + TARGETS_PG if t not in TARGETS_CA]
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
    # trace/0 (audit D-0768 (2); C23): never refused (kill: MG direct testset: the 0x001...0x3ff rows raise nothing, the state changes)
    m("MISS1-TR3", '    if (ld.debugstatus_visible & PORT_MASK) != 0\n',
      "    if false\n", [MG]),
    # trace/0 refused whatever is visible (kill: MG tr01, tr02 raise the refusal inside the row; the direct testset's 0, 0x200 and 0x400 rows)
    m("MISS1-TR4", '    if (ld.debugstatus_visible & PORT_MASK) != 0\n',
      "    if true\n", [MG]),
    # the refusal's port mask misses the exception port (kill: MG direct testset: the 0x100 row, `LK.PORT_MASK == 0x1ff`)
    m("MISS1-TR5", "const PORT_MASK = 0x1ff\n", "const PORT_MASK = 0x0ff\n", [MG], eq=None),
    # the refusal comes AFTER the state change (kill: MG direct testset: tracing/0 is true after the refused call, in each refused row)
    m("MISS1-TR6", '    if (ld.debugstatus_visible & PORT_MASK) != 0\n',
      "    if tracemode(ld, true, nothing) && (ld.debugstatus_visible & PORT_MASK) != 0\n", [MG]),
    # the refusal when no port is visible, none when one is (kill: MG tr01, tr02, the direct testset's first call)
    m("MISS1-TR7", '    if (ld.debugstatus_visible & PORT_MASK) != 0\n',
      "    if (ld.debugstatus_visible & PORT_MASK) == 0\n", [MG]),
    # the refusal names another step (kill: MG direct testset: `e.step == "DBG2"`; docs/r2_owners.tsv owns the key under DBG2)
    m("MISS1-TR8", '"trace/0 with a visible port: the tracer (pl-trace.c tracePort)", "DBG2"',
      '"trace/0 with a visible port: the tracer (pl-trace.c tracePort)", "DBG1"', [MG]),
    # '$unload_file'/1: no check of the argument (kill: MG ul04/ul05)
    m("MISS1-UL1", "    name === nothing && return FFALSE\n\n    sf = lookupSourceFile(gd, name, false)\n",
      "    sf = lookupSourceFile(gd, name::T, false)\n", [MG], file=S),
    # '$unload_file'/1: the public table is kept (kill: MG ul06 exports)
    m("MISS1-UL2", "                    empty!(m.public_)               # clearHTableWP(m->public)\n",
      "", [MG], file=S),
    # the pc key's offset is off by one, either way (kill: MG ca14 pins 15)
    m("MISS1-PC1", "return PL_unify_int64(ld, A3, offset) ? FTRUE : FFALSE",
      "return PL_unify_int64(ld, A3, offset + 1) ? FTRUE : FFALSE", TARGETS_CA),
    m("MISS1-PC2", "return PL_unify_int64(ld, A3, offset) ? FTRUE : FFALSE",
      "return PL_unify_int64(ld, A3, offset - 1) ? FTRUE : FFALSE", TARGETS_CA),
    # put/2 ignores its stream (kill: MG pu07 existence_error, pu09 permission_error)
    m("MISS1-PG1", "function pl_put2_va(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n    return put_code(ld, PL__t0, PL__t0 + 1)",
      "function pl_put2_va(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n    return put_code(ld, 0, PL__t0 + 1)",
      TARGETS_PG, file=F),
    # put/1's truth value is inverted (kill: MG pu01, pu02, pu10)
    m("MISS1-PG2", "    return put_code(ld, 0, PL__t0) ? FTRUE : FFALSE\nend\n\n# PORT: pl-file.c get_nonblank",
      "    return put_code(ld, 0, PL__t0) ? FFALSE : FTRUE\nend\n\n# PORT: pl-file.c get_nonblank", TARGETS_PG, file=F),
    # get_nonblank does not skip blanks (kill: MG ge01, ge03, ge14)
    m("MISS1-PG3", "        isBlankW(c) || return PL_unify_integer(ld, chr, c)",
      "        false || return PL_unify_integer(ld, chr, c)", TARGETS_PG, file=F),
    # get_nonblank answers 0, not -1, at the end of the stream (kill: MG ge04, ge05, ge06, ge16)
    m("MISS1-PG4", "            PL_unify_integer(ld, chr, -1) || return false     # TRY()",
      "            PL_unify_integer(ld, chr, 0) || return false     # TRY()", TARGETS_PG, file=F),
    # get/1 reads the second argument's stream slot: the stream is not the current input (kill: MG ge15, ge16)
    m("MISS1-PG5", "    return get_nonblank(ld, 0, PL__t0) ? FTRUE : FFALSE",
      "    return get_nonblank(ld, PL__t0, PL__t0) ? FTRUE : FFALSE", TARGETS_PG, file=F),
    # get/2 reads the current input, not its stream (kill: MG ge01, ge02, ge11)
    m("MISS1-PG6", "    return get_nonblank(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE",
      "    return get_nonblank(ld, 0, PL__t0 + 1) ? FTRUE : FFALSE", TARGETS_PG, file=F),
    # '$call_no_catch' takes the truth value of the goal (kill: MG cn02)
    m("MISS1-CN1", "        PL_clear_exception(ld)\n    end\n\n    return FTRUE\n",
      "        PL_clear_exception(ld)\n    end\n\n    return rc ? FTRUE : FFALSE\n", TARGETS_CN, file=P),
    # '$call_no_catch' leaves the exception pending (kill: MG cn03: the row's catch/3 sees foo)
    m("MISS1-CN2", "        PL_clear_exception(ld)\n    end\n\n    return FTRUE\n",
      "    end\n\n    return FTRUE\n", TARGETS_CN, file=P),
    # '$call_no_catch' never handles the exception (kill: MG cn03)
    m("MISS1-CN3", "    if !rc && ex[] != 0\n        print_unhandled_exception",
      "    if false\n        print_unhandled_exception", TARGETS_CN, file=P),
    # '$call_no_catch' runs the goal as PL_Q_PASS_EXCEPTION: the ball propagates (kill: MG cn03)
    m("MISS1-CN4", "    rc = callProlog(gd, ld, 0, A1, PL_Q_NORMAL, ex)",
      "    rc = callProlog(gd, ld, 0, A1, PL_Q_PASS_EXCEPTION, ex)", TARGETS_CN, file=P),
    # '$call_no_catch' does not print the uncaught ball (kill: MG cn07 through the program's message_hook/3 collector)
    m("MISS1-CN5", "        print_unhandled_exception(gd, ld, ex[])     # printed by the VM at the throw upstream\n",
      "", TARGETS_CN, file=P),
]
