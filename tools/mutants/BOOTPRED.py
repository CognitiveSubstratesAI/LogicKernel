# ORIGINAL: BOOTPRED's mutant list — no swipl-devel counterpart.
# tools/mutants/BOOTPRED.py — the mutation battery of BOOTPRED (audit D-0281): `'$garbage_collect'/1` (pl-gc.c
# pl_garbage_collect), thread_self/1 (pl-thread.c pl_thread_self), with_mutex/2 (pl-mutex.c pl_with_mutex) and, in the
# groups written later, the six pl-dict.c predicates. Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_bootpred_swipl.jl (rows bp01-bp26 named in
# each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in its file at the commit that adds this list (a text count, no Julia).
# TARGETS (audit D-0238): test_bootpred_swipl.jl is the only test file that names these predicates (no other test file
# calls thread_self, with_mutex or '$garbage_collect'), so it is the whole list.
TB = ["test/core_lang/test_bootpred_swipl.jl"]
TARGETS = TB
GC = "src/pl-gc.jl"
TH = "src/pl-thread.jl"
MX = "src/pl-mutex.jl"
EXT = "src/pl-ext.jl"
MUTANTS = [
    # ── pl-gc.c pl_garbage_collect ──
    dict(id="BOOTPRED-G1 '$garbage_collect'/1 fails (KILL bp20-bp26)", file=GC, targets=TB,
         old="function pl_garbage_collect(ld::PL_local_data{T}, d::term_t)::foreign_t where {T}\n    return FTRUE\n",
         new="function pl_garbage_collect(ld::PL_local_data{T}, d::term_t)::foreign_t where {T}\n    return FFALSE\n"),
    dict(id="BOOTPRED-G2 '$garbage_collect' registered under another name: '$garbage_collect'(0) is unknown (KILL bp20-bp26)",
         file=EXT, targets=TB,
         old='    PL_extension("\\$garbage_collect", 1, pl_garbage_collect, 0x00),',
         new='    PL_extension("\\$garbage_collectx", 1, pl_garbage_collect, 0x00),'),
    # ── pl-thread.c pl_thread_self ──
    dict(id="BOOTPRED-T1 thread_self/1 answers another atom (KILL bp01, bp02, bp04, bp06-bp08)", file=TH, targets=TB,
         old="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE\n",
         new="    return PL_unify_atom(ld, self, mk_sym(T, :other)) ? FTRUE : FFALSE\n"),
    dict(id="BOOTPRED-T2 thread_self/1 inverts its verdict: the unification result is negated (KILL bp01, bp03)", file=TH, targets=TB,
         old="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE\n",
         new="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FFALSE : FTRUE\n"),
    dict(id="BOOTPRED-T3 thread_self/1 succeeds without unifying (KILL bp03, bp05)", file=TH, targets=TB,
         old="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE\n",
         new="    return FTRUE\n"),
    # ── pl-mutex.c pl_with_mutex ──
    dict(id="BOOTPRED-M1 with_mutex/2 calls the mutex term instead of the goal (KILL bp09-bp16, bp19)", file=MX, targets=TB,
         old="    rval = callProlog(_query_gd(ld), ld, 0, goal, PL_Q_PASS_EXCEPTION)\n",
         new="    rval = callProlog(_query_gd(ld), ld, 0, mutex, PL_Q_PASS_EXCEPTION)\n"),
    dict(id="BOOTPRED-M2 with_mutex/2 does not pass the goal's exception on (KILL bp12, bp18)", file=MX, targets=TB,
         old="    rval = callProlog(_query_gd(ld), ld, 0, goal, PL_Q_PASS_EXCEPTION)\n",
         new="    rval = callProlog(_query_gd(ld), ld, 0, goal, 0)\n"),
    dict(id="BOOTPRED-M3 with_mutex/2 always succeeds (KILL bp11, bp15)", file=MX, targets=TB,
         old="    return rval ? FTRUE : FFALSE\n",
         new="    return FTRUE\n"),
    dict(id="BOOTPRED-M4 with_mutex/2 is not transparent: the goal runs in the context of system (KILL bp17; UNVERIFIED on the kernel)",
         file=EXT, targets=TB,
         old='    PL_extension("with_mutex", 2, pl_with_mutex, PL_FA_TRANSPARENT | PL_FA_ISO)',
         new='    PL_extension("with_mutex", 2, pl_with_mutex, PL_FA_ISO)'),
]
