# ORIGINAL: the TH1AA mutant list (setThreadLocalDefinition! of the kernel's ENGINES=OFF build, src/pl-proc.jl) — no swipl-devel counterpart.
# tools/mutants/TH1AA.py — the mutation battery of step TH1-A (audit D-0740 item 2: the kernel is MULTI_THREADED=OFF ENGINES=OFF, so
# `setThreadLocalDefinition` is the `#else` body of pl-proc.c:3829-3838: `setDynamicDefinition(def, val)`, then set or clear
# `P_VOLATILE|P_THREAD_LOCAL`, always true). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. The KILL lists are what the
# rows are EXPECTED to do (read, not run): the battery's verdict is the evidence. Every `old` was counted in its file with a throwaway
# `python3 -I` script (a text count, no Julia). Successors of LB2-78 .. LB2-83 (tools/mutants/LB2c.py, retired with the O_ENGINES body).
# TARGETS (audit D-0238): every test file that reaches the mutated function: the new file (rows tl01-tl24 and its white-box testset),
# test_nth_clause_swipl.jl (rows t01-t18, `_NTH_OFF`), test_load_swipl.jl (`:- thread_local p/1`, the redefine path) and test_pr1_swipl.jl
# (`'$get_predicate_attribute'(_, thread_local, _)` of a declared predicate).
TARGETS = [
    "test/db/test_thread_local_off_swipl.jl",
    "test/db/test_nth_clause_swipl.jl",
    "test/files/test_load_swipl.jl",
    "test/core_lang/test_pr1_swipl.jl",
]
V = "src/pl-proc.jl"
MUTANTS = [
    dict(id="TH1AA-M1 thread_local does not make the predicate dynamic (KILL tl03 (the `dynamic` property), the white-box testset; assertz would still create it)",
         file=V, targets=TARGETS,
         old="    setDynamicDefinition!(def, val)\n    if val\n",
         new="    if val\n"),
    dict(id="TH1AA-M2 thread_local does not set P_THREAD_LOCAL (KILL tl02, the white-box testset, test_pr1 rd7, test_load's redefine row)",
         file=V, targets=TARGETS,
         old="        def.flags |= P_VOLATILE | P_THREAD_LOCAL\n",
         new="        def.flags |= P_VOLATILE\n"),
    dict(id="TH1AA-M3 thread_local does not set P_VOLATILE (KILL tl04, the white-box testset)",
         file=V, targets=TARGETS,
         old="        def.flags |= P_VOLATILE | P_THREAD_LOCAL\n",
         new="        def.flags |= P_THREAD_LOCAL\n"),
    dict(id="TH1AA-M4 thread_local false does not clear P_THREAD_LOCAL (KILL tl16, the white-box testset, nth t06 t17)",
         file=V, targets=TARGETS,
         old="        def.flags &= ~(P_VOLATILE | P_THREAD_LOCAL)\n",
         new="        def.flags &= ~P_VOLATILE\n"),
    dict(id="TH1AA-M5 thread_local false does not clear P_VOLATILE (KILL the white-box testset)",
         file=V, targets=TARGETS,
         old="        def.flags &= ~(P_VOLATILE | P_THREAD_LOCAL)\n",
         new="        def.flags &= ~P_THREAD_LOCAL\n"),
    dict(id="TH1AA-M6 thread_local false leaves the predicate dynamic: setDynamicDefinition! always gets true (KILL tl17 tl18, the white-box testset)",
         file=V, targets=TARGETS,
         old="    setDynamicDefinition!(def, val)\n",
         new="    setDynamicDefinition!(def, true)\n"),
    dict(id="TH1AA-M7 the O_ENGINES refusal is back: a predicate with clauses is not accepted (KILL tl13 tl14 tl15, nth t02 t03 t09, the white-box testset)",
         file=V, targets=TARGETS,
         old="    setDynamicDefinition!(def, val)\n    if val\n",
         new="    val && def.impl_clauses.first_clause !== nothing &&\n        return PL_error(ld, ERR_MODIFY_STATIC_PROC, def, \"\")\n    setDynamicDefinition!(def, val)\n    if val\n"),
    dict(id="TH1AA-M8 the O_ENGINES early return is back for a predicate that is not thread-local: false is a no-op (KILL tl17, tl18)",
         file=V, targets=TARGETS,
         old="    setDynamicDefinition!(def, val)\n    if val\n",
         new="    !val && (def.flags & P_THREAD_LOCAL) == 0 && return true\n    setDynamicDefinition!(def, val)\n    if val\n"),
    dict(id="TH1AA-M9 the O_ENGINES refusal of thread-local to static is back (KILL tl16 tl19, nth t06 t17, the white-box testset)",
         file=V, targets=TARGETS,
         old="    setDynamicDefinition!(def, val)\n    if val\n",
         new="    !val && (def.flags & P_THREAD_LOCAL) != 0 &&\n        return PL_error(ld, ERR_MODIFY_STATIC_PROC, def, \"predicate is thread-local\")\n    setDynamicDefinition!(def, val)\n    if val\n"),
    dict(id="TH1AA-M10 setThreadLocalDefinition! answers false (KILL tl01 and every row that declares a thread-local predicate, nth t01)",
         file=V, targets=TARGETS,
         old="        def.flags &= ~(P_VOLATILE | P_THREAD_LOCAL)\n    end\n    return true\n",
         new="        def.flags &= ~(P_VOLATILE | P_THREAD_LOCAL)\n    end\n    return false\n"),
]
