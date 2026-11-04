# ORIGINAL: CT1a's mutant list (setlocale/3 of pl-ctype.c); its counterpart is the port itself.
# tools/mutants/CT1A.py — the mutation battery of CT1a (setlocale/3: pl-ctype.c lccats and PRED_IMPL setlocale, the
# Latin-1 text of PL_get_chars, libc's setlocale through ccall), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY
# once), `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_setlocale_swipl.jl (rows t0-t31 of
# test_setlocale_swipl.pl, named in each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in its file at wip/ct1a f311b021 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * the guards `what === nothing && return FFALSE` and `locale === nothing && return FFALSE` after _ctype_chars: with
#     one gone the predicate goes on with an exception already pending and answers true or false by the code after it;
#     what the engine then does with a pending exception and a truth value is the engine's, not this port's, so a
#     verdict would test the VM, not setlocale/3.
#   * pl-sys.jl `PL_error(ld, "", 0, MSG_ERRNO, ERR_SYSCALL, "setlocale", e)`: the operation name and `e` of the
#     system_error branch reach only the context message; row t24 pins it, but libc's answer for a 5000-character name
#     is the host's (EINVAL on the glibc 2.39 of the pins), so a mutant on it is a mutant of the host.
#   * LC_COLLATE/LC_MONETARY/LC_NUMERIC/LC_TIME values: the rows set one name on a category and read it back from the
#     same category; two categories swapped (3 and 4, say) answer alike (the values are <locale.h>'s, a constant table).
# TARGETS (audit D-0238): setlocale/3 is called by test_setlocale_swipl.jl only (git grep setlocale test/); the
# registration test test/foreign/test_builtins_swipl.jl walks `_FOREIGN_VA` through its `_B_FIRST` names, a list of other predicates.
TS = ["test/core_lang/test_setlocale_swipl.jl"]
TARGETS = TS
S = "src/pl-sys.jl"
C = "src/os/pl-ctype.jl"
MUTANTS = [
    # ── pl-ctype.c PRED_IMPL setlocale ──
    dict(id="CT1a-A1 the set is done when Old equals New, not when it differs: nothing is set (KILL t5, t6, t7, t9)",
         file=S, targets=TS,
         old="if rc != CMP_EQUAL",
         new="if rc == CMP_EQUAL"),
    dict(id="CT1a-A2 Old is compared with itself: New is never set (KILL t5, t6, t7, t8, t9, t12)",
         file=S, targets=TS,
         old="PL_compare(ld, A2, A3)",
         new="PL_compare(ld, A2, A2)"),
    dict(id="CT1a-A3 ENOENT answers system_error and any other errno existence_error (KILL t15, t21, t22, t23, t24)",
         file=S, targets=TS,
         old="if e == ENOENT",
         new="if e != ENOENT"),
    dict(id="CT1a-A4 libc's errno is dropped: a missing locale answers system_error (KILL t15, t21, t22, t23)",
         file=S, targets=TS,
         old="p == C_NULL && return (nothing, e)",
         new="p == C_NULL && return (nothing, 0)"),
    dict(id="CT1a-A5 an unknown category raises no domain_error: the call fails (KILL t16, t20, t29)",
         file=S, targets=TS,
         old="    PL_domain_error(ld, \"category\", A1)\n",
         new="    nothing\n"),
    dict(id="CT1a-A6 a category is found by prefix, not by its whole name (KILL t16: 'all ', 'ctype\\n')",
         file=S, targets=TS,
         old="if lcp.name == what",
         new="if startswith(what, lcp.name)"),
    dict(id="CT1a-A7 an Old that does not unify no longer fails: New is set anyway (KILL t10, t11)",
         file=S, targets=TS,
         old="PL_unify_atom(ld, A2, mk_sym(T, Symbol(old))) || return FFALSE",
         new="PL_unify_atom(ld, A2, mk_sym(T, Symbol(old)))"),
    dict(id="CT1a-A8 an unbound New is read as a text: instantiation_error instead of the query (KILL t0, t1, t2)",
         file=S, targets=TS,
         old="if !PL_is_variable(ld, A3)",
         new="if true"),
    # ── PL_get_chars: ISO Latin-1, the C string ──
    dict(id="CT1a-B1 the Latin-1 bound is 0xFFFF: the euro sign (0x20AC) is taken as a byte (KILL t28, t30, t31)",
         file=S, targets=TS,
         old="UInt32(c) > 0xff",
         new="UInt32(c) > 0xffff"),
    dict(id="CT1a-B2 the text keeps its first NUL: an embedded NUL reaches libc (KILL t25, t26)",
         file=S, targets=TS,
         old="resize!(b, i - 1)",
         new="resize!(b, i)"),
    # ── pl-ctype.c lccats ──
    dict(id="CT1a-C1 messages is LC_CTYPE: an environment read for messages takes LANG, not LC_MESSAGES (KILL t14)",
         file=C, targets=TS,
         old="lccat(LC_MESSAGES, \"messages\")",
         new="lccat(LC_CTYPE, \"messages\")"),
    dict(id="CT1a-C2 all is LC_CTYPE: the composite name of the process locale is not read (KILL t14)",
         file=C, targets=TS,
         old="lccat(LC_ALL, \"all\")",
         new="lccat(LC_CTYPE, \"all\")"),
    # ── equivalent ──
    dict(id="CT1a-E1 the NULL answer of libc's query is not tested: no category of lccats makes it answer NULL",
         file=S, targets=TS,
         equivalent="src/pl-sys.jl:172 — setlocale(category, NULL) answers the current locale's name for every category of lccats (C11 7.11.1.1), so the guard's branch is dead code",
         old="old === nothing && return FFALSE",
         new="nothing"),
]
