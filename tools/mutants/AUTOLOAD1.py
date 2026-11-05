# ORIGINAL: AUTOLOAD1's mutant list — no swipl-devel counterpart.
# tools/mutants/AUTOLOAD1.py — the mutation battery of AUTOLOAD1 (A1: trapUndefined / getProcDefinedDefinition take `ld`, mcall_cont
# makes upstream's frame set-up, pl-vmi.c:5707-5722; A4: the `autoload` flag setter, propagateAutoload, PL_set_prolog_flag, the boot
# pair of compileFileList, pl-prologflag.c:928-1000 and :1681, pl-qlf.c:4798/4808; Q3: the loud error for an undefined predicate in
# the boot session, pl-proc.c:3051-3053, audit D-0387 item 3). Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as HF1.py and MOD3a2.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Verdicts: written by the battery, not yet run.
# KILL: the A4 and Q3 mutants by test/core_lang/test_autoload_flag_swipl.jl (rows af01-af25 and its LK-ONLY testsets: the mask bit after
# each value, PL_set_prolog_flag, the existence error for `$autoload:set_autoload/1` with the boot session off, the Q3 error with it on)
# and test/files/test_qlf_swipl.jl (the compileFileList rows read the flag back). The boot-session Q3 error is killed by test/core_lang/test_autoload_trap.jl's `bootsession` row (LB4 b2: the boot session
# is the template's alone, so test_qlf_swipl.jl's boot_from_source! row could not hold on a copy of it) and by test_autoload_flag_swipl.jl's Q3 testset (:359).
# The A1 mutants by any test that meta-calls an undefined predicate: mcall_cont's undefined branch runs `trapUndefined` between
# `FR = NFR` and the restore, and `normal_call` (pl-wam.jl:3324) reads `FR` as the new frame's parent.
# A1c (the `ld.environment_frame = FR` line, src/pl-wam.jl:3735) is a DEFERRED KILL, owner AUTOLOAD1 A5 (audit D-0400 item 2), declared through
# the `equivalent` field so that the battery expects it to SURVIVE (run 41741989891 at 95331639: survived in 296 s; re-run CI-way on the
# staged tree: "EQUIVALENT (declared)"). Why no test can see it before A5: `_save_registers!` (src/pl-wam.jl:1622) saves the LOCAL `FR`, not
# environment_frame; trapUndefined/autoImport/getUnknownModule/createUndefSupervisor take no frame; the Q3 error unwinds with
# environment_frame 0 (measured); `normal_call` sets it again (src/pl-wam.jl:3337). Its only reader is the Prolog query of the autoloader
# (PL_open_query, src/pl-wam.jl:1987: the parent frame, `saved_environment`), which runs the hook, undefined until A5 (A3 guard). No Julia
# stand-in hook is allowed. AT A5 the declaration goes and a row asserting the query's parent frame (prolog_current_frame inside the hook)
# replaces it (refusal-flip rule D-0376).
# A1a's TARGETS start with test_export_import_swipl.jl: with the frame its own parent targets loop until LIMIT_S (inferred from 4796 s =
# 3 x 1500 s + ~300 s in run 41741989891, against 150-300 s for the others: three hung) before test_export_import_swipl.jl:397 fails; `run_targets` stops at the first
# deciding target, so the failing one goes first.
# NOT LISTED (each with its reason):
#   * (A3 moved the mcall_cont `setLTop!` line into the list as AUTOLOAD1-A1e: its killer is the A1 row of test_autoload_trap.jl, a hook run
#     through `call(user:foo)`.)
#   * `setGenerationFrame` and `programPointer` of the same block: normal_call sets the same fields again before any use (pl-wam.jl:3326-3328).
#   * A3's `cid == 0` early return of `autoLoader` (pl-proc.c: `!(cid = PL_open_foreign_frame())`): PL_open_foreign_frame never returns 0 in the
#     kernel (it grows the local stack or raises a Julia error), so the branch is dead code here, kept as upstream has it.
#   * A3's guard order (the hook lookup BEFORE the foreign frame and the nesting push, against after them): both orders give the same answers
#     and the same final state (the frame, the context and the nesting are restored); only the cost differs.
#   * A3's `lookupProcedure(...)` refresh when the definition did not change: equivalent unless the hook relinks the module's procedure,
#     which AUTOLOAD1-A3i's row does (a hook that defines `fi` in system and calls `user:fi`).
#   * compileFileList's flag value of `PL_set_prolog_flag(... FT_BOOL)`: the existing atom flag ignores the creation type, so FT_BOOL
#     against FT_ATOM has no observable effect.
# TARGETS (audit D-0238, D-0388 item 2): each mutant lists every test file that exercises its mutated code, and every file listed holds
# a @testset (checked with `grep -L '@testset\|@test'`; no helper file such as rules_common.jl). A1: test_module_path.jl (trapUndefined
# called directly) plus MOD3a2.py's TMC (mcall_cont through the meta-call) and RUN lists plus the rule, assertion and type-test files that
# call an undefined predicate through call/N. A4: the setter's own file, test_set_flag_swipl.jl and test_push_flag_swipl.jl (push/pop
# go through set_flag_value; the `_SF_REFUSED`/`_PF_REFUSED` pins were dropped), test_prolog_flag_swipl.jl (the flag's mask bit is set by
# hand there and its key set is listed), test_qlf_swipl.jl (compileFileList). Q3: test_autoload_trap.jl and test_autoload_flag_swipl.jl (test_qlf_swipl.jl stays in the list); test_source_file_swipl.jl
# sets `bootsession` and runs no query (Q3-safe) so it is not a target.
# A3: every A3 mutant lists TA3 (test_autoload_trap.jl, the A1 files, the flag file, the qlf file): every file that reaches an undefined
# predicate with the autoload flag on. The hook is the test's own (clauses compiled into `system`), no Julia stand-in.
# The `old` strings were counted EXACTLY once in their file at the commit that adds this list (a text count, no Julia);
# RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TAF = "test/core_lang/test_autoload_flag_swipl.jl"
TQLF = "test/files/test_qlf_swipl.jl"
TSF = "test/core_lang/test_set_flag_swipl.jl"
TPF = "test/core_lang/test_push_flag_swipl.jl"
TPL = "test/core_lang/test_prolog_flag_swipl.jl"
TMP = "test/core_lang/test_module_path.jl"
TMC = ["test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_catch_swipl.jl", "test/core_lang/test_findall_swipl.jl",
       "test/core_lang/test_metacall_control.jl"]      # mcall_cont through i_metacall_common (as MOD3a2.py)
