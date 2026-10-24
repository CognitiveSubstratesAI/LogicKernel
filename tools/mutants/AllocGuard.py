# ORIGINAL: the AllocCheck span guard's mutant list — no swipl-devel counterpart.
# tools/mutants/AllocGuard.py — the mutation battery of the call-site pass (audit D-0142: the span checks of
# test/static_analysis_body.jl attributed a site by the run loop's frame in its backtrace, which a callee with
# several callers does not carry). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`. Each mutant blinds one part of the pass; the
# fixture (`_SA_SPAN_FIXTURE`, the "controls" part) and the run loop's own callees must catch it.
TARGETS = ["test/test_static_analysis.jl"]
T = TARGETS
G = "test/static_analysis_gates.jl"
B = "test/static_analysis_body.jl"
MUTANTS = [
    dict(id="AG1 the pass collects no callee", file=G, targets=T,
         old='''        (st isa Expr && st.head === :invoke) || continue''',
         new='''        (st isa Expr && st.head === :invoke_never) || continue'''),
    dict(id="AG2 an unlisted callee is not AllocChecked", file=B, targets=T,
         old='''        kind in (:cold, :error) && continue''',
         new='''        true && continue'''),
    dict(id="AG3 no block is a throw path", file=G, targets=T,
         old='''                t[b] = changed = true''',
         new='''                changed = false'''),
    dict(id="AG4 a growth callee's sites are not checked against the growth frames", file=B, targets=T,
         old='''            if kind !== :growth || !any(fr -> fr.func in SPAN_GROWTH_FRAMES, s.backtrace)''',
         new='''            if kind !== :growth'''),
]
