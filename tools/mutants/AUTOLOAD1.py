# ORIGINAL: AUTOLOAD1's mutant list — no swipl-devel counterpart.
# tools/mutants/AUTOLOAD1.py — the mutation battery of AUTOLOAD1 (A1: trapUndefined / getProcDefinedDefinition take `ld`, mcall_cont
# makes upstream's frame set-up, pl-vmi.c:5707-5722; A4: the `autoload` flag setter, propagateAutoload, PL_set_prolog_flag, the boot
# pair of compileFileList, pl-prologflag.c:928-1000 and :1681, pl-qlf.c:4798/4808; Q3: the loud error for an undefined predicate in
# the boot session, pl-proc.c:3051-3053, audit D-0387 item 3). Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as HF1.py and MOD3a2.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Verdicts: written by the battery, not yet run.
# KILL: the A4 and Q3 mutants by test/core_lang/test_autoload_flag_swipl.jl (rows af01-af25 and its LK-ONLY testsets: the mask bit after
# each value, PL_set_prolog_flag, the existence error for `$autoload:set_autoload/1` with the boot session off, the Q3 error with it on)
# and test/files/test_qlf_swipl.jl (the compileFileList rows read the flag back; the boot_from_source! row expects the Q3 error).
# The A1 mutants by any test that meta-calls an undefined predicate: mcall_cont's undefined branch runs `trapUndefined` between
# `FR = NFR` and the restore, and `normal_call` (pl-wam.jl:3324) reads `FR` as the new frame's parent.
# NOT LISTED (each with its reason):
#   * mcall_cont's `setLTop!(ld, argFrameP(mc_nf.base, DEF.arity))` (pl-vmi.c:5719 `lTop = argFrameP(NFR, arity)`): lTop above the
#     arguments matters only while a Prolog query runs inside `trapUndefined`, which A3 (the autoloader) adds; until A3 no test can see
#     it. A3 adds the mutant and its kill row. This is not a declared equivalent: it is unkillable BEFORE A3.
#   * `setGenerationFrame` and `programPointer` of the same block: normal_call sets the same fields again before any use (pl-wam.jl:3326-3328).
#   * compileFileList's flag value of `PL_set_prolog_flag(... FT_BOOL)`: the existing atom flag ignores the creation type, so FT_BOOL
#     against FT_ATOM has no observable effect.
# TARGETS (audit D-0238, D-0388 item 2): each mutant lists every test file that exercises its mutated code, and every file listed holds
# a @testset (checked with `grep -L '@testset\|@test'`; no helper file such as rules_common.jl). A1: test_module_path.jl (trapUndefined
# called directly) plus MOD3a2.py's TMC (mcall_cont through the meta-call) and RUN lists plus the rule, assertion and type-test files that
# call an undefined predicate through call/N. A4: the setter's own file, test_set_flag_swipl.jl and test_push_flag_swipl.jl (push/pop
# go through set_flag_value; the `_SF_REFUSED`/`_PF_REFUSED` pins were dropped), test_prolog_flag_swipl.jl (the flag's mask bit is set by
# hand there and its key set is listed), test_qlf_swipl.jl (compileFileList). Q3: test_qlf_swipl.jl and the new file; test_source_file_swipl.jl
# sets `bootsession` and runs no query (Q3-safe) so it is not a target.
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
TA4 = [TAF, TSF, TPF, TPL, TQLF]
TQ3 = [TQLF, TAF]
TARGETS = TA1 + TA4 + ["test/test_type_discipline.jl"]       # the baseline's targets (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
P = "src/os/pl-prologflag.jl"
Q = "src/pl-qlf.jl"
PR = "src/pl-proc.jl"
MUTANTS = [
    # ── pl-vmi.c mcall_cont (A1): the frame set-up around trapUndefined ──
    dict(id="AUTOLOAD1-A1a mcall_cont does not restore FR after trapUndefined: normal_call makes the new frame its own parent (KILL any meta-call of an undefined predicate)",
         file=W, targets=TA1,
         old="        FR = ld.frames[FR].parent                   # FR = FR->parent\n",
         new="        nothing\n"),
    dict(id="AUTOLOAD1-A1b mcall_cont does not set the new frame's parent (NFR->parent = FR): the restore reads a stale parent (KILL as A1a)",
         file=W, targets=TA1,
         old="        mc_nf.parent = FR                           # NFR->parent = FR\n",
         new="        nothing\n"),
    dict(id="AUTOLOAD1-A1c mcall_cont does not make the new frame the environment frame: the register reload and the restore read the caller's frame (KILL as A1a)",
         file=W, targets=TA1,
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
    dict(id="AUTOLOAD1-Q3a trapUndefined does not raise in the boot session: createUndefSupervisor as before (KILL test_qlf_swipl.jl boot_from_source! row, the Q3 testset of the new file)",
         file=PR, targets=TQ3,
         old="    if gd.bootsession ",
         new="    if false && gd.bootsession "),
]
