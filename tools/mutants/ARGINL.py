# ORIGINAL: ARGINL's mutant list — no swipl-devel counterpart.
# tools/mutants/ARGINL.py — the mutation battery of ARGINL (`arg/3` inline in a clause body: pl-comp.c compileBodyArg3,
# pl-vmi.c B_ARG_CF, B_ARG_VF, arg3_fast, arg3_slow, decompileBodyNoShift's B_ARG_CF/B_ARG_VF case, pl-gc.c
# clearUninitialisedVarsFrame's B_ARG_CF/B_ARG_VF case), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_arg_body_swipl.jl (rows named in each id's
# KILL: g_* run the clauses, o_* the same goals with vmi_builtin false, rb_* read the clauses back, inf_* count the
# inference the inline form saves, dg* run arg/3 as the goal of `$/1`) and by test/compile/test_body_code_swipl.jl's
# cells ab1-ab10 ("bc" in a KILL: the code of the clause compared whole with swipl's). Verdicts: written by the battery,
# not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in the source at wip/arginl (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * arg3_slow's `_slot_new_var!(ld, a3_arg)` (upstream `globaliseFirstVar(aarg)`): without it the first variable's slot
#     keeps its uninitialised word and the callee reads it — an internal error of the run loop, not a verdict
#     (the mutant would kill the runner, a RUNAWAY by the playbook); the g_* rows of the slow route cover the line.
#   * arg3_fast's `_is_gcompound(a3_w)` test: dropped, an atom's word is read as a compound pointer (an out-of-range
#     read of the runner's memory), not a verdict.
#   * RUNAWAY WATCH (read, not run): C5, C7 (the compound or the index slot is read before any write) and R12 (the operand
#     count is off by one, so an operand word is run as an opcode) may end the runner with no verdict, as the two above.
#     If a battery job exits 143 twice with the same ids, treat them by the playbook's runaway rule (prove caught under
#     `ulimit -v` + `timeout`); the rows named in each id's KILL decide when the run ends with a verdict.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code; the step's own file first
# (a run stops at the first target that decides). Clause bodies with an arg/3 goal are in test_arg_body_swipl.jl,
# test_body_code_swipl.jl (cells ab1-ab10), test_rules_swipl.jl (the `ag` clause), test_p1_swipl.jl (arg/3 as a
# predicate); the decompiler's case is reached through clause/2 (test_decompile.jl, test_clause_swipl.jl,
# test_retract_swipl.jl); the pl-gc.jl case through `$/1` (test_det_swipl.jl).
TS = ["test/core_lang/test_arg_body_swipl.jl"]
TB = ["test/compile/test_body_code_swipl.jl"]
TR = ["test/core_lang/test_rules_swipl.jl", "test/core_lang/test_p1_swipl.jl"]
TDC = [
    "test/compile/test_decompile.jl", "test/db/test_clause_swipl.jl",
    "test/db/test_retract_swipl.jl"
]
TDET = ["test/core_lang/test_det_swipl.jl"]
RUN = TS + TR
COMP = TS + TB + TR
DEC = TS + TB + TDC
GC = TS + TDET
TARGETS = TS + TB + TR + TDC + TDET   # the baseline's (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
C = "src/pl-comp.jl"
G = "src/pl-gc.jl"
MUTANTS = [
    # ── pl-comp.c compileBodyArg3 ──
    dict(id="ARGINL-C1 compileBodyArg3 emits B_ARG_VF for a constant index (KILL bc ab1, ab8, g_cf1, g_cf2)", file=C, targets=COMP,
         old="Output_3!(ci, B_ARG_CF, reinterpret(code, i), VAROFFSET(v2), VAROFFSET(v3))",
         new="Output_3!(ci, B_ARG_VF, reinterpret(code, i), VAROFFSET(v2), VAROFFSET(v3))"),
    dict(id="ARGINL-C2 compileBodyArg3 emits B_ARG_CF for a variable index (KILL bc ab2, g_vf1, g_vfenum)", file=C, targets=COMP,
         old="Output_3!(ci, B_ARG_VF, VAROFFSET(v1), VAROFFSET(v2), VAROFFSET(v3))",
         new="Output_3!(ci, B_ARG_CF, VAROFFSET(v1), VAROFFSET(v2), VAROFFSET(v3))"),
    dict(id="ARGINL-C3 the constant-index form does not mark the third variable seen: the next goal's use is a first occurrence (KILL bc ab1, ab8)", file=C, targets=COMP,
         old="                isFirstVarSet!(ci.used_var, v3)\n                Output_3!(ci, B_ARG_CF,",
         new="                Output_3!(ci, B_ARG_CF,"),
    dict(id="ARGINL-C4 the variable-index form does not mark the third variable seen (KILL bc ab2)", file=C, targets=COMP,
         old="                isFirstVarSet!(ci.used_var, v3)\n                Output_3!(ci, B_ARG_VF,",
         new="                Output_3!(ci, B_ARG_VF,"),
    dict(id="ARGINL-C5 the compound may be a first occurrence: arg(1, T, X) with T new compiles inline (KILL bc ab4, g_f2, g_cfvar)", file=C, targets=COMP,
         old="if v2 >= 0 && !isFirstVar(ci.used_var, v2)",
         new="if v2 >= 0"),
    dict(id="ARGINL-C6 the result may be a seen variable: arg(1, T, X) with X seen compiles inline (KILL bc ab3, g_s3yes, g_s3bind)", file=C, targets=COMP,
         old="if v3 >= 0 && isFirstVar(ci.used_var, v3)",
         new="if v3 >= 0"),
    dict(id="ARGINL-C7 the index may be a first occurrence: arg(I, T, X) with I new compiles inline (KILL bc ab5, g_f1)", file=C, targets=COMP,
         old="if v1 >= 0 && !isFirstVar(ci.used_var, v1)",
         new="if v1 >= 0"),
    dict(id="ARGINL-C8 a constant index compiles inline only when it is NOT a tagged integer (KILL bc ab1, ab6, ab7, ab8)", file=C, targets=COMP,
         old="            if isTaggedInt(a1)",
         new="            if !isTaggedInt(a1)"),
    dict(id="ARGINL-C9 the constant operand is one too big (KILL bc ab1, g_cf1, rb_00)", file=C, targets=COMP,
         old="                i = int64_value(a1)",
         new="                i = int64_value(a1) + 1"),
    # ── pl-vmi.c arg3_fast ──
    dict(id="ARGINL-R1 arg3_fast accepts the index 0 (KILL inf_cf0, inf_vf0; g_cf0, g_vf0 when the read is the functor cell)", file=W, targets=RUN,
         old="if a3_ai > 0 && a3_ai <= a3_arity",
         new="if a3_ai >= 0 && a3_ai <= a3_arity"),
    dict(id="ARGINL-R2 arg3_fast refuses the index equal to the arity: the last argument takes the call (KILL inf_cflast, inf_vflast)", file=W, targets=RUN,
         old="if a3_ai > 0 && a3_ai <= a3_arity",
         new="if a3_ai > 0 && a3_ai < a3_arity"),
    dict(id="ARGINL-R3 arg3_fast has no upper bound: an index past the arity reads beyond the compound (KILL inf_cf3, inf_vf3, g_cf3, g_vf3)", file=W, targets=RUN,
         old="if a3_ai > 0 && a3_ai <= a3_arity",
         new="if a3_ai > 0"),
    dict(id="ARGINL-R4 the arity is one too small (KILL inf_cflast, inf_vflast)", file=W, targets=RUN,
         old="a3_arity = arityFunctor(ld.functors, ld.gstack[a3_q])",
         new="a3_arity = arityFunctor(ld.functors, ld.gstack[a3_q]) - 1"),
    dict(id="ARGINL-R5 the argument linked is the next one (KILL g_cf1, g_cf2, g_vf1, g_cfsh, g_lk)", file=W, targets=RUN,
         old="_deref_loc(ld, a3_q + a3_ai))",
         new="_deref_loc(ld, a3_q + a3_ai + 1))"),
    dict(id="ARGINL-R6 the argument linked is always the first (KILL g_cf2, g_vf2, g_lk2)", file=W, targets=RUN,
         old="_deref_loc(ld, a3_q + a3_ai))",
         new="_deref_loc(ld, a3_q + 1))"),
    dict(id="ARGINL-R7 the flag vmi_builtin is not tested: the inline form runs with the flag off (KILL inf_cf, inf_vf, inf_cflast, inf_vflast)", file=W, targets=RUN,
         old="_is_gcompound(a3_w) && truePrologFlag(ld, PLFLAG_VMI_BUILTIN)",
         new="_is_gcompound(a3_w)"),
    # ── pl-vmi.c arg3_slow ──
    dict(id="ARGINL-R8 the slow route hands the compound as the index (KILL g_vfenum, g_vfenum1, g_vfatom, g_nd, g_f1)", file=W, targets=RUN,
         old="_slot_copy!(ld, ARGP.pos + 1, a3_idx)",
         new="_slot_copy!(ld, ARGP.pos + 1, a3_term)"),
    dict(id="ARGINL-R9 the slow route hands the integer plus one (KILL g_cf0, g_cfm1, g_cf3, o_cf0)", file=W, targets=RUN,
         old="consInt(a3_ai)",
         new="consInt(a3_ai + 1)"),
    dict(id="ARGINL-R10 B_ARG_CF's NULL index is slot 1 (the slow route copies the first variable, not the integer) (KILL g_cf0, g_cfm1, g_cf3)", file=W, targets=RUN,
         old="a3_idx = 0 ",
         new="a3_idx = 1 "),
    # ── pl-vmi.c B_ARG_CF, B_ARG_VF ──
    dict(id="ARGINL-R11 B_ARG_CF reads the integer one too big (KILL g_cf1, g_cf2, inf_cf)", file=W, targets=RUN,
         old="a3_ai = reinterpret(Int64, PCc[PC])",
         new="a3_ai = reinterpret(Int64, PCc[PC]) + 1"),
    dict(id="ARGINL-R12 B_ARG_CF steps over two operands, not three (KILL every g_cf row)", file=W, targets=RUN,
         old="    PC += 3\n    @goto arg3_fast",
         new="    PC += 2\n    @goto arg3_fast"),
    dict(id="ARGINL-R13 B_ARG_VF reads the index from the compound's slot (KILL g_vf1, g_vf2, g_vfenum)", file=W, targets=RUN,
         old="a3_idx = varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1",
         new="a3_idx = varFrameP(ld.frames[FR].base, Int(PCc[PC + 1])) + 1"),
    dict(id="ARGINL-R14 B_ARG_VF never takes the fast route: the index is always taken as no integer (KILL inf_vf, inf_vflast)", file=W, targets=RUN,
         old="a3_ai = Int64(valInt(a3_iw))",
         new="a3_ai = Int64(0)"),
    # ── pl-comp.c decompileBodyNoShift ──
    dict(id="ARGINL-D1 the decompiler reads a variable index as an integer and the reverse (KILL rb_00, rb_01, rb_03)", file=C, targets=DEC,
         old="            if op == B_ARG_VF\n",
         new="            if op == B_ARG_CF\n"),
    dict(id="ARGINL-D2 the decompiler pushes the second operand twice, the result variable is lost (KILL rb_00, rb_03, rb_10)", file=C, targets=DEC,
         old="            push!(di.argp, makeVarRef(codes[di.pc + 2]))\n            di.pc += 3\n            build_term!(di, mk_sym(T, :arg), 3)",
         new="            push!(di.argp, makeVarRef(codes[di.pc + 1]))\n            di.pc += 3\n            build_term!(di, mk_sym(T, :arg), 3)"),
    dict(id="ARGINL-D3 the decompiler's integer is one too big (KILL rb_00, rb_01, rb_02)", file=C, targets=DEC,
         old="mk_gnd(T, reinterpret(Int64, codes[di.pc]))",
         new="mk_gnd(T, reinterpret(Int64, codes[di.pc]) + 1)"),
    # ── pl-gc.c clearUninitialisedVarsFrame ──
    dict(id="ARGINL-G1 clearUninitialisedVarsFrame clears the second operand, not the third (KILL g_dgf1, g_dgf2, o_dgf1, o_dgf2)", file=G, targets=GC,
         old="            _setVar!(ld, base, Int(codes[pc + 3]))",
         new="            _setVar!(ld, base, Int(codes[pc + 2]))"),
]
