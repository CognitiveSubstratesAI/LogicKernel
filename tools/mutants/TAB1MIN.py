# ORIGINAL: TAB1MIN's mutant list — no swipl-devel counterpart.
# tools/mutants/TAB1MIN.py — the mutation battery of TAB1-min (the load-time slice of boot/tabling.pl's `:- table` path):
# T1 pl-tabling.c `$tbl_trienode`/`$tbl_is_trienode` (src/pl-tabling.jl), T2 the tabling attributes (`table_props`,
# `tbl_get/set_predicate_attribute`, the `$set_predicate_attribute`/`$get_predicate_attribute` branches in src/pl-proc.jl,
# the `TP_*` flags in src/pl-incl.jl), T4 pl-wrap.c (`$c_wrap_predicate`, find_wrapper, assert_wrapper, unify_wrapped,
# wrapper_vmi; src/pl-wrap.jl), T5 pl-supervisor.c freeCodesDefinition's wrapper branch and pl-wrap.c
# skipWrapperPrefix/isCallWrapper/resetWrappedSupervisor, T3 the three opcodes S_WRAP/S_CALLWRAPPER/S_TABLED (src/pl-vmi.jl, the
# 7th `PL_code_data` block in src/pl-supervisor.jl, the run loop's named refusals in src/pl-wam.jl). Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_tabling_min_swipl.jl (rows tmt01-tmt22,
# tma01-tma23, tmw01-tmw13, tmc01-tmc07 and its two LK-only white-box testsets, named in each id's KILL).
# Verdicts: written by the battery, not yet run. Nothing was compiled or run when this file was written (edit-only writer):
# every KILL names the row the code reading says decides it; the battery decides.
# The `old` strings are single-line substrings of the source at wip/tab1min (one is a two-line anchor, marked) written
# BEFORE `tools/warm.sh fmt` ran: RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly
# once). Each `old` was checked to occur exactly once in its file (a text count by a throwaway python3 -I script, no Julia).
# NOT LISTED (each with its reason):
#   * `k == DU_WORD && ` dropped from `pl_tbl_is_trienode1_va` (src/pl-tabling.jl): no killing row. `w` of a non-word
#     location (variable, compound) is that location's raw cell, which would have to equal the reserved atom's word by
#     accident for a row to tell the two apart; rows tmt06/tmt07 execute the line but cannot distinguish.
#   * `freeCodesDefinition!(gd, def, true)` removed from `tbl_set_incremental_predicate` (src/pl-tabling.jl): no killing
#     row. It resets the supervisor of a predicate whose incremental flag CHANGES; rows tma09/tma10 change it on predicates
#     that have no wrapper and the virgin supervisor, where the call does nothing. A row needs a wrapped predicate whose
#     wrapped supervisor is not virgin when its incremental flag flips: left to the gate (decide with the dispatcher).
#   * `unregisterWrappedSupervisor` (src/pl-wrap.jl): a no-op by design (atoms live for ever here); nothing to mutate.
#   * `@assert c !== nothing` in `resetWrappedSupervisor` and `@assert cref !== nothing` in `assert_wrapper`: the asserts
#     mirror upstream's `assert()`; a row would have to reach a state the callers exclude.
#   * T3 (src/pl-global.jl idle `index_context` literal, src/pl-incl.jl `PL_code_data`): the FIELD ORDER of the seven blocks is
#     not observable: the constructor is positional, `initSupervisors` is its only other caller, and swapping two of the
#     identical-shaped empty `code[]` vectors in the idle literal (pl-global.jl) changes nothing a test can read; likewise the
#     `@label` span effect on `static_analysis_body`'s call-path spans is not a behaviour.
#   * T3 mutants that change WHICH opcode is the first one outside `VMI_RUN` (test/foreign/test_query.jl:305-330 takes
#     `first(notrun)`): none is listed. `:I_NOP` (code 0) stays that opcode under every mutant below, so test_query.jl does not
#     decide any of them and is not a target (the E13-E15 mutants drop a later name from `VMI_RUN`).
# TARGETS (audit D-0238): the step's own file first (a run stops at the first target that decides). Only
# test_tabling_min_swipl.jl names `$c_wrap_predicate`, `$tbl_trienode` and sets a tabling attribute; test_pr1_swipl.jl (row
# pr93) reads the `tabled` attribute through `$get_predicate_attribute`; `freeCodesDefinition!`, `resetProcedure!` and
# `isCallWrapper`/`skipWrapperPrefix` run on every static clause add and every abolish, so the supervisor and reset mutants also
# list test_pr1_swipl.jl and test_event_swipl.jl (the update listeners `resetProcedure!` destroys); the 2-argument
# `freeCodesDefinition!` is also called by test_procedures.jl and test_assert_swipl.jl.
TM = ["test/core_lang/test_tabling_min_swipl.jl"]
PR1 = ["test/core_lang/test_pr1_swipl.jl"]
EV = ["test/core_lang/test_event_swipl.jl"]
GET = TM + PR1                                 # the getter and the flag constants
SUP = TM + PR1 + EV                            # supervisor / reset code that every clause add reaches
SUP2 = SUP + ["test/db/test_procedures.jl", "test/db/test_assert_swipl.jl"]   # the 2-argument freeCodesDefinition!
TARGETS = TM + PR1 + EV + ["test/db/test_procedures.jl", "test/db/test_assert_swipl.jl"]   # the baseline's (mutate_ci.py plan reads TARGETS)
TB = "src/pl-tabling.jl"
WR = "src/pl-wrap.jl"
PR = "src/pl-proc.jl"
SV = "src/pl-supervisor.jl"
IN = "src/pl-incl.jl"
VM = "src/pl-vmi.jl"
WM = "src/pl-wam.jl"
MUTANTS = [
    # ── T1: pl-tabling.c tbl_trienode, tbl_is_trienode ──
    dict(id="TAB1MIN-A1 `$tbl_is_trienode` accepts every word but the reserved atom (KILL tmt03, tmt04)", file=TB, targets=TM,
         old="w == ATOM_trienode",
         new="w != ATOM_trienode"),
    dict(id="TAB1MIN-A2 `$tbl_trienode` builds the text atom `trienode`, not the reserved symbol (KILL tmt11, tmt03)", file=TB, targets=TM,
         old="mk_reserved_symbol(T, :trienode)",
         new="mk_sym(T, :trienode)"),
    # ── T2: pl-tabling.c set_bool_attr, tbl_get/set_predicate_attribute, get_size_or_inf, tbl_reset_tabling_attributes ──
    dict(id="TAB1MIN-B1 set_bool_attr sets the tabled bit, not the flag asked for (KILL tma04, tma11, tma12)", file=TB, targets=TM,
         old="props.flags |= flag",
         new="props.flags |= TP_TABLED"),
    dict(id="TAB1MIN-B2 set_bool_attr false does not clear the flag (KILL tma05)", file=TB, targets=TM,
         old="props.flags &= ~flag",
         new="props.flags &= ~UInt32(0)"),
    dict(id="TAB1MIN-B3 the tabled_variant getter reads the tabled bit (KILL tma03)", file=TB, targets=GET,
         old="PL_unify_integer(ld, value, (p.flags & TP_VARIANT) != 0 ? 1 : 0)",
         new="PL_unify_integer(ld, value, (p.flags & TP_TABLED) != 0 ? 1 : 0)"),
    dict(id="TAB1MIN-B4 a size of -1 (infinite) is unified by the getter: `none` becomes -1 (KILL tma13)", file=TB, targets=GET,
         old="v0 != -1 &&",
         new="v0 != -2 &&"),
    dict(id="TAB1MIN-B5 tbl_reset_tabling_attributes! does not clear the properties (KILL tma22)", file=TB, targets=SUP,
         old="p === nothing || clear_table_props!(p)",
         new="p === nothing || nothing"),
    dict(id="TAB1MIN-B6 the incremental attribute sets the monotonic flag (KILL tma09, tma10)", file=TB, targets=TM,
         old="set_bool_attr(ld, def, TP_INCREMENTAL, value)",
         new="set_bool_attr(ld, def, TP_MONOTONIC, value)"),
    dict(id="TAB1MIN-B7 an incremental flag that changes is not set: the test of the change is inverted (KILL tma09)", file=TB, targets=TM,
         old="if val != now",
         new="if val == now"),
    dict(id="TAB1MIN-B8 `infinite` is no longer recognised: the size attribute raises a type error (KILL tma13, tma19)", file=TB, targets=TM,
         old="inf !== nothing && sym_key(inf) == sym_key(mk_sym(T, :infinite))",
         new="inf !== nothing && sym_key(inf) != sym_key(mk_sym(T, :infinite))"),
    dict(id="TAB1MIN-B9 subgoal_abstract is stored as answer_abstract (KILL tma18)", file=TB, targets=TM,
         old="p.subgoal_abstract = v",
         new="p.answer_abstract = v"),
    dict(id="TAB1MIN-B10 max_answers is not stored (KILL tma19)", file=TB, targets=TM,
         old="p.max_answers = v",
         new="p.max_answers = -1"),
    dict(id="TAB1MIN-B11 the TP_VARIANT bit equals the tabled bit: tabled_variant reads 1 after `tabled` (KILL tma03)", file=IN, targets=GET,
         old="const TP_VARIANT = UInt32(0x0040)",
         new="const TP_VARIANT = UInt32(0x0001)"),
    dict(id="TAB1MIN-B12 `$set_predicate_attribute` never takes the tabling branch (KILL tma02-tma23)", file=PR, targets=GET,
         old="if _tbl_is_predicate_attribute(T, sym_key(key))",
         new="if false"),
    dict(id="TAB1MIN-B13 `$get_predicate_attribute` fails for the tabling keys (KILL tma02, tma03, tma11)", file=PR, targets=GET,
         old="return tbl_get_predicate_attribute(ld, def, key, value) ? FTRUE : FFALSE",
         new="return FFALSE"),
    dict(id="TAB1MIN-B14 resetProcedure! does not clear the tabling properties (KILL tma22)", file=PR, targets=SUP,
         old="def.tabling === nothing || tbl_reset_tabling_attributes!(def)",
         new="def.tabling === nothing || nothing"),
    # ── T4: pl-wrap.c find_wrapper, assert_wrapper, unify_wrapped, wrapper_vmi, c_wrap_predicate ──
    dict(id="TAB1MIN-C1 find_wrapper never finds the wrapper of the same name: the rewrap makes a new closure (KILL tmw05, tmc02)", file=WR, targets=SUP,
         old="codes[i + 3] == name && return",
         new="codes[i + 3] != name && return"),
    dict(id="TAB1MIN-C2 the `table` wrapper of a variant tabled predicate is S_CALLWRAPPER (KILL white-box d05 S_TABLED)", file=WR, targets=SUP,
         old="return S_TABLED",
         new="return S_CALLWRAPPER"),
    dict(id="TAB1MIN-C3 wrapper_vmi tests the variant bit inverted (KILL white-box d05 S_TABLED)", file=WR, targets=SUP,
         old="(def.tabling.flags & TP_VARIANT) != 0",
         new="(def.tabling.flags & TP_VARIANT) == 0"),
    dict(id="TAB1MIN-C4 unify_wrapped of an atom head fails (KILL tmw04)", file=WR, targets=TM,
         old="return PL_unify_atom(ld, wrapped, clo)",
         new="return false"),
    dict(id="TAB1MIN-C5 the rewrap keeps the old wrapper clause (KILL tmw05's count, white-box wd.number_of_clauses)", file=WR, targets=TM,
         old="retractClauseDefinition!(gd, old.predicate, old, false)",
         new="nothing"),
    dict(id="TAB1MIN-C6 the rewrap leaves the old clause reference in the side table (KILL white-box d05w)", file=WR, targets=TM,
         old="crefs[Int(codes[i + 1])] = cref",
         new="nothing"),
    dict(id="TAB1MIN-C7 unify_wrapped links the arguments from the wrong argument position (KILL tmw14, tmw15: the only wrapped heads of arity >= 2; tmw03 and tmw12 are arity 1)", file=WR, targets=TM,
         old="_PL_get_arg(ld, i, head, a)",
         new="_PL_get_arg(ld, 1, head, a)"),
    # ── T5: pl-wrap.c skipWrapperPrefix, isCallWrapper, resetWrappedSupervisor; pl-supervisor.c freeCodesDefinition ──
    dict(id="TAB1MIN-D1 skipWrapperPrefix steps one cell over S_MQUAL/S_LMQUAL (KILL unit skipWrapperPrefix)", file=WR, targets=SUP,
         old="pc += 2",
         new="pc += 1"),
    dict(id="TAB1MIN-D2 skipWrapperPrefix leaves S_SSU_DET unskipped (KILL unit skipWrapperPrefix)", file=WR, targets=SUP,
         old="elseif op == S_SSU_DET",
         new="elseif op == S_VIRGIN"),
    dict(id="TAB1MIN-D3 isCallWrapper leaves out S_TABLED (KILL unit isCallWrapper, tmc05, tmc06)", file=WR, targets=SUP,
         old="c == S_CALLWRAPPER || c == S_TABLED",
         new="c == S_CALLWRAPPER"),
    dict(id="TAB1MIN-D4 resetWrappedSupervisor resets only the outermost closure (KILL tmc03)", file=WR, targets=SUP,
         old="while isCallWrapper(codes[cw])",
         new="if isCallWrapper(codes[cw])"),
    dict(id="TAB1MIN-D5 resetWrappedSupervisor leaves the wrapped supervisor in place (KILL white-box c06 supervisor, tmc07)", file=WR, targets=SUP,
         old="c.supervisor = def0.code_data.virgin",
         new="nothing"),
    dict(id="TAB1MIN-D6 resetWrappedSupervisor keeps the old side table (KILL white-box c06 supervisor_crefs: only if the single-clause supervisor of the called c06 had a side-table entry; the gate decides)", file=WR, targets=SUP,
         old="c.supervisor_crefs = ClauseRef{T}[]",
         new="nothing"),
    dict(id="TAB1MIN-D7 freeCodesDefinition! never takes the wrapper branch: the wrapper is dropped (KILL tmc02, tmc03, white-box _tm_wrapped)", file=SV, targets=SUP,
         old="if isCallWrapper(codes[skipWrapperPrefix(codes)])   # unlikely",
         new="if false   # unlikely"),
    dict(id="TAB1MIN-D8 freeCodesDefinition! of a wrapped predicate resets to virgin when lingering (KILL tmc02, tmc03)", file=SV, targets=SUP,
         old="if !do_linger",
         new="if do_linger"),
    dict(id="TAB1MIN-D9 the 2-argument freeCodesDefinition! no longer refuses a wrapped predicate (KILL white-box @test_throws; two-line anchor)", file=SV, targets=SUP2,
         old="if isCallWrapper(codes[skipWrapperPrefix(codes)])\n            throw(",
         new="if false\n            throw("),
    dict(id="TAB1MIN-D10 _assertDefinition! calls the 2-argument freeCodesDefinition!: a clause added to a wrapped predicate raises (KILL tmc01-tmc07: the program does not load)", file=PR, targets=TM,
         old="freeCodesDefinition!(gd, def, true)",
         new="freeCodesDefinition!(def, true)"),
    # ── T3: pl-vmi.c S_WRAP / S_CALLWRAPPER / S_TABLED, pl-supervisor.c MAKE_SV1(wrapper, S_WRAP), the run loop's named refusals ──
    # (every KILL names the white-box testset "wrapper opcodes and the wrapper block (T3, LK-only)", test/core_lang/test_tabling_min_swipl.jl:451-496)
    dict(id="TAB1MIN-E1 initSupervisors builds the wrapper block from S_TABLED (KILL test_tabling_min_swipl.jl:471 `cd.wrapper == code[S_WRAP, I_EXIT]`; :492 the entered block raises S_TABLED, not S_WRAP)", file=SV, targets=TM,
         old="code[S_WRAP, I_EXIT]",
         new="code[S_TABLED, I_EXIT]"),
    dict(id="TAB1MIN-E2 _shared_supervisor does not know the wrapper block (KILL test_tabling_min_swipl.jl:473 `_shared_supervisor(cd, cd.wrapper)`)", file=SV, targets=SUP,
         old="codes === cd.wrapper",
         new="false"),
    dict(id="TAB1MIN-E3 S_CALLWRAPPER is declared with two operands (KILL test_tabling_min_swipl.jl:463 `ic.arguments == 3`, :468 the decoder step lands inside the instruction)", file=VM, targets=TM,
         old="code_info(:S_CALLWRAPPER, 0x00, 3,",
         new="code_info(:S_CALLWRAPPER, 0x00, 2,"),
    dict(id="TAB1MIN-E4 S_TABLED's second and third operands are declared untyped (KILL test_tabling_min_swipl.jl:463 `ic.argtype == want`)", file=VM, targets=TM,
         old="code_info(:S_TABLED, 0x00, 3, (CA1_CLAUSEREF, CA1_DATA, CA1_DATA, 0x00))",
         new="code_info(:S_TABLED, 0x00, 3, (CA1_CLAUSEREF, 0x00, 0x00, 0x00))"),
    dict(id="TAB1MIN-E5 S_WRAP is declared with an operand (KILL test_tabling_min_swipl.jl:459 `iw.arguments == 0`)", file=VM, targets=TM,
         old="code_info(:S_WRAP, 0x00, 0,",
         new="code_info(:S_WRAP, 0x00, 1,"),
    dict(id="TAB1MIN-E6 S_TABLED leaves a gap after S_CALLWRAPPER (KILL test_tabling_min_swipl.jl:455 `S_TABLED == S_CALLWRAPPER + 1`; the table lookup may fail at load first)", file=VM, targets=TM,
         old="const S_TABLED = code(161)",
         new="const S_TABLED = code(162)"),
    dict(id="TAB1MIN-E7 S_WRAP's refusal names TAB1 (KILL test_tabling_min_swipl.jl:492 `e.step == \"WRAP1\"`)", file=WM, targets=TM,
         old='"the VM instruction S_WRAP (calling a wrapped predicate from a closure)",\n            "WRAP1"',
         new='"the VM instruction S_WRAP (calling a wrapped predicate from a closure)",\n            "TAB1"'),
    dict(id="TAB1MIN-E8 S_CALLWRAPPER's refusal names TAB1 (KILL test_tabling_min_swipl.jl:482 `e.step == \"WRAP1\"`)", file=WM, targets=TM,
         old='"the VM instruction S_CALLWRAPPER (calling a wrapped predicate)",\n            "WRAP1"',
         new='"the VM instruction S_CALLWRAPPER (calling a wrapped predicate)",\n            "TAB1"'),
    dict(id="TAB1MIN-E9 S_TABLED's refusal names WRAP1 (KILL test_tabling_min_swipl.jl:485 `e.step == \"TAB1\"`)", file=WM, targets=TM,
         old='"the VM instruction S_TABLED (calling a tabled predicate)", "TAB1"',
         new='"the VM instruction S_TABLED (calling a tabled predicate)", "WRAP1"'),
    dict(id="TAB1MIN-E10 S_WRAP continues with the next instruction instead of refusing (KILL test_tabling_min_swipl.jl:492 `e isa NotPortedError`: the entered wrapper block answers)", file=WM, targets=TM,
         old="@label S_WRAP\n    throw(",
         new="@label S_WRAP\n    @goto next_instruction\n    throw("),
    dict(id="TAB1MIN-E11 S_CALLWRAPPER continues with the next instruction instead of refusing (KILL test_tabling_min_swipl.jl:482 `e isa NotPortedError`)", file=WM, targets=TM,
         old="@label S_CALLWRAPPER\n    throw(",
         new="@label S_CALLWRAPPER\n    @goto next_instruction\n    throw("),
    dict(id="TAB1MIN-E12 S_TABLED continues with the next instruction instead of refusing (KILL test_tabling_min_swipl.jl:485 `e isa NotPortedError`)", file=WM, targets=TM,
         old="@label S_TABLED\n    throw(",
         new="@label S_TABLED\n    @goto next_instruction\n    throw("),
    dict(id="TAB1MIN-E13 VMI_RUN does not list S_WRAP (KILL test_tabling_min_swipl.jl:479 `nm in VMI_RUN`; :492 the refusal is the unknown-instruction one, without the owner)", file=WM, targets=TM,
         old=":S_WRAP, :S_CALLWRAPPER, :S_TABLED",
         new=":S_CALLWRAPPER, :S_TABLED"),
    dict(id="TAB1MIN-E14 VMI_RUN does not list S_CALLWRAPPER (KILL test_tabling_min_swipl.jl:479; :482 `e.step == \"WRAP1\"`)", file=WM, targets=TM,
         old=":S_WRAP, :S_CALLWRAPPER, :S_TABLED",
         new=":S_WRAP, :S_TABLED"),
    dict(id="TAB1MIN-E15 VMI_RUN does not list S_TABLED (KILL test_tabling_min_swipl.jl:479; :485 `e.step == \"TAB1\"`)", file=WM, targets=TM,
         old=":S_WRAP, :S_CALLWRAPPER, :S_TABLED",
         new=":S_WRAP, :S_CALLWRAPPER"),
    dict(id="TAB1MIN-E16 unify_closure gives the closure copy the virgin supervisor, not the wrapper block (KILL test_tabling_min_swipl.jl:476 `c01.def.codes === cd.wrapper`)", file=WR, targets=TM,
         old="def.code_data.wrapper,",
         new="def.code_data.virgin,"),
]
