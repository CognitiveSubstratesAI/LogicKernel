# ORIGINAL: sync-2's mutant list — no swipl-devel counterpart.
# tools/mutants/Sync2.py — the mutation battery of sync-2 (8e1bc111 -> cbf4e189, V10.1.19; audit D-0123, D-0126,
# D-0137, D-0138), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# The rows are test/core_lang/test_cleanup_swipl.jl's k39-k48 (Q3: call_internal_det_foreign) against the 10.1.19
# oracle, and the arithmetic and control differentials for moveNumber and setJumpChoice!.
#
# NOT MUTATED: callProlog's `&& ld.exception_term == 0` after the fast path — every '$' det foreign predicate the
# kernel registers returns FFALSE when it raises, so the conjunct only matters for one that raises and returns
# FTRUE, which none does (upstream's own `rc && !exception_term`); the Q2 labels' bodies (normal_call_grow,
# exit_det_error, exit_watched) — the statements moved unchanged from exit_continue and normal_call (pending audit).
CLEAN = ["test/core_lang/test_cleanup_swipl.jl"]
ARITH = ["test/core_lang/test_arith_swipl.jl"]
W = "src/pl-wam.jl"
P = "src/pl-pro.jl"
A = "src/pl-arith.jl"
TARGETS = CLEAN + ARITH
MUTANTS = [
    dict(id="SY1 callProlog does not take the fast path (setup rows: sig_atomic/1)", file=P, targets=CLEAN,
         old='''    if (flags & PL_Q_PASS_EXCEPTION) != 0
        used, rc = call_internal_det_foreign(gd, ld, proc, args)''',
         new='''    if false
        used, rc = call_internal_det_foreign(gd, ld, proc, args)'''),
    dict(id="SY2 call_term does not take the fast path (cleanup rows)", file=W, targets=CLEAN,
         old='''    used, rc = call_internal_det_foreign(gd, ld, proc, av)
    used && return rc != FFALSE''',
         new='''    used, rc = (false, FFALSE)
    used && return rc != FFALSE'''),
    dict(id="SY3 the fast path takes any name, not only '$' (k47: retractall/1)", file=W, targets=CLEAN,
         old='''        startswith(sym_text(def.name), '$')''',
         new='''        true'''),
    dict(id="SY4 the fast path takes a transparent predicate (k48: '$set_predicate_attribute'/3)", file=W, targets=CLEAN,
         old='''        (def.flags & (P_NONDET | P_TRANSPARENT)) == 0 &&''',
         new='''        (def.flags & P_NONDET) == 0 &&'''),
    dict(id="SY5 moveNumber does not copy a small integer's value", file=A, targets=ARITH,
         old='''    if t === V_INTEGER
        to.i = from.i
    elseif t === V_FLOAT''',
         new='''    if t === V_INTEGER
        nothing
    elseif t === V_FLOAT'''),
    dict(id="SY6 moveNumber does not copy a float's value", file=A, targets=ARITH,
         old='''    elseif t === V_FLOAT
        to.f = from.f''',
         new='''    elseif t === V_FLOAT
        nothing'''),
    dict(id="SY7 moveNumber does not set the type", file=A, targets=ARITH,
         old='''    to.type = t
    return nothing
end''',
         new='''    return nothing
end'''),
    dict(id="SY8 setJumpChoice! does not set the jump", file=W, targets=CLEAN,
         old='''    ld.choices[ch].value_pc = p                 # (ch)->value.jump.pc = (p)''',
         new='''    ld.choices[ch].value_pc = 0                 # (ch)->value.jump.pc = (p)'''),
]
