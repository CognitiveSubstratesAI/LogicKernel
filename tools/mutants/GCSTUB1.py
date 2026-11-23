# ORIGINAL: the TH1 GC-stub mutant list — no swipl-devel counterpart.
# tools/mutants/GCSTUB1.py — the mutation battery of `$gc_clear/1`, `$gc_stop/0`, `$gc_wait/1` (pl-thread.c:7299-7366) and `$can_yield/0`
# (pl-pro.c:455-464): src/pl-thread.jl, src/pl-pro.jl, src/pl-ext.jl (their registration) and src/pl-thread.jl:474 (the engine query's flag).
# Run ONCE, in CI (.github/workflows/mutation.yml; locally one mutant under debug is fine, no local list: D-0220). Format: tools/mutate_drive.py's
# (as TH1E.py, TH1V.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# KILL: test/core_lang/test_engine_yield_swipl.jl: rows gs01-gs11 (expected values measured on swipl 10.1.20, pin 18168e62) and the testset
# "'$gc_wait'/1 is refused by name". The KILL lists are what the rows are EXPECTED to do (read, not run): the battery's verdict is the evidence.
# Written by a coding agent with NO Julia process: every `old` was counted exactly once with a throwaway `python3 -I` script (a text count);
# RE-FIT any `old` that `tools/warm.sh fmt` rewrapped.
# MAY SURVIVE: GCSTUB1-C4 (the exception raised by PL_get_atom_ex stays pending when the predicate then returns true: if the VM raises it anyway, the
# row sees the same error; the battery decides, then a row or the reason).
# TARGETS (audit D-0238): every file that runs the mutated code. The four predicates are reached only by name, from the one test file above;
# `$can_yield` through an engine's query is also reached by the engine rows of test_engines_swipl.jl (the PL_Q_ALLOW_YIELD flag, mutant C4).
P = "src/pl-thread.jl"
R = "src/pl-pro.jl"
X = "src/pl-ext.jl"
TARGETS = [
    "test/core_lang/test_engine_yield_swipl.jl",
    "test/core_lang/test_engines_swipl.jl",
]
MUTANTS = [
    # ---- '$gc_stop'/0
    dict(id="GCSTUB1-S1 `$gc_stop` succeeds (KILL gs08: swipl fails while no GC thread runs)",
         file=P, targets=TARGETS,
         old="function pl_gc_stop(ld::PL_local_data{T})::foreign_t where {T}\n    return FFALSE\n",
         new="function pl_gc_stop(ld::PL_local_data{T})::foreign_t where {T}\n    return FTRUE\n"),
    dict(id="GCSTUB1-S2 `$gc_stop` is registered under another name (KILL gs08: existence_error instead of failure)",
         file=X, targets=TARGETS,
         old=r'PL_extension("\$gc_stop", 0, pl_gc_stop, 0x00)',
         new=r'PL_extension("\$gc_stops", 0, pl_gc_stop, 0x00)'),
    # ---- '$gc_clear'/1
    dict(id="GCSTUB1-C1 `$gc_clear` refuses garbage_collect_clauses with the domain error (KILL gs02)",
         file=P, targets=TARGETS,
         old="act !== :garbage_collect_atoms && act !== :garbage_collect_clauses\n",
         new="act !== :garbage_collect_atoms\n"),
    dict(id="GCSTUB1-C2 `$gc_clear` accepts `bogus` too (KILL gs04: swipl raises domain_error(action, bogus))",
         file=P, targets=TARGETS,
         old="act !== :garbage_collect_atoms && act !== :garbage_collect_clauses\n",
         new="act !== :garbage_collect_atoms && act !== :garbage_collect_clauses && act !== :bogus\n"),
    dict(id="GCSTUB1-C3 the domain error names `actions` (KILL gs03, gs04)",
         file=P, targets=TARGETS,
         old='PL_domain_error(ld, "action", A1)',
         new='PL_domain_error(ld, "actions", A1)'),
    dict(id="GCSTUB1-C4 a non-atom argument is not refused: succeeds after the type error was raised (KILL gs05, gs06, gs07)",
         file=P, targets=TARGETS,
         old="    a === nothing && return FFALSE\n    act = Symbol(sym_text(a))\n",
         new="    a === nothing && return FTRUE\n    act = Symbol(sym_text(a))\n"),
    dict(id="GCSTUB1-C5 `$gc_clear` rejects every valid action (KILL gs01, gs02)",
         file=P, targets=TARGETS,
         old="if act !== :garbage_collect_atoms && act !== :garbage_collect_clauses\n",
         new="if act !== :garbage_collect_atoms || act !== :garbage_collect_clauses\n"),
    dict(id="GCSTUB1-C6 `$gc_clear` is registered with another name (KILL gs01..gs07: existence_error)",
         file=X, targets=TARGETS,
         old=r'PL_extension("\$gc_clear", 1, pl_gc_clear, 0x00)',
         new=r'PL_extension("\$gc_clean", 1, pl_gc_clear, 0x00)'),
    # ---- '$gc_wait'/1: the named refusal
    dict(id="GCSTUB1-W1 `$gc_wait` succeeds instead of refusing (KILL the testset \"'$gc_wait'/1 is refused by name\")",
         file=P, targets=TARGETS,
         old="    throw(\n        NotPortedError{T}(\n            mk_sym(T, Symbol(\"\\$gc_wait\")), \"gc_wait/1: blocks for the GC thread (none)\",\n            \"TH1\"\n        )\n    )\n",
         new="    return FTRUE\n"),
    dict(id="GCSTUB1-W2 the refusal names another step (KILL the testset: `err.step == \"TH1\"`)",
         file=P, targets=TARGETS,
         old="\"gc_wait/1: blocks for the GC thread (none)\",\n            \"TH1\"",
         new="\"gc_wait/1: blocks for the GC thread (none)\",\n            \"TH2\""),
    dict(id="GCSTUB1-W3 `$gc_wait` is registered under another name (KILL the testset: existence_error, not the refusal)",
         file=X, targets=TARGETS,
         old=r'PL_extension("\$gc_wait", 1, pl_gc_wait, 0x00)',
         new=r'PL_extension("\$gc_waits", 1, pl_gc_wait, 0x00)'),
    # ---- '$can_yield'/0
    dict(id="GCSTUB1-Y1 `$can_yield` is inverted (KILL gs09, gs10, gs11)",
         file=R, targets=TARGETS,
         old="    return PL_can_yield(ld) ? FTRUE : FFALSE\n",
         new="    return PL_can_yield(ld) ? FFALSE : FTRUE\n"),
    dict(id="GCSTUB1-Y2 `$can_yield` is always true (KILL gs09)",
         file=R, targets=TARGETS,
         old="    return PL_can_yield(ld) ? FTRUE : FFALSE\n",
         new="    return FTRUE\n"),
    dict(id="GCSTUB1-Y3 `$can_yield` is always false (KILL gs10, gs11)",
         file=R, targets=TARGETS,
         old="    return PL_can_yield(ld) ? FTRUE : FFALSE\n",
         new="    return FFALSE\n"),
    dict(id="GCSTUB1-Y4 the engine's query is opened without PL_Q_ALLOW_YIELD (KILL gs10, gs11 and the yield rows ey01..)",
         file=P, targets=TARGETS,
         old="PL_Q_CATCH_EXCEPTION | PL_Q_ALLOW_YIELD | PL_Q_EXT_STATUS",
         new="PL_Q_CATCH_EXCEPTION | PL_Q_EXT_STATUS"),
    dict(id="GCSTUB1-Y5 `$can_yield` is registered under another name (KILL gs09..gs11)",
         file=R, targets=TARGETS,
         old=r'PL_extension("\$can_yield", 0, pl_can_yield0_va, PL_FA_VARARGS)',
         new=r'PL_extension("\$can_yields", 0, pl_can_yield0_va, PL_FA_VARARGS)'),
]
