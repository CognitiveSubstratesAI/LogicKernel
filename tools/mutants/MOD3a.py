# ORIGINAL: MOD3a's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD3a.py — the mutation battery of MOD3a (`M:Goal` in a clause body: pl-comp.c getTargetModule,
# pushTargetModule, compileBody's CB_COLON, compileSubClause's meta-call and call selection, compileClause's
# P_MFCONTEXT + I_CONTEXT, decompile's I_CONTEXT, decompileBody's I_CALLM/I_DEPARTM; pl-vmi.c I_CONTEXT, I_CALLM,
# I_DEPARTM, mcall_cont's resolution of an undefined definition), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD2.py): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`. Killed by test/core_lang/test_colon_body_swipl.jl (rows b01-b46 named in each id's
# KILL) and test/compile/test_body_code_swipl.jl's "M:Goal in a body compiles as swipl's (MOD3a)" testset and its
# multifile pin ("bc" in a KILL). Hand-run before the commit (D-0104, `tools/mutate.sh run-in-tree`): verdicts in
# lk-channel evidence/MOD3a/mutants_verdicts.tsv.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once).
# NOT LISTED (each with its reason):
#   * compileBody!'s unwind (`while !isempty(stack) … ci.colon_context = uframe.tmsave`, pl-comp.c:2663-2671): EQUIVALENT,
#     read not run — on `rc != BOOLEX_TRUE` every caller drops the compileInfo with the error (src/pl-comp.jl compileClause
#     `return nothing` after `compileBody!`, _compileGoalClause! the same), so the restored context is never read; upstream's
#     callers drop `ci` the same way.
#   * getTargetModule's temporary-module refusal: no temporary module can be made yet (`'$destroy_module'`/class
#     `temporary`: MOD5b); the branch is ported and unreached until then — MOD5b adds its row and mutant.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code; the step's own file first
# (a run stops at the first target that decides). M:Goal reaches the run loop's I_CONTEXT/I_CALLM/I_DEPARTM from
# test_context_module_swipl.jl's `call(m2:G)` goal clauses and test_attvar_wakeup.jl's qualified goals; mcall_cont (M2)
# is also MOD2's meta-call path (cleanup, catch, findall); the compiler's colon context and compileClause reach every
# file that compiles bodies with `:`; the decompiler's I_CONTEXT/I_CALLM/I_DEPARTM, clause/2 and retract/1.
TS = ["test/core_lang/test_colon_body_swipl.jl"]
TB = ["test/compile/test_body_code_swipl.jl"]
TCM = ["test/core_lang/test_context_module_swipl.jl"]
TA = ["test/core_lang/test_attvar_wakeup.jl"]           # F2: uhook/3's `Module:attr_unify_hook(…)`
TMC = ["test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_catch_swipl.jl", "test/core_lang/test_findall_swipl.jl",
       "test/core_lang/test_metacall_control.jl"]      # mcall_cont through i_metacall_common