TRUN = ["test/core_lang/test_colon_body_swipl.jl", "test/core_lang/test_context_module_swipl.jl",
        "test/core_lang/test_attvar_wakeup.jl"]         # I_CALLM / I_DEPARTM into mcall_cont (as MOD3a2.py)
TCALL = ["test/core_lang/test_rules_swipl.jl", "test/db/test_assert_swipl.jl", "test/foreign/test_builtins_swipl.jl",
         "test/foreign/test_typetests_swipl.jl", "test/core_lang/test_export_import_swipl.jl"]   # call/N of undefined predicates
TA1 = [TMP] + TMC + TRUN + TCALL
TA1A = [TCALL[-1]] + [t for t in TA1 if t != TCALL[-1]]    # A1a: the fast failing target first (see the header)
TA4 = [TAF, TSF, TPF, TPL, TQLF]
TQ3 = [TQLF, TAF]
TAT = "test/core_lang/test_autoload_trap.jl"
TA3 = [TAT] + TA1 + [TAF, TQLF]      # A3: every file that reaches an undefined predicate (D-0238)
TARGETS = TA3 + TA4 + ["test/test_type_discipline.jl"]       # the baseline's targets (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
P = "src/os/pl-prologflag.jl"
Q = "src/pl-qlf.jl"
PR = "src/pl-proc.jl"
MUTANTS = [
    # ── pl-vmi.c mcall_cont (A1): the frame set-up around trapUndefined ──
    dict(id="AUTOLOAD1-A1a mcall_cont does not restore FR after trapUndefined: normal_call makes the new frame its own parent (KILL any meta-call of an undefined predicate)",
         file=W, targets=TA1A,
         old="        FR = ld.frames[FR].parent                   # FR = FR->parent\n",
         new="        nothing\n"),
    dict(id="AUTOLOAD1-A1b mcall_cont does not set the new frame's parent (NFR->parent = FR): the restore reads a stale parent (KILL test_autoload_trap.jl 'A1b\'s killer': every pooled frame record's parent is poisoned to 999999 before the call, the restore then returns into a frame no stack has; a BoundsError instead of the answer t(7))",
         file=W, targets=[TAT] + TA1,
         old="        mc_nf.parent = FR                           # NFR->parent = FR\n",
         new="        nothing\n"),
    dict(id="AUTOLOAD1-A1c mcall_cont does not set `ld.environment_frame` to the new frame (DEFERRED KILL, owner AUTOLOAD1 A5; audit D-0400 item 2)",
         file=W, targets=TA1,
         equivalent="DEFERRED KILL, owner AUTOLOAD1 A5: the Prolog query inside trapUndefined is the only reader of environment_frame in this window (src/pl-wam.jl:3735); the hook is undefined until A5 (A3 guard)",
         old="        FR = NFR                                    # environment_frame = FR = NFR\n        ld.environment_frame = FR\n",
         new="        FR = NFR                                    # environment_frame = FR = NFR\n"),
    dict(id="AUTOLOAD1-A1d mcall_cont leaves FR at the caller's frame when it sets the environment frame (FR = NFR dropped, environment_frame set to the caller) (KILL as A1a)",
         file=W, targets=TA1,
         old="        FR = NFR                                    # environment_frame = FR = NFR\n        ld.environment_frame = FR\n",
         new="        ld.environment_frame = FR\n"),
    # ── pl-prologflag.c setAutoload (A4) ──
    dict(id="AUTOLOAD1-A4a setAutoload leaves the mask bit set for `false` (KILL af01 and the mask-bit testset)",
         file=P, targets=TA4,
         old="        clearPrologFlagMask!(ld, PLFLAG_AUTOLOAD)\n",
         new="        nothing\n"),
    dict(id="AUTOLOAD1-A4b setAutoload accepts any atom: no domain_error(autoload, A) (KILL the domain_error row of test_autoload_flag_swipl.jl)",
         file=P, targets=TA4,
         old="        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :autoload), _flag_atom_ref(ld, a))\n",
         new="        return true\n"),
    dict(id="AUTOLOAD1-A4c setAutoload refuses `user` (KILL the `user` row of test_autoload_flag_swipl.jl)",
         file=P, targets=TA4,
         old="        k == sym_key(mk_sym(T, :user)) ||\n",
         new=""),
    dict(id="AUTOLOAD1-A4d set_flag_value ignores setAutoload's failure: a bad value is stored (KILL the 'bad value leaves the flag unchanged' rows)",
         file=P, targets=TA4,
         old="            setAutoload(ld, a) || return false\n",
         new="            setAutoload(ld, a)\n"),
    # ── pl-prologflag.c propagateAutoload, set_prolog_flag_ptr (A4) ──
    dict(id="AUTOLOAD1-A4e propagateAutoload runs inside the boot session: the existence error for $autoload:set_autoload/1 reaches every row (KILL test_autoload_flag_swipl.jl rows, compileFileList rows of test_qlf_swipl.jl)",
         file=P, targets=TA4,
         old="    gd.bootsession && return true\n",
         new="    false && return true\n"),
    dict(id="AUTOLOAD1-A4f set_prolog_flag_ptr does not propagate the autoload flag (KILL the LK-ONLY testset: set_prolog_flag(autoload, false) with the boot session off raises the existence error)",
         file=P, targets=TA4,
         old="    sym_key(k) == sym_key(mk_sym(T, :autoload)) &&\n        !propagateAutoload(gd, ld, value) &&\n        return nothing\n",
         new=""),
    # ── pl-fli.c PL_set_prolog_flag, pl-qlf.c compileFileList (A4) ──
    dict(id="AUTOLOAD1-A4g PL_set_prolog_flag puts false for a true value (KILL the PL_set_prolog_flag white-box row, the compileFileList flag-after rows)",
         file=P, targets=TA4,
         old='mk_sym(T, Symbol(val ? "true" : "false")))     # PL_put_bool\n',
         new='mk_sym(T, Symbol("false")))     # PL_put_bool\n'),
    dict(id="AUTOLOAD1-A4h compileFileList leaves autoload false after the files (pl-qlf.c:4808) (KILL test_qlf_swipl.jl: the flag read back after the call is true)",
         file=Q, targets=[TQLF, TAF],
         old='    PL_set_prolog_flag(gd, ld, "autoload", true)\n',
         new='    PL_set_prolog_flag(gd, ld, "autoload", false)\n'),
    dict(id="AUTOLOAD1-A4i compileFileList compiles with autoload on (pl-qlf.c:4798) (KILL test_qlf_swipl.jl: r(autoload_off) is never asserted)",
         file=Q, targets=[TQLF],
         old='    PL_set_prolog_flag(gd, ld, "autoload", false)\n',
         new='    PL_set_prolog_flag(gd, ld, "autoload", true)\n'),
    # ── pl-proc.c trapUndefined (Q3) ──
    # ── pl-wam.c / pl-vmi.c mcall_cont (A1, killed since A3): lTop above the arguments while the autoloader's query runs ──
    dict(id="AUTOLOAD1-A1e mcall_cont does not set lTop above the new frame's arguments: the hook's query frame overwrites the caller's frame (KILL the A1 row of test_autoload_trap.jl: call(user:foo) with a hook, then the caller's variables)",
         file=W, targets=[TAT] + TMC + TRUN,
         old="        setLTop!(ld, argFrameP(mc_nf.base, DEF.arity))  # lTop = argFrameP(NFR, arity)\n",
         new="        nothing\n"),
    # ── pl-proc.c autoLoader, test_autoload_loop, trapUndefined (A3) ──
    dict(id="AUTOLOAD1-A3a autoLoader creates the hook and drops the defined test (upstream's PL_pred, the Prolog half assumed loaded): an unbooted database queries an undefined hook (KILL test_module_path.jl's S_UNDEF rows and the guard row of test_autoload_trap.jl)",
         file=PR, targets=TA3,
         old="    (hook === nothing || !isDefinedProcedure(gd, hook)) && return answer\n",
         new='    hook === nothing && (hook = lookupProcedure(mk_sym(T, Symbol("\\$undefined_procedure")), 4, MODULE_system(gd)))\n'),
    dict(id="AUTOLOAD1-A3b the autoloader also runs in the boot session (!gd.bootsession -> true) (KILL the boot-session row: the Q3 error, hook not called)",
         file=PR, targets=TA3,
         old="PLFLAG_AUTOLOAD) && !gd.bootsession",
         new="PLFLAG_AUTOLOAD) && true"),
    dict(id="AUTOLOAD1-A3c the autoloader ignores the autoload flag (KILL the flag-false row: the hook is called)",
         file=PR, targets=TA3,
         old="truePrologFlag(ld, PLFLAG_AUTOLOAD) && !gd.bootsession",
         new="!gd.bootsession"),
    dict(id="AUTOLOAD1-A3d the answer `fail` does not return (it falls to the error label: S_UNDEF) (KILL the fail row: the supervisor stays S_VIRGIN)",
         file=PR, targets=TA3,
         old="                key == sym_key(mk_sym(T, :fail)) && return def\n",
         new="                nothing\n"),
    dict(id="AUTOLOAD1-A3e the retry warns on the FIRST retry (retry_times != 0 -> == 0) (KILL the defining-retry row: a message appears) ",
         file=PR, targets=TA3,
         old="if retry_times != 0 ",
         new="if retry_times == 0 "),
    dict(id="AUTOLOAD1-A3f the retry warns only on the third retry (retry_times != 0 -> > 1) (KILL the non-defining retry row: the hook ran three times)",
         file=PR, targets=TA3,
         old="if retry_times != 0 ",
         new="if retry_times > 1 "),
    dict(id="AUTOLOAD1-A3g test_autoload_loop never finds a loop (KILL the loop rows: returns true, the hook is called)",
         file=PR, targets=TA3,
         old="        if nesting[i] === def\n",
         new="        if false && nesting[i] === def\n"),
    dict(id="AUTOLOAD1-A3h test_autoload_loop does not record `autoload_loop` (KILL the loop row: autoload_loop === def)",
         file=PR, targets=TA3,
         old="            ld.autoload_loop = def\n",
         new="            nothing\n"),
    dict(id="AUTOLOAD1-A3i the definition is not refreshed after the autoloader (KILL the refresh row: the stale definition is returned)",
         file=PR, targets=TA3,
         old="            def = lookupProcedure(name, arity, m).definition        # lookupDefinition(functor, module)\n",
         new="            nothing\n"),
    dict(id="AUTOLOAD1-A3j the autoloader's query does not pass the exception on (PL_Q_PASS_EXCEPTION dropped) (KILL the raising-hook row: the ball is not pending)",
         file=PR, targets=TA3,
         old="PL_Q_NODEBUG | PL_Q_PASS_EXCEPTION, hook, argv\n",
         new="PL_Q_NODEBUG, hook, argv\n"),
    dict(id="AUTOLOAD1-A3k the hook gets the predicate's name as its module (KILL every hook row: the head (user, Name, Arity, A) does not match)",
         file=PR, targets=TA3,
         old="    PL_put_atom(ld, argv, gd.modules[def.module_].atom)\n",
         new="    PL_put_atom(ld, argv, def.name)\n"),
    dict(id="AUTOLOAD1-A3l the hook gets the module as the predicate's name (KILL every hook row)",
         file=PR, targets=TA3,
         old="    PL_put_atom(ld, argv + 1, def.name)\n",
         new="    PL_put_atom(ld, argv + 1, gd.modules[def.module_].atom)\n"),
    dict(id="AUTOLOAD1-A3m the hook always gets arity 0 (KILL the ar/2 row)",
         file=PR, targets=TA3,
         old="    PL_put_integer(ld, argv + 2, def.arity)\n",
         new="    PL_put_integer(ld, argv + 2, 0)\n"),
    dict(id="AUTOLOAD1-A3n the autoloader does not push `def` on the nesting (pop! then raises on the empty chain) (KILL the restored-chain rows)",
         file=PR, targets=TA3,
         old="    push!(ld.autoload_nesting, def)\n",
         new="    nothing\n"),
    dict(id="AUTOLOAD1-A3o the autoloader does not pop the nesting (KILL the restored-chain rows: the chain is not empty)",
         file=PR, targets=TA3,
         old="    pop!(ld.autoload_nesting)\n",
         new="    nothing\n"),
    dict(id="AUTOLOAD1-A3p the autoloader does not pop the input context (KILL the restored-context rows: input_context_stack grew)",
         file=PR, targets=TA3,
         old="    pop_input_context(ld)\n",
         new="    nothing\n"),
    dict(id="AUTOLOAD1-A3q the autoloader does not discard its foreign frame (KILL the restored-frame row: fli_context grew)",
         file=PR, targets=TA3,
         old="    PL_discard_foreign_frame(ld, cid)\n    return answer\n",
         new="    return answer\n"),
    dict(id="AUTOLOAD1-A3r trapUndefined calls the autoloader even inside a loop (the loop test's result ignored) (KILL the loop row: the hook is called)",
         file=PR, targets=TA3,
         old="            test_autoload_loop(gd, ld, def) || return def\n",
         new="            test_autoload_loop(gd, ld, def)\n"),
    dict(id="AUTOLOAD1-Q3a trapUndefined does not raise in the boot session: createUndefSupervisor as before (KILL test_autoload_trap.jl 'the autoload flag false and the boot session' testset: `err isa ErrorException`; the Q3 testset of test_autoload_flag_swipl.jl)",
         file=PR, targets=[TAT] + TQ3,
         old="    if gd.bootsession ",
         new="    if false && gd.bootsession "),
]
