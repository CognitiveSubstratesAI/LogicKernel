# `src/tabling/` — SLG tabling

Variant tabling with suspension for left recursion, SCC-based completion for mutual recursion,
tabled negation under the well-founded semantics (delays and completion), and answer-subsumption
modes. Tabling modes and answer deduplication are CALLER options.

Port class: **as code** for WFS delays and completion (SWI-Prolog `src/pl-tabling.c`,
`boot/tabling.pl`), with SWI run as a LIVE differential (`test/oracle/`).

Depends on: `unify`, `trie`, `db`. Entry file when it lands: `tabling.jl`.
