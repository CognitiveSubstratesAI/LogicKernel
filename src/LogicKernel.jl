"""
    LogicKernel

A standalone logic-programming kernel: terms, unification, a clause database, argument
indexing, term tries, SLG tabling and a clause VM — with NO MeTTa semantics. Answers come back
in order with duplicates kept; deduplication and tabling modes are caller options.

Subsystems and their dependency order are in `docs/architecture.md`. Nothing is ported yet: this
is the skeleton, and each subsystem directory under `src/` says what will live there.
"""
module LogicKernel

# ── includes, in dependency order (docs/architecture.md) ────────────────────────────────────────
# terms → unify → constraints → trie → index → db → tabling → vm
# Each subsystem gets ONE entry file, `src/<subsystem>/<subsystem>.jl`, included here when its
# first code lands. None exists yet.

# ── exports ─────────────────────────────────────────────────────────────────────────────────────
# None yet. The first are the term interface's functions (`src/terms/`).

end # module LogicKernel
