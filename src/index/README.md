# `src/index/` — clause and argument indexing

JIT argument indexing with SWI-Prolog's assessment formula, a per-bucket discrimination trie, the
grounded-value key, and later the **deep key** (two levels, lazy level 2) designed in MeTTaCore's
`docs/tracking/COMPILER_PLAN.md`.

🔴 **THE CONTRACT: INDEXING NEVER CHANGES ANSWERS.** An index yields a SUPERSET of the clauses that
match, and enumerating it yields exactly the true multiset, in source order. It only removes work.
Two consequences that have already cost answers elsewhere:

* a grounded key must follow `==`, never `hash`/`isequal` — they disagree on `0.0`/`-0.0` and on
  every container. A value that cannot be keyed is a WILDCARD, never a shared bucket;
* SWI's deep (nested-argument) indexing returns from the functor sublist without visiting the
  variable-clause sublist. For a language where every clause fires, the two must be UNIONED.

Port class: index assessment **as code**; the rest re-expressed. Extracted from MeTTaCore's
`src/standard/Index.jl`.

Depends on: `terms`. Entry file when it lands: `index.jl`.
