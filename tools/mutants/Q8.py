# ORIGINAL: ported from swipl-devel 1412ce49 ("'$current_prolog_flag'/5 ... enumerating `local` scope without local flags",
# pl-prologflag.c pl_prolog_flag5); the mutant list of the Q8 mirror step — no swipl-devel counterpart.
# tools/mutants/Q8.py — the mutation battery of the Q8 mirror (pl_prolog_flag5: an explicit `local` scope fails before the
# enumerator is made, the state freed), run ONCE, in CI. The format is tools/mutate_drive.py's. Killed by
# test/core_lang/test_prolog_flag_swipl.jl (the scope-argument testset: the `local` query has no answer and leaves no live state).
TARGETS = ["test/core_lang/test_prolog_flag_swipl.jl"]
T = TARGETS
P = "src/os/pl-prologflag.jl"
MUTANTS = [
    dict(id="Q8-M1 an explicit `local` scope does not fail early", file=P, targets=T,
         equivalent="src/os/pl-prologflag.jl:535 pl_prolog_flag5 (the walk, src/os/pl-prologflag.jl:570 `scope == 0 || PL_unify_atom(ld, scope, ...)`): without the early failure the walk goes straight on to the global table (`e.is_local` is false there), and every flag's scope unification `global` fails against the caller's `local`, so the query still has no answer and frees its state; the early failure is upstream's structure (1412ce49), not a different answer",
         old="            if e.is_local                               # if ( e->scope == ATOM_local )\n",
         new="            if false                                    # if ( e->scope == ATOM_local )\n"),
    dict(id="Q8-M2 the early failure leaves the state allocated", file=P, targets=T,
         old="""                # upstream 1412ce49: if ( !LD->prolog_flag.table ) { freeHeap(e, sizeof(*e)); fail; } — the kernel has none
                free_foreign_state!(pool, idx)
""",
         new="""                # upstream 1412ce49: if ( !LD->prolog_flag.table ) { freeHeap(e, sizeof(*e)); fail; } — the kernel has none
"""),
    dict(id="Q8-M3 the early failure succeeds", file=P, targets=T,
         old="""                free_foreign_state!(pool, idx)
                return FFALSE
            end
        else""",
         new="""                free_foreign_state!(pool, idx)
                return FTRUE
            end
        else"""),
    dict(id="Q8-M4 every named scope fails early (`global` too)", file=P, targets=T,
         old="            if e.is_local                               # if ( e->scope == ATOM_local )\n",
         new="            if e.explicit_scope                         # if ( e->scope == ATOM_local )\n"),
]