TSC = ["test/compile/test_ssu_compile_swipl.jl"]       # compileClause
TDC = ["test/db/test_clause_swipl.jl", "test/db/test_retract_swipl.jl"]   # decompile!, decompileBodyNoShift!
RUN = TS + TCM + TA
COMP = TS + TB + TCM + TA + TSC
DEC = TS + TB + TDC
TARGETS = TS + TB + TCM + TA + TMC + TSC + TDC + ["test/foreign/test_query.jl"]   # the baseline's (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
C = "src/pl-comp.jl"
MUTANTS = [
    # ── pl-vmi.c I_CONTEXT ──
    dict(id="MOD3a-X1 I_CONTEXT sets no context: `qm:H :- B` runs in qm (KILL b17, b20, b42)", file=W, targets=RUN,
         old="        setContextModule!(ld.frames[FR], ict_m)     # setContextModule(FR, m)\n",
         new="        nothing\n"),
    dict(id="MOD3a-X2 I_CONTEXT ignores P_TRANSPARENT: a transparent clause runs in its body module (KILL b18)", file=W, targets=RUN,
         old="    if (DEF.flags & P_TRANSPARENT) == 0             # isoff(DEF, P_TRANSPARENT)\n        setContextModule!(ld.frames[FR], ict_m)",
         new="    if true\n        setContextModule!(ld.frames[FR], ict_m)"),
    # ── pl-vmi.c I_DEPARTM, I_CALLM, mcall_cont ──
    dict(id="MOD3a-D1 I_DEPARTM's last call sets no context: the transparent callee takes the caller's (KILL b01)", file=W, targets=RUN,
         old="    setContextModule!(ld.frames[FR], Int(PCc[PC]))  # setContextModule(FR, code2ptr(Module, *PC++))\n",
         new="    nothing\n"),
    dict(id="MOD3a-D2 I_DEPARTM always takes I_CALLM's path: no frame reuse, lTop grows with the depth (KILL b45; audit D-0229)",
         file=W, targets=RUN,
         old="    if !(ld.BFR == 0 || ld.choices[ld.BFR].base <= ld.frames[FR].base) ||\n        !ld.prolog_flag_last_call\n        @goto I_CALLM",
         new="    if true\n        @goto I_CALLM"),
    dict(id="MOD3a-M1 I_CALLM passes user, not its module, to mcall_cont (KILL b02, b05, b08)", file=W, targets=RUN,
         old="    mc_mi = Int(PCc[PC])                            # Module module = code2ptr(Module, *PC++)\n",
         new="    mc_mi = MODULE_user(gd).index\n"),
    dict(id="MOD3a-M2 mcall_cont tests the transparency of the UNRESOLVED definition (KILL b08)", file=W, targets=RUN + TMC,
         old="        DEF = getProcDefinedDefinition(gd, DEF)     # DEF = trapUndefined(DEF)\n",
         new="        nothing\n"),
    # ── pl-comp.c getTargetModule ──
    dict(id="MOD3a-T1 getTargetModule accepts a variable met first (KILL b31, bc)", file=C, targets=COMP,
         old="        if ci.islocal || !isFirstVar(ci.used_var, iv)\n",
         new="        if true\n"),
    dict(id="MOD3a-T2 getTargetModule does not link a goal clause's module variable (KILL b35, b36, b37, b38)", file=C, targets=COMP,
         old="                link_local_var!(ci, t, iv) || return false\n",
         new="                nothing\n"),
    dict(id="MOD3a-T3 getTargetModule's type error does not fail the compilation (KILL b32, b33, b41, bc)", file=C, targets=COMP,
         old="        PL_error(ld, ERR_TYPE, mk_sym(T, :module), _target_culprit(ld, ci, t))\n        return false\n",
         new="        return true\n"),
    # ── pl-comp.c compileBody (CB_COLON), compileSubClause ──
    dict(id="MOD3a-B1 CB_COLON does not restore the context: the goals after `m:G` are m's (KILL bc p2, p5)", file=C, targets=COMP,
         old="        ci.colon_context = frame.tmsave\n        @goto resume\n",
         new="        @goto resume\n"),
    dict(id="MOD3a-S1 a goal of another module compiled as I_CALL/I_DEPART (KILL b01, b02, b21, bc)", file=C, targets=COMP,
         old="    if tm === ci.module_                                       # if ( tm == ci->module )\n",
         new="    if true\n"),
    dict(id="MOD3a-S2 call/N compiled inline under a colon context (KILL b10, b26, bc p7)", file=C, targets=COMP,
         old="    if is_call && ci.colon_context.type == TM_NONE             # (no at context: MOD3b)\n",
         new="    if is_call\n"),
    dict(id="MOD3a-S3 a goal under a variable module is not meta-called (KILL b03, b04, b23, b34, bc p3)", file=C, targets=COMP,
         old="    ci.colon_context.type == TM_VAR && @goto metacall\n",
         new="    nothing\n"),
    dict(id="MOD3a-S4 the meta-call under a colon context drops the `Module:` wrapper (KILL b11, b12, b28, bc p11, p12)", file=C, targets=COMP,
         old="    if ci.colon_context.type != TM_NONE\n        Output_1!(ci, B_FUNCTOR, _colon_functor_operand(ci))",
         new="    if false\n        Output_1!(ci, B_FUNCTOR, _colon_functor_operand(ci))"),
    # ── pl-comp.c compileClause: P_MFCONTEXT + I_CONTEXT ──
    dict(id="MOD3a-P1 P_MFCONTEXT only for multifile: `qm:H :- B` from user gets no I_CONTEXT (KILL b17, b24, b42, b44, bc p4, p5)", file=C, targets=COMP,
         old="            (m.index != def.module_ || (proc.definition.flags & P_MULTIFILE) != 0)\n",
         new="            ((proc.definition.flags & P_MULTIFILE) != 0)\n"),
    dict(id="MOD3a-P2 P_MFCONTEXT not for a multifile predicate (KILL b25, bc multifile pin)", file=C, targets=COMP,
         old="            (m.index != def.module_ || (proc.definition.flags & P_MULTIFILE) != 0)\n",
         new="            (m.index != def.module_)\n"),
    # ── pl-comp.c decompile, decompileBody ──
    dict(id="MOD3a-K1 decompile skips I_CONTEXT handling (KILL b24, b25, b44)", file=C, targets=DEC,
         old="    clause.codes[pc] == I_CONTEXT || return pc\n",
         new="    return pc\n"),
    dict(id="MOD3a-K2 I_CALLM/I_DEPARTM decompile without `Module:` (KILL b21, b22, b26, b29)", file=C, targets=DEC,
         old="            build_term!(di, mk_sym(T, :(:)), 2)                 # BUILD_TERM(FUNCTOR_colon2)\n",
         new="            pop!(di.argp); pop!(di.argp); push!(di.argp, g)\n"),
]
