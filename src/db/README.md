# `src/db/` — the clause database

Predicate definitions, clause storage in source order, generations (the logical update view: a
running enumeration sees the database as it was when it started), and clause garbage collection.

Port class: **as design**, re-expressed, never transliterated (SWI-Prolog `src/pl-proc.c`): every
clause fires, there is no cut, and results are multisets.

Depends on: `terms`, `index`. Entry file when it lands: `db.jl`.
