# `src/constraints/` — attributed-variable hooks

Attributed variables: attaching data to an unbound variable and running a hook when unification
binds it. The substrate for constraint solvers, not a solver itself.

Port class: **as code** (SWI-Prolog `src/pl-attvar.c`).

Depends on: `terms`, `unify`. Entry file when it lands: `constraints.jl`.
