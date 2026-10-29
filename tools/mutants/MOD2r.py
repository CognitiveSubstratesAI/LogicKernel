# ORIGINAL: MOD2's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD2r.py — the mutation battery of MOD2 (the context module: pl-wam.c contextModule, setContextModule,
# PL_open_query's context, callCleanupHandler's module; pl-vmi.c I_DEPART, I_LCALL, mcall_cont; pl-comp.c compileClause's
# goal-clause context; pl-modul.c stripModule, strip_module/3, pl_context_module; pl-fli.c PL_strip_module(_ex);
# pl-proc.c get_module's GP_FIND default; pl-attvar.c suspend; pl-ext.c's PL_meta_predicate transparency; the stand-ins'
# transparency and qualification), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as SSU2.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_context_module_swipl.jl (rows c01-c42 named in each id's KILL; "wb" is its
# PL_open_query testset), H2 by test/core_lang/test_cleanup_swipl.jl:295, FX1 by test/test_type_discipline.jl. Hand-run before the commit (D-0104, `tools/mutate.sh run-in-tree`): verdicts in lk-channel
# evidence/MOD2/mutants_verdicts.tsv.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once).
# NOT LISTED (each with its reason):
#   * contextModule's fallback `MODULE_user(gd)` (the loop's exit): EQUIVALENT, read not run — every frame chain ends at a
#     query's top frame, whose predicate `$c_call_prolog/0` (system) is not transparent (PL_open_query), so the loop always
#     returns from inside; pl-wam.c:1755 the same.
#   * PL_open_query's `saved_environment` branch is REACHED since D-0209 item 5: callPortray (pl-write.c, ported)
#     calls `user:portray/1` through PL_call_predicate with ctx NULL while write_term/3 runs; row c36 (a transparent
#     portray/1 asserting its context) — mutant Q3 below.
#   * I_LCALL's `clearLocal(FR, FR_CLEAR_NEXT)`: FR_CLEAR_NEXT ⊇ FR_LCO_CLEAR; FR_DET/FR_DETGUARD reach a transparent
#     last call only under `$/1` or det/1 declarations, which no row here combines with a transparent predicate.
# TARGETS (audit D-0238 item 4): each mutant lists every test file that exercises its mutated code, not only this step's
# file — the early battery's narrow targets let H2 "survive" although test_cleanup_swipl.jl:295 kills it. The step's own
# file comes first (a run stops at the first target that decides); the others are the files that reach the same path:
# the transparent stand-ins (cleanup, catch, findall), the attvar wakeup (freeze/when/call_residue_vars/'$suspend'),
# the query API, callPortray, the strip functions' callers, clause/2, retractall/1.
TS = ["test/core_lang/test_context_module_swipl.jl"]
TD = ["test/test_type_discipline.jl"]                 # MOD2-FX1 (D-0231)
TC = ["test/core_lang/test_cleanup_swipl.jl"]          # MOD2-H1/H2 (D-0237: row :295)
TK = ["test/core_lang/test_catch_swipl.jl"]
TF = ["test/core_lang/test_findall_swipl.jl"]
TA = ["test/core_lang/test_attvar_wakeup.jl"]          # freeze/when/call_residue_vars, '$suspend', AV3-W4 (FX1's first row)
TQ = ["test/foreign/test_query.jl"]
TW = ["test/core_text/test_write_swipl.jl"]           # callPortray
TP = ["test/core_lang/test_module_path.jl"]            # strip_module/3, the strip functions
TB = ["test/db/test_assert_swipl.jl"]
TL = ["test/db/test_clause_swipl.jl"]
TR = ["test/db/test_retractall_swipl.jl"]
RUN = TS + TC + TK + TF                              # run-loop context paths: every transparent stand-in reaches them
# the standard streams (c36's fix, D-0245): the step's own file first, then every file that reaches initIO or
# restoreStandardStream through a standard stream alias (D-0238)
TSTD = ["test/files/test_open_close_swipl.jl", "test/core_lang/test_blob.jl", "test/core_text/test_write_family_swipl.jl",
        "test/foreign/test_exceptions_swipl.jl", "test/core_lang/test_context_module_swipl.jl",
        "test/core_text/test_read_positions_swipl.jl", "test/core_text/test_canonical_readatom_swipl.jl",
        "test/core_lang/test_write_cells.jl", "test/core_lang/test_numbervars_cells.jl"]
