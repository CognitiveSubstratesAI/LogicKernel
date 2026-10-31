# ORIGINAL: MOD3b's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD3b.py — the mutation battery of MOD3b (`Goal@Module` in a clause body: pl-comp.c getTargetModule's
# `at` flavour, compileBody's CB_ATSIGN, compileSubClause's O_CALL_AT_MODULE (call selection, the meta-call branch),
# decompileBody's I_CALLATM/I_DEPARTATM/I_CALLATMV/I_DEPARTATMV; pl-vmi.c I_DEPARTATM, I_CALLATM, I_DEPARTATMV,
# I_CALLATMV, i_metacall_common's `@` branch), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3a.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_at_body_swipl.jl (rows a01-a77 named in each
# id's KILL) and test/compile/test_body_code_swipl.jl's `_BC_MOD3B` rows ("bc" in a KILL). Verdicts: written by the
# battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in the source at wip/mod3b 1f75955 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * compileBody!'s unwind (`uframe.kind == CB_ATSIGN && (ci.at_context = uframe.tmsave)`, pl-comp.c:2668-2671):
#     EQUIVALENT, read not run — on `rc != BOOLEX_TRUE` every caller drops the compileInfo with the error
#     (compileClause `return nothing` after `compileBody!`, _compileGoalClause! the same), so the restored context is
#     never read; MOD3a's CB_COLON unwind is the same case.
#   * checkCallAtContextInstantiation's module tests and the call-site `mc_atok || @goto b_throw`: with the check gone, a
#     variable goal under `@` loops in the goal-clause compile (the meta-call of `@(G, M)` is `call(@(G, M))` again), a
#     HANG, not a verdict; and the module tests are answered by PL_error's ERR_TYPE rule (instantiation_error) the same
#     way. A mutant that hangs or is answered twice proves nothing about the check, so none is listed.
#   * callatm/callatmv's `@assert false` (the branch for a call instruction other than I_CALL/I_DEPART): unreachable,
#     only I_CALL and I_DEPART are passed.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code; the step's own file first
# (a run stops at the first target that decides). Only test_at_body_swipl.jl, test_body_code_swipl.jl (the `_BC_MOD3B`
# rows) and test_metacall_control.jl name a Prolog `@` goal; the other files reach the compiler, the decompiler or the
# run loop without it and are listed where the mutated code is shared with them (colon context, call/N, meta-call).
TS = ["test/core_lang/test_at_body_swipl.jl"]
TB = ["test/compile/test_body_code_swipl.jl"]
TM = ["test/core_lang/test_metacall_control.jl"]
TC = ["test/core_lang/test_colon_body_swipl.jl"]
TSC = ["test/compile/test_ssu_compile_swipl.jl"]       # compileClause
TDC = ["test/db/test_clause_swipl.jl", "test/db/test_retract_swipl.jl"]   # decompile!
TMC = ["test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_catch_swipl.jl", "test/core_lang/test_findall_swipl.jl"]
RUN = TS + TM
COMP = TS + TB + TM + TC + TSC
DEC = TS + TB + TC + TDC
TARGETS = TS + TB + TM + TC + TSC + TDC + TMC + ["test/foreign/test_query.jl"]   # the baseline's (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
C = "src/pl-comp.jl"
MUTANTS = [
    # ── pl-vmi.c I_CALLATM, I_DEPARTATM, I_DEPARTATMV, I_CALLATMV ──
    dict(id="MOD3b-A1 I_CALLATM does not skip the procedure-module operand: I_CALLM reads the wrong operands (KILL a02, a04)",
         file=W, targets=RUN,
         old="    PC += 1                                         # PC++: the procedure-module\n",
         new="    nothing\n"),
    dict(id="MOD3b-A2 I_DEPARTATM does not skip the procedure-module operand (KILL a01, a03)", file=W, targets=RUN,
         old="    PC += 1                                         # PC++: ignore the :-qualifier\n",
         new="    nothing\n"),
    dict(id="MOD3b-A3 I_DEPARTATM goes to I_CALLM: no frame reuse, lTop grows with the depth (KILL a71)", file=W, targets=RUN,
         old="    @goto I_DEPARTM                                 # VMI_GOTO(I_DEPARTM)\n",
         new="    @goto I_CALLM\n"),
    dict(id="MOD3b-A5 I_DEPARTATMV with a choice point left does not go to I_CALLATMV (KILL a74)", file=W, targets=RUN,
         old="        @goto I_CALLATMV                            # VMI_GOTO(I_CALLATMV)\n",
         new="        nothing\n"),
    dict(id="MOD3b-A7 I_DEPARTATMV sets no context module: the callee keeps the caller's (KILL a06, a08)", file=W, targets=RUN,
         old="        setContextModule!(ld.frames[FR], lookupModule(gd, _atom_value(ld, atv_w)).index)  # setContextModule(FR, lookupModule(word2atom(*ap)))\n",
         new="        nothing\n"),
    dict(id="MOD3b-A8 I_DEPARTATMV sets the context module to user, not the variable's module (KILL a06, a08)", file=W, targets=RUN,
         old="lookupModule(gd, _atom_value(ld, atv_w)).index)  # setContextModule(FR, lookupModule(word2atom(*ap)))",
         new="MODULE_user(gd).index)"),
    dict(id="MOD3b-A9 I_CALLATMV resolves the variable's module as user (KILL a07, a10)", file=W, targets=RUN,
         old="        mc_mi = lookupModule(gd, _atom_value(ld, atv_w)).index  # Module module = lookupModule(word2atom(*ap))\n",
         new="        mc_mi = MODULE_user(gd).index\n"),
    dict(id="MOD3b-A10 I_CALLATMV reads the procedure from the module-variable operand slot (KILL a05, a07, a10)", file=W, targets=RUN,
         old="    atv_proc = _call_procedure(ld, FR, PCc[PC + 1]) # Procedure proc = code2ptr(Procedure, *PC++)\n",
         new="    atv_proc = _call_procedure(ld, FR, PCc[PC])\n"),
    dict(id="MOD3b-A12 callatmv_type_error reports type_error(callable, …) for the module operand (KILL a22, a24, a26)", file=W, targets=RUN,
         old="    PL_error(ld, ERR_TYPE, mk_sym(T, :module), atv_t)\n",
         new="    PL_error(ld, ERR_TYPE, mk_sym(T, :callable), atv_t)\n"),
    # ── pl-vmi.c i_metacall_common's `@` branch ──
    dict(id="MOD3b-M1 the metacall check runs for every 2-ary goal, not only @/2 (KILL a28-a39, bc; TMC wide)",
         file=W, targets=RUN + TMC,
         old="    if mc_arity == 2 && sym_key(mc_name) == gd.functors_control.at_sign &&   # fd->functor == FUNCTOR_at_sign2\n",
         new="    if mc_arity == 2 && true &&\n"),
    # ── pl-comp.c compileSubClause: call selection, the meta-call branch ──
    dict(id="MOD3b-C1 call/N compiled inline under an at context (KILL a20, bc)", file=C, targets=COMP,
         old="    if is_call && ci.colon_context.type == TM_NONE && ci.at_context.type == TM_NONE\n",
         new="    if is_call && ci.colon_context.type == TM_NONE\n"),
    dict(id="MOD3b-C3a the procedure-module operand is the module index even for the clause's own module (KILL a42, bc)",
         file=C, targets=COMP,
         old="        ctm = tm === ci.module_ ? code(0) : code(tm.index)     # (tm==ci->module) ? (code)0 : ptr2code(tm)\n",
         new="        ctm = code(tm.index)\n"),
    dict(id="MOD3b-C3b the procedure-module operand is always 0 (KILL a40, bc)", file=C, targets=COMP,
         old="        ctm = tm === ci.module_ ? code(0) : code(tm.index)     # (tm==ci->module) ? (code)0 : ptr2code(tm)\n",
         new="        ctm = code(0)\n"),
    dict(id="MOD3b-C4 the module operand of I_CALLATM is the procedure's module (KILL a01, bc)", file=C, targets=COMP,
         old="ci, callatm(call), ctm, code(ci.at_context.module_), addProcedure!(ci, proc)",
         new="ci, callatm(call), ctm, code(tm.index), addProcedure!(ci, proc)"),
    dict(id="MOD3b-C5a I_DEPART under an at context compiles to I_CALLATM: no last-call (KILL a71)", file=C, targets=COMP,
         old="    call == I_DEPART && return I_DEPARTATM\n",
         new="    call == I_DEPART && return I_CALLATM\n"),
    dict(id="MOD3b-C5b I_DEPART under an at-variable context compiles to I_CALLATMV: no last-call (KILL a70)", file=C, targets=COMP,
         old="    call == I_DEPART && return I_DEPARTATMV\n",
         new="    call == I_DEPART && return I_CALLATMV\n"),
    dict(id="MOD3b-C6 a variable module under an at compiles to the module-atom instruction (KILL a06, a07, a08, a10)",
         file=C, targets=COMP,
         old="                ci, callatmv(call), ctm, VAROFFSET(ci.at_context.var_index),\n",
         new="                ci, callatm(call), ctm, VAROFFSET(ci.at_context.var_index),\n"),
    dict(id="MOD3b-C7 the meta-call under an at context builds `:`, not `@` (KILL a05, a47, a48)", file=C, targets=COMP,
         old="        Output_1!(ci, B_FUNCTOR, _at_functor_operand(ci))      # Output_1(ci, B_FUNCTOR, FUNCTOR_at_sign2)\n",
         new="        Output_1!(ci, B_FUNCTOR, _colon_functor_operand(ci))\n"),
    dict(id="MOD3b-C8 the meta-call pushes the colon context as the at module (KILL a05)", file=C, targets=COMP,
         old="        pushTargetModule!(ci, ci.at_context)\n",
         new="        pushTargetModule!(ci, ci.colon_context)\n"),
    dict(id="MOD3b-C9 the meta-call under an at context leaves the B_FUNCTOR frame open (no B_POP) (KILL a05, a47, a48, bc)",
         file=C, targets=COMP,
         old="        pushTargetModule!(ci, ci.at_context)\n        Output_0!(ci, B_POP)\n",
         new="        pushTargetModule!(ci, ci.at_context)\n"),
    # ── pl-comp.c getTargetModule (the `at` flavour), compileBody (CB_ATSIGN) ──
    dict(id="MOD3b-C10a getTargetModule stores a module target in the colon context, not the at context (KILL a01)",
         file=C, targets=COMP,
         old="        at ? (ci.at_context = tm) : (ci.colon_context = tm)    # tm->module = lookupModule(…); tm->type = TM_MODULE\n",
         new="        ci.colon_context = tm\n"),
    dict(id="MOD3b-C10b getTargetModule stores a variable target in the colon context, not the at context (KILL a06)",
         file=C, targets=COMP,
         old="            at ? (ci.at_context = tm) : (ci.colon_context = tm)    # tm->var_index = iv; tm->type = TM_VAR\n",
         new="            ci.colon_context = tm\n"),
    dict(id="MOD3b-C11a compileBody reads the module of G@M from child 2 (the goal) (KILL a01, a14, bc)", file=C, targets=COMP,
         old="            if !getTargetModule!(gd, ld, ci, child(body, 3), true)  # getTargetModule(&ci->at_context, …)\n",
         new="            if !getTargetModule!(gd, ld, ci, child(body, 2), true)\n"),
    dict(id="MOD3b-C11b compileBody compiles child 3 (the module) as the goal of G@M (KILL a01, a14, bc)", file=C, targets=COMP,
         old="            body = child(body, 2)                              # body = argTermP(*body, 0)\n",
         new="            body = child(body, 3)\n"),
    dict(id="MOD3b-C11c compileBody takes the module of G@M with getTargetModule's colon flavour (KILL a01, a06, a14)",
         file=C, targets=COMP,
         old="            if !getTargetModule!(gd, ld, ci, child(body, 3), true)  # getTargetModule(&ci->at_context, …)\n",
         new="            if !getTargetModule!(gd, ld, ci, child(body, 3), false)\n"),
    dict(id="MOD3b-C12 CB_ATSIGN does not restore the at context: the goals after `G@M` stay at M (KILL a14, a76)",
         file=C, targets=COMP,
         old="        ci.at_context = frame.tmsave\n",
         new="        nothing\n"),
    dict(id="MOD3b-C14 the CB_ATSIGN frame saves no context: nested at restores to none (KILL a76)", file=C, targets=COMP,
         old="ci.cut, true, true,\n                    atsave\n",
         new="ci.cut, true, true,\n                    TARGET_MODULE_NONE\n"),
    # ── pl-comp.c decompileBody: I_CALLATM, I_DEPARTATM, I_CALLATMV, I_DEPARTATMV ──
    dict(id="MOD3b-D1 the decompiler never wraps the goal in the procedure-module (KILL a40, bc)", file=C, targets=DEC,
         old="            if pm != 0                                          # if ( pm )\n",
         new="            if false\n"),
    dict(id="MOD3b-D2 the decompiler builds a module atom for a variable operand (KILL a06, a07, a08, a10)", file=C, targets=DEC,
         old="                _dvar!(di, nested, cm)                          # nested ? unifyVar(ARGP++, …, cm) : makeVarRef(cm)\n",
         new="                push!(di.argp, _atom_word!(ld, (ld.GD::PL_global_data{T}).modules[1].atom))\n"),
    dict(id="MOD3b-D3 the decompiler builds `:` instead of `@` (KILL a01-a13, bc)", file=C, targets=DEC,
         old="            build_term!(di, mk_sym(T, Symbol(\"@\")), 2)          # BUILD_TERM(FUNCTOR_at_sign2)\n",
         new="            build_term!(di, mk_sym(T, :(:)), 2)\n"),
    dict(id="MOD3b-D4 the decompiler names the first module for a module operand (KILL a01, a40, bc)", file=C, targets=DEC,
         old="modules[Int(cm)].atom)\n                )  # *ARGP++ = cm->name",
         new="modules[1].atom)\n                )"),
    dict(id="MOD3b-D5 the decompiler skips two operands of an at instruction, not three (KILL a01-a13, bc)", file=C, targets=DEC,
         old="            di.pc += 3\n            build_term!(di, def.name, def.arity)                # BUILD_TERM(proc->definition->functor)\n            if pm != 0",
         new="            di.pc += 2\n            build_term!(di, def.name, def.arity)                # BUILD_TERM(proc->definition->functor)\n            if pm != 0"),
]
