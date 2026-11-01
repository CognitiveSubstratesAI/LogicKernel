# ORIGINAL: F1B's mutant list — no swipl-devel counterpart.
# tools/mutants/F1B.py — the mutation battery of F1b (pl-prologflag.c set_flag_value, set_prolog_flag, create_prolog_flag,
# keep_flag, check_oneof_flag, check_flag_write_access, check_create_flag; the mask migration: pl-comp.c, pl-wam.c reading
# `truePrologFlag`, `determinism_error_flag`), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/core_lang/test_set_flag_swipl.jl (rows sf01-sf89 named in each id's KILL, "refused" = its
# testset of the flags refused by name, "uf" = its user_flags=error testset), test_det_swipl.jl, test_rules_swipl.jl,
# test_exceptions_swipl.jl, test_portable_smallint_swipl.jl, test_body_code_swipl.jl, test_head_unify_swipl.jl.
# Verdicts: written by the battery, not yet run. The `old` strings are written in the repo's formatted style BEFORE
# `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string
# that does not occur exactly once). Every `old` was checked to occur exactly once in the source at wip/f1b (a text count,
# no Julia).
# The older lists D1f.py (D1-95, D1-96; D1g.py carries those two for this gate), MOD3a.py, SSU1.py, V9f.py also run against the
# migrated sites: their batteries run with this one at the gate (their stale anchors were re-fitted in the same stack).
# D-0280 item 5 (finding 3): D1-96 STAYS EQUIVALENT. PLFLAG_ISO is read in src/pl-comp.jl only inside `protected_predicate`
# (pl-comp.jl:3564-3572), so the clause-type argument of D1f.py (the clause type comes from the clause's own flags,
# pl-comp.jl:3786-3790 and :3981) does not depend on the iso or protect_static_code flags that F1b made settable; row sf83 pins the
# unchanged answer (a by-reference SSU clause under iso). D1-95 (protected_predicate true only for P_FOREIGN) is KILLED by
# sf80 (iso on: clause/3 by reference on a static clause is refused), sf81-sf86 (the by-value forms and the controls); its
# `equivalent` is dropped in D1f.py (D-0291 item 2c).
# NOT LISTED (each with its reason):
#   * truePrologFlag(ld, PLFLAG_CHARESCAPE_UNICODE) at pl-write.jl:2223 and :2292: no test row clears the mask bit (the
#     tests of character_escapes_unicode(false) pass the write OPTION), so a mutant there has no kill row. Left to the
#     audit: a row that clears the flag and writes a control character through print/1.
#   * truePrologFlag(ld, PLFLAG_OPTIMISE) at pl-comp.jl:2409 (the refusal of compileArith under optimise): the kill rows
#     are in test_body_code_swipl.jl but not read here by id; not listed until a first battery run names one.
#   * set_flag_value's `if f.index != 0` guard: with the guard `true` the mask shift of index 0 is out of range (an error
#     at the first flag without a bit), an error, not a verdict.
#   * setStreamTypeCheck's and setWriteAttributes's field writes: rows sf41/sf42 read the table value back, not the field
#     (`ld.IO_stream_type_check`, `ld.prolog_flag_write_attributes` have no reader in a test of this step).
#   * S_UNDEF with `unknown` = fail / warning (the undefined-procedure branch of the flag), `var_prefix` read in pl-read.jl
#     (`rd.var_prefix`) and the `print_write_options` flag-table branch: no cheap anchor (each needs a row that sets the flag and
#     then reads the effect through the loader or the writer, which the sf rows do not do); not added in the landing-B gate.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code.
TF = ["test/core_lang/test_set_flag_swipl.jl"]
TP = ["test/core_lang/test_prolog_flag_swipl.jl"]
TCL = ["test/db/test_clause_swipl.jl"]
TDET = ["test/core_lang/test_det_swipl.jl"]
TLCO = ["test/core_lang/test_rules_swipl.jl", "test/foreign/test_exceptions_swipl.jl"]
TOPT = ["test/compile/test_body_code_swipl.jl", "test/core_lang/test_firstvar_swipl.jl", "test/core_lang/test_head_unify_swipl.jl"]
TPORT = ["test/compile/test_portable_smallint_swipl.jl", "test/compile/test_body_code_swipl.jl"]
TARGETS = TF + TP + TCL + TDET + TLCO + TOPT + TPORT
P = "src/os/pl-prologflag.jl"
C = "src/pl-comp.jl"
W = "src/pl-wam.jl"
E = "src/pl-error.jl"
S = "src/pl-string.jl"   # PL_get_int64_ex lives here (main's string step); the F1b copy in pl-error.jl was dropped in the re-stack
MUTANTS = [
    # ── pl-prologflag.c set_flag_value: FT_BOOL ──
    dict(id="F1B-A1 a Boolean flag set true does not set its mask bit (KILL sf30, sf31, sf46, sf47, sf85)", file=P, targets=TF + TLCO + TOPT,
         old="                setPrologFlagMask!(ld, f.index)\n",
         new="                nothing\n"),
    dict(id="F1B-A2 a Boolean flag set false does not clear its mask bit (KILL sf30, sf31, sf46, sf47)", file=P, targets=TF + TLCO + TOPT,
         old="                clearPrologFlagMask!(ld, f.index)\n",
         new="                nothing\n"),
    dict(id="F1B-A3 a Boolean flag keeps its old atom: the table does not follow the mask (KILL sf09, sf30, sf31, sf85)", file=P, targets=TF + TP,
         old="        f.a = mk_sym(T, val ? Symbol(\"true\") : Symbol(\"false\"))\n",
         new="        nothing\n"),
    dict(id="F1B-A4 protect_static_code set false after true is not refused (KILL sf88)", file=P, targets=TF,
         old=" && val == false\n",
         new=" && false\n"),
    dict(id="F1B-A5 the debugger flag `debug` is not refused by name (KILL refused)", file=P, targets=TF,
         old="            _flag_not_ported(k, \"debugmode and tracemode (the debugger)\")\n",
         new="            nothing\n"),
    # ── set_flag_value: FT_ATOM, FT_INTEGER; the validators ──
    dict(id="F1B-B1 an atom flag with a oneof takes any atom (KILL sf54)", file=P, targets=TF,
         old="        check_oneof_flag(ld, f.oneof, a, true) || return false\n",
         new="        nothing\n"),
    dict(id="F1B-B2 check_oneof_flag answers false without the domain_error (KILL sf54)", file=P, targets=TF,
         old="        if error\n            dom = PL_new_term_ref(ld)\n",
         new="        if false\n            dom = PL_new_term_ref(ld)\n"),
    dict(id="F1B-B3 `status` is not an accepted value of on_error and on_warning (KILL sf43, sf44)", file=P, targets=TF,
         old="       k == sym_key(mk_sym(T, :status))\n",
         new="       false\n"),
    dict(id="F1B-B4 an integer flag out of int64 range raises a type_error, not the representation_error (KILL sf61)", file=S, targets=TF,
         old="        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int64_t))\n",
         new="        PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)\n"),
    dict(id="F1B-B5 occurs_check is not stored in the local data (KILL sf39, sf40)", file=P, targets=TF,
         old="        ld.prolog_flag_occurs_check = v\n",
         new="        nothing\n"),
    # ── access and creation ──
    dict(id="F1B-C1 a read-only flag may be written (KILL sf01, sf02, sf51)", file=P, targets=TF + TP,
         old="    if (f.flags & FF_READONLY) != 0 && (flags & FF_FORCE) == 0\n",
         new="    if false\n"),
    dict(id="F1B-C2 keep_flag never keeps: create_prolog_flag with keep(true) overwrites (KILL sf58)", file=P, targets=TF + TP,
         old="    (flags & FF_KEEP) == 0 && return 0\n",
         new="    return 0\n"),
    dict(id="F1B-C3 user_flags=error does not refuse a new key (KILL uf)", file=P, targets=TF,
         old="            return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :prolog_flag), key)\n",
         new="            return true\n"),
    # ── pl-comp.c protected_predicate (D1-95's neighbourhood) ──
    dict(id="F1B-D1 protected_predicate ignores iso (KILL sf80, sf81)", file=C, targets=TF + TCL,
         old="        (protect_static_code || truePrologFlag(ld, PLFLAG_ISO))\n",
         new="        (protect_static_code)\n"),
    dict(id="F1B-D2 protected_predicate ignores protect_static_code (KILL sf86)", file=C, targets=TF + TCL,
         old="        (protect_static_code || truePrologFlag(ld, PLFLAG_ISO))\n",
         new="        (truePrologFlag(ld, PLFLAG_ISO))\n"),
    # ── the mask migration: the readers ──
    dict(id="F1B-E1 determinism_error=silent is read as error (KILL test_det_swipl.jl silent rows)", file=P, targets=TDET,
         old="    k == sym_key(mk_sym(T, :silent)) && return :silent\n",
         new="    k == sym_key(mk_sym(T, :silent)) && return :error\n"),
    dict(id="F1B-E2 determinism_error=warning is read as error (KILL test_det_swipl.jl warning rows)", file=P, targets=TDET,
         old="    k == sym_key(mk_sym(T, :warning)) && return :warning\n",
         new="    k == sym_key(mk_sym(T, :warning)) && return :error\n"),
    dict(id="F1B-E3 the I_DEPART last-call test ignores the flag: LCO stays on (KILL test_rules_swipl.jl, test_exceptions_swipl.jl LCO-off rows)", file=W, targets=TLCO,
         old="        truePrologFlag(ld, PLFLAG_LASTCALL) &&\n",
         new="        true &&\n"),
    dict(id="F1B-E4 the I_DEPARTATM last-call test ignores the flag (KILL test_rules_swipl.jl LCO-off rows)", file=W, targets=TLCO,
         old="        truePrologFlag(ld, PLFLAG_LASTCALL)\n        _assert_frame_above_choice",
         new="        true\n        _assert_frame_above_choice"),
    dict(id="F1B-E5 the portable-VMI small-int test ignores the flag (KILL test_portable_smallint_swipl.jl)", file=C, targets=TPORT,
         old="    if PLMINTAGGEDINT <= i <= PLMAXTAGGEDINT                # isTaggedInt(w)\n        if truePrologFlag(ld, PLFLAG_PORTABLE_VMI)\n",
         new="    if PLMINTAGGEDINT <= i <= PLMAXTAGGEDINT                # isTaggedInt(w)\n        if false\n"),
    dict(id="F1B-E6 optimise does not fold a constant boolean test to I_TRUE/I_FAIL (KILL test_body_code_swipl.jl optimise rows)", file=C, targets=TOPT,
         old="\n    if truePrologFlag(ld, PLFLAG_OPTIMISE)\n        Output_0!(ci, val ? I_TRUE : I_FAIL)",
         new="\n    if false\n        Output_0!(ci, val ? I_TRUE : I_FAIL)"),
    dict(id="F1B-E7 optimise_unify is always on (KILL test_body_code_swipl.jl, test_head_unify_swipl.jl clear rows)", file=C, targets=TOPT,
         old="            truePrologFlag(ld, PLFLAG_OPTIMISE_UNIFY)\n",
         new="            true\n"),
]
