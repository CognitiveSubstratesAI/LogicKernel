# ORIGINAL: ported from swipl-devel d4621369 ("'$attv_unify'(X,X) on an attributed variable created a
# self-reference", pl-attvar.c attv_unify); the mutant list of the FIXED step Q10 — no swipl-devel counterpart.
# tools/mutants/Q10fix.py — the mutation battery of the FIXED step Q10 (pl_attv_unify2_va: `v == av` returns
# before the link; the link word is computed before `av` is dereferenced again), run ONCE, in CI. The format is
# tools/mutate_drive.py's. Killed by test/core_lang/test_attvar_store.jl (the `$attv_unify(X, X)` testset, which
# reads the attvar cell's raw word first, so a regression fails instead of hanging).
TARGETS = ["test/core_lang/test_attvar_store.jl"]
T = TARGETS
A = "src/pl-attvar.jl"
MUTANTS = [
    dict(id="Q10fix-M1 no early return for '$attv_unify'(X,X): the attvar is bound to a reference to itself", file=A, targets=T,
         old="        v[3] == av && return FTRUE                          #   if ( v == av ) return true: '$attv_unify'(X,X)\n",
         new=""),
    dict(id="Q10fix-M2 av not dereferenced again after the link word is computed", file=A, targets=T,
         equivalent="src/pl-attvar.jl pl_attv_unify2_va: _link_val_loc! (:300) only reads cells and may add a value-table entry (_side_value_word!, src/pl-inline.jl:503); global-stack positions are indices, so av cannot move and the second _deref_loc(A1) returns the same position",
         old="        _, _, av = _deref_loc(ld, -(A1 + 1))                #   av = valTermRef(A1); deRef(av)\n",
         new=""),
]
