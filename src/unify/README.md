# `src/unify/` — unification, bindings, substitution, variants

Unification over the term interface, binding environments, substitution, renaming apart, and
**variant** checking/canonicalisation (equal up to consistent variable renaming) plus term hashing.

Port class: **as code** for variant checking and term hashing (the algorithms carry over).
Upstream: SWI-Prolog `src/pl-variant.c`, `src/pl-termhash.c`.

⚠️ No choice points and no trail: nondeterminism in this kernel is the sink/continuation model.

Depends on: `terms`. Entry file when it lands: `unify.jl`.