TARGETS = TS + TD + TC + TK + TF + TA + TQ + TW + TP + TB + TL + TR + [t for t in TSTD if t not in TS]   # the baseline's (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
I = "src/pl-incl.jl"
M = "src/pl-modul.jl"
F = "src/pl-fli.jl"
E = "src/pl-ext.jl"
P = "src/pl-proc.jl"
A = "src/pl-attvar.jl"
O = "src/os/pl-file.jl"
MUTANTS = [
    # ── pl-wam.c contextModule, setContextModule ──
    dict(id="MOD2-C1 contextModule ignores FR_CONTEXT: a transparent frame's context is never read (KILL c02, c03, c05, c08, wb)", file=W, targets=RUN,
         old="        (f.flags & FR_CONTEXT) != 0 && return f.context     # ison(fr, FR_CONTEXT)\n",
         new="        nothing\n"),
    dict(id="MOD2-C2 contextModule ignores P_TRANSPARENT: a transparent frame answers its predicate's module (KILL c01: system, c10, c31, c32)", file=W, targets=RUN,
         old="        (def.flags & P_TRANSPARENT) == 0 && return def.module_  # isoff(fr->predicate, P_TRANSPARENT)\n",
         new="        return def.module_\n"),
    dict(id="MOD2-C3 setContextModule! does not set FR_CONTEXT (KILL c02, c03, c07, wb)", file=W, targets=RUN,
         old="    fr.flags |= FR_CONTEXT                          # setLocal(fr, FR_CONTEXT)\n",
         new="    nothing\n"),
    # ── pl-vmi.c I_DEPART ──
    dict(id="MOD2-D1 I_DEPART's transparent branch never taken (KILL c06: user)", file=W, targets=RUN,
         old="        if (DEF.flags & P_TRANSPARENT) != 0         # ison(DEF, P_TRANSPARENT)\n            id_f.context = contextModule(gd, ld, FR)    # FR->context = contextModule(FR)\n",
         new="        if false\n            id_f.context = contextModule(gd, ld, FR)    # FR->context = contextModule(FR)\n"),
    dict(id="MOD2-D2 design H4: I_DEPART reads the context AFTER setFramePredicate (KILL c06: the walk passes the frame)", file=W, targets=RUN,
         old="            id_f.context = contextModule(gd, ld, FR)    # FR->context = contextModule(FR)\n",
         new="            setFramePredicate(id_f, DEF)\n            id_f.context = contextModule(gd, ld, FR)    # FR->context = contextModule(FR)\n"),
    # ── pl-vmi.c I_LCALL ──
    dict(id="MOD2-L1 I_LCALL's transparent branch never taken (KILL c05, c28: user)", file=W, targets=RUN,
         old="    if (DEF.flags & P_TRANSPARENT) != 0             # ison(DEF, P_TRANSPARENT)\n        il_f.context = il_ctx0                      # FR->context = ctx0\n",
         new="    if false\n        il_f.context = il_ctx0                      # FR->context = ctx0\n"),
    dict(id="MOD2-L2 design H4: I_LCALL reads ctx0 AFTER the predicate is replaced (KILL c05)", file=W, targets=RUN,
         old="    il_ctx0 = contextModule(gd, ld, FR)             # Module ctx0 = contextModule(FR)\n    il_f = ld.frames[FR]\n",
         new="    il_f = ld.frames[FR]\n    setFramePredicate(il_f, il_proc.definition)\n    il_ctx0 = contextModule(gd, ld, FR)             # Module ctx0 = contextModule(FR)\n"),
    # ── pl-incl.h lcoSetNextFrameFlags (design H5) ──
    dict(id="MOD2-K1 design H5: a last call keeps FR_CONTEXT into a non-transparent predicate (KILL c29: m2)", file=I, targets=RUN,
         old="    next.flags = fr.flags & ~(FR_LCO_CLEAR | FR_CLEAR_ALWAYS)\n",
         new="    next.flags = fr.flags & ~(FR_LCO_CLEAR | FR_DETGUARD_SET)\n"),
    # ── pl-vmi.c mcall_cont, pl-comp.c compileClause (goal clause) ──
    dict(id="MOD2-M1 mcall_cont does not set a transparent predicate's context (KILL c02, c03)", file=W, targets=RUN,
         old="    if (DEF.flags & P_TRANSPARENT) != 0             # ison(DEF, P_TRANSPARENT)\n        setContextModule!(ld.frames[NFR], mc_mi)    # setContextModule(NFR, module)\n",
         new="    if false\n        setContextModule!(ld.frames[NFR], mc_mi)    # setContextModule(NFR, module)\n"),
    dict(id="MOD2-G1 the goal clause's frame gets no context (KILL c07: system)", file=W, targets=RUN,
         old="    setContextModule!(mc_f2, mc_mi)                 # setContextModule(fr, module)\n",
         new="    nothing\n"),
    # ── pl-wam.c PL_open_query ──
    dict(id="MOD2-Q1 PL_open_query ignores ctx (KILL c08, wb m2:context_module)", file=W, targets=TS + TQ,
         old="        if ctx !== nothing\n            setContextModule!(f, ctx.index)\n",
         new="        if false\n            setContextModule!(f, ctx.index)\n"),
    dict(id="MOD2-Q3 PL_open_query's saved-environment branch gives user (KILL c36: portray/1 under write_term/3 from m2)", file=W, targets=TS + TW,
         old="            setContextModule!(f, contextModule(gd, ld, q.saved_environment))\n",
         new="            setContextModule!(f, MODULE_user(gd).index)\n"),
    dict(id="MOD2-B4 findall/4's INTERIM qualification dropped: findall_loop/4 calls the goal in system (KILL c18, c19, c30)", file=E, targets=TS + TF,
         old="                _boot_mqual(T, q[4], Goal, q[1:3]),     # INTERIM: S_MQUAL (MOD4)\n                _boot_term(\n                    :cleanup_bag,",
         new="                _boot_term(:(=), T[Goal, q[4]]),\n                _boot_term(\n                    :cleanup_bag,"),
    dict(id="MOD2-Q2 PL_open_query's last branch gives system, not user (KILL wb: the frame's context)", file=W, targets=TS + TQ,
         old="            setContextModule!(f, MODULE_user(gd).index)\n",
         new="            setContextModule!(f, MODULE_system(gd).index)\n"),
    # ── pl-wam.c callCleanupHandler / call_term ──
    # H1/H2 target test_cleanup_swipl.jl too (D-0237): the early battery (run 40927313858, targets TS only) left H2 alive —
    # in every cleanup of c01-c42 the handler's environment frame has the cleanup frame's context (h2_probe.txt) — but
    # with the wrap deleted test_cleanup_swipl.jl:295 fails on all three term types: there the query's goal IS the
    # cleanup frame, so the handler's environment is the query's system frame while contextModule(fr) is user.
    dict(id="MOD2-H1 the handler's INTERIM qualification uses user, not contextModule(fr) (KILL c08: existence error of user:tpt; c35)", file=W, targets=TS + TC,
         old="                ccm = contextModule(gd, ld, fr)\n",
         new="                ccm = MODULE_user(gd).index\n"),
    dict(id="MOD2-H2 no INTERIM qualification: call_term's verbatim stripModule takes the environment frame's context (D-0212 item 3; KILL test_cleanup_swipl.jl:295: the query's goal is the cleanup frame, the handler's environment the query's system frame, so log/1 is looked up in system — existence_error vs swipl's logs(q(!)); c35/c39-c42 cannot kill it, D-0233 probe)", file=W, targets=TS + TC,
         old="    _is_colon2_word(ld, k, w) && return nothing                     # is_qualified(p): as it is\n    colon2 = lookupFunctorDef(",
         new="    return nothing\n    colon2 = lookupFunctorDef("),
    dict(id="MOD2-S1 stripModule_cells: an unqualified goal gets user, not the environment frame's context (KILL c20, c22, c27)", file=M, targets=RUN + TP,
         old="        elseif ld.environment_frame != 0            # environment_frame ? contextModule(…) : MODULE_user\n",
         new="        elseif false\n"),
    dict(id="MOD2-S2 PL_strip_module: an unqualified term gets user (KILL c11, c17)", file=F, targets=TS + TP + TB,
         old="        m = if ld.environment_frame != 0\n            contextModule(gd, ld, ld.environment_frame)\n        else\n            MODULE_user(gd).index\n        end\n    end\n    raw != plain",
         new="        m = MODULE_user(gd).index\n    end\n    raw != plain"),
    dict(id="MOD2-S3 PL_strip_module_ex: an unqualified term gets user (KILL c15, c16)", file=F, targets=TS + TP + TB,
         old="        m = if ld.environment_frame != 0\n            contextModule(gd, ld, ld.environment_frame)\n        else\n            MODULE_user(gd).index\n        end\n    end\n    _slot_link_loc!",
         new="        m = MODULE_user(gd).index\n    end\n    _slot_link_loc!"),
    dict(id="MOD2-F1 get_procedure_find: an unqualified head is looked up in user (KILL c34)", file=P, targets=TS + TL,
         old="    elseif ld.environment_frame != 0                    # environment_frame ? contextModule(…) : user\n",
         new="    elseif false\n"),
    dict(id="MOD2-U1 '$suspend'/3 qualifies with user (KILL c33)", file=A, targets=TS + TA,
         old="            ld, gd.modules[contextModule(gd, ld, ld.environment_frame)].atom\n        )",
         new="            ld, mk_sym(T, :user)\n        )"),
    # ── registration: strip_module/3, context_module/1, retractall/1 ──
    dict(id="MOD2-P1 strip_module/3 not transparent: its own (system) frame answers (KILL c10, c11)", file=M, targets=TS + TP,
         old='    PL_extension("strip_module", 3, pl_strip_module3_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),\n',
         new='    PL_extension("strip_module", 3, pl_strip_module3_va, PL_FA_VARARGS),\n'),
    dict(id="MOD2-P2 context_module/1 not transparent (KILL c01: system)", file=E, targets=TS,
         old='    PL_extension("context_module", 1, pl_context_module, PL_FA_TRANSPARENT),   # META (MOD2)\n',
         new='    PL_extension("context_module", 1, pl_context_module, 0x00),\n'),
    dict(id="MOD2-R1 retractall/1 not made transparent (pl-ext.c:397) (KILL c17: [1])", file=E, targets=TS + TR,
         old='        ("assert", 1), ("asserta", 1), ("assertz", 1), ("retract", 1), ("retractall", 1),\n',
         new='        ("assert", 1), ("asserta", 1), ("assertz", 1), ("retract", 1),\n'),
    # ── the stand-ins (pl-ext.jl) ──
    dict(id="MOD2-B1 no stand-in made transparent (KILL c18-c21, c23, c25-c27, c30)", file=E, targets=RUN + TA,
         old="    _boot_transparent!(gd)                          # INTERIM: S_MQUAL (MOD4)\n",
         new="    nothing\n"),
    dict(id="MOD2-B2 catch/3 not transparent: its goal and recovery run in system (KILL c20, c21)", file=E, targets=TS + TK,
         old='        ("call", 7), ("call", 8), ("catch", 3), ("setup_call_cleanup", 3),',
         new='        ("call", 7), ("call", 8), ("setup_call_cleanup", 3),'),
    dict(id="MOD2-B3 the stand-ins qualify with user, not the context module (KILL c18, c23, c24, c25, c26, c30)", file=E, targets=TS + TA,
         old="            _boot_term(:(=), T[g, _boot_term(colon, T[v[3], g0])])\n",
         new="            _boot_term(:(=), T[g, _boot_term(colon, T[mk_sym(T, :user), g0])])\n"),
    # ── the stacked fix before MOD2 (D-0231): the V9d condition slot is a tagged word, not a term ──
    dict(id="MOD2-FX1 D-0231: C_IFTHENELSE writes its slot as mk_gnd(T, ::Int64) again (KILL test_type_discipline: the D-0231 rows on Term{Union{BigInt, Float64, String}} — MethodError; EQUIVALENT on the reference type, the same word)", file=W, targets=TD + TA,
         old="    @label C_IFTHENELSE\n    ld.slots[varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1] = consInt(\n        ld.choices[ld.BFR].base\n    )                                               # == C_IFTHEN\n",
         new="    @label C_IFTHENELSE\n    setSlotValue!(ld, varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1, mk_gnd(T, ld.choices[ld.BFR].base))\n"),
    # ── the standard streams (c36's fix, D-0245): pl-stream.c S__iob0's file descriptor whatever Base.stdX is ──
    dict(id="MOD2-ST1 _std_io always takes the file descriptor: a holdable Base.stdX is not the stream's own IO (KILL test_open_close_swipl.jl: s.handle.io === io)", file=O, targets=TSTD,
         old="    io isa Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint} && return io\n    return fdio(fd, false)\n",
         new="    return fdio(fd, false)\n"),
    dict(id="MOD2-ST2 _std_io's fallback gives no IO: an unholdable Base.stdX leaves no standard stream (KILL test_open_close_swipl.jl: the IOContext stderr rows)", file=O, targets=TSTD,
         old="    return fdio(fd, false)\n",
         new="    return nothing\n"),
    dict(id="MOD2-ST3 initIO's user_error over file descriptor 1 (KILL test_open_close_swipl.jl: user_error is <fd 2>)", file=O, targets=TSTD,
         old="    serr = _std_stream(\n        _std_io(Base.stderr, 2), ",
         new="    serr = _std_stream(\n        _std_io(Base.stderr, 1), "),
    dict(id="MOD2-ST4 restoreStandardStream wraps Base.stderr itself again (KILL test_open_close_swipl.jl: restoreStandardStream under an IOContext stderr)", file=O, targets=TSTD,
         old="        _std_stream(_std_io(Base.stderr, 2), SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU)\n    else",
         new="        _std_stream(Base.stderr, SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU)\n    else"),
]
